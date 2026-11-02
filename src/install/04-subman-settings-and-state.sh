
subman_config_file_path() {
  printf '%s/subman.env' "${SB_PROJECT_DIR}"
}

normalize_subman_api_url() {
  local url
  url=$(trim_whitespace "${1:-}")
  while [[ "${url}" == */ ]]; do
    url=${url%/}
  done
  # Accept the deployment address and the common API/node endpoint pastes.
  url=${url%/api/nodes}
  url=${url%/api}
  printf '%s' "${url}"
}

validate_subman_connection_settings() {
  [[ "${SUBMAN_API_URL:-}" =~ ^https?://[^/[:space:]?#@]+(/[^[:space:]?#]*)?$ &&
     -n "${SUBMAN_API_TOKEN:-}" && -n "${SUBMAN_EXPECTED_GIST_ID:-}" &&
     "${SUBMAN_API_TOKEN}" != *$'\n'* && "${SUBMAN_API_TOKEN}" != *$'\r'* ]] || {
    printf '[WARN] SubMan 设置无效：请输入不含账号、查询参数或片段的 HTTP(S) 部署地址，以及 Token 和目标 Gist ID。\n' >&2
    return 1
  }
}

load_subman_config() {
  local config_file
  config_file=$(subman_config_file_path)

  SUBMAN_API_URL=""
  SUBMAN_API_TOKEN=""
  SUBMAN_NODE_PREFIX=""
  SUBMAN_EXPECTED_GIST_ID=""

  [[ -f "${config_file}" ]] || return 0

  # shellcheck disable=SC1090
  source "${config_file}"
  SUBMAN_API_URL=$(normalize_subman_api_url "${SUBMAN_API_URL:-}")
  SUBMAN_API_TOKEN=${SUBMAN_API_TOKEN:-}
  SUBMAN_NODE_PREFIX=$(trim_whitespace "${SUBMAN_NODE_PREFIX:-}")
  SUBMAN_EXPECTED_GIST_ID=$(trim_whitespace "${SUBMAN_EXPECTED_GIST_ID:-}")
}

write_subman_config() {
  local config_file config_dir tmp_file
  SUBMAN_EXPECTED_GIST_ID=$(trim_whitespace "${SUBMAN_EXPECTED_GIST_ID:-}")
  if [[ -z "${SUBMAN_EXPECTED_GIST_ID}" ]]; then
    log_warn "预期 Workspace Gist ID 不能为空；SubMan 配置未修改。"
    return 1
  fi
  SUBMAN_API_URL=$(normalize_subman_api_url "${SUBMAN_API_URL:-}")
  validate_subman_connection_settings || return 1
  config_file=$(subman_config_file_path)
  config_dir=$(dirname "${config_file}")
  mkdir -p "${config_dir}" || return 1
  tmp_file=$(mktemp "${config_dir}/.subman.env.tmp.XXXXXX") || return 1
  if ! chmod 600 "${tmp_file}"; then
    rm -f -- "${tmp_file}"
    return 1
  fi
  if ! {
    write_env_assignment "SUBMAN_API_URL" "${SUBMAN_API_URL}" &&
    write_env_assignment "SUBMAN_API_TOKEN" "${SUBMAN_API_TOKEN}" &&
    write_env_assignment "SUBMAN_NODE_PREFIX" "${SUBMAN_NODE_PREFIX}" &&
    write_env_assignment "SUBMAN_EXPECTED_GIST_ID" "${SUBMAN_EXPECTED_GIST_ID}"
  } > "${tmp_file}"; then
    rm -f -- "${tmp_file}"
    return 1
  fi
  if [[ -f "${config_file}" ]]; then
    if ! cp -p -- "${config_file}" "${config_file}.bak" || ! chmod 600 "${config_file}.bak"; then
      rm -f -- "${tmp_file}"
      return 1
    fi
  fi
  if ! mv -- "${tmp_file}" "${config_file}"; then
    rm -f -- "${tmp_file}"
    return 1
  fi
  chmod 600 "${config_file}"
}

prompt_subman_config_if_needed() {
  local input_url input_token input_prefix input_gist_id

  load_subman_config

  while [[ -z "${SUBMAN_API_URL}" ]]; do
    read -rp "SubMan 部署地址（如 https://subman.example.com）: " input_url || return 1
    SUBMAN_API_URL=$(normalize_subman_api_url "${input_url}")
    [[ -z "${SUBMAN_API_URL}" ]] && log_warn "SubMan API 地址不能为空。"
  done

  while [[ -z "${SUBMAN_API_TOKEN}" ]]; do
    read -rsp "SubMan API Token（输入隐藏）: " input_token || return 1
    printf '\n' >&2
    SUBMAN_API_TOKEN=$(trim_whitespace "${input_token}")
    [[ -z "${SUBMAN_API_TOKEN}" ]] && log_warn "SubMan API Token 不能为空。"
  done

  if [[ -z "${SUBMAN_NODE_PREFIX}" ]]; then
    read -rp "SubMan 同步身份前缀 (默认: $(hostname)): " input_prefix || return 1
    SUBMAN_NODE_PREFIX=$(trim_whitespace "${input_prefix}")
    [[ -z "${SUBMAN_NODE_PREFIX}" ]] && SUBMAN_NODE_PREFIX=$(hostname)
  fi

  while [[ -z "${SUBMAN_EXPECTED_GIST_ID}" ]]; do
    read -rp "预期 SubMan Workspace Gist ID（从目标 Workspace 核对）: " input_gist_id || return 1
    SUBMAN_EXPECTED_GIST_ID=$(trim_whitespace "${input_gist_id}")
    [[ -z "${SUBMAN_EXPECTED_GIST_ID}" ]] && log_warn "预期 Workspace Gist ID 不能为空；请从目标 SubMan Workspace 核对。"
  done

  write_subman_config
}

configure_subman_interactive() (
  local input_url input_token input_prefix input_gist_id old_url old_prefix
  load_subman_config
  old_url=${SUBMAN_API_URL} old_prefix=${SUBMAN_NODE_PREFIX}
  printf 'SubMan 连接设置（留空保留原值；新目标会在保存前只读校验）。\n'
  read -rp "SubMan 部署地址（留空保留）: " input_url || return 1
  if [[ -n "${input_url}" ]]; then SUBMAN_API_URL=$(normalize_subman_api_url "${input_url}"); fi
  if [[ "${SUBMAN_API_URL}" != "${old_url}" ]]; then
    # Never send a saved credential to a different deployment during preflight.
    SUBMAN_API_TOKEN=""
    SUBMAN_EXPECTED_GIST_ID=""
    printf '[INFO] 部署地址已改变，请重新填写 Token 和目标 Gist ID。\n' >&2
  fi
  read -rsp "SubMan API Token（隐藏输入；地址未变时留空保留）: " input_token || return 1
  printf '\n' >&2
  if [[ -n "${input_token}" ]]; then SUBMAN_API_TOKEN=$(trim_whitespace "${input_token}"); fi
  read -rp "同步身份前缀（留空保留；修改会建立新节点身份）: " input_prefix || return 1
  if [[ -n "${input_prefix}" ]]; then SUBMAN_NODE_PREFIX=$(trim_whitespace "${input_prefix}"); fi
  SUBMAN_NODE_PREFIX=${SUBMAN_NODE_PREFIX:-$(hostname)}
  read -rp "目标 Workspace Gist ID（地址改变时必须重新填写；否则留空保留）: " input_gist_id || return 1
  if [[ -n "${input_gist_id}" ]]; then SUBMAN_EXPECTED_GIST_ID=$(trim_whitespace "${input_gist_id}"); fi
  validate_subman_connection_settings || return 1
  if [[ -n "${old_prefix}" && "${SUBMAN_NODE_PREFIX}" != "${old_prefix}" ]]; then
    printf '[INFO] 更换前缀会使用新的 externalKey；旧节点保留，必要时在原目标手动清理。\n' >&2
  fi
  reset_subman_api_result
  if ! preflight_subman_workspace; then
    report_subman_api_failure "连接校验"
    printf '[WARN] 连接或目标 Workspace 校验失败；原 SubMan 设置未修改。\n' >&2
    return 1
  fi
  write_subman_config || return 1
  printf '[SUCCESS] SubMan 设置已保存；原设置备份为 subman.env.bak，未推送或删除任何节点。\n'
)

write_protocol_index() {
  local recorded_version
  recorded_version=$(resolve_protocol_index_singbox_version)
  ensure_protocol_state_dir
  {
    printf 'INSTALLED_PROTOCOLS=%s\n' "$1"
    printf 'PROTOCOL_STATE_VERSION=1\n'
    if [[ -n "${recorded_version}" ]]; then
      printf 'INSTALLED_SINGBOX_VERSION=%s\n' "${recorded_version}"
    fi
  } > "${SB_PROTOCOL_INDEX_FILE}"
}

extract_protocols_from_index() {
  [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]] || return 0
  local installed
  installed=$(grep '^INSTALLED_PROTOCOLS=' "${SB_PROTOCOL_INDEX_FILE}" 2>/dev/null | cut -d'=' -f2- || true)
  installed=${installed//\"/}
  installed=${installed//\'/}
  installed=${installed//\\,/,}
  printf '%s' "${installed}"
}

extract_recorded_singbox_version_from_index() {
  [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]] || return 0

  local recorded_version
  recorded_version=$(grep '^INSTALLED_SINGBOX_VERSION=' "${SB_PROTOCOL_INDEX_FILE}" 2>/dev/null | cut -d'=' -f2- || true)
  recorded_version=${recorded_version//\"/}
  recorded_version=${recorded_version//\'/}
  recorded_version=$(trim_whitespace "${recorded_version}")
  printf '%s' "${recorded_version}"
}

detect_installed_singbox_version() {
  [[ -x "${SINGBOX_BIN_PATH}" ]] || return 0

  local installed_version
  installed_version=$("${SINGBOX_BIN_PATH}" version 2>/dev/null | head -n1 | awk '{print $3}' || true)
  installed_version=$(trim_whitespace "${installed_version}")
  printf '%s' "${installed_version}"
}

singbox_library_path() {
  local bin_dir
  bin_dir=$(dirname "${SINGBOX_BIN_PATH}") || return 1
  printf '%s/lib/libcronet.so' "$(dirname "${bin_dir}")"
}

# Snapshot the optional NaiveProxy runtime separately from the project
# directory.  Core upgrades replace /usr/local/bin/sing-box, while
# libcronet.so lives beside the binary family and therefore needs its own
# rollback record.  The state markers distinguish a managed regular file from
# an unrelated file/symlink that must never be overwritten or removed.
singbox_library_snapshot() {
  local destination=$1
  local lib_path
  local lib_state='absent'
  local marker_state='absent'

  [[ -n "${destination}" && ! -L "${destination}" ]] || return 1
  lib_path=$(singbox_library_path) || return 1
  mkdir -p "${destination}" || return 1

  if [[ -f "${SB_NAIVE_LIBRARY_MARKER}" && ! -L "${SB_NAIVE_LIBRARY_MARKER}" ]]; then
    cp -p -- "${SB_NAIVE_LIBRARY_MARKER}" "${destination}/libcronet.sha256" || return 1
    marker_state='present'
  elif [[ -e "${SB_NAIVE_LIBRARY_MARKER}" || -L "${SB_NAIVE_LIBRARY_MARKER}" ]]; then
    marker_state='unmanaged'
  fi
  if [[ -f "${lib_path}" && ! -L "${lib_path}" ]]; then
    if [[ "${marker_state}" == "present" ]]; then
      cp -p -- "${lib_path}" "${destination}/libcronet.so" || return 1
      lib_state='present'
    else
      lib_state='unmanaged'
    fi
  elif [[ -e "${lib_path}" || -L "${lib_path}" ]]; then
    lib_state='unmanaged'
  fi

  printf '%s\n' "${lib_state}" > "${destination}/library.state" || return 1
  printf '%s\n' "${marker_state}" > "${destination}/marker.state" || return 1
  chmod 600 "${destination}/library.state" "${destination}/marker.state" || return 1
}

singbox_library_restore_snapshot() {
  local snapshot_dir=$1
  local lib_path lib_dir staged expected_hash actual_hash
  local lib_state marker_state
  local status=0

  [[ -d "${snapshot_dir}" && ! -L "${snapshot_dir}" ]] || return 1
  [[ -f "${snapshot_dir}/library.state" && ! -L "${snapshot_dir}/library.state" ]] || return 1
  [[ -f "${snapshot_dir}/marker.state" && ! -L "${snapshot_dir}/marker.state" ]] || return 1
  lib_state=$(tr -d '[:space:]' < "${snapshot_dir}/library.state") || return 1
  marker_state=$(tr -d '[:space:]' < "${snapshot_dir}/marker.state") || return 1
  lib_path=$(singbox_library_path) || return 1
  lib_dir=$(dirname "${lib_path}")

  case "${lib_state}" in
    present)
      [[ -f "${snapshot_dir}/libcronet.so" && ! -L "${snapshot_dir}/libcronet.so" ]] || return 1
      [[ ! -L "${lib_path}" && ! -d "${lib_path}" ]] || return 1
      mkdir -p "${lib_dir}" || return 1
      staged=$(mktemp "${lib_dir}/.libcronet.restore.XXXXXXXX") || return 1
      if ! cp -p -- "${snapshot_dir}/libcronet.so" "${staged}" ||
         ! chmod 0644 "${staged}" ||
         ! mv -f -- "${staged}" "${lib_path}"; then
        rm -f -- "${staged}"
        return 1
      fi
      ;;
    absent)
      if [[ -f "${lib_path}" && ! -L "${lib_path}" ]]; then
        if [[ -f "${SB_NAIVE_LIBRARY_MARKER}" && ! -L "${SB_NAIVE_LIBRARY_MARKER}" ]]; then
          expected_hash=$(tr -d '[:space:]' < "${SB_NAIVE_LIBRARY_MARKER}") || return 1
          actual_hash=$(sha256sum "${lib_path}" | awk '{print $1}') || return 1
          if [[ -n "${expected_hash}" && "${expected_hash}" == "${actual_hash}" ]]; then
            rm -f -- "${lib_path}" || return 1
          else
            status=1
          fi
        fi
      elif [[ -L "${lib_path}" || -d "${lib_path}" ]]; then
        status=1
      fi
      ;;
    unmanaged)
      :
      ;;
    *)
      return 1
      ;;
  esac

  case "${marker_state}" in
    present)
      [[ -f "${snapshot_dir}/libcronet.sha256" && ! -L "${snapshot_dir}/libcronet.sha256" ]] || return 1
      [[ ! -L "${SB_NAIVE_LIBRARY_MARKER}" && ! -d "${SB_NAIVE_LIBRARY_MARKER}" ]] || return 1
      mkdir -p "${SB_PROJECT_DIR}" || return 1
      staged=$(mktemp "${SB_NAIVE_LIBRARY_MARKER}.restore.XXXXXXXX") || return 1
      if ! cp -p -- "${snapshot_dir}/libcronet.sha256" "${staged}" ||
         ! chmod 600 "${staged}" ||
         ! mv -f -- "${staged}" "${SB_NAIVE_LIBRARY_MARKER}"; then
        rm -f -- "${staged}"
        return 1
      fi
      ;;
    absent)
      if [[ -f "${SB_NAIVE_LIBRARY_MARKER}" && ! -L "${SB_NAIVE_LIBRARY_MARKER}" ]]; then
        rm -f -- "${SB_NAIVE_LIBRARY_MARKER}" || return 1
      elif [[ -L "${SB_NAIVE_LIBRARY_MARKER}" || -d "${SB_NAIVE_LIBRARY_MARKER}" ]]; then
        status=1
      fi
      ;;
    unmanaged)
      :
      ;;
    *)
      return 1
      ;;
  esac

  if [[ "${lib_state}" == "present" || "${lib_state}" == "absent" ]] &&
     [[ "$(dirname "${lib_path}")" == "/usr/local/lib" ]] &&
     command -v ldconfig >/dev/null 2>&1; then
    ldconfig || status=1
  fi
  return "${status}"
}

resolve_protocol_index_singbox_version() {
  local installed_version recorded_version

  installed_version=$(detect_installed_singbox_version)
  if [[ -n "${installed_version}" ]]; then
    printf '%s' "${installed_version}"
    return 0
  fi

  recorded_version=$(extract_recorded_singbox_version_from_index)
  if [[ -n "${recorded_version}" ]]; then
    printf '%s' "${recorded_version}"
  fi
}

list_indexed_protocols_raw() {
  local installed protocol
  local protocols=()
  installed=$(extract_protocols_from_index)
  [[ -z "${installed}" ]] && return 0

  IFS=',' read -r -a protocols <<< "${installed}"
  for protocol in "${protocols[@]}"; do
    protocol=$(trim_whitespace "${protocol}")
    [[ -n "${protocol}" ]] && printf '%s\n' "${protocol}"
  done
}

protocol_state_exists() {
  local protocol
  protocol=$(normalize_protocol_id "$1") || return 1
  [[ -f "$(protocol_state_file "${protocol}")" ]]
}

validate_protocol_state_schema() {
  local protocol=$1 state_file=$2 schema
  [[ -f "${state_file}" ]] || return 0
  if [[ "${protocol}" == "mixed" ]]; then
    if grep -Eq "^[[:space:]]*CONFIG_SCHEMA_VERSION=(2|\"2\"|'2')[[:space:]]*$" "${state_file}"; then
      mixed_structured_marker_is_valid "${state_file}" || {
        printf '[ERROR] Mixed schema 2 marker 格式无效；已保留文件，拒绝执行其内容。\n' >&2
        return 1
      }
      return 0
    fi
  fi
  schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${state_file}") || return 1
  schema=${schema//\"/}
  schema=${schema//\'/}
  case "${protocol}:${schema:-1}" in
    vless-reality:1|vless-reality:2|vless-plain:2|mixed:1|mixed:2|socks:2|http:2|shadowsocks:2|trojan:2|vmess:2|hy2:1|hy2:2|anytls:1|anytls:2|snell:2|tuic:2|hysteria:2|naive:2|shadowtls:2) return 0 ;;
  esac
  printf '[ERROR] 协议状态格式无法识别；已保留文件，请使用写入该状态的脚本版本恢复。\n' >&2
  return 1
}

validate_protocol_index_for_rebuild() {
  local schema indexed protocol protocols state_file state_id
  # The rebuild clears legacy .env files, including ones not in the index.
  # Validate their identity before permitting that operation.
  for state_file in "${SB_PROTOCOL_STATE_DIR}"/*.env; do
    [[ -e "${state_file}" ]] || continue
    [[ "${state_file}" == "${SB_PROTOCOL_INDEX_FILE}" ]] && continue
    state_id=${state_file##*/}
    state_id=${state_id%.env}
    if ! protocol=$(normalize_protocol_id "${state_id}") || [[ "${protocol}" != "${state_id}" ]]; then
      printf '[ERROR] 发现未识别的协议状态文件；已保留文件，禁止有损重建，请恢复兼容脚本。\n' >&2
      return 1
    fi
    validate_protocol_state_schema "${protocol}" "${state_file}" || return 1
  done
  [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]] || return 0
  schema=$(sed -n 's/^PROTOCOL_STATE_VERSION=//p' "${SB_PROTOCOL_INDEX_FILE}") || return 1
  schema=${schema//\"/}
  schema=${schema//\'/}
  if [[ "${schema:-1}" != "1" ]]; then
    printf '[ERROR] 协议索引格式无法识别；已保留状态，禁止有损重建，请恢复兼容脚本。\n' >&2
    return 1
  fi
  protocols=$(list_indexed_protocols_raw) || return 1
  while IFS= read -r indexed; do
    [[ -n "${indexed}" ]] || continue
    if ! protocol=$(normalize_protocol_id "${indexed}"); then
      printf '[ERROR] 索引包含未知协议；已保留全部条目，请使用支持该协议的脚本。\n' >&2
      return 1
    fi
    validate_protocol_state_schema "${protocol}" "$(protocol_state_file "${protocol}")" || return 1
  done <<< "${protocols}"
}

reconcile_protocol_index_if_needed() {
  local inventory_state_file=${1:-}
  local indexed_protocols=() valid_protocols=()
  local protocol joined_protocols current_protocols config_protocols

  [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]] || return 0
  validate_protocol_index_for_rebuild || return 1
  validate_live_inbound_inventory "${SINGBOX_CONFIG_FILE}" "${inventory_state_file}" || return 1

  mapfile -t indexed_protocols < <(list_indexed_protocols_raw)
  current_protocols=$(extract_protocols_from_index)

  for protocol in "${indexed_protocols[@]}"; do
    protocol=$(normalize_protocol_id "${protocol}") || return 1
    if protocol_state_exists "${protocol}"; then
      if ! protocol_array_contains "${protocol}" ${valid_protocols[@]+"${valid_protocols[@]}"}; then
        valid_protocols+=("${protocol}")
      fi
    else
      # A stale index entry with no corresponding config is a supported legacy
      # repair. If the live inbound still exists, dropping it would lose data;
      # explicit takeover must reconstruct its state first.
      if [[ -f "${SINGBOX_CONFIG_FILE}" ]]; then
        if ! jq -e 'type == "object"' "${SINGBOX_CONFIG_FILE}" >/dev/null 2>&1 ||
           [[ "$(config_protocol_inbound_count "${protocol}" "${SINGBOX_CONFIG_FILE}" 2>/dev/null || printf 0)" -gt 0 ]]; then
          printf '[ERROR] 协议状态缺失但配置仍需保留；未修改索引，请执行接管以恢复状态。\n' >&2
          return 1
        fi
      fi
      log_warn "检测到无对应状态或运行配置的过期索引条目: ${protocol}" >&2
    fi
  done

  if [[ ${#valid_protocols[@]} -eq 0 ]]; then
    if [[ -f "${SINGBOX_CONFIG_FILE}" ]]; then
      # A retained HY2 revision can coexist with explicitly unowned listeners.
      # Enumerating an empty managed index must not adopt those listeners or
      # erase the tombstone needed by a later create at the current revision.
      if [[ -z "${current_protocols}" ]] && plain_proxy_inactive_store_snapshot hy2 >/dev/null 2>&1; then
        config_protocols=$(list_config_protocols) || return 1
        [[ -n "${config_protocols}" ]] || return 0
      fi
      # Keep the original index in the rebuild snapshot. An empty/unrecognized
      # config or a failed state write must not erase it, even in an if/|| call.
      rebuild_protocol_state_from_config || return $?
    fi
    return 0
  fi

  joined_protocols=$(IFS=,; printf '%s' "${valid_protocols[*]}")
  if [[ "${joined_protocols}" != "${current_protocols}" ]]; then
    write_protocol_index "${joined_protocols}"
  fi
}

list_installed_protocols() {
  reconcile_protocol_index_if_needed "${1:-}" || return $?
  list_indexed_protocols_raw
}

list_exportable_client_protocols() {
  local protocol protocols

  protocols=$(list_installed_protocols) || return 1
  while IFS= read -r protocol; do
    [[ -n "${protocol}" ]] || continue
    if [[ "$(protocol_registry_field "${protocol}" client_export)" == "true" ]]; then
      printf '%s\n' "${protocol}"
    fi
  done <<< "${protocols}"
}

save_vless_reality_state() {
  if [[ -z "${SB_UUID}" ]]; then
    SB_UUID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
  fi

  if [[ -z "${SB_SHORT_ID_1}" ]]; then
    SB_SHORT_ID_1=$(openssl rand -hex 8)
  fi

  if [[ -z "${SB_SHORT_ID_2}" && "${SB_VLESS_PRESERVE_SINGLE_SHORT_ID:-n}" != "y" ]]; then
    SB_SHORT_ID_2=$(openssl rand -hex 8)
  fi

  VLESS_REALITY_DEFAULT_INSTANCE_ID="${VLESS_REALITY_DEFAULT_INSTANCE_ID:-main}"
  VLESS_REALITY_INSTANCE_IDS="${VLESS_REALITY_INSTANCE_IDS:-${SB_VLESS_INSTANCE_ID:-main}}"
  save_vless_reality_protocol_state
  save_vless_reality_instance_state
}

save_mixed_state() {
  local state_file store_file instance_id current_revision record_file candidate_file state_schema
  state_file=$(protocol_state_file "mixed")

  state_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${state_file}" 2>/dev/null | head -n1 || true)
  state_schema=${state_schema//\"/}
  state_schema=${state_schema//\'/}
  if [[ "${state_schema}" == "2" ]]; then
    mixed_structured_state_active || {
      printf '[ERROR] Mixed 结构化状态无效，未写入状态文件。\n' >&2
      return 1
    }
    store_file=$(mixed_structured_store_file) || return 1
    instance_id=${SB_MIXED_INSTANCE_ID:-${SB_INSTANCE_ID:-}}
    if [[ -z "${instance_id}" ]]; then
      instance_id=$(jq -r '.default_instance_id' "${store_file}") || return 1
    fi
    structured_instance_store_validate_id "${instance_id}" || return 1
    current_revision=$(structured_instance_store_revision "${store_file}") || return 1
    record_file=$(mktemp) || return 1
    candidate_file=$(mktemp) || {
      rm -f -- "${record_file}"
      return 1
    }
    if ! jq -c --arg id "${instance_id}" \
        --arg name "${SB_NODE_NAME:-}" \
        --arg port "${SB_PORT:-}" \
        --arg auth_enabled "${SB_MIXED_AUTH_ENABLED:-}" \
        --arg username "${SB_MIXED_USERNAME:-}" \
        --arg password "${SB_MIXED_PASSWORD:-}" \
        --arg outbound_policy "${SB_OUTBOUND_POLICY:-default}" \
        'first(.instances[] | select(.id == $id) |
          .name = $name |
          .listen.port = ($port | tonumber) |
          .authentication = {
            enabled: ($auth_enabled == "y"),
            username: (if $auth_enabled == "y" then $username else "" end),
            password: (if $auth_enabled == "y" then $password else "" end)
          } |
          .outbound_policy = $outbound_policy)' "${store_file}" > "${record_file}"; then
      rm -f -- "${record_file}" "${candidate_file}"
      return 1
    fi
    if [[ ! -s "${record_file}" ]] ||
       ! structured_instance_store_validate_instance_argument "${record_file}"; then
      rm -f -- "${record_file}" "${candidate_file}"
      printf '[ERROR] Mixed 结构化实例记录无效，未写入状态文件。\n' >&2
      return 1
    fi
    if ! structured_instance_store_candidate mixed "${store_file}" replace \
        "${record_file}" "${current_revision}" > "${candidate_file}" ||
       ! publish_structured_instance_store mixed "${candidate_file}" "${current_revision}"; then
      rm -f -- "${record_file}" "${candidate_file}"
      return 1
    fi
    rm -f -- "${record_file}" "${candidate_file}"
    load_mixed_structured_instance "${instance_id}" || return 1
    return 0
  fi

  if [[ -e "$(mixed_structured_store_file)" ]]; then
    printf '[ERROR] 已有 Mixed 结构化状态或 revision 记录；请使用实例管理入口，未覆盖为 legacy 状态。\n' >&2
    return 1
  fi

  {
    write_env_assignment "INSTALLED" "1"
    write_env_assignment "CONFIG_SCHEMA_VERSION" "1"
    write_env_assignment "NODE_NAME" "${SB_NODE_NAME}"
    write_env_assignment "PORT" "${SB_PORT}"
    write_env_assignment "AUTH_ENABLED" "${SB_MIXED_AUTH_ENABLED}"
    write_env_assignment "USERNAME" "${SB_MIXED_USERNAME}"
    write_env_assignment "PASSWORD" "${SB_MIXED_PASSWORD}"
  } > "${state_file}"
}

save_plain_proxy_state() {
  local protocol=${1:-} state_file store_file current_revision
  local record_file candidate_file operation expected_revision
  local listen_address=${SB_MIXED_LISTEN_ADDRESS:-} port=${SB_PORT:-}
  local auth_enabled=${SB_MIXED_AUTH_ENABLED:-y} username=${SB_MIXED_USERNAME:-} password=${SB_MIXED_PASSWORD:-}
  local tag name policy=${SB_OUTBOUND_POLICY:-default} tls_json='{"enabled":false}' auth_json='{}' network_json='["tcp","udp"]' transport_json='{"type":"none"}' client_trust=certificate instance_id=${SB_INSTANCE_ID:-main}
  local snell_version=${SB_SNELL_VERSION:-6} snell_psk=${SB_SNELL_PSK:-} snell_users_json=${SB_SNELL_USER_JSON:-[]} snell_obfs_mode=${SB_SNELL_OBFS_MODE:-} snell_obfs_host=${SB_SNELL_OBFS_HOST:-} snell_mode=${SB_SNELL_MODE:-}
  local tuic_users_json=${SB_TUIC_AUTH_JSON:-[]} tuic_tls_json=${SB_TUIC_TLS_JSON:-'{"enabled":false}'} tuic_client_trust=${SB_TUIC_CLIENT_TRUST:-system}
  local tuic_congestion_control=${SB_TUIC_CONGESTION_CONTROL:-bbr} tuic_auth_timeout_seconds=${SB_TUIC_AUTH_TIMEOUT_SECONDS:-3} tuic_heartbeat_seconds=${SB_TUIC_HEARTBEAT_SECONDS:-10} tuic_zero_rtt_handshake=${SB_TUIC_ZERO_RTT_HANDSHAKE:-n} tuic_udp_relay_mode=${SB_TUIC_UDP_RELAY_MODE:-native} tuic_udp_over_stream=${SB_TUIC_UDP_OVER_STREAM:-n}
  local hysteria_users_json=${SB_HYSTERIA_AUTH_JSON:-[]} hysteria_tls_json=${SB_HYSTERIA_TLS_JSON:-'{"enabled":false}'} hysteria_client_trust=${SB_HYSTERIA_CLIENT_TRUST:-system}
  local hysteria_up_mbps=${SB_HYSTERIA_UP_MBPS:-100} hysteria_down_mbps=${SB_HYSTERIA_DOWN_MBPS:-100} hysteria_obfs_enabled=${SB_HYSTERIA_OBFS_ENABLED:-n} hysteria_obfs_password=${SB_HYSTERIA_OBFS_PASSWORD:-} hysteria_quic_json=${SB_HYSTERIA_QUIC_JSON:-'{"connection_receive_window":"","disable_path_mtu_discovery":false,"initial_packet_size":0,"max_concurrent_streams":0,"stream_receive_window":""}'}
  local naive_users_json=${SB_NAIVE_AUTH_JSON:-[]} naive_tls_json=${SB_NAIVE_TLS_JSON:-'{"enabled":false}'} naive_client_trust=${SB_NAIVE_CLIENT_TRUST:-system}
  local naive_network_json=${SB_NAIVE_NETWORK_JSON:-'["tcp","udp"]'} naive_quic_congestion_control=${SB_NAIVE_QUIC_CONGESTION_CONTROL:-bbr} naive_quic=${SB_NAIVE_QUIC:-n} naive_insecure_concurrency=${SB_NAIVE_INSECURE_CONCURRENCY:-0} naive_stream_receive_window=${SB_NAIVE_STREAM_RECEIVE_WINDOW:-} naive_quic_session_receive_window=${SB_NAIVE_QUIC_SESSION_RECEIVE_WINDOW:-} naive_extra_headers_json=${SB_NAIVE_EXTRA_HEADERS_JSON:-'{}'}

  if [[ "${protocol}" == "shadowtls" ]]; then
    save_shadowtls_state
    return $?
  fi

  structured_instance_store_protocol "${protocol}" >/dev/null || return 1
  case "${protocol}" in
    socks) tag=${SB_MIXED_INBOUND_TAG:-socks-in}; name=${SB_NODE_NAME:-SOCKS} ;;
    http)
      tag=${SB_MIXED_INBOUND_TAG:-http-in}; name=${SB_NODE_NAME:-HTTP}
      [[ -n "${SB_HTTP_TLS_JSON:-}" ]] || return 1
      tls_json=${SB_HTTP_TLS_JSON}
      validate_http_tls_state_json "${tls_json}" || return 1
      ;;
    shadowsocks)
      tag=${SB_MIXED_INBOUND_TAG:-ss-in}; name=${SB_NODE_NAME:-Shadowsocks}
      [[ -n "${SB_SHADOWSOCKS_AUTH_JSON:-}" && -n "${SB_SHADOWSOCKS_NETWORK_JSON:-}" ]] || return 1
      auth_json=${SB_SHADOWSOCKS_AUTH_JSON}; network_json=${SB_SHADOWSOCKS_NETWORK_JSON}
      jq -e 'type == "object"' <<< "${auth_json}" >/dev/null 2>&1 || return 1
      jq -e 'type == "array" and length > 0' <<< "${network_json}" >/dev/null 2>&1 || return 1
      ;;
    trojan)
      tag=${SB_MIXED_INBOUND_TAG:-trojan-in}; name=${SB_NODE_NAME:-Trojan}
      auth_json=${SB_TROJAN_AUTH_JSON:-[]}; tls_json=${SB_TROJAN_TLS_JSON:-'{"enabled":false}'}
      transport_json=${SB_TROJAN_TRANSPORT_JSON:-'{"type":"none"}'}
      client_trust=${SB_TROJAN_CLIENT_TRUST:-certificate}
      jq -e 'type == "array" and length > 0' <<< "${auth_json}" >/dev/null 2>&1 || return 1
      jq -e 'type == "object"' <<< "${tls_json}" >/dev/null 2>&1 || return 1
      jq -e 'type == "object"' <<< "${transport_json}" >/dev/null 2>&1 || return 1
      [[ "${client_trust}" == certificate || "${client_trust}" == system ]] || return 1
      ;;
    vmess)
      tag=${SB_MIXED_INBOUND_TAG:-vmess-in}; name=${SB_NODE_NAME:-VMess}
      auth_json=${SB_VMESS_AUTH_JSON:-[]}; tls_json=${SB_VMESS_TLS_JSON:-'{"enabled":false}'}
      transport_json=${SB_VMESS_TRANSPORT_JSON:-'{"type":"none"}'}
      client_trust=${SB_VMESS_CLIENT_TRUST:-certificate}
      jq -e 'type == "array" and length > 0' <<< "${auth_json}" >/dev/null 2>&1 || return 1
      jq -e 'type == "object"' <<< "${tls_json}" >/dev/null 2>&1 || return 1
      jq -e 'type == "object"' <<< "${transport_json}" >/dev/null 2>&1 || return 1
      [[ "${client_trust}" == certificate || "${client_trust}" == system ]] || return 1
      ;;
    vless-plain)
      tag=${SB_MIXED_INBOUND_TAG:-vless-plain-in}; name=${SB_NODE_NAME:-VLESS}
      auth_json=${SB_VLESS_PLAIN_AUTH_JSON:-[]}; tls_json=${SB_VLESS_PLAIN_TLS_JSON:-'{"enabled":false}'}
      transport_json=${SB_VLESS_PLAIN_TRANSPORT_JSON:-'{"type":"none"}'}
      client_trust=${SB_VLESS_PLAIN_CLIENT_TRUST:-system}
      jq -e 'type == "array" and length > 0' <<< "${auth_json}" >/dev/null 2>&1 || return 1
      jq -e 'type == "object"' <<< "${tls_json}" >/dev/null 2>&1 || return 1
      jq -e 'type == "object"' <<< "${transport_json}" >/dev/null 2>&1 || return 1
      [[ "${client_trust}" == certificate || "${client_trust}" == system ]] || return 1
      ;;
    snell)
      tag=${SB_MIXED_INBOUND_TAG:-snell-in}; name=${SB_NODE_NAME:-Snell}
      snell_version=${SB_SNELL_VERSION:-6}; snell_psk=${SB_SNELL_PSK:-}; snell_users_json=${SB_SNELL_USER_JSON:-[]}
      snell_obfs_mode=${SB_SNELL_OBFS_MODE:-}; snell_obfs_host=${SB_SNELL_OBFS_HOST:-}; snell_mode=${SB_SNELL_MODE:-}
      ensure_snell_materials || return 1
      snell_version=${SB_SNELL_VERSION}; snell_psk=${SB_SNELL_PSK}; snell_users_json=${SB_SNELL_USER_JSON}
      snell_obfs_mode=${SB_SNELL_OBFS_MODE}; snell_obfs_host=${SB_SNELL_OBFS_HOST}; snell_mode=${SB_SNELL_MODE}
      ;;
    tuic)
      tag=${SB_MIXED_INBOUND_TAG:-tuic-in}; name=${SB_NODE_NAME:-TUIC}
      tuic_users_json=${SB_TUIC_AUTH_JSON:-[]}; tuic_tls_json=${SB_TUIC_TLS_JSON:-'{"enabled":false}'}
      tuic_client_trust=${SB_TUIC_CLIENT_TRUST:-system}
      ensure_tuic_materials || return 1
      tuic_users_json=${SB_TUIC_AUTH_JSON}; tuic_tls_json=${SB_TUIC_TLS_JSON}; tuic_client_trust=${SB_TUIC_CLIENT_TRUST}
      tuic_congestion_control=${SB_TUIC_CONGESTION_CONTROL}; tuic_auth_timeout_seconds=${SB_TUIC_AUTH_TIMEOUT_SECONDS}; tuic_heartbeat_seconds=${SB_TUIC_HEARTBEAT_SECONDS}; tuic_zero_rtt_handshake=${SB_TUIC_ZERO_RTT_HANDSHAKE}; tuic_udp_relay_mode=${SB_TUIC_UDP_RELAY_MODE}; tuic_udp_over_stream=${SB_TUIC_UDP_OVER_STREAM}
      ;;
    hysteria)
      tag=${SB_MIXED_INBOUND_TAG:-hysteria-in}; name=${SB_NODE_NAME:-Hysteria}
      hysteria_users_json=${SB_HYSTERIA_AUTH_JSON:-[]}; hysteria_tls_json=${SB_HYSTERIA_TLS_JSON:-'{"enabled":false}'}
      hysteria_client_trust=${SB_HYSTERIA_CLIENT_TRUST:-system}
      hysteria_up_mbps=${SB_HYSTERIA_UP_MBPS:-100}; hysteria_down_mbps=${SB_HYSTERIA_DOWN_MBPS:-100}
      hysteria_obfs_enabled=${SB_HYSTERIA_OBFS_ENABLED:-n}; hysteria_obfs_password=${SB_HYSTERIA_OBFS_PASSWORD:-}
      hysteria_quic_json=${SB_HYSTERIA_QUIC_JSON:-'{"connection_receive_window":"","disable_path_mtu_discovery":false,"initial_packet_size":0,"max_concurrent_streams":0,"stream_receive_window":""}'}
      ensure_hysteria_materials || return 1
      hysteria_users_json=${SB_HYSTERIA_AUTH_JSON}; hysteria_tls_json=${SB_HYSTERIA_TLS_JSON}; hysteria_client_trust=${SB_HYSTERIA_CLIENT_TRUST}
      hysteria_up_mbps=${SB_HYSTERIA_UP_MBPS}; hysteria_down_mbps=${SB_HYSTERIA_DOWN_MBPS}; hysteria_obfs_enabled=${SB_HYSTERIA_OBFS_ENABLED}; hysteria_obfs_password=${SB_HYSTERIA_OBFS_PASSWORD}; hysteria_quic_json=${SB_HYSTERIA_QUIC_JSON}
      ;;
    naive)
      tag=${SB_MIXED_INBOUND_TAG:-naive-in}; name=${SB_NODE_NAME:-NaiveProxy}
      naive_users_json=${SB_NAIVE_AUTH_JSON:-[]}; naive_tls_json=${SB_NAIVE_TLS_JSON:-'{"enabled":false}'}; naive_client_trust=${SB_NAIVE_CLIENT_TRUST:-system}
      naive_network_json=${SB_NAIVE_NETWORK_JSON:-'["tcp","udp"]'}; naive_quic_congestion_control=${SB_NAIVE_QUIC_CONGESTION_CONTROL:-bbr}; naive_quic=${SB_NAIVE_QUIC:-n}
      naive_insecure_concurrency=${SB_NAIVE_INSECURE_CONCURRENCY:-0}; naive_stream_receive_window=${SB_NAIVE_STREAM_RECEIVE_WINDOW:-}; naive_quic_session_receive_window=${SB_NAIVE_QUIC_SESSION_RECEIVE_WINDOW:-}; naive_extra_headers_json=${SB_NAIVE_EXTRA_HEADERS_JSON:-'{}'}
      ensure_naive_materials || return 1
      naive_users_json=${SB_NAIVE_AUTH_JSON}; naive_tls_json=${SB_NAIVE_TLS_JSON}; naive_client_trust=${SB_NAIVE_CLIENT_TRUST}
      naive_network_json=${SB_NAIVE_NETWORK_JSON}; naive_quic_congestion_control=${SB_NAIVE_QUIC_CONGESTION_CONTROL}; naive_quic=${SB_NAIVE_QUIC}
      naive_insecure_concurrency=${SB_NAIVE_INSECURE_CONCURRENCY}; naive_stream_receive_window=${SB_NAIVE_STREAM_RECEIVE_WINDOW}; naive_quic_session_receive_window=${SB_NAIVE_QUIC_SESSION_RECEIVE_WINDOW}; naive_extra_headers_json=${SB_NAIVE_EXTRA_HEADERS_JSON}
      ;;
    *) return 1 ;;
  esac
  state_file=$(protocol_state_file "${protocol}") || return 1
  if [[ -e "${state_file}" || -L "${state_file}" ]]; then
    [[ -f "${state_file}" && ! -L "${state_file}" ]] || return 1
    validate_protocol_state_schema "${protocol}" "${state_file}" || return 1
    plain_proxy_structured_marker_is_valid "${state_file}" || return 1
  fi
  store_file=$(plain_proxy_structured_store_file "${protocol}") || return 1
  if [[ -f "${state_file}" ]]; then
    [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  elif [[ -e "${store_file}" || -L "${store_file}" ]]; then
    plain_proxy_inactive_store_snapshot "${protocol}" >/dev/null || return 1
  fi
  [[ -n "${listen_address}" ]] || listen_address=${SB_DEFAULT_LISTEN_ADDRESS}
  structured_instance_store_validate_id "${instance_id}" || return 1
  [[ -n "${tag}" ]] || return 1
  validate_port_number "${port}" || return 1
  structured_instance_store_validate_address "${listen_address}" || return 1
  if [[ "${protocol}" != shadowsocks && "${protocol}" != snell && "${protocol}" != tuic && "${protocol}" != hysteria && "${protocol}" != naive ]]; then
    case "${auth_enabled}" in y|n) ;; *) return 1 ;; esac
  fi
  if [[ "${protocol}" == http ]]; then
    validate_http_client_connection "${port}" "${auth_enabled}" "${username}" "${password}" || return 1
  elif [[ "${protocol}" != shadowsocks && "${protocol}" != snell && "${protocol}" != tuic && "${protocol}" != hysteria && "${protocol}" != naive && "${protocol}" != trojan && "${protocol}" != vmess && "${protocol}" != vless-plain ]]; then
    validate_mixed_client_connection "${port}" "${auth_enabled}" "${username}" "${password}" || return 1
  fi
  [[ "${policy}" == default || "${policy}" == direct || "${policy}" == warp ]] || return 1
  if [[ "${protocol}" == http || "${protocol}" == trojan || "${protocol}" == vmess || "${protocol}" == vless-plain || "${protocol}" == tuic || "${protocol}" == hysteria || "${protocol}" == naive ]]; then
    jq -e 'type == "object"' <<< "${tls_json}" >/dev/null 2>&1 || return 1
  fi

  record_file=$(mktemp) || return 1
  candidate_file=$(mktemp) || { rm -f -- "${record_file}"; return 1; }
  if ! jq -n -cS --arg id "${instance_id}" --arg name "${name}" --arg tag "${tag}" \
      --arg address "${listen_address}" --argjson port "${port}" \
      --argjson enabled "$([[ "${auth_enabled}" == y ]] && printf true || printf false)" \
      --arg username "${username}" --arg password "${password}" --arg policy "${policy}" --argjson tls "${tls_json}" --argjson auth "${auth_json}" --argjson network "${network_json}" --argjson transport "${transport_json}" --arg client_trust "${client_trust}" --arg protocol "${protocol}" \
      --argjson snell_version "${snell_version}" --arg snell_psk "${snell_psk}" --argjson snell_users "${snell_users_json}" --arg snell_obfs_mode "${snell_obfs_mode}" --arg snell_obfs_host "${snell_obfs_host}" --arg snell_mode "${snell_mode}" \
      --argjson tuic_users "${tuic_users_json}" --argjson tuic_tls "${tuic_tls_json}" --arg tuic_trust "${tuic_client_trust}" --arg tuic_cc "${tuic_congestion_control}" --argjson tuic_auth_timeout "${tuic_auth_timeout_seconds}" --argjson tuic_heartbeat "${tuic_heartbeat_seconds}" --argjson tuic_zero_rtt "$([[ "${tuic_zero_rtt_handshake}" == y ]] && printf true || printf false)" --arg tuic_relay "${tuic_udp_relay_mode}" --argjson tuic_uos "$([[ "${tuic_udp_over_stream}" == y ]] && printf true || printf false)" \
      --argjson hysteria_users "${hysteria_users_json}" --argjson hysteria_tls "${hysteria_tls_json}" --arg hysteria_trust "${hysteria_client_trust}" --argjson hysteria_up "${hysteria_up_mbps}" --argjson hysteria_down "${hysteria_down_mbps}" --argjson hysteria_obfs_enabled "$([[ "${hysteria_obfs_enabled}" == y ]] && printf true || printf false)" --arg hysteria_obfs_password "${hysteria_obfs_password}" --argjson hysteria_quic "${hysteria_quic_json}" \
      --argjson naive_users "${naive_users_json}" --argjson naive_tls "${naive_tls_json}" --arg naive_trust "${naive_client_trust}" --argjson naive_network "${naive_network_json}" --arg naive_cc "${naive_quic_congestion_control}" --argjson naive_quic "$([[ "${naive_quic}" == y ]] && printf true || printf false)" --argjson naive_insecure_concurrency "${naive_insecure_concurrency}" --arg naive_stream_receive_window "${naive_stream_receive_window}" --arg naive_quic_session_receive_window "${naive_quic_session_receive_window}" --argjson naive_extra_headers "${naive_extra_headers_json}" \
      '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},authentication:{enabled:$enabled,username:(if $enabled then $username else "" end),password:(if $enabled then $password else "" end)},outbound_policy:$policy,dependencies:[]} + (if $protocol == "http" then {tls:$tls} elif $protocol == "shadowsocks" then {listen:{address:$address,port:$port,network:$network},authentication:$auth} elif $protocol == "trojan" or $protocol == "vmess" or $protocol == "vless-plain" then {authentication:{users:$auth},tls:$tls,transport:$transport,client_trust:$client_trust} elif $protocol == "snell" then {version:$snell_version,authentication:{psk:$snell_psk,users:$snell_users},obfs_mode:$snell_obfs_mode,obfs_host:$snell_obfs_host,mode:$snell_mode} elif $protocol == "tuic" then {authentication:{users:$tuic_users},tls:$tuic_tls,client_trust:$tuic_trust,tuic:{auth_timeout_seconds:$tuic_auth_timeout,congestion_control:$tuic_cc,heartbeat_seconds:$tuic_heartbeat,udp_over_stream:$tuic_uos,udp_relay_mode:$tuic_relay,zero_rtt_handshake:$tuic_zero_rtt}} elif $protocol == "hysteria" then {authentication:{users:$hysteria_users},tls:$hysteria_tls,client_trust:$hysteria_trust,bandwidth:{up_mbps:$hysteria_up,down_mbps:$hysteria_down},obfs:{enabled:$hysteria_obfs_enabled,password:$hysteria_obfs_password},hysteria:$hysteria_quic} elif $protocol == "naive" then {authentication:{users:$naive_users},tls:$naive_tls,client_trust:$naive_trust,listen:{address:$address,port:$port,network:$naive_network},naive:{quic_congestion_control:$naive_cc,quic:$naive_quic,insecure_concurrency:$naive_insecure_concurrency,stream_receive_window:$naive_stream_receive_window,quic_session_receive_window:$naive_quic_session_receive_window,extra_headers:$naive_extra_headers}} else {} end)' > "${record_file}"; then
    rm -f -- "${record_file}" "${candidate_file}"; return 1
  fi
  structured_instance_store_validate_instance_argument "${record_file}" "${protocol}" || {
    rm -f -- "${record_file}" "${candidate_file}"; return 1;
  }
  if [[ -f "${store_file}" ]]; then
    validate_structured_instance_store "${protocol}" "${store_file}" || { rm -f -- "${record_file}" "${candidate_file}"; return 1; }
    current_revision=$(structured_instance_store_revision "${store_file}") || { rm -f -- "${record_file}" "${candidate_file}"; return 1; }
    expected_revision=${current_revision}
    if jq -e --arg id "${instance_id}" 'any(.instances[]; .id == $id)' "${store_file}" >/dev/null 2>&1; then operation=replace; else operation=create; fi
    structured_instance_store_candidate "${protocol}" "${store_file}" "${operation}" "${record_file}" "${expected_revision}" > "${candidate_file}" || {
      rm -f -- "${record_file}" "${candidate_file}"; return 1;
    }
  else
    structured_instance_store_candidate "${protocol}" "" create "${record_file}" 0 > "${candidate_file}" || {
      rm -f -- "${record_file}" "${candidate_file}"; return 1;
    }
    expected_revision=0
  fi
  if ! publish_structured_instance_store "${protocol}" "${candidate_file}" "${expected_revision}" ||
     ! save_plain_proxy_structured_marker "${protocol}"; then
    rm -f -- "${record_file}" "${candidate_file}"; return 1
  fi
  rm -f -- "${record_file}" "${candidate_file}"
  load_plain_proxy_structured_instance "${protocol}" "${instance_id}"
}

save_socks_state() { save_plain_proxy_state socks; }
save_http_state() { save_plain_proxy_state http; }
save_shadowsocks_state() { save_plain_proxy_state shadowsocks; }
save_trojan_state() { save_plain_proxy_state trojan; }
save_vmess_state() { save_plain_proxy_state vmess; }
save_vless_plain_state() { save_plain_proxy_state vless-plain; }

save_hy2_state() {
  local state_file
  state_file=$(protocol_state_file "hy2")

  {
    write_env_assignment "INSTALLED" "1"
    write_env_assignment "CONFIG_SCHEMA_VERSION" "1"
    write_env_assignment "NODE_NAME" "${SB_NODE_NAME}"
    write_env_assignment "PORT" "${SB_PORT}"
    write_env_assignment "DOMAIN" "${SB_HY2_DOMAIN}"
    write_env_assignment "PASSWORD" "${SB_HY2_PASSWORD}"
    write_env_assignment "USER_NAME" "${SB_HY2_USER_NAME}"
    write_env_assignment "UP_MBPS" "${SB_HY2_UP_MBPS}"
    write_env_assignment "DOWN_MBPS" "${SB_HY2_DOWN_MBPS}"
    write_env_assignment "OBFS_ENABLED" "${SB_HY2_OBFS_ENABLED}"
    write_env_assignment "OBFS_TYPE" "${SB_HY2_OBFS_TYPE}"
    write_env_assignment "OBFS_PASSWORD" "${SB_HY2_OBFS_PASSWORD}"
    write_env_assignment "TLS_MODE" "${SB_HY2_TLS_MODE}"
    write_env_assignment "ACME_MODE" "${SB_HY2_ACME_MODE}"
    write_env_assignment "ACME_EMAIL" "${SB_HY2_ACME_EMAIL}"
    write_env_assignment "ACME_DOMAIN" "${SB_HY2_ACME_DOMAIN}"
    write_env_assignment "ACME_EXTRA_JSON" "$(acme_extra_json_or_default "${SB_HY2_ACME_EXTRA_JSON:-}")"
    write_env_assignment "DNS_PROVIDER" "${SB_HY2_DNS_PROVIDER}"
    write_env_assignment "CF_API_TOKEN" "${SB_HY2_CF_API_TOKEN}"
    write_env_assignment "CERT_PATH" "${SB_HY2_CERT_PATH}"
    write_env_assignment "KEY_PATH" "${SB_HY2_KEY_PATH}"
    write_env_assignment "MASQUERADE" "${SB_HY2_MASQUERADE}"
  } > "${state_file}"
}

save_anytls_state() {
  local state_file
  state_file=$(protocol_state_file "anytls")

  {
    write_env_assignment "INSTALLED" "1"
    write_env_assignment "CONFIG_SCHEMA_VERSION" "1"
    write_env_assignment "NODE_NAME" "${SB_NODE_NAME}"
    write_env_assignment "PORT" "${SB_PORT}"
    write_env_assignment "DOMAIN" "${SB_ANYTLS_DOMAIN}"
    write_env_assignment "PASSWORD" "${SB_ANYTLS_PASSWORD}"
    write_env_assignment "USER_NAME" "${SB_ANYTLS_USER_NAME}"
    write_env_assignment "TLS_MODE" "${SB_ANYTLS_TLS_MODE}"
    write_env_assignment "ACME_MODE" "${SB_ANYTLS_ACME_MODE}"
    write_env_assignment "ACME_EMAIL" "${SB_ANYTLS_ACME_EMAIL}"
    write_env_assignment "ACME_DOMAIN" "${SB_ANYTLS_ACME_DOMAIN}"
    write_env_assignment "ACME_EXTRA_JSON" "$(acme_extra_json_or_default "${SB_ANYTLS_ACME_EXTRA_JSON:-}")"
    write_env_assignment "DNS_PROVIDER" "${SB_ANYTLS_DNS_PROVIDER}"
    write_env_assignment "CF_API_TOKEN" "${SB_ANYTLS_CF_API_TOKEN}"
    write_env_assignment "CERT_PATH" "${SB_ANYTLS_CERT_PATH}"
    write_env_assignment "KEY_PATH" "${SB_ANYTLS_KEY_PATH}"
  } > "${state_file}"
}

save_snell_state() {
  save_plain_proxy_state snell
}

save_tuic_state() {
  save_plain_proxy_state tuic
}

save_hysteria_state() {
  save_plain_proxy_state hysteria
}

save_naive_state() {
  save_plain_proxy_state naive
}

save_shadowtls_state() {
  local state_file store_file record_file candidate_file current_file current_revision expected_revision operation
  local instance_id=${SB_INSTANCE_ID:-main} tag=${SB_MIXED_INBOUND_TAG:-shadowtls-in} name=${SB_NODE_NAME:-ShadowTLS}
  local address=${SB_MIXED_LISTEN_ADDRESS:-${SB_DEFAULT_LISTEN_ADDRESS}} port=${SB_PORT:-443} policy=${SB_OUTBOUND_POLICY:-default}
  local version=${SB_SHADOWTLS_VERSION:-3} password=${SB_SHADOWTLS_PASSWORD:-} users=${SB_SHADOWTLS_AUTH_JSON:-[]}
  local handshake=${SB_SHADOWTLS_HANDSHAKE_JSON:-'{"server":"","server_port":443}'}
  local handshake_map=${SB_SHADOWTLS_HANDSHAKE_FOR_SERVER_NAME_JSON:-'{}'} strict_mode=${SB_SHADOWTLS_STRICT_MODE:-n}
  local wildcard_sni=${SB_SHADOWTLS_WILDCARD_SNI:-off} detour_tag detour_port=${SB_SHADOWTLS_DETOUR_PORT:-}
  local trust=${SB_SHADOWTLS_CLIENT_TRUST:-system} client_tls=${SB_SHADOWTLS_CLIENT_TLS_JSON:-'{"enabled":true,"server_name":"","certificate_path":""}'}
  local client_server_name client_certificate_path

  structured_instance_store_validate_id "${instance_id}" || return 1
  [[ -n "${tag}" ]] || return 1
  validate_port_number "${port}" || return 1
  structured_instance_store_validate_address "${address}" || return 1
  [[ "${version}" =~ ^[123]$ ]] || return 1
  [[ "${strict_mode}" == y || "${strict_mode}" == n ]] || return 1
  [[ "${wildcard_sni}" == off || "${wildcard_sni}" == authed || "${wildcard_sni}" == all ]] || return 1
  [[ "${trust}" == system || "${trust}" == certificate ]] || return 1
  [[ -n "${detour_port}" ]] || detour_port=$(pick_random_high_port) || return 1
  validate_port_number "${detour_port}" || return 1
  [[ "${detour_port}" != "${port}" ]] || return 1
  detour_tag="shadowtls-inner-${instance_id}"
  jq -e 'type == "array"' <<< "${users}" >/dev/null 2>&1 || return 1
  jq -e 'type == "object"' <<< "${handshake}" >/dev/null 2>&1 || return 1
  jq -e 'type == "object"' <<< "${handshake_map}" >/dev/null 2>&1 || return 1
  client_server_name=$(jq -r '.server_name // empty' <<< "${client_tls}") || return 1
  client_certificate_path=$(jq -r '.certificate_path // ""' <<< "${client_tls}") || return 1
  [[ -n "${client_server_name}" ]] || return 1
  if [[ "${trust}" == system ]]; then
    client_certificate_path=""
  else
    [[ "${client_certificate_path}" == /* ]] || return 1
  fi

  state_file=$(protocol_state_file shadowtls) || return 1
  store_file=$(plain_proxy_structured_store_file shadowtls) || return 1
  if [[ -e "${state_file}" || -L "${state_file}" ]]; then
    [[ -f "${state_file}" && ! -L "${state_file}" ]] || return 1
    plain_proxy_structured_marker_is_valid "${state_file}" || return 1
  fi
  if [[ -f "${store_file}" ]]; then
    validate_structured_instance_store shadowtls "${store_file}" || return 1
    current_revision=$(structured_instance_store_revision "${store_file}") || return 1
    expected_revision=${current_revision}
    if jq -e --arg id "${instance_id}" 'any(.instances[]; .id == $id)' "${store_file}" >/dev/null 2>&1; then operation=replace; else operation=create; fi
  else
    current_revision=0
    expected_revision=0
    operation=create
    current_file=""
  fi
  [[ -n "${current_file:-}" ]] || current_file="${store_file}"
  if [[ ! -f "${current_file}" ]]; then current_file=""; fi

  record_file=$(mktemp) || return 1
  candidate_file=$(mktemp) || { rm -f -- "${record_file}"; return 1; }
  if ! jq -n -cS --arg id "${instance_id}" --arg name "${name}" --arg tag "${tag}" --arg address "${address}" --argjson port "${port}" \
      --argjson version "${version}" --arg password "${password}" --argjson users "${users}" --argjson handshake "${handshake}" \
      --argjson handshake_map "${handshake_map}" --argjson strict_mode "$([[ "${strict_mode}" == y ]] && printf true || printf false)" \
      --arg wildcard_sni "${wildcard_sni}" --arg detour_tag "${detour_tag}" --argjson detour_port "${detour_port}" \
      --arg trust "${trust}" --arg server_name "${client_server_name}" --arg certificate_path "${client_certificate_path}" --arg policy "${policy}" \
      '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},version:$version,authentication:{password:$password,users:$users},handshake:$handshake,handshake_for_server_name:$handshake_map,strict_mode:$strict_mode,wildcard_sni:$wildcard_sni,detour:{tag:$detour_tag,listen:{address:"127.0.0.1",port:$detour_port}},dependencies:[$detour_tag],client_trust:$trust,client_tls:{server_name:$server_name,certificate_path:$certificate_path},outbound_policy:$policy}' > "${record_file}"; then
    rm -f -- "${record_file}" "${candidate_file}"; return 1
  fi
  structured_instance_store_validate_instance_argument "${record_file}" shadowtls || { rm -f -- "${record_file}" "${candidate_file}"; return 1; }
  if ! structured_instance_store_candidate shadowtls "${current_file}" "${operation}" "${record_file}" "${expected_revision}" > "${candidate_file}"; then
    rm -f -- "${record_file}" "${candidate_file}"; return 1
  fi
  if ! publish_structured_instance_store shadowtls "${candidate_file}" "${expected_revision}" || ! save_plain_proxy_structured_marker shadowtls; then
    rm -f -- "${record_file}" "${candidate_file}"; return 1
  fi
  rm -f -- "${record_file}" "${candidate_file}"
  load_plain_proxy_structured_instance shadowtls "${instance_id}"
}

save_protocol_state() {
  local protocol
  protocol=$(normalize_protocol_id "$1") || return 1
  ensure_protocol_state_dir || return 1

  case "${protocol}" in
    vless-reality) save_vless_reality_state ;;
    mixed) save_mixed_state ;;
    socks) save_socks_state ;;
    http) save_http_state ;;
    shadowsocks) save_shadowsocks_state ;;
    trojan) save_trojan_state ;;
    vmess) save_vmess_state ;;
    vless-plain) save_vless_plain_state ;;
    hy2) save_hy2_state ;;
    anytls) save_anytls_state ;;
    snell) save_snell_state ;;
    tuic) save_tuic_state ;;
    hysteria) save_hysteria_state ;;
    naive) save_naive_state ;;
    shadowtls) save_shadowtls_state ;;
    *) log_error "不支持的协议状态保存类型: ${protocol}" ;;
  esac
}

migrate_legacy_single_protocol_state_if_needed() {
  [[ -f "${SINGBOX_CONFIG_FILE}" ]] || return 0
  if [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    # Older single-Mixed installations can retain an index without mixed.env.
    # Recover only in the explicit additional-install workflow, never as a
    # side effect of protocol enumeration. Do not discard the index first:
    # the existing rebuild transaction must restore it on any failure.
    [[ "${1:-}" == "recover-incomplete-index" ]] || return 0
    validate_protocol_index_for_rebuild || return 1
    [[ "$(list_indexed_protocols_raw)" == "mixed" ]] || return 0
    local state_entry
    for state_entry in "${SB_PROTOCOL_STATE_DIR}"/* "${SB_PROTOCOL_STATE_DIR}"/.[!.]* "${SB_PROTOCOL_STATE_DIR}"/..?*; do
      [[ -e "${state_entry}" || -L "${state_entry}" ]] || continue
      [[ "${state_entry}" == "${SB_PROTOCOL_INDEX_FILE}" ]] || return 0
    done
    # Only the legacy single-user, default-tag/listener shape is losslessly
    # represented by this old state format. Custom fields require takeover.
    jq -e --arg listen "$(stack_inbound_listen_address)" '
      (.inbounds | type == "array" and length == 1) and
      (.inbounds[0] |
        .type == "mixed" and .tag == "mixed-in" and
        ((keys - ["type", "tag", "listen", "listen_port", "users"]) | length == 0) and
        ((has("listen") | not) or .listen == $listen) and
        (.listen_port | type == "number" and . == floor and . >= 1 and . <= 65535) and
        ((.users // []) | type == "array" and length <= 1 and
          all(.[]; type == "object" and
            ((keys - ["username", "password"]) | length == 0) and
            (.username | type == "string" and length > 0) and
            (.password | type == "string" and length > 0))))
    ' "${SINGBOX_CONFIG_FILE}" >/dev/null 2>&1 || return 0
  fi
  rebuild_protocol_state_from_config || return 1
  migrate_vless_reality_state_to_instances_if_needed
}

list_retained_instance_protocols() {
  local protocol
  while IFS= read -r protocol; do
    structured_instance_store_protocol "${protocol}" >/dev/null || continue
    if plain_proxy_inactive_store_snapshot "${protocol}" >/dev/null 2>&1; then
      printf '%s\n' "${protocol}"
    fi
  done < <(list_registered_protocols)
}

instance_management_empty_config_baseline() {
  local state_file indexed inbound
  [[ -f "${SINGBOX_CONFIG_FILE}" && ! -L "${SINGBOX_CONFIG_FILE}" ]] || return 1
  jq -e 'type == "object" and (.inbounds | type == "array")' "${SINGBOX_CONFIG_FILE}" >/dev/null || return 1
  while IFS= read -r inbound; do
    manual_client_inbound_is_unmanaged "${inbound}" || return 1
  done < <(jq -c '.inbounds[]' "${SINGBOX_CONFIG_FILE}")
  validate_protocol_index_for_rebuild || return 1
  indexed=$(list_indexed_protocols_raw) || return 1
  [[ -z "${indexed}" ]] || return 1
  for state_file in "${SB_PROTOCOL_STATE_DIR}"/*.env; do
    [[ -e "${state_file}" ]] || continue
    [[ "${state_file}" == "${SB_PROTOCOL_INDEX_FILE}" ]] || return 1
  done
}

prompt_installed_protocol_selection() {
  local protocols=() retained_protocols=() choice selected_protocol index protocol
  if [[ "${2:-n}" != y ]]; then
    mapfile -t protocols < <(list_installed_protocols)
  fi
  IFS=',' read -r -a retained_protocols <<< "${1:-}"
  for protocol in ${retained_protocols[@]+"${retained_protocols[@]}"}; do
    if ! protocol_array_contains "${protocol}" ${protocols[@]+"${protocols[@]}"}; then
      protocols+=("${protocol}")
    fi
  done

  if [[ ${#protocols[@]} -eq 0 ]]; then
    log_error "当前未检测到已安装协议。"
  fi

  while true; do
    echo -e "\n${BLUE}--- 已安装协议 ---${NC}"
    for index in "${!protocols[@]}"; do
      selected_protocol=$(state_protocol_to_runtime "${protocols[$index]}")
      if protocol_array_contains "${protocols[$index]}" ${retained_protocols[@]+"${retained_protocols[@]}"}; then
        echo "$((index + 1)). $(protocol_display_name "${selected_protocol}")（暂无实例，可重新创建）"
      else
        echo "$((index + 1)). $(protocol_display_name "${selected_protocol}")"
      fi
    done
    echo "0. 返回"
    choice=$(prompt_choice "请选择 [0-${#protocols[@]}]: " 0 "${#protocols[@]}" "")

    if [[ "${choice}" == "0" ]]; then
      return 0
    fi

    if [[ "${choice}" =~ ^[1-9][0-9]*$ ]] && (( choice >= 1 && choice <= ${#protocols[@]} )); then
      SELECTED_PROTOCOL="${protocols[$((choice - 1))]}"
      return 0
    fi

    log_warn "无效选项，请重新选择。"
  done
}
