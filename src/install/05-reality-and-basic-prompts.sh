
prompt_vless_reality_update() {
  local in_node in_p in_uuid current_port

  read -rp "新节点名称 (当前: ${SB_NODE_NAME}, 留空保持): " in_node || return 1
  in_node=$(trim_whitespace "${in_node:-}")
  [[ -n "${in_node}" ]] && SB_NODE_NAME="${in_node}"

  current_port="${SB_PORT}"
  in_p=$(prompt_port "新端口 (当前: ${SB_PORT}, 留空保持): " "${SB_PORT}") || return 1
  if [[ "${in_p}" != "${current_port}" ]]; then
    if [[ "${in_p}" != "${current_port}" ]] && port_in_configured_protocol_state "${in_p}"; then
      log_error "端口已被现有协议配置占用: ${in_p}"
    fi
    SB_PORT="${in_p}"
    check_port_conflict "${SB_PORT}"
  fi

  read -rp "新 UUID (当前: ${SB_UUID}, 留空保持): " in_uuid || return 1
  in_uuid=$(trim_whitespace "${in_uuid:-}")
  [[ -n "${in_uuid}" ]] && SB_UUID="${in_uuid}"

  prompt_reality_sni_update || return 1
  prompt_vless_reality_rate_limit_update_fields || return 1
  prompt_vless_reality_advanced_update_fields || return 1
  validate_current_reality_sni_alpn_or_warn
  # Node routing is edited from the unified rules menu; preserve this instance.
  return 0
}

validate_reality_sni_syntax() {
  local domain=${1:-}

  [[ -n "${domain}" && ${#domain} -le 253 ]] || return 1
  [[ "${domain}" != *"://"* ]] || return 1
  [[ "${domain}" != *"/"* ]] || return 1
  [[ "${domain}" != *":"* ]] || return 1
  [[ "${domain}" != *[[:space:]]* ]] || return 1
  [[ "${domain}" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

probe_reality_sni_tls() {
  local domain=$1
  local output timeout_cmd=()

  if ! validate_reality_sni_syntax "${domain}"; then
    printf 'SNI 必须是纯域名，例如 www.example.com'
    return 1
  fi

  if ! command -v openssl >/dev/null 2>&1; then
    printf '未检测到 openssl，无法执行 TLS 1.3/证书校验'
    return 1
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout_cmd=(timeout 7)
  fi

  if ! output=$(printf '' | "${timeout_cmd[@]}" openssl s_client \
    -connect "${domain}:443" \
    -servername "${domain}" \
    -verify_hostname "${domain}" \
    -verify_return_error \
    -tls1_3 \
    -brief 2>&1); then
    if grep -qi 'certificate verify failed\|hostname mismatch\|verify error' <<< "${output}"; then
      printf 'TLS 证书校验失败或证书主机名不匹配'
    elif grep -qi 'wrong version number\|protocol version\|tlsv1 alert protocol version\|no protocols available' <<< "${output}"; then
      printf '目标站点未成功协商 TLS 1.3'
    elif grep -qi 'timed out\|timeout' <<< "${output}"; then
      printf '连接 443/TLS 超时'
    else
      printf '无法完成 443/TLS 1.3 握手'
    fi
    return 1
  fi

  if ! grep -Eqi 'Protocol version: TLSv1\.3|Protocol[[:space:]]*:[[:space:]]*TLSv1\.3' <<< "${output}"; then
    printf '目标站点未成功协商 TLS 1.3'
    return 1
  fi

  return 0
}

probe_reality_sni_alpn() {
  local domain=$1
  local mode=${2:-off}
  local alpn_value output timeout_cmd=()

  case "${mode}" in
    h2_http1) alpn_value="h2,http/1.1" ;;
    http1) alpn_value="http/1.1" ;;
    off|"") return 0 ;;
    *)
      printf '未知 ALPN 预设: %s' "${mode}"
      return 1
      ;;
  esac

  if ! validate_reality_sni_syntax "${domain}"; then
    printf 'SNI 必须是纯域名，例如 www.example.com'
    return 1
  fi

  if ! command -v openssl >/dev/null 2>&1; then
    printf '未检测到 openssl，无法执行 ALPN 校验'
    return 1
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout_cmd=(timeout 7)
  fi

  if ! output=$(printf '' | "${timeout_cmd[@]}" openssl s_client \
    -connect "${domain}:443" \
    -servername "${domain}" \
    -tls1_3 \
    -alpn "${alpn_value}" 2>&1); then
    printf '无法完成 ALPN/TLS 1.3 握手'
    return 1
  fi

  case "${mode}" in
    h2_http1)
      grep -Eq 'ALPN protocol: (h2|http/1\.1)' <<< "${output}" || {
        printf '目标站点未协商 h2 或 http/1.1'
        return 1
      }
      ;;
    http1)
      grep -Eq 'ALPN protocol: http/1\.1' <<< "${output}" || {
        printf '目标站点未协商 http/1.1'
        return 1
      }
      ;;
  esac
}

confirm_reality_sni_warning_continue() {
  local reason=$1
  local choice

  log_warn "Reality SNI 校验未通过：${reason}" >&2
  if [[ "${SB_REALITY_SNI_VALIDATION_ASSUME_YES:-0}" == "1" ]]; then
    log_warn "当前为非交互输入，已继续使用该 SNI。" >&2
    return 0
  fi

  choice=$(prompt_yes_no "是否仍然继续使用该 SNI [y/n] (默认 n): " "n")
  [[ "${choice}" == "y" ]]
}

read_manual_reality_sni_with_validation() {
  local default_sni=$1
  local prompt=$2
  local manual_sni reason

  while true; do
    read -rp "${prompt}" manual_sni || return 1
    manual_sni=$(trim_whitespace "${manual_sni:-}")
    manual_sni=${manual_sni:-${default_sni}}

    if ! validate_reality_sni_syntax "${manual_sni}"; then
      log_warn "SNI 必须是纯域名，不含 URL、端口或路径；请重新输入。" >&2
      continue
    fi
    if reason=$(probe_reality_sni_tls "${manual_sni}"); then
      SB_SNI="${manual_sni}"
      return 0
    fi

    if confirm_reality_sni_warning_continue "${reason}"; then
      SB_SNI="${manual_sni}"
      return 0
    fi
  done
}

validate_current_reality_sni_alpn_or_warn() {
  local reason

  SB_VLESS_ALPN_MODE="${SB_VLESS_ALPN_MODE:-off}"
  validate_vless_reality_alpn_mode "${SB_VLESS_ALPN_MODE}" || SB_VLESS_ALPN_MODE="off"

  if [[ "${SB_VLESS_ALPN_MODE}" == "off" ]]; then
    return 0
  fi

  if reason=$(probe_reality_sni_alpn "${SB_SNI}" "${SB_VLESS_ALPN_MODE}"); then
    log_success "Reality SNI ALPN 校验通过: ${SB_SNI} ($(vless_reality_alpn_mode_display_name "${SB_VLESS_ALPN_MODE}"))"
    return 0
  fi

  if ! confirm_reality_sni_warning_continue "${reason}"; then
    log_warn "已关闭 ALPN 预设以避免继续使用不兼容的 SNI/ALPN 组合。"
    SB_VLESS_ALPN_MODE="off"
  fi
}

# The checker is pinned to reviewed source until its first Release is published.
# A fixed digest verifies the downloaded bytes before any code is executed.
prepare_reality_target_checker() {
  local destination=$1 staged digest dependency
  staged="${destination}.part"
  if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
    log_warn "reality-target-checker 需要 Bash >= 4.3；可改用手动 SNI 校验。" >&2
    return 1
  fi
  for dependency in bash curl openssl dig jq timeout sha256sum mktemp date; do
    if ! command -v "${dependency}" >/dev/null 2>&1; then
      log_warn "SNI 探测缺少依赖 ${dependency}（dig 由 Debian/Ubuntu 的 dnsutils 或 RHEL 系的 bind-utils 提供）。可安装依赖后重试或手动输入。" >&2
      return 1
    fi
  done
  if ! curl --disable --fail --silent --show-error --location --max-redirs 3 \
    --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 60 \
    --retry 2 --output "${staged}" "${SB_REALITY_CHECKER_URL}" 2>/dev/null; then
    log_warn "SNI 探测器下载失败，未执行远程内容，SNI 未变更。" >&2
    rm -f -- "${staged}" || return 1
    return 1
  fi
  digest=$(sha256sum -- "${staged}") || { rm -f -- "${staged}"; return 1; }
  if [[ "${digest%% *}" != "${SB_REALITY_CHECKER_SHA256}" ]] || ! bash -n "${staged}"; then
    log_warn "SNI 探测器完整性或语法校验失败，未执行远程内容，SNI 未变更。" >&2
    rm -f -- "${staged}" || return 1
    return 1
  fi
  mv -- "${staged}" "${destination}" || return 1
}

# Discovery is opt-in. Check-only use neither downloads nor requires Python.
# The caller owns this private directory and never executes a partial bundle.
prepare_reality_target_discovery() {
  local directory=$1 filename expected staged digest
  if ! command -v python3 >/dev/null 2>&1 ||
    ! python3 -c 'import sys; raise SystemExit(sys.version_info < (3, 9))' 2>/dev/null; then
    log_warn "候选发现需要 Python >= 3.9；可安装后重试，或使用候选域名检测/手动 SNI 校验。" >&2
    return 1
  fi
  [[ -d "${directory}" && ! -L "${directory}" ]] || return 1
  prepare_reality_target_checker "${directory}/reality-target-checker.sh" || return $?
  for filename in reality-target-discover.py reality-target-sources.py; do
    case "${filename}" in
      reality-target-discover.py) expected=${SB_REALITY_DISCOVER_SHA256} ;;
      reality-target-sources.py) expected=${SB_REALITY_SOURCES_SHA256} ;;
    esac
    staged="${directory}/${filename}.part"
    if ! curl --disable --fail --silent --show-error --location --max-redirs 3 \
      --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 60 \
      --retry 2 --output "${staged}" \
      "https://raw.githubusercontent.com/KnowSky404/reality-target-checker/${SB_REALITY_CHECKER_COMMIT}/${filename}" 2>/dev/null; then
      log_warn "候选发现模块下载失败，未执行远程内容，SNI 未变更。" >&2
      rm -f -- "${staged}" || return 1
      return 1
    fi
    digest=$(sha256sum -- "${staged}") || { rm -f -- "${staged}"; return 1; }
    # Parsing Python syntax must not import or execute downloaded top-level code.
    if [[ "${digest%% *}" != "${expected}" ]] ||
      ! python3 -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_bytes(), filename=sys.argv[1])' "${staged}" 2>/dev/null; then
      log_warn "候选发现模块完整性或语法校验失败，未执行远程内容，SNI 未变更。" >&2
      rm -f -- "${staged}" || return 1
      return 1
    fi
    mv -- "${staged}" "${directory}/${filename}" || return 1
  done
}

# Stop only the running checker's own descendants, including the separate
# process groups created by its per-operation GNU timeout commands.
stop_reality_checker_process_tree() {
  local process_id=$1 child children_file attempt children_pending
  local children=()
  [[ "${process_id}" =~ ^[1-9][0-9]*$ ]] || return 1
  children_file="/proc/${process_id}/task/${process_id}/children"
  if [[ -r "${children_file}" ]]; then
    # proc's children record has no trailing newline; read still fills the array.
    if read -r -a children < "${children_file}"; then :; fi
  fi
  # Bash 4.3 treats an empty array expansion as unset under nounset.
  if (( ${#children[@]} > 0 )); then
    for child in "${children[@]}"; do
      stop_reality_checker_process_tree "${child}" || return 1
    done
    # Keep the owner alive long enough to reap its children. Terminating a
    # timeout/group leader first can kill the Bash checker before its nested
    # timeout tree is inspected, leaving a live grandchild behind.
    for ((attempt=0;attempt<20;attempt++)); do
      children_pending=n
      for child in "${children[@]}"; do
        [[ ! -e "/proc/${child}" ]] || children_pending=y
      done
      [[ "${children_pending}" == y ]] || break
      command sleep 0.01 || return 1
    done
  fi
  if kill -0 "${process_id}" 2>/dev/null; then
    if ! kill -TERM "${process_id}" 2>/dev/null; then
      if kill -0 "${process_id}" 2>/dev/null; then
        log_warn "SNI 探测子进程无法终止，SNI 未变更。" >&2
        return 1
      fi
    fi
  fi
}

run_reality_target_check() (
  local checker=$1 domain=$2 report=$3 checker_dir checker_pid="" signal_status=0 result=0
  checker_dir=$(dirname -- "${checker}") || return 1
  trap 'signal_status=130; if [[ -n "${checker_pid}" ]]; then stop_reality_checker_process_tree "${checker_pid}"; fi' INT
  trap 'signal_status=143; if [[ -n "${checker_pid}" ]]; then stop_reality_checker_process_tree "${checker_pid}"; fi' TERM
  trap 'signal_status=129; if [[ -n "${checker_pid}" ]]; then stop_reality_checker_process_tree "${checker_pid}"; fi' HUP
  # Own nested temp files even if the deadline escalates to KILL. Waiting on a
  # background child lets traps run immediately on terminal cancellation.
  (( signal_status == 0 )) || return "${signal_status}"
  storage_enter_module_workspace "${checker_dir}" || return 1
  TMPDIR="${checker_dir}" timeout --signal=TERM --kill-after=2 90 \
    bash "${checker}" check "${domain}" --json --timeout 3 > "${report}" &
  checker_pid=$!
  if (( signal_status != 0 )); then
    stop_reality_checker_process_tree "${checker_pid}" || return 1
  fi
  wait "${checker_pid}" || result=$?
  if (( signal_status != 0 )); then
    # The first wait can be interrupted before timeout has reaped the checker.
    if wait "${checker_pid}"; then :; fi
    return "${signal_status}"
  fi
  return "${result}"
)

run_reality_target_discovery() (
  local checker=$1 report=$2 mode=$3 scope=$4 asn=${5:-}
  local checker_dir checker_pid="" timer_pid="" signal_status=0 result=0 deadline
  local args=(discover)
  case "${mode}" in
    plan)
      [[ "${scope}" =~ ^[1-9][0-9]{0,9}$ && -z "${asn}" ]] || return 2
      (( 10#${scope} <= 4294967295 )) || return 2
      args+=(--asn "${scope}" --plan-only)
      deadline=30
      ;;
    scan)
      [[ "${scope}" =~ ^[0-9.]+/[0-9]+$ ]] || return 2
      args+=("${scope}")
      if [[ -n "${asn}" ]]; then
        [[ "${asn}" =~ ^[1-9][0-9]{0,9}$ ]] || return 2
        (( 10#${asn} <= 4294967295 )) || return 2
        args+=(--asn "${asn}")
      fi
      deadline=315
      ;;
    *) return 2 ;;
  esac
  args+=(--json --timeout 3 --max-hosts 256 --concurrency 8 --rate 10
    --max-candidates 256 --samples 1 --deadline 300)
  checker_dir=$(dirname -- "${checker}") || return 1
  trap 'signal_status=130; if [[ -n "${checker_pid}" ]]; then stop_reality_checker_process_tree "${checker_pid}"; fi' INT
  trap 'signal_status=143; if [[ -n "${checker_pid}" ]]; then stop_reality_checker_process_tree "${checker_pid}"; fi' TERM
  trap 'signal_status=129; if [[ -n "${checker_pid}" ]]; then stop_reality_checker_process_tree "${checker_pid}"; fi' HUP
  (( signal_status == 0 )) || return "${signal_status}"
  storage_enter_module_workspace "${checker_dir}" || return 1
  TMPDIR="${checker_dir}" PYTHONDONTWRITEBYTECODE=1 \
    timeout --signal=TERM --kill-after=2 "${deadline}" \
    bash "${checker}" "${args[@]}" > "${report}" 2>"${report}.stderr" &
  checker_pid=$!
  # Timer output stays on stderr, and the parent stops/reaps it immediately
  # after the checker; a fast result never waits for a heartbeat interval.
  (
    trap - EXIT ERR RETURN DEBUG INT TERM HUP
    local elapsed=0
    while kill -0 "${checker_pid}" 2>/dev/null; do
      if ! sleep 1; then break; fi
      elapsed=$((elapsed + 1))
      if (( elapsed % 10 == 0 )) && kill -0 "${checker_pid}" 2>/dev/null; then
        log_info "候选发现仍在执行，已等待 ${elapsed} 秒。" >&2
      fi
    done
    # Child-first cleanup can interrupt a logging child while the checker
    # finishes; normal timer completion must not inherit that child's status.
    return 0
  ) &
  timer_pid=$!
  if (( signal_status != 0 )); then
    stop_reality_checker_process_tree "${checker_pid}" || result=1
  fi
  wait "${checker_pid}" || result=$?
  if (( signal_status != 0 )); then
    if wait "${checker_pid}"; then :; fi
  fi
  stop_reality_checker_process_tree "${timer_pid}" || result=1
  if wait "${timer_pid}"; then :; else
    case $? in 143) ;; *) result=1 ;; esac
  fi
  (( signal_status == 0 )) || return "${signal_status}"
  return "${result}"
)

validate_reality_target_report() {
  local report=$1 domain=$2 status=$3
  [[ "${status}" == 0 || "${status}" == 3 ]] || return 1
  jq -s -e --arg domain "${domain}" --arg version "${SB_REALITY_CHECKER_VERSION}" --argjson status "${status}" '
    length == 1 and (.[0] |
    .schema_version == "1.0" and .tool_version == $version and
    .target == $domain and .sni == $domain and .port == 443 and
    .summary.exit_code == $status and
    .summary.status == (if $status == 0 then "PASS" else "WARN" end) and
    .summary.basic_tls == "PASS" and .summary.compatibility == "PASS" and
    .selection.scope == "dns" and .selection.complete == true and
    (.risks | type == "array") and (.unknowns | type == "array") and
    (.endpoints | type == "array" and length > 0 and length <= 16 and
      all(.[]; . as $endpoint |
        (.checks | type == "array") and
        all(["tcp443", "tls13", "cert_chain", "cert_san", "cert_validity", "alpn_h2", "x25519"][];
          . as $id | [$endpoint.checks[] | select(.id == $id)] |
          length == 1 and .[0].status == "PASS"))) and
    (if $status == 0 then (.risks | length == 0) and (.unknowns | length == 0) else true end))
  ' "${report}" >/dev/null 2>&1
}

select_reality_sni_candidate() (
  # Subshell-local traps leave the installer's management/transaction traps intact.
  umask 077
  local temp_dir domain status choice risk_ids interrupted_status=0
  [[ $# -gt 0 && $# -le 5 ]] || return 1
  for domain in "$@"; do
    validate_reality_sni_syntax "${domain}" || return 1
  done
  temp_dir=$(storage_mktemp -d) || return 1
  trap 'rm -rf -- "${temp_dir}"' EXIT
  trap 'interrupted_status=130; log_warn "SNI 探测中断，SNI 未变更。" >&2; return 130' INT
  trap 'interrupted_status=143; log_warn "SNI 探测中断，SNI 未变更。" >&2; return 143' TERM
  trap 'interrupted_status=129; log_warn "SNI 探测中断，SNI 未变更。" >&2; return 129' HUP
  prepare_reality_target_checker "${temp_dir}/checker.sh" || return $?
  (( interrupted_status == 0 )) || return "${interrupted_status}"
  for domain in "$@"; do
    domain=${domain,,}
    log_info "reality-target-checker 探测 ${domain}（A/AAAA，每个域名最多 90 秒）..." >&2
    status=0
    run_reality_target_check "${temp_dir}/checker.sh" "${domain}" "${temp_dir}/report.json" \
      2> "${temp_dir}/checker.stderr" || status=$?
    (( interrupted_status == 0 )) || return "${interrupted_status}"
    case "${status}" in 129|130|137|143) return "${status}" ;; esac
    if ! validate_reality_target_report "${temp_dir}/report.json" "${domain}" "${status}"; then
      log_warn "${domain} 未通过探测或报告无效（退出码 ${status}），未选择该域名。" >&2
      continue
    fi
    if [[ "${status}" == 3 ]]; then
      # Only render bounded check IDs, never network-supplied reason/redirect text.
      risk_ids=$(jq -r '[.risks[], .unknowns[]] | map(.id | select(type == "string" and test("^[a-zA-Z0-9_]{1,40}$"))) | unique | join(", ")' "${temp_dir}/report.json") || return 1
      log_warn "${domain} 基础 TLS 和 h2/X25519 通过；附加风险或未知项: ${risk_ids:-unavailable}。ASN/CDN 检测不能保证目标不存在共享网络风险。" >&2
      choice=$(prompt_yes_no "是否接受这些附加风险并使用 ${domain} [y/n] (默认 n): " "n") || return 1
      [[ "${choice}" == y ]] || continue
    fi
    (( interrupted_status == 0 )) || return "${interrupted_status}"
    printf '%s' "${domain}"
    return 0
  done
  log_warn "没有通过并获接受的候选 SNI；SNI 未变更，不回退固定域名。" >&2
  return 1
)

validate_reality_discovery_cidr() {
  local cidr=$1 plan=${2:-}
  python3 - "${cidr}" "${plan}" <<'PY'
import ipaddress
import json
import re
import sys

try:
    value, plan = sys.argv[1:]
    if not re.fullmatch(r"[0-9.]+/(?:2[4-9]|3[0-2])", value):
        raise ValueError
    network = ipaddress.IPv4Network(value, strict=True)
    if plan:
        with open(plan, encoding="utf-8") as source:
            prefixes = json.load(source)["asn"]["prefixes_v4"]
        if not any(network.subnet_of(ipaddress.IPv4Network(prefix, strict=True)) for prefix in prefixes):
            raise ValueError
except (ValueError, KeyError, TypeError, OSError):
    sys.exit(1)
PY
}

validate_reality_discovery_plan() {
  local report=$1 asn=$2 status=$3
  [[ "${status}" == 0 ]] || return 1
  jq -s -e --arg version "${SB_REALITY_CHECKER_VERSION}" --argjson asn "${asn}" '
    length == 1 and (.[0] |
      .schema_version == "1.0" and .tool_version == $version and
      .report_type == "discovery_plan" and .requires_selection == true and
      .asn.asn == $asn and .asn.status == "PASS" and
      .summary.status == "PASS" and .summary.exit_code == 0 and
      .scope.selection == "cidr_hosts" and .scope.prefixes == [] and
      .scope.host_count == 0 and .targets == [] and .seeds == [])
  ' "${report}" >/dev/null 2>&1 || return 1
  # Validate every prefix before displaying provider-supplied data or using it
  # as a scope constraint. The plan itself never authorizes an active scan.
  python3 - "${report}" <<'PY'
import ipaddress
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as source:
        prefixes = json.load(source)["asn"]["prefixes_v4"]
    if not isinstance(prefixes, list) or not 0 < len(prefixes) <= 65536:
        raise ValueError
    for value in prefixes:
        if not isinstance(value, str) or str(ipaddress.IPv4Network(value, strict=True)) != value:
            raise ValueError
except (ValueError, KeyError, TypeError, OSError):
    sys.exit(1)
PY
}

validate_reality_discovery_report() {
  local report=$1 cidr=$2 status=$3 asn=${4:-}
  [[ "${status}" == 0 || "${status}" == 3 ]] || return 1
  jq -s -e --arg version "${SB_REALITY_CHECKER_VERSION}" --arg cidr "${cidr}" \
    --arg asn "${asn}" --argjson status "${status}" '
    length == 1 and (.[0] |
      .schema_version == "1.0" and .tool_version == $version and .report_type == "discovery" and
      .summary.exit_code == $status and
      .summary.status == (if $status == 0 then "PASS" else "WARN" end) and
      .scope.cidr == $cidr and .scope.prefixes == [$cidr] and
      .scope.selection == "cidr_hosts" and .scope.within_budget == true and
      .scope.requires_known_ipv6 == false and
      .scope.limits.max_hosts == 256 and .scope.limits.samples == 1 and
      .scan.complete == true and .scan.reasons == [] and
      (.candidates | type == "array" and length > 0 and length <= 256 and
        all(.[]; (.eligible | type == "boolean") and (.sni | type == "string"))) and
      (if $asn == "" then true else
        .plan.asn.status == "PASS" and (.plan.asn.asn | tostring) == $asn end))
  ' "${report}" >/dev/null 2>&1 || return 1
  # Fixed-IP verdicts are only domain seeds. Check scope membership here, then
  # rerun a complete DNS-scoped check before the domain can become an SNI.
  python3 - "${report}" "${cidr}" <<'PY'
import ipaddress
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as source:
        report = json.load(source)
    network = ipaddress.IPv4Network(sys.argv[2], strict=True)
    count = network.num_addresses if network.prefixlen >= 31 else network.num_addresses - 2
    hosts = report["hosts"]
    if (type(report["scope"]["host_count"]) is not int or not 1 <= count <= 256
            or report["scope"]["host_count"] != count or not isinstance(hosts, list)
            or len(hosts) != count or report["scan"]["hosts_completed"] != count):
        raise ValueError
    expected = {str(ip) for ip in network.hosts()}
    if {host["ip"] for host in hosts} != expected or any(host["completed"] is not True for host in hosts):
        raise ValueError
    for candidate in report["candidates"]:
        if candidate["ip"] not in expected:
            raise ValueError
except (ValueError, KeyError, TypeError, OSError):
    sys.exit(1)
PY
}

select_reality_sni_discovery() (
  umask 077
  local mode=${1:-} scope=${2:-} cidr=${3:-} asn="" temp_dir status domain names selected_sni
  local runner_pid="" interrupted_status=0
  local candidates=()
  # Every potentially blocking phase has an owned child. This lets a signal
  # sent only to the selector (not its process group) cancel downloads, discovery
  # and final DNS checks without waiting for their individual network deadlines.
  run_reality_discovery_owned_phase() {
    local phase_status=0
    (( interrupted_status == 0 )) || return "${interrupted_status}"
    (
      trap - EXIT ERR RETURN DEBUG INT TERM HUP
      "$@"
    ) <&0 &
    runner_pid=$!
    if (( interrupted_status != 0 )); then
      stop_reality_checker_process_tree "${runner_pid}" || phase_status=1
    fi
    wait "${runner_pid}" || phase_status=$?
    if (( interrupted_status != 0 )); then
      if wait "${runner_pid}"; then :; fi
    fi
    runner_pid=""
    (( interrupted_status == 0 )) || return "${interrupted_status}"
    return "${phase_status}"
  }
  case "${mode}" in
    cidr) cidr=${scope} ;;
    asn)
      asn=${scope^^}
      asn=${asn#AS}
      [[ "${asn}" =~ ^[1-9][0-9]{0,9}$ ]] && (( 10#${asn} <= 4294967295 )) || {
        log_warn "ASN 必须为 1 至 4294967295 的整数，可带 AS 前缀；SNI 未变更。" >&2
        return 1
      }
      ;;
    *) return 1 ;;
  esac
  if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))'; then
    log_warn "候选发现需要 Python >= 3.9；可改用候选域名检测或手动输入。" >&2
    return 1
  fi
  if [[ "${mode}" == cidr || -n "${cidr}" ]] && ! validate_reality_discovery_cidr "${cidr}"; then
    log_warn "请输入严格对齐的 IPv4 CIDR（/24 至 /32，最多 256 个主机）；SNI 未变更。" >&2
    return 1
  fi
  temp_dir=$(storage_mktemp -d) || return 1
  trap 'rm -rf -- "${temp_dir}"' EXIT
  trap 'interrupted_status=130; if [[ -n "${runner_pid}" ]]; then stop_reality_checker_process_tree "${runner_pid}"; fi; log_warn "候选发现中断，SNI 未变更。" >&2' INT
  trap 'interrupted_status=143; if [[ -n "${runner_pid}" ]]; then stop_reality_checker_process_tree "${runner_pid}"; fi; log_warn "候选发现中断，SNI 未变更。" >&2' TERM
  trap 'interrupted_status=129; if [[ -n "${runner_pid}" ]]; then stop_reality_checker_process_tree "${runner_pid}"; fi; log_warn "候选发现中断，SNI 未变更。" >&2' HUP
  run_reality_discovery_owned_phase prepare_reality_target_discovery "${temp_dir}" || return $?
  if [[ "${mode}" == asn ]]; then
    log_info "查询 AS${asn} 的 IPv4 公告计划（尚未扫描目标端口）..." >&2
    status=0
    run_reality_discovery_owned_phase run_reality_target_discovery \
      "${temp_dir}/reality-target-checker.sh" "${temp_dir}/plan.json" plan "${asn}" || status=$?
    case "${status}" in 129|130|137|143) return "${status}" ;; esac
    if ! validate_reality_discovery_plan "${temp_dir}/plan.json" "${asn}" "${status}"; then
      log_warn "ASN 计划不可用或没有可用 IPv4 公告，未开始扫描；SNI 未变更。" >&2
      return 1
    fi
    log_info "公告前缀（最多显示 20 项；可输入其中更小的子网；公告快照不保证实时独占归属）:" >&2
    jq -r '.asn.prefixes_v4[:20][]' "${temp_dir}/plan.json" >&2 || return 1
    if [[ -z "${cidr}" ]]; then
      read -rp "明确选择要扫描的 IPv4 CIDR（/24 至 /32；留空取消）: " cidr || {
        (( interrupted_status == 0 )) || return "${interrupted_status}"
        return 1
      }
      cidr=$(trim_whitespace "${cidr}")
    fi
    if ! validate_reality_discovery_cidr "${cidr}" "${temp_dir}/plan.json"; then
      log_warn "网段无效、超出主机预算或不在本次 ASN 公告内，未开始扫描；SNI 未变更。" >&2
      return 1
    fi
  fi
  log_info "发现范围 ${cidr}：最多 256 主机、并发 8、每秒启动 10 个任务、总预算 300 秒。" >&2
  status=0
  run_reality_discovery_owned_phase run_reality_target_discovery \
    "${temp_dir}/reality-target-checker.sh" "${temp_dir}/discovery.json" scan "${cidr}" "${asn}" || status=$?
  case "${status}" in 129|130|137|143) return "${status}" ;; esac
  if ! validate_reality_discovery_report "${temp_dir}/discovery.json" "${cidr}" "${status}" "${asn}"; then
    log_warn "候选发现没有完整可用报告（退出码 ${status}），SNI 未变更。" >&2
    return 1
  fi
  names=$(jq -r '.candidates[] | select(.eligible == true) | .sni |
    select(test("^[a-zA-Z0-9.-]{1,253}\\z"))' "${temp_dir}/discovery.json") || return 1
  while IFS= read -r domain; do
    domain=${domain,,}
    validate_reality_sni_syntax "${domain}" || continue
    if (( ${#candidates[@]} > 0 )) && [[ " ${candidates[*]} " == *" ${domain} "* ]]; then
      continue
    fi
    candidates+=("${domain}")
    [[ ${#candidates[@]} -lt 5 ]] || break
  done <<< "${names}"
  if [[ ${#candidates[@]} == 0 ]]; then
    log_warn "本次有限发现没有可复核的候选域名；SNI 未变更。" >&2
    return 1
  fi
  log_info "对前 ${#candidates[@]} 个去重候选重新执行完整 DNS 检测；固定 IP 发现结果不能替代域名检查。" >&2
  if run_reality_discovery_owned_phase select_reality_sni_candidate "${candidates[@]}" > "${temp_dir}/selected-sni"; then
    selected_sni=$(cat -- "${temp_dir}/selected-sni") || return 1
    (( interrupted_status == 0 )) || return "${interrupted_status}"
    printf '%s' "${selected_sni}"
  else
    return $?
  fi
)

prompt_reality_target_discovery() {
  local choice scope selected_sni
  echo "候选发现只扫描明确选择的 IPv4 网段（/24 至 /32）；ASN 查询先生成计划，再选择网段。"
  echo "1. 输入 IPv4 CIDR (默认)"
  echo "2. 查询 ASN 公告后选择 IPv4 CIDR"
  choice=$(prompt_choice "请选择 [1-2] (默认 1): " 1 2 1) || return 1
  if [[ "${choice}" == 2 ]]; then
    read -rp "ASN（例如 AS64500；留空取消）: " scope || return 1
    choice=asn
  else
    read -rp "要扫描的 IPv4 CIDR（最多 256 主机；留空取消）: " scope || return 1
    choice=cidr
  fi
  scope=$(trim_whitespace "${scope}")
  [[ -n "${scope}" ]] || return 1
  if selected_sni=$(select_reality_sni_discovery "${choice}" "${scope}"); then
    SB_SNI="${selected_sni}"
    log_success "已选择 Reality SNI: ${SB_SNI}"
  else
    return $?
  fi
}

reality_region_candidate_records() {
  local region=${1:-} record
  case "${region}" in HK|US-LAX|DE-FRA|JP-TYO|KR-SEL) ;; *) return 1 ;; esac
  for record in "${SB_REALITY_REGION_CANDIDATES[@]}"; do
    if [[ "${record}" == "${region}|"* ]]; then
      printf '%s\n' "${record}"
    fi
  done
}

prompt_reality_region_candidates() {
  local choice region records record_region category institution domain category_label selected_sni
  local candidates=()
  echo "地区按机构所在地分组；实际解析 IP / ASN 或 CDN 节点可能位于其他地区。"
  echo "1. HK 中国-香港"
  echo "2. US-LAX 美国-洛杉矶"
  echo "3. DE-FRA 德国-法兰克福"
  echo "4. JP-TYO 日本-东京"
  echo "5. KR-SEL 韩国-首尔"
  echo "0. 返回"
  choice=$(prompt_choice "请选择地区 [0-5] (默认 0): " 0 5 0) || return 1
  case "${choice}" in
    1) region=HK ;;
    2) region=US-LAX ;;
    3) region=DE-FRA ;;
    4) region=JP-TYO ;;
    5) region=KR-SEL ;;
    *) return 1 ;;
  esac
  records=$(reality_region_candidate_records "${region}") || return 1
  echo "${region} 候选官网（仍须检测；不代表已通过或适合 REALITY）:"
  while IFS='|' read -r record_region category institution domain; do
    [[ "${record_region}" == "${region}" ]] && validate_reality_sni_syntax "${domain}" || return 1
    case "${category}" in
      bank) category_label=银行 ;;
      government) category_label=政府 ;;
      university) category_label=学校 ;;
      *) return 1 ;;
    esac
    printf '  [%s] %s: %s\n' "${category_label}" "${institution}" "${domain}"
    candidates+=("${domain}")
  done <<< "${records}"
  [[ ${#candidates[@]} -gt 0 && ${#candidates[@]} -le 5 ]] || return 1
  echo "按以上顺序检测，选择首个通过并获接受的域名；附加风险默认拒绝。"
  if selected_sni=$(select_reality_sni_candidate "${candidates[@]}"); then
    SB_SNI="${selected_sni}"
    log_success "已选择 Reality SNI: ${SB_SNI}"
    return 0
  else
    return $?
  fi
}

prompt_reality_target_candidates() {
  local input domain selected_sni
  local candidates=()
  echo "本方式只检测提供的域名；按输入顺序选择首个通过并获接受的目标。"
  echo "探测包括 TLS/证书/h2/X25519，以及通过 DNS 查询的 ASN/CDN 线索。"
  read -rp "[VLESS + REALITY] 候选域名（空格或逗号分隔，最多 5 个；留空取消）: " input || return 1
  input=${input//,/ }
  read -r -a candidates <<< "${input}"
  if [[ ${#candidates[@]} -eq 0 || ${#candidates[@]} -gt 5 ]]; then
    log_warn "请输入 1 至 5 个候选域名；SNI 未变更。"
    return 1
  fi
  for domain in "${candidates[@]}"; do
    if ! validate_reality_sni_syntax "${domain}"; then
      log_warn "候选必须为纯域名，不含 URL、端口或路径；SNI 未变更。"
      return 1
    fi
  done
  if selected_sni=$(select_reality_sni_candidate "${candidates[@]}"); then
    SB_SNI="${selected_sni}"
    log_success "已选择 Reality SNI: ${SB_SNI}"
    return 0
  else
    return $?
  fi
}

prompt_reality_sni_install() {
  local choice status
  while true; do
    echo "[VLESS + REALITY] REALITY 域名选择:"
    echo "1. 使用 reality-target-checker 探测候选 SNI (默认)"
    echo "2. 手动输入（TLS 校验）"
    echo "3. 从明确的网段 / ASN 发现候选 SNI"
    echo "4. 检测地区内置候选（银行 / 政府 / 学校）"
    choice=$(prompt_choice "请选择 [1-4] (默认 1): " 1 4 1) || return 1
    case "${choice}" in
      4)
        if prompt_reality_region_candidates; then return 0; else status=$?; fi
        [[ "${status}" == 1 ]] || return "${status}"
        log_warn "尚未选择 SNI，请重试或选择其他输入方式。"
        ;;
      3)
        if prompt_reality_target_discovery; then return 0; else status=$?; fi
        [[ "${status}" == 1 ]] || return "${status}"
        log_warn "尚未选择 SNI，请重试或选择其他输入方式。"
        ;;
      2)
        read_manual_reality_sni_with_validation "" \
          "[VLESS + REALITY] REALITY 域名（必填，无固定默认值）: " || return 1
        return 0
        ;;
      *)
        if prompt_reality_target_candidates; then return 0; else status=$?; fi
        [[ "${status}" == 1 ]] || return "${status}"
        log_warn "尚未选择 SNI，请重试探测或手动输入。"
        ;;
    esac
  done
}

prompt_reality_sni_update() {
  local choice status
  while true; do
    echo "[VLESS + REALITY] REALITY SNI 更新方式:"
    echo "1. 保留当前 SNI: ${SB_SNI} (默认)"
    echo "2. 使用 reality-target-checker 探测候选 SNI"
    echo "3. 手动输入（TLS 校验）"
    echo "4. 从明确的网段 / ASN 发现候选 SNI"
    echo "5. 检测地区内置候选（银行 / 政府 / 学校）"
    choice=$(prompt_choice "请选择 [1-5] (默认 1): " 1 5 1) || return 1
    case "${choice}" in
      5)
        if prompt_reality_region_candidates; then return 0; else status=$?; fi
        [[ "${status}" == 1 ]] || return "${status}"
        ;;
      4)
        if prompt_reality_target_discovery; then return 0; else status=$?; fi
        [[ "${status}" == 1 ]] || return "${status}"
        ;;
      2)
        if prompt_reality_target_candidates; then return 0; else status=$?; fi
        [[ "${status}" == 1 ]] || return "${status}"
        ;;
      3)
        read_manual_reality_sni_with_validation "${SB_SNI}" \
          "[VLESS + REALITY] 新 REALITY SNI (当前: ${SB_SNI}, 留空保持): " || return 1
        return 0
        ;;
      *) log_info "保留当前 Reality SNI: ${SB_SNI}"; return 0 ;;
    esac
  done
}

prompt_reality_sni_for_new_instance() {
  local default_sni=${1:-} choice status
  if ! validate_reality_sni_syntax "${default_sni}"; then
    prompt_reality_sni_install || return $?
    return $?
  fi
  while true; do
    echo "[VLESS + REALITY] REALITY SNI 选择:"
    echo "1. 复用现有 SNI: ${default_sni} (默认)"
    echo "2. 使用 reality-target-checker 探测候选 SNI"
    echo "3. 手动输入（TLS 校验）"
    echo "4. 从明确的网段 / ASN 发现候选 SNI"
    echo "5. 检测地区内置候选（银行 / 政府 / 学校）"
    choice=$(prompt_choice "请选择 [1-5] (默认 1): " 1 5 1) || return 1
    case "${choice}" in
      5)
        if prompt_reality_region_candidates; then return 0; else status=$?; fi
        [[ "${status}" == 1 ]] || return "${status}"
        ;;
      4)
        if prompt_reality_target_discovery; then return 0; else status=$?; fi
        [[ "${status}" == 1 ]] || return "${status}"
        ;;
      2)
        if prompt_reality_target_candidates; then return 0; else status=$?; fi
        [[ "${status}" == 1 ]] || return "${status}"
        ;;
      3)
        read_manual_reality_sni_with_validation "${default_sni}" \
          "[VLESS + REALITY] REALITY SNI (默认 ${default_sni}): " || return 1
        return 0
        ;;
      *) SB_SNI="${default_sni}"; log_info "复用 Reality SNI: ${SB_SNI}"; return 0 ;;
    esac
  done
}

prompt_vless_reality_rate_limit_fields() {
  local in_limit in_up in_down

  SB_VLESS_RATE_LIMIT_UP_MBPS="${SB_VLESS_RATE_LIMIT_UP_MBPS:-}"
  SB_VLESS_RATE_LIMIT_DOWN_MBPS="${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}"

  in_limit=$(prompt_yes_no "[VLESS + REALITY] 是否配置限速 [y/n] (默认 n): " "n") || return 1
  if [[ "${in_limit}" != "y" ]]; then
    SB_VLESS_RATE_LIMIT_UP_MBPS=""
    SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
    return 0
  fi

  in_up=$(prompt_optional_positive_integer "[VLESS + REALITY] 上行带宽 Mbps (留空表示上行不限速): " "" "上行带宽") || return 1
  in_down=$(prompt_optional_positive_integer "[VLESS + REALITY] 下行带宽 Mbps (留空表示下行不限速): " "" "下行带宽") || return 1

  SB_VLESS_RATE_LIMIT_UP_MBPS="${in_up}"
  SB_VLESS_RATE_LIMIT_DOWN_MBPS="${in_down}"

  if [[ -z "${SB_VLESS_RATE_LIMIT_UP_MBPS}" && -z "${SB_VLESS_RATE_LIMIT_DOWN_MBPS}" ]]; then
    log_warn "上下行均为空，将按不限速保存。"
  fi
}

prompt_vless_reality_rate_limit_update_fields() {
  local choice in_up in_down current_summary

  SB_VLESS_RATE_LIMIT_UP_MBPS="${SB_VLESS_RATE_LIMIT_UP_MBPS:-}"
  SB_VLESS_RATE_LIMIT_DOWN_MBPS="${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}"
  current_summary=$(vless_reality_rate_limit_summary \
    "${SB_VLESS_RATE_LIMIT_UP_MBPS}" \
    "${SB_VLESS_RATE_LIMIT_DOWN_MBPS}")

  echo "[VLESS + REALITY] 当前限速: ${current_summary}"
  echo "1. 保留当前限速 (默认)"
  echo "2. 重新设置限速"
  echo "3. 清空限速"
  choice=$(prompt_choice "请选择 [1-3] (默认 1): " 1 3 1) || return 1

  case "${choice}" in
    2)
      in_up=$(prompt_optional_positive_integer "[VLESS + REALITY] 上行带宽 Mbps (留空表示上行不限速): " "" "上行带宽") || return 1
      in_down=$(prompt_optional_positive_integer "[VLESS + REALITY] 下行带宽 Mbps (留空表示下行不限速): " "" "下行带宽") || return 1

      SB_VLESS_RATE_LIMIT_UP_MBPS="${in_up}"
      SB_VLESS_RATE_LIMIT_DOWN_MBPS="${in_down}"
      ;;
    3)
      SB_VLESS_RATE_LIMIT_UP_MBPS=""
      SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
      ;;
    *)
      log_info "保留当前 REALITY 限速: ${current_summary}"
      ;;
  esac
}

prompt_vless_reality_advanced_update_fields() {
  local choice tfo_choice current_alpn current_tfo

  SB_VLESS_ALPN_MODE="${SB_VLESS_ALPN_MODE:-off}"
  validate_vless_reality_alpn_mode "${SB_VLESS_ALPN_MODE}" || SB_VLESS_ALPN_MODE="off"
  SB_VLESS_TCP_FAST_OPEN="${SB_VLESS_TCP_FAST_OPEN:-n}"
  [[ "${SB_VLESS_TCP_FAST_OPEN}" == "y" || "${SB_VLESS_TCP_FAST_OPEN}" == "n" ]] || SB_VLESS_TCP_FAST_OPEN="n"

  current_alpn=$(vless_reality_alpn_mode_display_name "${SB_VLESS_ALPN_MODE}")
  current_tfo="关闭"
  [[ "${SB_VLESS_TCP_FAST_OPEN}" == "y" ]] && current_tfo="开启"

  echo "[VLESS + REALITY] 高级配置:"
  echo "- 当前 ALPN: ${current_alpn}"
  echo "- 当前 TCP Fast Open: ${current_tfo}"
  echo "ALPN 预设:"
  echo "1. 保留当前 ALPN (默认)"
  echo "2. 关闭"
  echo "3. h2 + http/1.1"
  echo "4. http/1.1"
  choice=$(prompt_choice "请选择 ALPN [1-4] (默认 1): " 1 4 1) || return 1
  case "${choice}" in
    2) SB_VLESS_ALPN_MODE="off" ;;
    3) SB_VLESS_ALPN_MODE="h2_http1" ;;
    4) SB_VLESS_ALPN_MODE="http1" ;;
    *) ;;
  esac

  tfo_choice=$(prompt_yes_no "是否启用 TCP Fast Open [y/n] (当前: ${SB_VLESS_TCP_FAST_OPEN}, 留空保持): " "${SB_VLESS_TCP_FAST_OPEN}") || return 1
  SB_VLESS_TCP_FAST_OPEN="${tfo_choice}"
}

prompt_mixed_update() {
  local in_p in_auth in_user in_pass

  in_p=$(prompt_port "新端口 (当前: ${SB_PORT}, 留空保持): " "${SB_PORT}")
  if [[ "${in_p}" != "${SB_PORT}" ]]; then
    SB_PORT="${in_p}"
    check_port_conflict "${SB_PORT}"
  fi

  in_auth=$(prompt_yes_no "是否启用用户名密码认证 [y/n] (当前: ${SB_MIXED_AUTH_ENABLED}, 留空保持): " "${SB_MIXED_AUTH_ENABLED}")
  SB_MIXED_AUTH_ENABLED="${in_auth}"

  if [[ "${SB_MIXED_AUTH_ENABLED}" == "y" ]]; then
    read -rp "新用户名 (当前: ${SB_MIXED_USERNAME}, 留空保持/自动生成): " in_user
    [[ -n "${in_user}" ]] && SB_MIXED_USERNAME="${in_user}"
    read -rp "新密码 (当前: 留空隐藏, 留空保持/自动生成): " in_pass
    [[ -n "${in_pass}" ]] && SB_MIXED_PASSWORD="${in_pass}"
    ensure_mixed_auth_credentials
  else
    log_warn "关闭 Mixed 认证会暴露开放代理，存在明显安全风险。"
    SB_MIXED_USERNAME=""
    SB_MIXED_PASSWORD=""
  fi
}

prompt_hy2_update() {
  local in_p in_domain in_password in_user_name in_up in_down in_obfs in_obfs_password in_tls_mode in_acme_mode in_acme_email in_acme_domain in_cf_api_token in_cert_path in_key_path in_masquerade

  in_p=$(prompt_port "新端口 (当前: ${SB_PORT}, 留空保持): " "${SB_PORT}")
  if [[ "${in_p}" != "${SB_PORT}" ]]; then
    SB_PORT="${in_p}"
    check_port_conflict "${SB_PORT}"
  fi

  read -rp "新域名 (当前: ${SB_HY2_DOMAIN}, 留空保持): " in_domain
  if [[ -n "${in_domain}" ]]; then
    in_domain=$(trim_whitespace "${in_domain}")
    if validate_tls_domain_points_to_server "Hysteria2" "${in_domain}"; then
      SB_HY2_DOMAIN="${in_domain}"
    else
      log_warn "已保留当前 Hysteria2 域名: ${SB_HY2_DOMAIN}"
    fi
  fi

  read -rp "新认证密码 (当前: 留空隐藏, 留空保持): " in_password
  [[ -n "${in_password}" ]] && SB_HY2_PASSWORD="${in_password}"

  read -rp "新用户名标识 (当前: ${SB_HY2_USER_NAME}, 留空保持): " in_user_name
  [[ -n "${in_user_name}" ]] && SB_HY2_USER_NAME="${in_user_name}"

  in_up=$(prompt_update_optional_positive_integer "上行带宽 Mbps (当前: ${SB_HY2_UP_MBPS:-未限制}, 留空清空限制): " "上行带宽")
  SB_HY2_UP_MBPS="${in_up}"

  in_down=$(prompt_update_optional_positive_integer "下行带宽 Mbps (当前: ${SB_HY2_DOWN_MBPS:-未限制}, 留空清空限制): " "下行带宽")
  SB_HY2_DOWN_MBPS="${in_down}"

  in_obfs=$(prompt_yes_no "是否启用 obfs / Salamander 混淆 [y/n] (当前: ${SB_HY2_OBFS_ENABLED}, 留空保持): " "${SB_HY2_OBFS_ENABLED}")
  SB_HY2_OBFS_ENABLED="${in_obfs}"

  if [[ "${SB_HY2_OBFS_ENABLED}" == "y" ]]; then
    if [[ -n "${SB_HY2_OBFS_PASSWORD}" ]]; then
      read -rp "obfs / Salamander 混淆密码 (当前: 已设置，留空保持；输入新值则覆盖): " in_obfs_password
    else
      read -rp "obfs / Salamander 混淆密码 (当前: 未设置，留空自动生成；输入新值则使用输入值): " in_obfs_password
    fi
    [[ -n "${in_obfs_password}" ]] && SB_HY2_OBFS_PASSWORD="${in_obfs_password}"
    [[ -z "${SB_HY2_OBFS_TYPE}" ]] && SB_HY2_OBFS_TYPE="salamander"
  else
    SB_HY2_OBFS_TYPE=""
    SB_HY2_OBFS_PASSWORD=""
  fi

  echo "TLS 模式:"
  echo "1. ACME 自动签发"
  echo "2. 手动证书路径"
  in_tls_mode=$(prompt_optional_choice "请选择 [1-2] (当前: ${SB_HY2_TLS_MODE}, 留空保持): " 1 2)
  case "${in_tls_mode}" in
    1) SB_HY2_TLS_MODE="acme" ;;
    2) SB_HY2_TLS_MODE="manual" ;;
    "") ;;
  esac

  if [[ -z "${in_tls_mode}" ]]; then
    :
  elif [[ "${SB_HY2_TLS_MODE}" == "acme" ]]; then
    echo "ACME 验证方式:"
    echo "1. HTTP-01"
    echo "2. DNS-01 (Cloudflare)"
    in_acme_mode=$(prompt_optional_choice "请选择 [1-2] (当前: ${SB_HY2_ACME_MODE}, 留空保持): " 1 2)
    case "${in_acme_mode}" in
      1) SB_HY2_ACME_MODE="http" ;;
      2) SB_HY2_ACME_MODE="dns" ;;
      "") ;;
    esac

    in_acme_email=$(prompt_optional_email "ACME 邮箱 (当前: ${SB_HY2_ACME_EMAIL}, 留空保持，用于证书通知): " "${SB_HY2_ACME_EMAIL}")
    SB_HY2_ACME_EMAIL="${in_acme_email}"
    in_acme_domain=$(prompt_optional_domain "ACME 域名 (当前: ${SB_HY2_ACME_DOMAIN:-${SB_HY2_DOMAIN}}, 留空保持): " "${SB_HY2_ACME_DOMAIN:-${SB_HY2_DOMAIN}}")
    SB_HY2_ACME_DOMAIN="${in_acme_domain}"

    if [[ "${SB_HY2_ACME_MODE}" == "dns" ]]; then
      read -rp "Cloudflare API Token (当前: 留空隐藏, 留空保持): " in_cf_api_token
      [[ -n "${in_cf_api_token}" ]] && SB_HY2_CF_API_TOKEN="${in_cf_api_token}"
    else
      SB_HY2_CF_API_TOKEN=""
    fi

    SB_HY2_CERT_PATH=""
    SB_HY2_KEY_PATH=""
  else
    in_cert_path=$(prompt_required_path "证书路径 (当前: ${SB_HY2_CERT_PATH}, 留空保持): " "${SB_HY2_CERT_PATH}")
    SB_HY2_CERT_PATH="${in_cert_path}"
    in_key_path=$(prompt_required_path "私钥路径 (当前: ${SB_HY2_KEY_PATH}, 留空保持): " "${SB_HY2_KEY_PATH}")
    SB_HY2_KEY_PATH="${in_key_path}"
    SB_HY2_ACME_MODE="http"
    SB_HY2_ACME_EMAIL=""
    SB_HY2_ACME_DOMAIN=""
    SB_HY2_CF_API_TOKEN=""
  fi

  in_masquerade=$(prompt_hy2_masquerade_url "伪装地址 (当前: ${SB_HY2_MASQUERADE}, 留空保持): " "${SB_HY2_MASQUERADE}") || return 1
  SB_HY2_MASQUERADE=${in_masquerade}

  ensure_hy2_materials
}

prompt_anytls_update() {
  local in_p in_domain in_password in_user_name in_tls_mode in_acme_mode in_acme_email in_acme_domain in_cf_api_token in_cert_path in_key_path

  in_p=$(prompt_port "新端口 (当前: ${SB_PORT}, 留空保持): " "${SB_PORT}")
  if [[ "${in_p}" != "${SB_PORT}" ]]; then
    SB_PORT="${in_p}"
    check_port_conflict "${SB_PORT}"
  fi

  read -rp "新域名 (当前: ${SB_ANYTLS_DOMAIN}, 留空保持): " in_domain
  if [[ -n "${in_domain}" ]]; then
    in_domain=$(trim_whitespace "${in_domain}")
    if validate_tls_domain_points_to_server "AnyTLS" "${in_domain}"; then
      SB_ANYTLS_DOMAIN="${in_domain}"
    else
      log_warn "已保留当前 AnyTLS 域名: ${SB_ANYTLS_DOMAIN}"
    fi
  fi

  read -rp "新认证密码 (当前: 留空隐藏, 留空保持): " in_password
  [[ -n "${in_password}" ]] && SB_ANYTLS_PASSWORD="${in_password}"

  read -rp "新用户名标识 (当前: ${SB_ANYTLS_USER_NAME}, 留空保持): " in_user_name
  [[ -n "${in_user_name}" ]] && SB_ANYTLS_USER_NAME="${in_user_name}"

  echo "TLS 模式:"
  echo "1. ACME 自动签发"
  echo "2. 手动证书路径"
  in_tls_mode=$(prompt_optional_choice "请选择 [1-2] (当前: ${SB_ANYTLS_TLS_MODE}, 留空保持): " 1 2)
  case "${in_tls_mode}" in
    1) SB_ANYTLS_TLS_MODE="acme" ;;
    2) SB_ANYTLS_TLS_MODE="manual" ;;
    "") ;;
  esac

  if [[ -z "${in_tls_mode}" ]]; then
    :
  elif [[ "${SB_ANYTLS_TLS_MODE}" == "acme" ]]; then
    echo "ACME 验证方式:"
    echo "1. HTTP-01"
    echo "2. DNS-01 (Cloudflare)"
    in_acme_mode=$(prompt_optional_choice "请选择 [1-2] (当前: ${SB_ANYTLS_ACME_MODE}, 留空保持): " 1 2)
    case "${in_acme_mode}" in
      1) SB_ANYTLS_ACME_MODE="http" ;;
      2) SB_ANYTLS_ACME_MODE="dns" ;;
      "") ;;
    esac

    in_acme_email=$(prompt_optional_email "ACME 邮箱 (当前: ${SB_ANYTLS_ACME_EMAIL}, 留空保持，用于证书通知): " "${SB_ANYTLS_ACME_EMAIL}")
    SB_ANYTLS_ACME_EMAIL="${in_acme_email}"
    in_acme_domain=$(prompt_optional_domain "ACME 域名 (当前: ${SB_ANYTLS_ACME_DOMAIN:-${SB_ANYTLS_DOMAIN}}, 留空保持): " "${SB_ANYTLS_ACME_DOMAIN:-${SB_ANYTLS_DOMAIN}}")
    SB_ANYTLS_ACME_DOMAIN="${in_acme_domain}"

    if [[ "${SB_ANYTLS_ACME_MODE}" == "dns" ]]; then
      read -rp "Cloudflare API Token (当前: 留空隐藏, 留空保持): " in_cf_api_token
      [[ -n "${in_cf_api_token}" ]] && SB_ANYTLS_CF_API_TOKEN="${in_cf_api_token}"
    else
      SB_ANYTLS_CF_API_TOKEN=""
    fi

    SB_ANYTLS_CERT_PATH=""
    SB_ANYTLS_KEY_PATH=""
  else
    in_cert_path=$(prompt_required_path "证书路径 (当前: ${SB_ANYTLS_CERT_PATH}, 留空保持): " "${SB_ANYTLS_CERT_PATH}")
    SB_ANYTLS_CERT_PATH="${in_cert_path}"
    in_key_path=$(prompt_required_path "私钥路径 (当前: ${SB_ANYTLS_KEY_PATH}, 留空保持): " "${SB_ANYTLS_KEY_PATH}")
    SB_ANYTLS_KEY_PATH="${in_key_path}"
    SB_ANYTLS_ACME_MODE="http"
    SB_ANYTLS_ACME_EMAIL=""
    SB_ANYTLS_ACME_DOMAIN=""
    SB_ANYTLS_CF_API_TOKEN=""
  fi

  ensure_anytls_materials
}

prompt_snell_update() {
  local in_p in_version in_psk in_obfs in_host in_mode
  in_p=$(prompt_port "新端口 (当前: ${SB_PORT}, 留空保持): " "${SB_PORT}") || return 1
  if [[ "${in_p}" != "${SB_PORT}" ]]; then SB_PORT=${in_p}; check_port_conflict "${SB_PORT}"; fi
  in_version=$(prompt_optional_choice "Snell 版本 [1=v5,2=v6] (当前: ${SB_SNELL_VERSION}, 留空保持): " 1 2 "$([[ "${SB_SNELL_VERSION}" == 5 ]] && printf 1 || printf 2)") || return 1
  case "${in_version}" in 1) SB_SNELL_VERSION=5 ;; 2) SB_SNELL_VERSION=6 ;; esac
  read -rsp "新 PSK (当前: 已设置，留空保持): " in_psk || return 1; printf '\n' >&2; [[ -z "${in_psk}" ]] || SB_SNELL_PSK=${in_psk}
  if [[ "${SB_SNELL_VERSION}" == 5 ]]; then
    in_obfs=$(prompt_optional_choice "v5 obfs [1=none,2=http] (当前: ${SB_SNELL_OBFS_MODE:-none}, 留空保持): " 1 2 "$([[ "${SB_SNELL_OBFS_MODE}" == http ]] && printf 2 || printf 1)") || return 1
    case "${in_obfs}" in 1) SB_SNELL_OBFS_MODE=none; SB_SNELL_OBFS_HOST="" ;; 2) SB_SNELL_OBFS_MODE=http; read -rp "v5 obfs host (当前: ${SB_SNELL_OBFS_HOST}，留空保持): " in_host || return 1; [[ -z "${in_host}" ]] || SB_SNELL_OBFS_HOST=$(trim_whitespace "${in_host}") ;; esac
    SB_SNELL_MODE=""
  else
    in_mode=$(prompt_optional_choice "v6 shaping [1=default,2=unshaped,3=unsafe-raw] (当前: ${SB_SNELL_MODE:-default}, 留空保持): " 1 3 "$([[ "${SB_SNELL_MODE}" == unshaped ]] && printf 2 || [[ "${SB_SNELL_MODE}" == unsafe-raw ]] && printf 3 || printf 1)") || return 1
    case "${in_mode}" in 1) SB_SNELL_MODE=default ;; 2) SB_SNELL_MODE=unshaped ;; 3) SB_SNELL_MODE=unsafe-raw ;; esac
    SB_SNELL_OBFS_MODE=""; SB_SNELL_OBFS_HOST=""
  fi
  snell_prompt_users "${SB_SNELL_USER_JSON:-[]}" || return 1
  ensure_snell_materials
}

prompt_snell_install() {
  local in_version in_psk in_obfs in_host in_mode
  set_protocol_defaults snell
  SB_NODE_NAME=$(default_instance_node_name "snell") || return 1
  SB_PORT=$(prompt_port "[Snell] 端口 (默认 ${SB_PORT}): " "${SB_PORT}") || return 1
  check_port_conflict "${SB_PORT}"
  in_version=$(prompt_choice "[Snell] 版本 [1=v5,2=v6] (默认 2): " 1 2 2) || return 1
  [[ "${in_version}" == 1 ]] && SB_SNELL_VERSION=5 || SB_SNELL_VERSION=6
  read -rsp "[Snell] PSK (留空自动生成): " in_psk || return 1; printf '\n' >&2; [[ -z "${in_psk}" ]] || SB_SNELL_PSK=${in_psk}
  if [[ "${SB_SNELL_VERSION}" == 5 ]]; then
    in_obfs=$(prompt_choice "[Snell] v5 obfs [1=none,2=http] (默认 1): " 1 2 1) || return 1
    if [[ "${in_obfs}" == 2 ]]; then SB_SNELL_OBFS_MODE=http; read -rp "[Snell] v5 obfs host: " in_host || return 1; SB_SNELL_OBFS_HOST=$(trim_whitespace "${in_host}"); else SB_SNELL_OBFS_MODE=none; fi
    SB_SNELL_MODE=""
  else
    in_mode=$(prompt_choice "[Snell] v6 shaping [1=default,2=unshaped,3=unsafe-raw] (默认 1): " 1 3 1) || return 1
    case "${in_mode}" in 2) SB_SNELL_MODE=unshaped ;; 3) SB_SNELL_MODE=unsafe-raw ;; *) SB_SNELL_MODE=default ;; esac
  fi
  snell_prompt_users '[]' || return 1
  ensure_snell_materials
}

prompt_protocol_update_fields() {
  local protocol
  protocol=$(normalize_protocol_id "$1")

  case "${protocol}" in
    vless-reality) prompt_vless_reality_update ;;
    vless-plain) prompt_vless_plain_update ;;
    mixed) prompt_mixed_update ;;
    socks) prompt_socks_update ;;
    http) prompt_http_update ;;
    shadowsocks) prompt_shadowsocks_update ;;
    trojan) prompt_trojan_update ;;
    vmess) prompt_vmess_update ;;
    hy2) prompt_hy2_update ;;
    anytls) prompt_anytls_update ;;
    snell) prompt_snell_update ;;
    tuic) prompt_tuic_update ;;
    hysteria) prompt_hysteria_update ;;
    naive) prompt_naive_update ;;
    shadowtls) prompt_shadowtls_update ;;
    *) log_error "不支持的协议修改类型: ${protocol}" ;;
  esac
}

shadowsocks_method_display_name() {
  case "${1:-}" in
    none) printf '无认证（明文）' ;;
    aes-128-gcm) printf 'AES-128-GCM' ;;
    aes-192-gcm) printf 'AES-192-GCM' ;;
    aes-256-gcm) printf 'AES-256-GCM' ;;
    chacha20-ietf-poly1305) printf 'ChaCha20-Poly1305' ;;
    xchacha20-ietf-poly1305) printf 'XChaCha20-Poly1305' ;;
    2022-blake3-aes-128-gcm) printf '2022 AES-128-GCM' ;;
    2022-blake3-aes-256-gcm) printf '2022 AES-256-GCM' ;;
    2022-blake3-chacha20-poly1305) printf '2022 ChaCha20-Poly1305' ;;
    *) return 1 ;;
  esac
}

shadowsocks_method_from_choice() {
  case "${1:-}" in
    1) printf 'none' ;;
    2) printf 'aes-128-gcm' ;;
    3) printf 'aes-192-gcm' ;;
    4) printf 'aes-256-gcm' ;;
    5) printf 'chacha20-ietf-poly1305' ;;
    6) printf 'xchacha20-ietf-poly1305' ;;
    7) printf '2022-blake3-aes-128-gcm' ;;
    8) printf '2022-blake3-aes-256-gcm' ;;
    9) printf '2022-blake3-chacha20-poly1305' ;;
    *) return 1 ;;
  esac
}

shadowsocks_method_choice() {
  case "${1:-}" in
    none) printf 1 ;; aes-128-gcm) printf 2 ;; aes-192-gcm) printf 3 ;;
    aes-256-gcm) printf 4 ;; chacha20-ietf-poly1305) printf 5 ;;
    xchacha20-ietf-poly1305) printf 6 ;; 2022-blake3-aes-128-gcm) printf 7 ;;
    2022-blake3-aes-256-gcm) printf 8 ;; 2022-blake3-chacha20-poly1305) printf 9 ;;
    *) return 1 ;;
  esac
}

shadowsocks_method_is_2022() {
  [[ "${1:-}" == 2022-* ]]
}

shadowsocks_method_key_bytes() {
  case "${1:-}" in
    2022-blake3-aes-128-gcm) printf 16 ;;
    2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305) printf 32 ;;
    *) return 1 ;;
  esac
}

shadowsocks_generate_key() {
  local bytes=${1:-16} key
  key=$(openssl rand -base64 "${bytes}" 2>/dev/null | tr -d '\n') || return 1
  [[ -n "${key}" ]] || return 1
  printf '%s' "${key}"
}

shadowsocks_prompt_method() {
  local current=${1:-2022-blake3-aes-128-gcm} choice default_choice method
  default_choice=$(shadowsocks_method_choice "${current}" 2>/dev/null || printf 7)
  echo 'Shadowsocks 加密方法:' >&2
  for choice in {1..9}; do
    method=$(shadowsocks_method_from_choice "${choice}") || return 1
    printf '%s. %s\n' "${choice}" "$(shadowsocks_method_display_name "${method}")" >&2
  done
  while true; do
    read -rp "请选择 [1-9]（当前 ${default_choice}）: " choice || return 1
    choice=$(trim_whitespace "${choice}")
    [[ -z "${choice}" ]] && choice=${default_choice}
    method=$(shadowsocks_method_from_choice "${choice}" 2>/dev/null || true)
    [[ -n "${method}" ]] && { printf '%s' "${method}"; return 0; }
    log_warn '请输入 1-9。' >&2
  done
}

shadowsocks_prompt_network() {
  local current=${1:-'["tcp","udp"]'} choice default_choice network
  jq -e 'type == "array" and length > 0 and length <= 2' <<< "${current}" >/dev/null 2>&1 || current='["tcp","udp"]'
  if jq -e 'sort == ["tcp","udp"]' <<< "${current}" >/dev/null 2>&1; then default_choice=1
  elif jq -e '.[0] == "tcp"' <<< "${current}" >/dev/null 2>&1; then default_choice=2
  else default_choice=3; fi
  echo '监听网络:' >&2
  echo '1. tcp + udp' >&2; echo '2. tcp' >&2; echo '3. udp' >&2
  while true; do
    read -rp "请选择 [1-3]（当前 ${default_choice}）: " choice || return 1
    choice=$(trim_whitespace "${choice}"); [[ -z "${choice}" ]] && choice=${default_choice}
    case "${choice}" in
      1) network='["tcp","udp"]' ;; 2) network='["tcp"]' ;; 3) network='["udp"]' ;; *) log_warn '请输入 1-3。' >&2; continue ;;
    esac
    printf '%s' "${network}"; return 0
  done
}

shadowsocks_prompt_auth() {
  local method=${1:-} current=${2:-} current_method current_password current_users_json
  local multi_choice multi_default count raw_count i name password user_password bytes users_json='[]'
  local users_names=() users_passwords=() current_count=0
  current_method=$(jq -r '.method // empty' <<< "${current}" 2>/dev/null || true)
  current_password=$(jq -j '.password // "", "\u0001"' <<< "${current}" 2>/dev/null || true); current_password=${current_password%$'\1'}
  current_users_json=$(jq -c '.users // []' <<< "${current}" 2>/dev/null || printf '[]')
  [[ "${current_method}" == "${method}" ]] || { current_password=''; current_users_json='[]'; }
  current_count=$(jq -r 'length' <<< "${current_users_json}") || return 1

  if [[ "${method}" == none || "${method}" == 2022-blake3-chacha20-poly1305 ]]; then
    multi_choice=n
  else
    multi_default=n; [[ ${current_count} -gt 0 ]] && multi_default=y
    multi_choice=$(prompt_yes_no '是否配置多用户 [y/n]（默认保留当前设置）: ' "${multi_default}") || return 1
  fi

  if [[ "${multi_choice}" == y ]]; then
    while true; do
      read -rp "用户数量（当前 ${current_count:-0}，请输入 1-128）: " raw_count || return 1
      [[ -z "${raw_count}" && ${current_count} -gt 0 ]] && raw_count=${current_count}
      [[ "${raw_count}" =~ ^[1-9][0-9]{0,2}$ ]] && (( raw_count <= 128 )) && { count=${raw_count}; break; }
      log_warn '用户数量必须为 1-128。' >&2
    done
  else
    count=0
  fi

  if [[ "${method}" == none ]]; then
    SB_SHADOWSOCKS_AUTH_JSON='{"method":"none","password":"","users":[]}'
    return 0
  fi
  if (( count == 0 )) || [[ "${method}" == 2022-blake3-aes-128-gcm || "${method}" == 2022-blake3-aes-256-gcm ]]; then
    if (( count > 0 )) || [[ "${method}" == 2022-* ]]; then
      bytes=$(shadowsocks_method_key_bytes "${method}" 2>/dev/null || printf 0)
      password=${current_password}
      read -rsp "主密码/PSK（留空保持或自动生成）: " raw_count || return 1; printf '\n' >&2
      [[ -z "${raw_count}" ]] || password=${raw_count}
      [[ -n "${password}" ]] || password=$(shadowsocks_generate_key "${bytes}") || return 1
    else
      password=${current_password}
      read -rsp '密码（留空保持或自动生成）: ' raw_count || return 1; printf '\n' >&2
      [[ -z "${raw_count}" ]] || password=${raw_count}
      [[ -n "${password}" ]] || password=$(generate_random_token '' 16) || return 1
    fi
  else
    password=""
  fi

  for ((i = 0; i < count; i++)); do
    name=$(jq -j --argjson i "${i}" '.[$i].name // "", "\u0001"' <<< "${current_users_json}") || return 1; name=${name%$'\1'}
    user_password=$(jq -j --argjson i "${i}" '.[$i].password // "", "\u0001"' <<< "${current_users_json}") || return 1; user_password=${user_password%$'\1'}
    [[ -n "${name}" ]] || name="ss-user-$((i + 1))"
    read -rp "用户 $((i + 1)) 名称（默认 ${name}）: " raw_count || return 1
    [[ -z "${raw_count}" ]] || name=${raw_count}
    read -rsp "用户 $((i + 1)) 密码（留空保持或自动生成）: " raw_count || return 1; printf '\n' >&2
    [[ -z "${raw_count}" ]] || user_password=${raw_count}
    if [[ -z "${user_password}" ]]; then
      if shadowsocks_method_is_2022 "${method}"; then bytes=$(shadowsocks_method_key_bytes "${method}") || return 1; user_password=$(shadowsocks_generate_key "${bytes}") || return 1
      else user_password=$(generate_random_token '' 16) || return 1; fi
    fi
    users_names+=("${name}"); users_passwords+=("${user_password}")
    users_json=$(jq -c --arg name "${name}" --arg password "${user_password}" '. + [{name:$name,password:$password}]' <<< "${users_json}") || return 1
  done
  SB_SHADOWSOCKS_AUTH_JSON=$(jq -n -cS --arg method "${method}" --arg password "${password}" --argjson users "${users_json}" '{method:$method,password:$password,users:$users}') || return 1
}

prompt_plain_proxy_install() {
  local protocol=${1:-} label in_user in_pass
  label=$(plain_proxy_management_label "${protocol}") || return 1
  set_protocol_defaults "${protocol}"
  SB_NODE_NAME=$(default_instance_node_name "${protocol}") || return 1
  echo -e "\n${BLUE}--- 配置 ${label} ---${NC}"
  SB_PORT=$(prompt_port "[${label}] 端口 (默认 ${SB_PORT}): " "${SB_PORT}") || return 1
  check_port_conflict "${SB_PORT}"
  SB_MIXED_AUTH_ENABLED=$(prompt_yes_no "[${label}] 是否启用用户名密码认证 [y/n] (默认 y): " y) || return 1
  if [[ "${SB_MIXED_AUTH_ENABLED}" == y ]]; then
    read -rp "[${label}] 用户名 (留空自动生成): " in_user || return 1
    read -rsp "[${label}] 密码 (留空自动生成): " in_pass || return 1
    printf '\n' >&2
    SB_MIXED_USERNAME=${in_user}; SB_MIXED_PASSWORD=${in_pass}
    ensure_mixed_auth_credentials || return 1
  else
    SB_MIXED_USERNAME=""; SB_MIXED_PASSWORD=""
    log_warn "你选择了关闭认证。开放的 ${label} 代理存在明显安全风险，请确认防火墙与访问源限制。"
  fi
  if [[ "${protocol}" == http ]]; then
    plain_proxy_management_prompt_tls http '{"enabled":false}' || return 1
  fi
}

prompt_plain_proxy_update() {
  local protocol=${1:-} label in_p in_auth in_user in_pass current_tls
  label=$(plain_proxy_management_label "${protocol}") || return 1
  in_p=$(prompt_port "新端口 (当前: ${SB_PORT}, 留空保持): " "${SB_PORT}") || return 1
  if [[ "${in_p}" != "${SB_PORT}" ]]; then SB_PORT=${in_p}; check_port_conflict "${SB_PORT}"; fi
  in_auth=$(prompt_yes_no "是否启用用户名密码认证 [y/n] (当前: ${SB_MIXED_AUTH_ENABLED}, 留空保持): " "${SB_MIXED_AUTH_ENABLED}") || return 1
  SB_MIXED_AUTH_ENABLED=${in_auth}
  if [[ "${in_auth}" == y ]]; then
    read -rp "新用户名 (留空保持/自动生成): " in_user || return 1
    [[ -z "${in_user}" ]] || SB_MIXED_USERNAME=${in_user}
    read -rsp "新密码 (留空保持/自动生成): " in_pass || return 1; printf '\n' >&2
    [[ -z "${in_pass}" ]] || SB_MIXED_PASSWORD=${in_pass}
    ensure_mixed_auth_credentials || return 1
  else
    SB_MIXED_USERNAME=""; SB_MIXED_PASSWORD=""
    log_warn "关闭 ${label} 认证会暴露开放代理，存在明显安全风险。"
  fi
  if [[ "${protocol}" == http ]]; then
    current_tls=${SB_HTTP_TLS_JSON:-'{"enabled":false}'}
    plain_proxy_management_prompt_tls http "${current_tls}" || return 1
  fi
}

prompt_socks_install() {
  prompt_plain_proxy_install socks
}

prompt_socks_update() {
  prompt_plain_proxy_update socks
}

prompt_http_install() {
  prompt_plain_proxy_install http
}

prompt_http_update() {
  prompt_plain_proxy_update http
}

prompt_shadowsocks_install() {
  local method current_auth
  set_protocol_defaults shadowsocks
  SB_NODE_NAME=$(default_instance_node_name "shadowsocks") || return 1
  echo -e "\n${BLUE}--- 配置 Shadowsocks ---${NC}"
  SB_PORT=$(prompt_port '[Shadowsocks] 端口（默认当前值）: ' "${SB_PORT}") || return 1
  method=$(shadowsocks_prompt_method '2022-blake3-aes-128-gcm') || return 1
  current_auth=${SB_SHADOWSOCKS_AUTH_JSON:-}
  shadowsocks_prompt_auth "${method}" "${current_auth}" || return 1
  SB_SHADOWSOCKS_NETWORK_JSON=$(shadowsocks_prompt_network '["tcp","udp"]') || return 1
  if [[ "${method}" == none ]]; then
    log_warn 'Shadowsocks none 不提供加密，仅适合受限内网；请确认防火墙与访问源限制。'
  fi
}

prompt_shadowsocks_update() {
  local method current_auth current_network
  current_auth=${SB_SHADOWSOCKS_AUTH_JSON:-}
  current_network=${SB_SHADOWSOCKS_NETWORK_JSON:-'["tcp","udp"]'}
  SB_PORT=$(prompt_port '新端口（当前值，留空保持）: ' "${SB_PORT}") || return 1
  method=$(jq -r '.method // "2022-blake3-aes-128-gcm"' <<< "${current_auth}" 2>/dev/null || printf '2022-blake3-aes-128-gcm')
  method=$(shadowsocks_prompt_method "${method}") || return 1
  shadowsocks_prompt_auth "${method}" "${current_auth}" || return 1
  SB_SHADOWSOCKS_NETWORK_JSON=$(shadowsocks_prompt_network "${current_network}") || return 1
  if [[ "${method}" == none ]]; then
    log_warn 'Shadowsocks none 不提供加密，仅适合受限内网；请确认防火墙与访问源限制。'
  fi
}
