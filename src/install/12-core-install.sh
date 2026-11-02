
# --- System Check & Dependencies ---
install_dependencies() {
  log_info "正在安装必要的基础依赖..."
  case "${OS_NAME}" in
    debian|ubuntu)
      run_with_progress "更新软件源" apt-get update -y || return $?
      run_with_progress "安装基础依赖" apt-get install -y curl wget jq tar openssl uuid-runtime qrencode iproute2 dnsutils ca-certificates || return $?
      ;;
    centos|almalinux|rocky)
      run_with_progress "安装基础依赖" yum install -y curl wget jq tar openssl util-linux qrencode iproute bind-utils ca-certificates || return $?
      ;;
  esac
  log_success "基础依赖安装完成。"
}

# --- Sing-box Manager ---
query_latest_singbox_release() (
  umask 077
  local temp_dir='' http_status='' curl_status=0 latest_tag='' failure=''
  trap '[[ -z "${temp_dir}" ]] || rm -rf -- "${temp_dir}"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/sbv-version-query.XXXXXXXX") || return 1
  if http_status=$(curl -sS --connect-timeout 10 --max-time 30 --max-filesize 1048576 \
    -o "${temp_dir}/response.json" -w '%{http_code}' \
    'https://api.github.com/repos/SagerNet/sing-box/releases/latest' \
    2> >(head -c "${SBV_CURL_STDERR_MAX_BYTES}" > "${temp_dir}/curl.stderr"; cat >/dev/null)); then
    if [[ ! "${http_status}" =~ ^2[0-9][0-9]$ ]]; then
      failure="http_${http_status:-unavailable}"
    elif ! latest_tag=$(jq -ser 'select(length == 1) | .[0] | select(type == "object") | .tag_name | strings | select(test("^v?[0-9]+\\.[0-9]+\\.[0-9]+$"))' "${temp_dir}/response.json" 2>/dev/null); then
      failure=invalid_release_response
    fi
  else
    curl_status=$?
    case "${curl_status}" in
      129|130|143) return "${curl_status}" ;;
      6) failure=dns_failure ;;
      7) failure=connection_failed ;;
      18) failure=partial_transfer ;;
      28) failure=timeout ;;
      *) failure="transport_${curl_status}" ;;
    esac
  fi
  if ! rm -rf -- "${temp_dir}"; then failure=cleanup_failed; fi
  temp_dir=''
  jq -cn --arg version "${latest_tag#v}" --arg code "${failure}" --arg http "${http_status}" \
    '{version:$version,code:$code,http_status:$http}'
)

get_latest_version() {
  [[ "${SB_VERSION}" == latest ]] || return 0
  local result failure='' query_status=0
  SB_LATEST_VERSION_LOOKUP_STATUS=unavailable
  SB_LATEST_VERSION_LOOKUP_CODE=prepare_failed
  SB_LATEST_VERSION_LOOKUP_HTTP_STATUS=''
  result=$(query_latest_singbox_release) || query_status=$?
  case "${query_status}" in
    129|130|143)
      SB_LATEST_VERSION_LOOKUP_CODE=signal_interrupted
      printf '[WARN] operation=version_lookup code=signal_interrupted changed=false; 已取消，未选择安装版本。\n' >&2
      return "${query_status}"
      ;;
    0)
      failure=$(jq -er '.code | strings' <<< "${result}") || failure=invalid_query_result
      SB_LATEST_VERSION_LOOKUP_HTTP_STATUS=$(jq -r '.http_status' <<< "${result}") || return 1
      ;;
    *) failure=prepare_failed ;;
  esac
  if [[ -n "${failure}" ]]; then
    SB_LATEST_VERSION_LOOKUP_CODE=${failure}
    SB_VERSION="${SB_SUPPORT_MAX_VERSION}"
    log_warn "版本查询 unavailable: ${failure}；使用适配版本 ${SB_SUPPORT_MAX_VERSION}，响应原文未记录。"
    return 0
  fi
  SB_VERSION=$(jq -er '.version | strings' <<< "${result}") || return 1
  SB_LATEST_VERSION_LOOKUP_STATUS=available
  SB_LATEST_VERSION_LOOKUP_CODE=''
  if [[ "${SB_VERSION}" != "${SB_SUPPORT_MAX_VERSION}" ]] && singbox_version_at_least "${SB_VERSION}" "${SB_SUPPORT_MAX_VERSION}"; then
    log_warn "最新版本 (${SB_VERSION}) 高于适配版本 (${SB_SUPPORT_MAX_VERSION})，可能存在兼容性风险。"
  fi
}

replace_singbox_binary_atomically() {
  singbox_atomic_file_copy "${1:-}" "${SINGBOX_BIN_PATH}" "${2:-0755}"
}

singbox_atomic_file_copy() (
  local source_file=${1:-} target_file=${2:-} mode=${3:-0755} staged=''
  [[ -f "${source_file}" && ! -L "${source_file}" ]] || return 1
  [[ ! -e "${target_file}" || -f "${target_file}" ]] && [[ ! -L "${target_file}" ]] || return 1
  [[ -d "$(dirname "${target_file}")" ]] || return 1
  staged=$(mktemp "$(dirname "${target_file}")/.$(basename "${target_file}").restore.XXXXXXXX") || return 1
  trap '[[ -z "${staged}" ]] || rm -f -- "${staged}"' EXIT
  cp -p -- "${source_file}" "${staged}" || return $?
  chmod "${mode}" "${staged}" || return $?
  mv -f -- "${staged}" "${target_file}" || return $?
  staged=''
)

singbox_file_matches_backup() {
  local target=$1 backup=$2
  [[ -f "${target}" && ! -L "${target}" && -f "${backup}" ]] || return 1
  cmp -s -- "${target}" "${backup}" || return 1
  [[ "$(stat -c '%a:%u:%g' -- "${target}")" == "$(stat -c '%a:%u:%g' -- "${backup}")" ]]
}

restore_singbox_update_artifacts() {
  local binary_backup=$1 library_backup_dir=$2 mode status=0 lib_path state target backup
  mode=$(stat -c '%a' -- "${binary_backup}") || return 1
  if ! replace_singbox_binary_atomically "${binary_backup}" "${mode}" ||
     ! singbox_file_matches_backup "${SINGBOX_BIN_PATH}" "${binary_backup}"; then
    status=1
  fi
  if ! singbox_library_restore_snapshot "${library_backup_dir}"; then
    status=1
  fi
  lib_path=$(singbox_library_path) || return 1
  for target in "${lib_path}" "${SB_NAIVE_LIBRARY_MARKER}"; do
    if [[ "${target}" == "${lib_path}" ]]; then
      state=$(cat "${library_backup_dir}/library.state") || return 1
      backup="${library_backup_dir}/libcronet.so"
    else
      state=$(cat "${library_backup_dir}/marker.state") || return 1
      backup="${library_backup_dir}/libcronet.sha256"
    fi
    case "${state}" in
      present)
        mode=$(stat -c '%a' "${backup}") || return 1
        if ! singbox_atomic_file_copy "${backup}" "${target}" "${mode}" ||
           ! singbox_file_matches_backup "${target}" "${backup}"; then status=1; fi
        ;;
      absent) [[ ! -e "${target}" && ! -L "${target}" ]] || status=1 ;;
      unmanaged) ;;
      *) return 1 ;;
    esac
  done
  return "${status}"
}

validate_singbox_release_archive() {
  local archive=$1 root=$2 manifest=$3 verbose=$4 entry kind binary_count=0 library_count=0
  tar -tzf "${archive}" > "${manifest}" 2>/dev/null || return 1
  tar -tvzf "${archive}" > "${verbose}" 2>/dev/null || return 1
  while IFS= read -r entry; do
    [[ "${entry}" == "${root}/" || "${entry}" == "${root}" ||
       ( "${entry}" == "${root}/"* && "${entry#"${root}/"}" =~ ^[A-Za-z0-9._/-]+$ ) ]] || return 1
    [[ "/${entry}/" != *'/../'* && "/${entry}/" != *'/./'* && "${entry}" != *'//'* ]] || return 1
    [[ "${entry}" != "${root}/sing-box" ]] || binary_count=$((binary_count + 1))
    [[ "${entry}" != "${root}/libcronet.so" ]] || library_count=$((library_count + 1))
  done < "${manifest}"
  while IFS= read -r entry; do
    kind=${entry:0:1}
    [[ "${kind}" == - || "${kind}" == d ]] || return 1
  done < "${verbose}"
  [[ "${binary_count}" == 1 && "${library_count}" -le 1 ]]
}

singbox_binary_version_matches() {
  local binary=$1 expected=$2 output first_line
  [[ -f "${binary}" && ! -L "${binary}" && -x "${binary}" ]] || return 1
  output=$(timeout 10 "${binary}" version 2>/dev/null) || return 1
  first_line=${output%%$'\n'*}
  [[ "${first_line}" == "sing-box version ${expected}" ]]
}

# Validate the candidate, rather than the old installed core, before an update
# can replace a compatible namespace runtime with a known-crashing build.
singbox_candidate_namespace_runtime_safe() {
  local binary=$1 version=$2 namespace_use output tags_line tags='[]' tags_status=not_assessed dependency probe_status=0
  [[ -e "${SINGBOX_CONFIG_FILE}" ]] || return 0
  [[ -f "${SINGBOX_CONFIG_FILE}" && ! -L "${SINGBOX_CONFIG_FILE}" ]] || return 3
  namespace_use=$(jq -sr 'if length != 1 or (.[0] | type) != "object" then error("invalid_configuration") else .[0] |
    (((.network_namespaces // []) | length) > 0 or
     any([.inbounds[]?, .outbounds[]?, .endpoints[]?, .http_clients[]?,
           .dns.servers[]?, .services[]?, .route.rule_set[]?, .certificate_providers[]?][];
       any([.netns?, .control_dialer.netns?, .tunnel_dialer.netns?, .http_client.netns?,
             .realm.http_client.netns?][];
         type == "string" and length > 0))) end' \
    "${SINGBOX_CONFIG_FILE}" 2>/dev/null) || return 3
  [[ "${namespace_use}" == true ]] || return 0
  [[ "$(uname -s)" == Linux && ( "$(uname -m)" == aarch64 || "$(uname -m)" == arm64 ) && "${version}" == 1.14.2 ]] || return 0
  output=$(timeout 10 "${binary}" version 2>/dev/null) || probe_status=$?
  case "${probe_status}" in 129|130|143) return "${probe_status}" ;; esac
  if [[ "${probe_status}" == 0 ]]; then
    tags_line=$(printf '%s\n' "${output}" | sed -n 's/^Tags:[[:space:]]*//p') || return 2
    if [[ "${output}" == *$'\nTags:'* && "${tags_line}" != *$'\n'* ]] &&
       tags=$(jq -enc --arg line "${tags_line}" '$line |
         if . == "" then [] else split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) end |
         select(all(.[]; test("^[A-Za-z0-9][A-Za-z0-9_.+\\-]{0,127}$"))) |
         select(length == (unique | length))'); then
      tags_status=available
    fi
  fi
  dependency=$(namespace_runtime_build_dependency_json Linux arm64 "${version}" "${tags_status}" "${tags}") || return 2
  case "$(jq -r .status <<< "${dependency}")" in
    available) return 0 ;;
    unavailable) return 1 ;;
    *) return 2 ;;
  esac
}

install_binary() (
  umask 077
  local expected_version=${SB_VERSION#v} root download_url target_dir temp_dir=''
  local staged_binary='' staged_lib='' staged_marker='' lib_path='' lib_dir=''
  local binary_before=n lib_before=n marker_before=n manage_library=n publish_started=n changed=false
  local stage=prepare failure_code=install_failed rollback_ok=true preserve=false status=0
  local curl_pid='' collector_pid='' curl_status=0 candidate_hash='' library_hash='' mode
  local binary_metadata='' library_metadata='' marker_metadata='' binary_identity=''
  local current_version=unavailable version_output='' namespace_status=0

  binary_install_finish() {
    local operation_status=$1 cleanup_status=0 rollback_status=0 path
    trap - EXIT INT TERM HUP
    for path in "${curl_pid}" "${collector_pid}"; do
      if [[ -n "${path}" ]] && kill -0 "${path}" 2>/dev/null; then
        if kill "${path}" 2>/dev/null; then :; fi
        if wait "${path}" 2>/dev/null; then :; fi
      fi
    done
    if [[ "${operation_status}" != 0 && "${publish_started}" == y ]]; then
      if [[ "${binary_before}" == y ]]; then
        if ! singbox_file_matches_backup "${SINGBOX_BIN_PATH}" "${temp_dir}/binary.before" ||
           [[ "$(stat -c '%d:%i' "${SINGBOX_BIN_PATH}" 2>/dev/null)" != "${binary_identity}" ]]; then changed=true; fi
        mode=$(stat -c '%a' "${temp_dir}/binary.before") || rollback_status=1
        if ! replace_singbox_binary_atomically "${temp_dir}/binary.before" "${mode:-0755}" ||
           ! singbox_file_matches_backup "${SINGBOX_BIN_PATH}" "${temp_dir}/binary.before"; then rollback_status=1; fi
      elif [[ -e "${SINGBOX_BIN_PATH}" || -L "${SINGBOX_BIN_PATH}" ]]; then
        changed=true
        rm -f -- "${SINGBOX_BIN_PATH}" || rollback_status=1
      fi
      if [[ "${manage_library}" == y ]]; then
        for path in "${lib_path}" "${SB_NAIVE_LIBRARY_MARKER}"; do
          if [[ "${path}" == "${lib_path}" ]]; then
            mode=0644
            if [[ "${lib_before}" == y ]]; then
              mode=$(stat -c '%a' "${temp_dir}/library.before") || rollback_status=1
              if ! singbox_atomic_file_copy "${temp_dir}/library.before" "${path}" "${mode}" ||
                 ! singbox_file_matches_backup "${path}" "${temp_dir}/library.before"; then rollback_status=1; fi
            else rm -f -- "${path}" || rollback_status=1; fi
          else
            mode=0600
            if [[ "${marker_before}" == y ]]; then
              mode=$(stat -c '%a' "${temp_dir}/marker.before") || rollback_status=1
              if ! singbox_atomic_file_copy "${temp_dir}/marker.before" "${path}" "${mode}" ||
                 ! singbox_file_matches_backup "${path}" "${temp_dir}/marker.before"; then rollback_status=1; fi
            else rm -f -- "${path}" || rollback_status=1; fi
          fi
        done
      fi
      if [[ "${rollback_status}" != 0 ]]; then rollback_ok=false; preserve=true; fi
    fi
    for path in "${staged_binary}" "${staged_lib}" "${staged_marker}"; do
      [[ -z "${path}" ]] || rm -f -- "${path}" || cleanup_status=1
    done
    if [[ -n "${temp_dir}" && "${preserve}" != true ]]; then
      rm -rf -- "${temp_dir}" || cleanup_status=1
    fi
    if [[ "${operation_status}" != 0 ]]; then
      printf '[ERROR] operation=install_binary stage=%s code=%s command_exit_code=%s changed=%s rollback_attempted=%s rolled_back=%s rollback_ok=%s manual_intervention_required=%s current_version=%s candidate_version=%s target_path=%s log_file=%s message=安装事务失败 detail=诊断原文未记录 hint=检查阶段和错误代码，回滚失败时使用保留的恢复材料\n' \
        "${stage}" "${failure_code}" "${operation_status}" "${changed}" \
        "$([[ "${publish_started}" == y ]] && printf true || printf false)" \
        "$([[ "${changed}" == true && "${publish_started}" == y && "${rollback_ok}" == true ]] && printf true || printf false)" \
        "$([[ "${publish_started}" == y && "${rollback_ok}" == true ]] && printf true || printf false)" \
        "${preserve}" "${current_version}" \
        "$([[ "${expected_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && printf '%s' "${expected_version}" || printf unavailable)" \
        "${SINGBOX_BIN_PATH}" "${SBV_LOG_FILE}" >&2
      [[ "${preserve}" != true ]] || printf '[ERROR] binary recovery material: %s\n' "${temp_dir}" >&2
    elif [[ "${cleanup_status}" != 0 ]]; then
      printf '[ERROR] operation=install_binary stage=cleanup code=cleanup_failed changed=%s recovery=%s\n' "${changed}" "${temp_dir}" >&2
      operation_status=1
    else
      log_success "二进制文件安装成功并已清理临时文件。"
    fi
    exit "${operation_status}"
  }
  trap 'binary_install_finish "$?"' EXIT
  trap 'failure_code=signal_interrupted; exit 130' INT
  trap 'failure_code=signal_interrupted; exit 143' TERM
  trap 'failure_code=signal_interrupted; exit 129' HUP

  [[ "${expected_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "${ARCH:-}" =~ ^(amd64|arm64)$ ]] || { failure_code=invalid_release; return 1; }
  target_dir=$(dirname "${SINGBOX_BIN_PATH}") || return 1
  [[ -d "${target_dir}" && ! -L "${SINGBOX_BIN_PATH}" ]] || { failure_code=unsafe_binary_target; return 1; }
  [[ ! -e "${SINGBOX_BIN_PATH}" || -f "${SINGBOX_BIN_PATH}" ]] || { failure_code=unsafe_binary_target; return 1; }
  if [[ -x "${SINGBOX_BIN_PATH}" ]] && version_output=$(timeout 10 "${SINGBOX_BIN_PATH}" version 2>/dev/null); then
    version_output=${version_output%%$'\n'*}
    if [[ "${version_output}" =~ ^sing-box\ version\ ([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then current_version=${BASH_REMATCH[1]}; fi
  fi
  temp_dir=$(mktemp -d "${target_dir}/.sing-box-install.XXXXXXXX") || return 1
  root="sing-box-${expected_version}-linux-${ARCH}"
  download_url="https://github.com/SagerNet/sing-box/releases/download/v${expected_version}/${root}.tar.gz"
  stage=download
  log_info "开始下载 sing-box ${expected_version}..."
  mkfifo "${temp_dir}/stderr.pipe" || return 1
  (head -c "${SBV_CURL_STDERR_MAX_BYTES}" > "${temp_dir}/download.stderr"; cat >/dev/null) < "${temp_dir}/stderr.pipe" &
  collector_pid=$!
  curl -fsSL --connect-timeout "${SBV_CURL_CONNECT_TIMEOUT}" --max-time "${SBV_CURL_MAX_TIME}" \
    --retry "${SBV_CURL_RETRY_COUNT}" --retry-delay "${SBV_CURL_RETRY_DELAY}" --retry-max-time "${SBV_CURL_MAX_TIME}" \
    -o "${temp_dir}/release.tar.gz" "${download_url}" 2> "${temp_dir}/stderr.pipe" &
  curl_pid=$!
  if wait "${curl_pid}"; then curl_status=0; else curl_status=$?; fi
  curl_pid=''
  if ! wait "${collector_pid}"; then failure_code=diagnostic_capture_failed; return 1; fi
  collector_pid=''
  if [[ "${curl_status}" != 0 ]]; then
    failure_code=$(classify_sbv_download_error "${curl_status}")
    return "${curl_status}"
  fi
  stage=validate
  failure_code=invalid_archive
  [[ -s "${temp_dir}/release.tar.gz" ]] || return 1
  validate_singbox_release_archive "${temp_dir}/release.tar.gz" "${root}" "${temp_dir}/manifest" "${temp_dir}/verbose" || return 1
  mkdir "${temp_dir}/extract" || return 1
  tar -xzf "${temp_dir}/release.tar.gz" -C "${temp_dir}/extract" --no-same-owner --no-same-permissions \
    -- "${root}/sing-box" 2>/dev/null || return 1
  [[ -f "${temp_dir}/extract/${root}/sing-box" && ! -L "${temp_dir}/extract/${root}/sing-box" ]] || return 1
  staged_binary=$(mktemp "${target_dir}/.sing-box.restore.XXXXXXXX") || return 1
  cp -- "${temp_dir}/extract/${root}/sing-box" "${staged_binary}" || return 1
  chmod 0755 "${staged_binary}" || return 1
  failure_code=unexpected_binary_version
  singbox_binary_version_matches "${staged_binary}" "${expected_version}" || return 1
  singbox_candidate_namespace_runtime_safe "${staged_binary}" "${expected_version}" || namespace_status=$?
  if [[ "${namespace_status}" != 0 ]]; then
    case "${namespace_status}" in
      1) failure_code=namespace_runtime_unsafe_build ;;
      2) failure_code=namespace_runtime_build_not_assessed ;;
      129|130|143) failure_code=signal_interrupted ;;
      *) failure_code=namespace_configuration_unavailable ;;
    esac
    return "${namespace_status}"
  fi
  candidate_hash=$(sha256sum "${staged_binary}") || return 1
  candidate_hash=${candidate_hash%% *}
  lib_path=$(singbox_library_path) || return 1
  lib_dir=$(dirname "${lib_path}") || return 1
  if grep -Fqx "${root}/libcronet.so" "${temp_dir}/manifest"; then
    if [[ -e "${lib_path}" && ! -f "${SB_NAIVE_LIBRARY_MARKER}" ]]; then
      log_warn "发现未由 sbv 管理的 ${lib_path}，保留现有文件并跳过 libcronet.so 替换。"
    else
      failure_code=unsafe_library_target
      [[ ! -L "${lib_path}" && ! -L "${SB_NAIVE_LIBRARY_MARKER}" ]] || return 1
      [[ ! -e "${lib_path}" || -f "${lib_path}" ]] || return 1
      [[ ! -e "${SB_NAIVE_LIBRARY_MARKER}" || -f "${SB_NAIVE_LIBRARY_MARKER}" ]] || return 1
      mkdir -p "${lib_dir}" "${SB_PROJECT_DIR}" || return 1
      tar -xzf "${temp_dir}/release.tar.gz" -C "${temp_dir}/extract" --no-same-owner --no-same-permissions \
        -- "${root}/libcronet.so" 2>/dev/null || return 1
      [[ -s "${temp_dir}/extract/${root}/libcronet.so" && ! -L "${temp_dir}/extract/${root}/libcronet.so" ]] || return 1
      staged_lib=$(mktemp "${lib_dir}/.libcronet.install.XXXXXXXX") || return 1
      cp -- "${temp_dir}/extract/${root}/libcronet.so" "${staged_lib}" || return 1
      chmod 0644 "${staged_lib}" || return 1
      library_hash=$(sha256sum "${staged_lib}") || return 1
      library_hash=${library_hash%% *}
      staged_marker=$(mktemp "${SB_PROJECT_DIR}/.libcronet-marker.install.XXXXXXXX") || return 1
      printf '%s\n' "${library_hash}" > "${staged_marker}" || return 1
      chmod 0600 "${staged_marker}" || return 1
      manage_library=y
    fi
  else
    log_warn "下载归档未包含 libcronet.so；NaiveProxy 客户端运行时依赖仍不可用。"
  fi
  stage=backup
  failure_code=backup_failed
  if [[ -f "${SINGBOX_BIN_PATH}" ]]; then
    cp -p -- "${SINGBOX_BIN_PATH}" "${temp_dir}/binary.before" || return 1
    singbox_file_matches_backup "${SINGBOX_BIN_PATH}" "${temp_dir}/binary.before" || return 1
    chown --reference="${temp_dir}/binary.before" "${staged_binary}" || return 1
    binary_identity=$(stat -c '%d:%i' "${SINGBOX_BIN_PATH}") || return 1
    binary_before=y
  fi
  if [[ "${manage_library}" == y ]]; then
    if [[ -f "${lib_path}" ]]; then
      cp -p -- "${lib_path}" "${temp_dir}/library.before" || return 1
      singbox_file_matches_backup "${lib_path}" "${temp_dir}/library.before" || return 1
      chown --reference="${temp_dir}/library.before" "${staged_lib}" || return 1
      lib_before=y
    fi
    if [[ -f "${SB_NAIVE_LIBRARY_MARKER}" ]]; then
      cp -p -- "${SB_NAIVE_LIBRARY_MARKER}" "${temp_dir}/marker.before" || return 1
      singbox_file_matches_backup "${SB_NAIVE_LIBRARY_MARKER}" "${temp_dir}/marker.before" || return 1
      chown --reference="${temp_dir}/marker.before" "${staged_marker}" || return 1
      marker_before=y
    fi
    library_metadata=$(stat -c '%a:%u:%g' "${staged_lib}") || return 1
    marker_metadata=$(stat -c '%a:%u:%g' "${staged_marker}") || return 1
  fi
  binary_metadata=$(stat -c '%a:%u:%g' "${staged_binary}") || return 1
  stage=commit
  failure_code=publish_failed
  publish_started=y
  mv -f -- "${staged_binary}" "${SINGBOX_BIN_PATH}" || return 1
  changed=true
  if [[ "${manage_library}" == y ]]; then
    mv -f -- "${staged_lib}" "${lib_path}" || return 1
    mv -f -- "${staged_marker}" "${SB_NAIVE_LIBRARY_MARKER}" || return 1
  fi
  stage=postcheck
  failure_code=postcheck_failed
  [[ ! -L "${SINGBOX_BIN_PATH}" && "$(sha256sum "${SINGBOX_BIN_PATH}" | awk '{print $1}')" == "${candidate_hash}" &&
     "$(stat -c '%a:%u:%g' "${SINGBOX_BIN_PATH}")" == "${binary_metadata}" ]] || return 1
  singbox_binary_version_matches "${SINGBOX_BIN_PATH}" "${expected_version}" || return 1
  if [[ "${manage_library}" == y ]]; then
    [[ ! -L "${lib_path}" && ! -L "${SB_NAIVE_LIBRARY_MARKER}" &&
       "$(sha256sum "${lib_path}" | awk '{print $1}')" == "${library_hash}" &&
       "$(cat "${SB_NAIVE_LIBRARY_MARKER}")" == "${library_hash}" &&
       "$(stat -c '%a:%u:%g' "${lib_path}")" == "${library_metadata}" &&
       "$(stat -c '%a:%u:%g' "${SB_NAIVE_LIBRARY_MARKER}")" == "${marker_metadata}" ]] || return 1
    if command -v ldconfig >/dev/null 2>&1; then
      if ! ldconfig; then log_warn "ldconfig 未能刷新 libcronet.so 缓存；运行 NaiveProxy 客户端时请设置 LD_LIBRARY_PATH=${lib_dir}。"; fi
    else
      log_warn "未找到 ldconfig；运行 NaiveProxy 客户端时请设置 LD_LIBRARY_PATH=${lib_dir}。"
    fi
  fi
  stage=cleanup
)

setup_service() {
  log_info "配置 systemd 服务..."
  cat > "${SINGBOX_SERVICE_FILE}" <<EOF || return $?
[Unit]
Description=sing-box service
After=network.target nss-lookup.target
[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=${SINGBOX_BIN_PATH} run -c ${SINGBOX_CONFIG_FILE}
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload || return $?
  systemctl enable sing-box >/dev/null 2>&1 || return $?

  if ! ensure_sbv_command_installed; then
    log_warn "全局命令 sbv 未能完成同步；当前安装流程继续，但请稍后手动重试。"
  fi
}

service_file_needs_repair() {
  [[ -f "${SINGBOX_SERVICE_FILE}" ]] || return 0
  grep -Fqx "ExecStart=${SINGBOX_BIN_PATH} run -c ${SINGBOX_CONFIG_FILE}" "${SINGBOX_SERVICE_FILE}" || return 0
  return 1
}
