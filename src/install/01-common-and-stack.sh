
# --- Common Utilities ---
warp_client_id_to_reserved_json() {
  local client_id decoded_bytes reserved_json
  client_id=$(trim_whitespace "${1:-}")

  if [[ -z "${client_id}" ]]; then
    printf '[]'
    return 0
  fi

  if ! decoded_bytes=$(printf '%s' "${client_id}" | base64 -d 2>/dev/null | od -An -t u1 -v 2>/dev/null); then
    log_error "Warp client_id 解码失败，请尝试重新注册 Warp。"
  fi

  reserved_json=$(printf '%s\n' "${decoded_bytes}" | tr -s '[:space:]' '\n' | sed '/^$/d' | jq -Rsc \
    'split("\n") | map(select(length > 0) | tonumber)')

  if ! jq -e 'length == 3' >/dev/null 2>&1 <<< "${reserved_json}"; then
    log_error "Warp client_id 长度异常，请尝试重新注册 Warp。"
  fi

  printf '%s' "${reserved_json}"
}

write_warp_credentials_atomic() (
  umask 077
  local warp_id=${1:-} warp_token=${2:-} warp_priv_key=${3:-} warp_pub_key=${4:-}
  local warp_v4=${5:-} warp_v6=${6:-} warp_client_id=${7:-}
  local candidate='' backup_candidate='' rollback_candidate='' expected_hash old_hash='' committed=n complete=n target candidate_inode=''
  warp_credentials_cleanup() {
    local result=$?
    if [[ "${committed}" != y && -n "${candidate_inode}" && -f "${SB_WARP_KEY_FILE}" && ! -L "${SB_WARP_KEY_FILE}" ]] &&
       [[ "$(stat -c '%d:%i' "${SB_WARP_KEY_FILE}")" == "${candidate_inode}" ]]; then
      committed=y
    fi
    if [[ "${committed}" == y && "${complete}" != y ]]; then
      if [[ -n "${old_hash}" ]]; then
        rollback_candidate=$(mktemp "${SB_PROJECT_DIR}/.warp.restore.XXXXXXXX") || return 2
        if cp -- "${SB_WARP_KEY_FILE}.bak" "${rollback_candidate}" && chmod 600 "${rollback_candidate}" &&
           mv -f -- "${rollback_candidate}" "${SB_WARP_KEY_FILE}" &&
           [[ "$(sha256sum "${SB_WARP_KEY_FILE}")" == "${old_hash}" ]]; then
          printf '[WARN] operation=warp_register stage=rollback rolled_back=true\n' >&2
        else
          printf '[ERROR] operation=warp_register stage=rollback rollback_ok=false manual_intervention_required=true\n' >&2
          return 2
        fi
      else
        rm -f -- "${SB_WARP_KEY_FILE}" || return 2
      fi
    fi
    for target in "${candidate}" "${backup_candidate}" "${rollback_candidate}"; do
      [[ -z "${target}" ]] || rm -f -- "${target}"
    done
    return "${result}"
  }
  trap warp_credentials_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  for target in "${SB_WARP_KEY_FILE}" "${SB_WARP_KEY_FILE}.bak"; do
    [[ ! -L "${target}" && ( ! -e "${target}" || -f "${target}" ) ]] || return 1
  done
  candidate=$(mktemp "${SB_PROJECT_DIR}/.warp.key.XXXXXXXX") || return 1
  {
    printf 'WARP_ID=%q\n' "${warp_id}"
    printf 'WARP_TOKEN=%q\n' "${warp_token}"
    printf 'WARP_PRIV_KEY=%q\n' "${warp_priv_key}"
    printf 'WARP_PUB_KEY=%q\n' "${warp_pub_key}"
    printf 'WARP_V4=%q\n' "${warp_v4}"
    printf 'WARP_V6=%q\n' "${warp_v6}"
    printf 'WARP_CLIENT_ID=%q\n' "${warp_client_id}"
  } > "${candidate}" || return 1
  chmod 600 "${candidate}" && bash -n "${candidate}" || return 1
  expected_hash=$(sha256sum < "${candidate}") || return 1
  if [[ -f "${SB_WARP_KEY_FILE}" ]]; then
    old_hash=$(sha256sum "${SB_WARP_KEY_FILE}") || return 1
    backup_candidate=$(mktemp "${SB_PROJECT_DIR}/.warp.backup.XXXXXXXX") || return 1
    cp -- "${SB_WARP_KEY_FILE}" "${backup_candidate}" && chmod 600 "${backup_candidate}" &&
      mv -f -- "${backup_candidate}" "${SB_WARP_KEY_FILE}.bak" || return 1
  fi
  candidate_inode=$(stat -c '%d:%i' "${candidate}") || return 1
  mv -f -- "${candidate}" "${SB_WARP_KEY_FILE}" || return 1
  committed=y
  [[ "$(sha256sum < "${SB_WARP_KEY_FILE}")" == "${expected_hash}" && "$(stat -c %a "${SB_WARP_KEY_FILE}")" == 600 ]] || return 1
  complete=y
)

warp_registration_response_valid() {
  local response_file=$1 address client_id decoded
  jq -e '
    def bounded: type == "string" and length > 0 and utf8bytelength <= 4096 and
      (test("[\\x00-\\x1f\\x7f]") | not);
    type == "object" and (.id | bounded) and (.token | bounded) and
    (.config.client_id | bounded) and
    (.config.interface.addresses.v4 | bounded) and
    (.config.interface.addresses.v6 | bounded)
  ' "${response_file}" >/dev/null 2>&1 || return 1
  address=$(jq -r '.config.interface.addresses.v4' "${response_file}") || return 1
  [[ "${address}" != *:* ]] && structured_instance_store_validate_address "${address}" || return 1
  address=$(jq -r '.config.interface.addresses.v6' "${response_file}") || return 1
  [[ "${address}" == *:* ]] && structured_instance_store_validate_address "${address}" || return 1
  client_id=$(jq -r '.config.client_id' "${response_file}") || return 1
  decoded=$(printf '%s' "${client_id}" | base64 -d 2>/dev/null | od -An -t u1 -v) || return 1
  [[ $(wc -w <<< "${decoded}") -eq 3 ]]
}

# The receipt lives beside the managed project so a configuration rollback
# cannot discard evidence of a possibly completed external POST.
register_warp() (
  umask 077
  local receipt="${SB_WARP_REGISTRATION_PENDING_FILE}"
  local temp_dir='' keypair priv_key pub_key install_id tos_date http_status curl_status=0 phase
  local response_file warp_id warp_token warp_v4 warp_v6 warp_client_id candidate='' target save_status
    warp_registration_error() {
    printf '[ERROR] operation=warp_register stage=%s code=%s changed=%s; %s\n' "$1" "$2" "${4:-false}" "$3" >&2
    log_info "Warp 注册失败: $2（敏感响应原文未记录）。" >> "${SBV_LOG_FILE}"
  }
  warp_registration_cleanup() {
    local result=$?
    [[ -z "${candidate}" ]] || rm -f -- "${candidate}"
    [[ -z "${temp_dir}" ]] || rm -rf -- "${temp_dir}"
    return "${result}"
  }
  trap warp_registration_cleanup EXIT
  trap 'warp_registration_error interrupted signal_interrupted "注册被中断；若请求已发送，恢复材料保留在 ${receipt}，禁止自动重复注册。"; exit 130' INT
  trap 'warp_registration_error interrupted signal_interrupted "注册被中断；若请求已发送，恢复材料保留在 ${receipt}，禁止自动重复注册。"; exit 143' TERM
  trap 'warp_registration_error interrupted signal_interrupted "注册被中断；若请求已发送，恢复材料保留在 ${receipt}，禁止自动重复注册。"; exit 129' HUP

  for target in "${SB_WARP_KEY_FILE}" "${SB_WARP_KEY_FILE}.bak" "${receipt}"; do
    if [[ -L "${target}" || ( -e "${target}" && ! -f "${target}" ) ]]; then
      warp_registration_error precheck unsafe_target '凭据或恢复路径不是普通文件，未发送请求。'
      return 1
    fi
  done
  candidate=''
  mkdir -p -- "${SB_PROJECT_DIR}" || return $?
  if [[ ! -e "${receipt}" && -f "${SB_WARP_KEY_FILE}" ]] && grep -Eq '^WARP_CLIENT_ID=.+$' "${SB_WARP_KEY_FILE}"; then
    warp_client_id=$(sed -n 's/^WARP_CLIENT_ID=//p' "${SB_WARP_KEY_FILE}") || return 1
    if [[ ! "${warp_client_id}" =~ ^[A-Za-z0-9+/]{4}$ ]]; then
      warp_registration_error precheck invalid_saved_credentials '现有 client_id 无效；未发送注册请求。'
      return 1
    fi
    log_info '发现现有 Warp 账户信息，正在加载...'
    return 0
  fi
  temp_dir=$(mktemp -d "${SB_PROJECT_DIR}.warp-register.XXXXXXXX") || return $?
  response_file="${temp_dir}/response.json"
  if [[ -f "${receipt}" ]]; then
    phase=$(jq -er 'select(.schema == 1) | .phase' "${receipt}" 2>/dev/null) || phase=unknown
    if [[ "${phase}" != received ]]; then
      warp_registration_error precheck remote_outcome_unknown "已有未对账注册请求；保留 ${receipt}，本次没有重复 POST。"
      return 1
    fi
    priv_key=$(jq -er '.private_key | strings | select(length > 0)' "${receipt}") || return 1
    pub_key=$(jq -er '.public_key | strings | select(length > 0)' "${receipt}") || return 1
    [[ ${#priv_key} -eq 44 && ${#pub_key} -eq 44 && "${priv_key}" =~ ^[A-Za-z0-9+/]+=$ && "${pub_key}" =~ ^[A-Za-z0-9+/]+=$ ]] || {
      warp_registration_error validate invalid_recovery '恢复密钥格式无效，保留现场且没有重复 POST。'; return 1;
    }
    jq -e '.response' "${receipt}" > "${response_file}" || return 1
    warp_registration_response_valid "${response_file}" || {
      warp_registration_error validate invalid_recovery '恢复材料无效，保留现场且没有重复 POST。'; return 1;
    }
    log_info '正在恢复已收到的 Warp 注册结果；本次没有重复 POST。'
  else
    if [[ -f "${SB_WARP_KEY_FILE}" ]]; then
      log_warn '发现旧版 Warp 账户信息缺少 client_id，正在重新注册...'
    fi
    keypair=$(run_singbox_generate_command wg-keypair 'WireGuard 密钥') || return $?
    priv_key=$(extract_generated_key_value "${keypair}" private) || return 1
    pub_key=$(extract_generated_key_value "${keypair}" public) || return 1
    [[ ${#priv_key} -eq 44 && ${#pub_key} -eq 44 && "${priv_key}" =~ ^[A-Za-z0-9+/]+=$ && "${pub_key}" =~ ^[A-Za-z0-9+/]+=$ ]] || {
      warp_registration_error prepare invalid_keypair 'WireGuard 密钥格式无效，未发送请求。'; return 1;
    }
    install_id=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid) || return 1
    tos_date=$(date -u +%FT%T.000Z) || return 1
    jq -cn --arg key "${pub_key}" --arg id "${install_id}" --arg tos "${tos_date}" \
      '{key:$key,install_id:$id,fcm_token:"",referrer:"",warp_enabled:false,tos:$tos,type:"Linux",locale:"en_US"}' \
      > "${temp_dir}/request.json" || return 1
    jq -cn --arg private "${priv_key}" --arg public "${pub_key}" --arg id "${install_id}" \
      '{schema:1,phase:"sent",private_key:$private,public_key:$public,install_id:$id}' \
      > "${temp_dir}/receipt.json" || return 1
    # noclobber serializes registration attempts without replacing recovery data.
    if (set -o noclobber; cat "${temp_dir}/receipt.json" > "${receipt}") 2>/dev/null; then
      :
    else
      warp_registration_error prepare registration_pending '已有注册请求，未发送第二次请求。'; return 1
    fi
    log_info '正在注册 Cloudflare Warp 免费账户...'
    # POST is deliberately never automatically retried: timeout/5xx may follow
    # an accepted registration. Keep the receipt for operator reconciliation.
    http_status=$(curl -sS --connect-timeout 10 --max-time 30 --max-filesize 1048576 \
      -X POST 'https://api.cloudflareclient.com/v0a2445/reg' \
      -H 'User-Agent: okhttp/4.12.0' -H 'Content-Type: application/json' \
      --data-binary "@${temp_dir}/request.json" -o "${response_file}" -w '%{http_code}' \
      2> >(head -c "${SBV_CURL_STDERR_MAX_BYTES}" > "${temp_dir}/curl.stderr"; cat >/dev/null)) || curl_status=$?
    if [[ ${curl_status} -ne 0 ]]; then
      # DNS/connect failure cannot have sent an HTTP request. Other outcomes are
      # uncertain, so the receipt survives to prevent accidental duplicate POSTs.
      if [[ ${curl_status} -eq 6 || ${curl_status} -eq 7 ]]; then
        rm -f -- "${receipt}" || return 1
      fi
      warp_registration_error request "transport_${curl_status}" 'Warp 注册 API 请求失败；未更改凭据，原始输出未记录，结果不确定时保留恢复材料。'
      return "${curl_status}"
    fi
    if [[ ! "${http_status}" =~ ^2[0-9][0-9]$ ]]; then
      if [[ "${http_status}" =~ ^4[0-9][0-9]$ ]]; then rm -f -- "${receipt}" || return 1; fi
      warp_registration_error request "http_${http_status:-unavailable}" 'Warp 注册失败（API 返回错误）；未更改凭据，敏感响应原文未记录。'
      return 1
    fi
    if ! warp_registration_response_valid "${response_file}"; then
      warp_registration_error validate invalid_response '注册响应缺失或不完整；未更改凭据，保留恢复材料且禁止自动重复 POST。'
      return 1
    fi
    candidate=$(mktemp "${receipt}.XXXXXXXX") || return 1
    jq --slurpfile response "${response_file}" '.phase="received" | .response=$response[0]' \
      "${receipt}" > "${candidate}" || return 1
    chmod 600 "${candidate}" && mv -f -- "${candidate}" "${receipt}" || return 1
    candidate=''
  fi
  warp_id=$(jq -r '.id' "${response_file}") || return 1
  warp_token=$(jq -r '.token' "${response_file}") || return 1
  warp_v4=$(jq -r '.config.interface.addresses.v4' "${response_file}") || return 1
  warp_v6=$(jq -r '.config.interface.addresses.v6' "${response_file}") || return 1
  warp_client_id=$(jq -r '.config.client_id' "${response_file}") || return 1
  if write_warp_credentials_atomic "${warp_id}" "${warp_token}" "${priv_key}" "${pub_key}" "${warp_v4}" "${warp_v6}" "${warp_client_id}"; then
    :
  else
    save_status=$?
    warp_registration_error commit credentials_save_failed "请检查凭据最终状态；注册结果已保留在 ${receipt}，再次执行将仅重试保存。" unknown
    return "${save_status}"
  fi
  if ! rm -f -- "${receipt}"; then
    printf '[ERROR] operation=warp_register stage=cleanup code=cleanup_failed changed=true; 凭据已提交，恢复材料尚未清理。\n' >&2
    return 1
  fi
  log_info 'Warp 注册 API 已返回（敏感响应原文未记录）。' >> "${SBV_LOG_FILE}"
  log_success 'Warp 账户注册成功。'
)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
  if [[ "${SB_AGENT_JSON_MODE:-n}" == y ]]; then
    echo -e "${BLUE}[INFO]${NC} $1" >&2
  else
    echo -e "${BLUE}[INFO]${NC} $1"
  fi
  mkdir -p "${SB_PROJECT_DIR}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "${SBV_LOG_FILE}"
}
log_success() {
  if [[ "${SB_AGENT_JSON_MODE:-n}" == y ]]; then
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
  else
    echo -e "${GREEN}[SUCCESS]${NC} $1"
  fi
  mkdir -p "${SB_PROJECT_DIR}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1" >> "${SBV_LOG_FILE}"
}
log_warn() {
  if [[ "${SB_AGENT_JSON_MODE:-n}" == y ]]; then
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
  else
    echo -e "${YELLOW}[WARN]${NC} $1"
  fi
  mkdir -p "${SB_PROJECT_DIR}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "${SBV_LOG_FILE}"
}
log_error() {
  if [[ "${SB_AGENT_JSON_MODE:-n}" == y ]]; then
    echo -e "${RED}[ERROR]${NC} $1" >&2
  else
    echo -e "${RED}[ERROR]${NC} $1"
  fi
  mkdir -p "${SB_PROJECT_DIR}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "${SBV_LOG_FILE}"
  exit 1
}

# Keep stdout available for JSON/command substitution. Labels are fixed caller
# text: never echo command arguments, URLs, credentials or provider responses.
run_with_progress() {
  local label=$1 status=0 timer interval=${SB_PROGRESS_INTERVAL_SECONDS:-5}
  local progress_owner=${BASHPID:-$$}
  shift
  [[ "${interval}" =~ ^[1-9][0-9]*$ ]] || interval=5
  printf '[INFO] %s：开始。\n' "${label}" >&2
  # A fresh Bash prevents the timer from inheriting a caller EXIT trap (for
  # example transaction rollback or the installer's private-directory cleanup).
  # Wait on a private ready pipe before a fast command can terminate it.
  # Its argv contains only the fixed label, interval and process/descriptor IDs.
  local progress_ready_fd progress_ready
  exec {progress_ready_fd}< <(
    trap - EXIT ERR RETURN DEBUG
    BASH_ENV=/dev/null exec "${BASH}" --noprofile --norc -s -- \
    "${progress_owner}" "${interval}" "${label}" "${SB_MANAGEMENT_LOCK_FD:-}" <<'SBV_PROGRESS_TIMER'
  set -euo pipefail
  PROGRESS_OWNER=$1
  PROGRESS_INTERVAL=$2
  PROGRESS_LABEL=$3
  PROGRESS_LOCK_FD=${4:-}
  PROGRESS_ELAPSED=0
  PROGRESS_SLEEPER=""
  if [[ "${PROGRESS_LOCK_FD}" =~ ^[0-9]+$ ]]; then
    exec {PROGRESS_LOCK_FD}>&-
  fi
  progress_finish() {
    trap - EXIT INT TERM HUP
    if [[ -n "${PROGRESS_SLEEPER}" ]]; then
      kill "${PROGRESS_SLEEPER}" 2>/dev/null || :
      wait "${PROGRESS_SLEEPER}" 2>/dev/null || :
    fi
  }
  trap progress_finish EXIT
  trap 'exit 0' TERM INT HUP
  printf 'ready\n' || exit 1
  while kill -0 "${PROGRESS_OWNER}" 2>/dev/null; do
    sleep "${PROGRESS_INTERVAL}" &
    PROGRESS_SLEEPER=$!
    wait "${PROGRESS_SLEEPER}" || exit 0
    PROGRESS_SLEEPER=""
    PROGRESS_ELAPSED=$((PROGRESS_ELAPSED + PROGRESS_INTERVAL))
    if kill -0 "${PROGRESS_OWNER}" 2>/dev/null; then
      printf '[INFO] %s：仍在执行，已等待 %s 秒。\n' "${PROGRESS_LABEL}" "${PROGRESS_ELAPSED}" >&2
    fi
  done
SBV_PROGRESS_TIMER
  )
  timer=$!
  IFS= read -r progress_ready <&"${progress_ready_fd}" || progress_ready=unavailable
  exec {progress_ready_fd}<&-
  if [[ "${progress_ready}" != ready ]]; then
    wait "${timer}" 2>/dev/null || :
    timer=""
    printf '[WARN] 进度计时器无法启动，操作继续执行。\n' >&2
  fi
  "$@" || status=$?
  if [[ -n "${timer}" ]]; then
    kill "${timer}" 2>/dev/null || :
    wait "${timer}" 2>/dev/null || :
  fi
  if [[ "${status}" == 0 ]]; then
    printf '[SUCCESS] %s：完成。\n' "${label}" >&2
  else
    printf '[WARN] %s：失败或中断（状态 %s）；请查看事务结果。\n' "${label}" "${status}" >&2
  fi
  return "${status}"
}

print_info() {
  if [[ "${SB_AGENT_JSON_MODE:-n}" == y ]]; then
    echo -e "${BLUE}[INFO]${NC} $1" >&2
  else
    echo -e "${BLUE}[INFO]${NC} $1"
  fi
}

print_success() {
  if [[ "${SB_AGENT_JSON_MODE:-n}" == y ]]; then
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
  else
    echo -e "${GREEN}[SUCCESS]${NC} $1"
  fi
}

print_warn() {
  if [[ "${SB_AGENT_JSON_MODE:-n}" == y ]]; then
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
  else
    echo -e "${YELLOW}[WARN]${NC} $1"
  fi
}

trim_whitespace() {
  local value=$1
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

normalize_singbox_version_input() {
  local input_version
  input_version=$(trim_whitespace "${1:-}")

  if [[ -z "${input_version}" ]]; then
    printf '%s' "${SB_SUPPORT_MAX_VERSION}"
    return 0
  fi

  if [[ "${input_version}" == "latest" ]]; then
    printf '%s' "${input_version}"
    return 0
  fi

  input_version="${input_version#v}"
  if [[ "${input_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s' "${input_version}"
    return 0
  fi

  return 1
}

singbox_version_at_least() {
  local version=${1#v}
  local minimum=${2#v}
  local version_major version_minor version_patch
  local minimum_major minimum_minor minimum_patch

  [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  [[ "${minimum}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1

  IFS='.' read -r version_major version_minor version_patch <<< "${version}"
  IFS='.' read -r minimum_major minimum_minor minimum_patch <<< "${minimum}"

  if (( 10#${version_major} != 10#${minimum_major} )); then
    (( 10#${version_major} > 10#${minimum_major} ))
    return
  fi

  if (( 10#${version_minor} != 10#${minimum_minor} )); then
    (( 10#${version_minor} > 10#${minimum_minor} ))
    return
  fi

  (( 10#${version_patch} >= 10#${minimum_patch} ))
}

resolve_config_target_singbox_version() {
  local installed_version candidate

  installed_version=$(detect_installed_singbox_version)
  candidate=${installed_version#v}
  if [[ ! "${candidate}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    candidate=${SB_VERSION:-}
  fi
  candidate=${candidate#v}

  if [[ "${candidate}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s' "${candidate}"
    return 0
  fi

  printf '%s' "${SB_SUPPORT_MAX_VERSION}"
}

singbox_config_supports_1_14() {
  local target_version

  target_version=$(resolve_config_target_singbox_version)
  singbox_version_at_least "${target_version}" "${SB_CONFIG_SCHEMA_1_14_MIN_VERSION}"
}

print_cli_help() {
  cat <<'EOF'
用法:
  sbv
  sbv --help
  sbv update sbv
  sbv update sing-box [latest|x.y.z]
  sbv update-sbv
  sbv update-sing-box [latest|x.y.z]
  sbv agent help
  sbv agent capabilities --json
  sbv agent component list|diagnose --json
  sbv agent component export --json --id ID [--expected-revision N]
  sbv agent component recover --json --yes --expected-revision N
  sbv agent component takeover --json --yes --expected-revision N [--allow-public]
  sbv agent component rebuild --json --yes --expected-revision N
  sbv agent component create|replace|delete ...
  sbv agent instance view|diagnose|export vless-reality|mixed|socks|http|shadowsocks|trojan|vmess|vless-plain|anytls|hy2|snell|tuic|hysteria|naive|shadowtls --json [--id ID] [--expected-revision N]
  sbv agent upgrade-check --json x.y.z
  sbv agent upgrade --json x.y.z --yes
  sbv uninstall

说明:
  不带参数时打开交互式管理菜单。
  update sbv                 更新管理脚本 /usr/local/bin/sbv。
  update sing-box            更新 sing-box 二进制并保留现有配置。
  update-sing-box [version]  update sing-box 的短别名，版本可为 latest 或 x.y.z。
  agent                      输出适合自动化读取的 JSON 状态、节点、能力和受保护升级结果。
  agent component            管理高级入站、Endpoint 与可复用出站/分组组件。
  agent instance view/diagnose/export
                             只读查看、诊断或敏感导出受管代理实例；不会迁移或重写状态。
EOF
}

extract_generated_key_value() {
  local output=$1
  local key_kind=$2
  local key_label

  if [[ "${key_kind}" == "private" ]]; then
    key_label='[Pp]rivate'
  else
    key_label='[Pp]ublic'
  fi

  printf '%s\n' "${output}" | sed -nE \
    "s/^[[:space:]]*${key_label}([[:space:]]+|)[Kk]ey[[:space:]]*:?[[:space:]]*([^[:space:]]+)[[:space:]]*$/\\2/p" \
    | head -n 1
}

run_singbox_generate_command() {
  local subcommand=$1
  local label=$2
  local output

  if output=$("${SINGBOX_BIN_PATH}" generate "${subcommand}" 2>&1); then
    printf '%s' "${output}"
    return 0
  else
    local command_status=$?
  fi

  log_info "${label}生成失败（退出码 ${command_status}；原始输出未记录）。" >> "${SBV_LOG_FILE}"
  log_error "${label}生成失败，请查看 ${SBV_LOG_FILE}" >&2
}

validate_warp_route_mode() {
  case "$1" in
    all|selective) return 0 ;;
    *) return 1 ;;
  esac
}

validate_instance_outbound_policy() {
  case "$1" in
    default|direct|warp) return 0 ;;
    *) return 1 ;;
  esac
}

outbound_policy_display_name() {
  case "$1" in
    direct) printf '强制 direct 出口' ;;
    warp) printf '强制 Warp 出口' ;;
    *) printf '跟随全局路由' ;;
  esac
}

prompt_instance_outbound_policy() {
  local prompt=${1:-"请选择出站策略"}
  local current=${2:-default}
  local default_choice choice

  validate_instance_outbound_policy "${current}" || current="default"
  if [[ ! -t 0 ]]; then
    printf '%s' "${current}"
    return 0
  fi

  case "${current}" in
    direct) default_choice=2 ;;
    warp) default_choice=3 ;;
    *) default_choice=1 ;;
  esac

  echo "实例出站策略:" >&2
  echo "1. 跟随全局路由" >&2
  echo "2. 强制 direct 出口" >&2
  echo "3. 强制 Warp 出口" >&2
  choice=$(prompt_choice "${prompt} [1-3] (当前: $(outbound_policy_display_name "${current}")): " 1 3 "${default_choice}") || return 1
  case "${choice}" in
    2) printf 'direct' ;;
    3) printf 'warp' ;;
    *) printf 'default' ;;
  esac
}

validate_inbound_stack_mode() {
  case "$1" in
    ipv4_only|ipv6_only|dual_stack) return 0 ;;
    *) return 1 ;;
  esac
}

validate_outbound_stack_mode() {
  case "$1" in
    ipv4_only|ipv6_only|prefer_ipv4|prefer_ipv6) return 0 ;;
    *) return 1 ;;
  esac
}

inbound_stack_mode_display_name() {
  case "$1" in
    ipv4_only) printf '仅 IPv4' ;;
    ipv6_only) printf '仅 IPv6' ;;
    dual_stack) printf '双栈' ;;
    *) printf '%s' "$1" ;;
  esac
}

outbound_stack_mode_display_name() {
  case "$1" in
    ipv4_only) printf '仅 IPv4' ;;
    ipv6_only) printf '仅 IPv6' ;;
    prefer_ipv4) printf 'IPv4 优先' ;;
    prefer_ipv6) printf 'IPv6 优先' ;;
    *) printf '%s' "$1" ;;
  esac
}

host_ip_stack_display_name() {
  case "$1" in
    dual) printf 'IPv4 / IPv6 双栈' ;;
    ipv6) printf '仅 IPv6' ;;
    *) printf '仅 IPv4' ;;
  esac
}

detect_host_ip_stack() {
  local has_ipv4="n"
  local has_ipv6="n"

  if command -v ip &>/dev/null; then
    # Drain each producer: grep -q can close the pipe before ip finishes,
    # making pipefail mistake SIGPIPE for a missing address family.
    if ip -o -4 addr show scope global 2>/dev/null | grep . >/dev/null; then
      has_ipv4="y"
    fi

    if ip -o -6 addr show scope global 2>/dev/null | grep . >/dev/null; then
      has_ipv6="y"
    fi
  fi

  if [[ "${has_ipv4}" == "y" && "${has_ipv6}" == "y" ]]; then
    printf 'dual'
  elif [[ "${has_ipv6}" == "y" ]]; then
    printf 'ipv6'
  else
    printf 'ipv4'
  fi
}

port_is_in_use() {
  local port=$1

  ss -H -tunlp 2>/dev/null | grep -Eq ":${port}[[:space:]]"
}

pick_random_high_port() {
  local port attempt

  for attempt in $(seq 1 128); do
    port=$((RANDOM % (SB_HIGH_PORT_MAX - SB_HIGH_PORT_MIN + 1) + SB_HIGH_PORT_MIN))
    if ! port_is_in_use "${port}"; then
      printf '%s' "${port}"
      return 0
    fi
  done

  for port in $(seq "${SB_HIGH_PORT_MIN}" "${SB_HIGH_PORT_MAX}"); do
    if ! port_is_in_use "${port}"; then
      printf '%s' "${port}"
      return 0
    fi
  done

  log_error "未找到 ${SB_HIGH_PORT_MIN}-${SB_HIGH_PORT_MAX} 范围内的可用端口。"
}

default_inbound_stack_mode() {
  case "$1" in
    dual) printf 'dual_stack' ;;
    ipv6) printf 'ipv6_only' ;;
    *) printf 'ipv4_only' ;;
  esac
}

default_outbound_stack_mode() {
  printf 'prefer_ipv4'
}

host_supports_inbound_stack_mode() {
  local host_stack=$1
  local inbound_stack_mode=$2

  case "${host_stack}:${inbound_stack_mode}" in
    dual:ipv4_only|dual:ipv6_only|dual:dual_stack|ipv4:ipv4_only|ipv6:ipv6_only) return 0 ;;
    *) return 1 ;;
  esac
}

infer_inbound_stack_mode_from_config() {
  local config_file=$1
  local host_stack=$2
  local listen_address

  listen_address=$(jq -r '.inbounds[0].listen // empty' "${config_file}" 2>/dev/null || true)
  case "${listen_address}" in
    0.0.0.0) printf 'ipv4_only' ;;
    ::)
      if [[ "${host_stack}" == "ipv6" ]]; then
        printf 'ipv6_only'
      else
        printf 'dual_stack'
      fi
      ;;
    *)
      default_inbound_stack_mode "${host_stack}"
      ;;
  esac
}

infer_outbound_stack_mode_from_config() {
  local config_file=$1
  local outbound_stack_mode

  outbound_stack_mode=$(jq -r '.dns.strategy // first(.outbounds[]? | select(.tag == "direct") | .domain_resolver.strategy) // empty' "${config_file}" 2>/dev/null || true)
  if validate_outbound_stack_mode "${outbound_stack_mode}"; then
    printf '%s' "${outbound_stack_mode}"
    return 0
  fi

  default_outbound_stack_mode
}

save_stack_mode_state() {
  mkdir -p "${SB_PROJECT_DIR}"
  cat > "${SB_STACK_STATE_FILE}" <<EOF
STACK_STATE_VERSION=1
INBOUND_STACK_MODE=${SB_INBOUND_STACK_MODE}
OUTBOUND_STACK_MODE=${SB_OUTBOUND_STACK_MODE}
EOF
}

load_stack_mode_state() {
  local host_stack saved_inbound saved_outbound

  host_stack=$(detect_host_ip_stack)
  SB_INBOUND_STACK_MODE=$(default_inbound_stack_mode "${host_stack}")
  SB_OUTBOUND_STACK_MODE=$(default_outbound_stack_mode)

  if [[ -f "${SB_STACK_STATE_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${SB_STACK_STATE_FILE}"
    saved_inbound=${INBOUND_STACK_MODE:-}
    saved_outbound=${OUTBOUND_STACK_MODE:-}

    if validate_inbound_stack_mode "${saved_inbound}" && host_supports_inbound_stack_mode "${host_stack}" "${saved_inbound}"; then
      SB_INBOUND_STACK_MODE="${saved_inbound}"
    fi

    if validate_outbound_stack_mode "${saved_outbound}"; then
      SB_OUTBOUND_STACK_MODE="${saved_outbound}"
    fi
    return 0
  fi

  if [[ -f "${SINGBOX_CONFIG_FILE}" ]]; then
    SB_INBOUND_STACK_MODE=$(infer_inbound_stack_mode_from_config "${SINGBOX_CONFIG_FILE}" "${host_stack}")
    SB_OUTBOUND_STACK_MODE=$(infer_outbound_stack_mode_from_config "${SINGBOX_CONFIG_FILE}")
  fi
}

ensure_stack_mode_state_loaded() {
  local inbound_valid="n"
  local outbound_valid="n"
  local current_inbound=${SB_INBOUND_STACK_MODE:-}
  local current_outbound=${SB_OUTBOUND_STACK_MODE:-}
  local host_stack

  host_stack=$(detect_host_ip_stack)

  if validate_inbound_stack_mode "${current_inbound}" && host_supports_inbound_stack_mode "${host_stack}" "${current_inbound}"; then
    inbound_valid="y"
  fi

  if validate_outbound_stack_mode "${current_outbound}"; then
    outbound_valid="y"
  fi

  if [[ "${inbound_valid}" == "y" && "${outbound_valid}" == "y" ]]; then
    return 0
  fi

  load_stack_mode_state

  if [[ "${inbound_valid}" == "y" ]]; then
    SB_INBOUND_STACK_MODE="${current_inbound}"
  fi

  if [[ "${outbound_valid}" == "y" ]]; then
    SB_OUTBOUND_STACK_MODE="${current_outbound}"
  fi
}
