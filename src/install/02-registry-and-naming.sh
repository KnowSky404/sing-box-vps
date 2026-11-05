
validate_protocol() {
  local runtime
  runtime=$(protocol_registry_field "$1" runtime_id) || return 1
  [[ "$1" == "${runtime}" ]]
}

protocol_display_name() {
  protocol_registry_field "$1" display_name || printf '%s' "$1"
}

node_naming_config_file_path() {
  printf '%s/node-naming.json' "${SB_PROJECT_DIR}"
}

validate_node_host_label() {
  local label=${1:-} label_bytes control_pattern=$'[\001-\037\177]'
  [[ "${label}" == "$(trim_whitespace "${label}")" ]] || return 1
  [[ -n "${label}" && ! "${label}" =~ ${control_pattern} ]] || return 1
  label_bytes=$(printf '%s' "${label}" | wc -c) || return 1
  [[ "${label_bytes}" -le 128 ]]
}

node_name_host_label() {
  local config_file label
  config_file=$(node_naming_config_file_path) || return 1
  [[ ! -L "${config_file}" ]] || return 1
  if [[ -e "${config_file}" ]]; then
    [[ -f "${config_file}" ]] || return 1
    command -v jq >/dev/null 2>&1 || {
      printf '[WARN] 读取已有 node-naming.json 需要 jq；请先安装 jq，原设置未修改。\n' >&2
      return 1
    }
    # Validate JSON before shell extraction: Bash cannot retain a NUL byte.
    jq -e 'type == "object" and keys == ["host_label"] and
      (.host_label | type == "string" and length > 0 and utf8bytelength <= 128 and
        (test("[\u0000-\u001F\u007F]") | not))' "${config_file}" >/dev/null || return 1
    label=$(jq -er 'select(type == "object" and keys == ["host_label"]) | .host_label | select(type == "string")' "${config_file}") || return 1
  else
    label=$(hostname) || return 1
  fi
  validate_node_host_label "${label}" || return 1
  printf '%s' "${label}"
}

write_node_naming_config() (
  local label=${1:-} config_file config_dir tmp_file='' had_original=n phase=prepare committed=n
  label=$(trim_whitespace "${label}") || return 1
  validate_node_host_label "${label}" || return 1
  config_file=$(node_naming_config_file_path) || return 1
  [[ ! -L "${config_file}" && ! -L "${config_file}.bak" ]] || return 1
  [[ ! -e "${config_file}" || -f "${config_file}" ]] || return 1
  [[ ! -e "${config_file}.bak" || -f "${config_file}.bak" ]] || return 1
  config_dir=$(dirname "${config_file}") || return 1
  mkdir -p "${config_dir}" || return 1
  trap '[[ -z "${tmp_file}" ]] || rm -f -- "${tmp_file}"' EXIT
  trap 'printf "[WARN] 显示标签设置已中断 (phase=%s, committed=%s)；请回读设置确认最终状态。\n" "${phase}" "${committed}" >&2; exit 1' HUP INT TERM
  tmp_file=$(storage_mktemp "${config_dir}/.node-naming.XXXXXX") || return 1
  chmod 600 "${tmp_file}" || return 1
  jq -n --arg label "${label}" '{host_label:$label}' > "${tmp_file}" || return 1
  jq -e --arg label "${label}" '. == {host_label:$label}' "${tmp_file}" >/dev/null || return 1
  if [[ -e "${config_file}" ]]; then
    phase=backup
    had_original=y
    cp -p -- "${config_file}" "${config_file}.bak" || return 1
    chmod 600 "${config_file}.bak" || return 1
  fi
  phase=commit
  mv -- "${tmp_file}" "${config_file}" || return 1
  committed=y
  tmp_file=''
  phase=postcheck
  if [[ "$(node_name_host_label)" != "${label}" ]]; then
    phase=rollback
    if [[ "${had_original}" == y ]]; then
      tmp_file=$(storage_mktemp "${config_dir}/.node-naming.XXXXXX") || return 1
      cp -p -- "${config_file}.bak" "${tmp_file}" || return 1
      mv -- "${tmp_file}" "${config_file}" || return 1
      tmp_file=''
    else
      rm -f -- "${config_file}" || return 1
    fi
    printf '[WARN] 显示标签回读失败，已恢复原设置。\n' >&2
    return 1
  fi
)

configure_node_naming_interactive() {
  local current answer
  current=$(node_name_host_label) || { log_warn '显示标签设置无法读取，请检查 node-naming.json。'; return 1; }
  printf '主机显示标签只用于新实例的默认名称；已有实例名称、同步身份和运行配置保持不变。\n'
  read -rp "主机显示标签（当前: ${current}，留空保持）: " answer || return 1
  [[ -n "${answer}" ]] || return 0
  if ! write_node_naming_config "${answer}"; then
    log_warn '主机显示标签未保存；请输入不含控制字符、最多 128 UTF-8 字节的非空名称。'
    return 1
  fi
  log_success '主机显示标签已保存；未重启服务或推送节点。'
}

default_instance_node_name() {
  local protocol=${1:-} snapshot=${2:-} host_label prefix candidate ordinal index=1
  protocol=$(normalize_protocol_id "${protocol}") || return 1
  host_label=$(node_name_host_label) || {
    printf '[WARN] 无法读取主机显示标签，未生成默认名称；请检查 node-naming.json。\n' >&2
    return 1
  }
  prefix="${host_label}-${protocol}"
  # Fresh prompts run before dependency installation. With no stored preference
  # or inventory, generating the first name must not require jq.
  if [[ -z "${snapshot}" ]]; then
    printf '%s-01' "${prefix}"
    return 0
  fi
  jq -e 'type == "object" and (.instances | type == "array") and
    all(.instances[]; .name | type == "string")' <<< "${snapshot}" >/dev/null || return 1
  while true; do
    printf -v ordinal '%02d' "${index}"
    candidate="${prefix}-${ordinal}"
    if ! jq -e --arg name "${candidate}" 'any(.instances[]; .name == $name)' <<< "${snapshot}" >/dev/null; then
      printf '%s' "${candidate}"
      return 0
    fi
    index=$((index + 1))
  done
}

default_instance_node_name_from_file() {
  local protocol=${1:-} snapshot_file=${2:-} snapshot
  [[ -f "${snapshot_file}" && ! -L "${snapshot_file}" ]] || return 1
  snapshot=$(cat -- "${snapshot_file}") || return 1
  default_instance_node_name "${protocol}" "${snapshot}"
}

# Display composition only: no instance, user, external-key or technical-tag writes.
format_node_display_name() {
  local base=${1:-} user_suffix=${2:-} up=${3:-} down=${4:-} label=${5:-}
  local suffix='' bandwidth stack digest
  base=$(trim_node_display_base "${base}") || return 1
  [[ -z "${user_suffix}" ]] || suffix="-${user_suffix}"
  bandwidth=$(bandwidth_limit_name_suffix "${up}" "${down}") || return 1
  [[ -z "${bandwidth}" ]] || suffix="${suffix}-${bandwidth}"
  stack=$(network_stack_suffix_from_label "${label}") || return 1
  [[ -z "${stack}" ]] || suffix="${suffix}-${stack}"
  digest=$(printf '%s' "${base}${suffix}" | sha256sum) || return 1
  digest=${digest%% *}
  jq -ern --arg base "${base}" --arg suffix "${suffix}" --arg digest "${digest:0:12}" '
    select(($base | length > 0 and (test("[\u0000-\u001F\u007F]") | not)) and
      ($suffix | test("[\u0000-\u001F\u007F]") | not)) |
    if (($base + $suffix) | utf8bytelength) <= 256 then $base + $suffix
    else ("-n-" + $digest + $suffix) as $tail |
      (256 - ($tail | utf8bytelength)) as $budget | select($budget > 0) |
      ($base[0:256] | until(utf8bytelength <= $budget; .[0:-1])) + $tail
    end'
}

trim_node_display_base() {
  jq -ern --arg value "${1:-}" '$value |
    gsub("^[\u0009-\u000D\u0020\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+|[\u0009-\u000D\u0020\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+$"; "") |
    select(length > 0 and (test("[\u0000-\u001F\u007F]") | not))'
}

node_display_address_label() {
  local listener=${1:-} server=${2:-}
  if listener_address_is_wildcard "${listener}"; then
    if [[ "${server}" == *:* ]]; then printf 'IPv6'
    elif [[ "${server}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then printf 'IPv4'; fi
  else
    printf '监听地址'
  fi
}

# Explicit per-operation context; never retained globally or read from live state.
# An optional instance ID limits preparation to that instance's configured users.
structured_node_user_digests() {
  local snapshot=${1:-} instance_id=${2:-} users_text user digest rows=''
  users_text=$(jq -r --arg id "${instance_id}" '
    if type != "object" or (.instances | type != "array") then
      error("invalid node naming snapshot") else . end |
    (if $id == "" then .instances else
      [.instances[] | select(.id == $id)] |
      if length == 1 then . else error("node naming instance unavailable") end end) |
    if all(.[]; (.authentication.users // []) | type == "array") then .
    else error("invalid node naming users") end |
    [.[].authentication.users[]?.name] |
    if all(.[]; type == "string" and length > 0 and
      (test("[\u0000-\u001F\u007F]") | not)) then unique[]
    else error("invalid node naming user") end' <<< "${snapshot}") || return 1
  while IFS= read -r user; do
    [[ -n "${user}" ]] || continue
    digest=$(printf '%s' "${user}" | sha256sum) || return 1
    digest=${digest%% *}
    [[ "${digest}" =~ ^[0-9a-f]{64}$ ]] || return 1
    rows="${rows}${user}"$'\t'"${digest}"$'\n'
  done <<< "${users_text}"
  printf '%s' "${rows}" | jq -Rn '[inputs | split("\t") |
    {key:.[0],value:.[1]}] | from_entries'
}

structured_node_display_name() {
  local protocol=${1:-} snapshot=${2:-} instance_id=${3:-} user_name=${4-} label=${5:-} user_digests=${6:-}
  local record base count duplicates digest
  local user_suffix='' instance_suffix='' up='' down=''
  protocol=$(normalize_protocol_id "${protocol}") || return 1
  record=$(jq -ce --arg id "${instance_id}" '
    [.instances[] | select(.id == $id)] | select(length == 1) | .[0]' <<< "${snapshot}") || return 1
  # Trim before shell extraction: preserve legitimate edge whitespace while
  # rejecting NUL/interior controls before Bash can discard a NUL byte.
  base=$(jq -er '.name | select(type == "string") |
    gsub("^[\u0009-\u000D\u0020\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+|[\u0009-\u000D\u0020\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+$"; "") |
    select(length > 0 and (test("[\u0000-\u001F\u007F]") | not))' <<< "${record}") || return 1
  count=$(jq -er '(.authentication.users // []) | length' <<< "${record}") || return 1
  if [[ "${count}" -gt 0 ]]; then
    jq -e --arg user "${user_name}" 'any(.authentication.users[]; .name == $user)' <<< "${record}" >/dev/null || return 1
  elif [[ "${protocol}" != shadowsocks || -n "${user_name}" ]]; then
    return 1
  fi
  duplicates=$(jq -er --arg base "${base}" '[.instances[] |
    select((.name | gsub("^[\u0009-\u000D\u0020\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+|[\u0009-\u000D\u0020\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+$"; "")) == $base)] | length' <<< "${snapshot}") || return 1
  if [[ "${duplicates}" -gt 1 ]]; then
    digest=$(printf '%s' "${protocol}:${instance_id}" | sha256sum) || return 1
    digest=${digest%% *}
    instance_suffix="i-${digest:0:12}"
  fi
  if [[ -n "${user_digests}" || "${count}" -gt 1 ]]; then
    if [[ -z "${user_digests}" ]]; then
      user_digests=$(structured_node_user_digests "${snapshot}" "${instance_id}") || return 1
    fi
    user_suffix=$(printf '%s\n%s\n' "${record}" "${user_digests}" | jq -ers --arg user "${user_name}" '
      select(length == 2) | .[0] as $record | .[1] as $digests |
      select(($digests | type == "object") and
        all($digests[]; type == "string" and test("^[0-9a-f]{64}$"))) |
      [$record.authentication.users[]?.name] as $users |
      select(all($users[]; . as $name | $digests | has($name))) |
      if ($users | length) > 1 then
        $digests[$user] as $digest |
        first(range(12; 65; 4) as $width |
          select(all($users[] | select(. != $user);
            . as $other | $digests[$other][0:$width] != $digest[0:$width])) |
          "u-" + $digest[0:$width])
      else "" end') || return 1
  fi
  if [[ -n "${instance_suffix}" ]]; then
    user_suffix="${instance_suffix}${user_suffix:+-${user_suffix}}"
  fi
  if [[ "${protocol}" == hy2 ]]; then
    up=$(jq -r '.bandwidth.up_mbps // empty' <<< "${record}") || return 1
    down=$(jq -r '.bandwidth.down_mbps // empty' <<< "${record}") || return 1
  fi
  format_node_display_name "${base}" "${user_suffix}" "${up}" "${down}" "${label}"
}

default_node_name_for_protocol() {
  local protocol suffix

  protocol=${1:-vless+reality}
  case "${protocol}" in
    vless+reality) suffix="vless" ;;
    hy2) suffix="hy2" ;;
    anytls) suffix="anytls" ;;
    snell) suffix="snell" ;;
    tuic) suffix="tuic" ;;
    hysteria) suffix="hysteria" ;;
    naive) suffix="naive" ;;
    shadowtls) suffix="shadowtls" ;;
    mixed) suffix="mixed" ;;
    *) suffix="${protocol}" ;;
  esac

  printf '%s-%s' "$(hostname)" "${suffix}"
}

normalize_node_name() {
  local node_name=$1

  node_name=$(trim_whitespace "${node_name}")
  case "${node_name}" in
    *+vless) node_name="${node_name%+vless}-vless" ;;
    *+hy2) node_name="${node_name%+hy2}-hy2" ;;
    *+anytls) node_name="${node_name%+anytls}-anytls" ;;
    *+snell) node_name="${node_name%+snell}-snell" ;;
    *+tuic) node_name="${node_name%+tuic}-tuic" ;;
    *+hysteria) node_name="${node_name%+hysteria}-hysteria" ;;
    *+naive) node_name="${node_name%+naive}-naive" ;;
    *+shadowtls) node_name="${node_name%+shadowtls}-shadowtls" ;;
    *+mixed) node_name="${node_name%+mixed}-mixed" ;;
  esac

  printf '%s' "${node_name}"
}

network_stack_suffix_from_label() {
  case "$1" in
    IPv4|ipv4|v4) printf 'v4' ;;
    IPv6|ipv6|v6) printf 'v6' ;;
    *) printf '' ;;
  esac
}

node_name_for_network_stack() {
  local base_name=$1
  local address_label=${2:-}
  local stack_suffix

  base_name=$(normalize_node_name "${base_name}")
  stack_suffix=$(network_stack_suffix_from_label "${address_label}")
  if [[ -n "${stack_suffix}" ]]; then
    printf '%s-%s' "${base_name}" "${stack_suffix}"
  else
    printf '%s' "${base_name}"
  fi
}

bandwidth_limit_name_suffix() {
  local up_mbps=${1:-}
  local down_mbps=${2:-}
  local parts=()

  if [[ -n "${up_mbps}" ]]; then
    parts+=("U${up_mbps}M")
  fi
  if [[ -n "${down_mbps}" ]]; then
    parts+=("D${down_mbps}M")
  fi

  if [[ ${#parts[@]} -eq 0 ]]; then
    printf ''
  else
    local IFS='-'
    printf '%s' "${parts[*]}"
  fi
}

display_node_name_for_protocol() {
  local protocol=$1
  local base_name=${2:-}
  local address_label=${3:-}
  local up_mbps="" down_mbps=""

  protocol=$(normalize_protocol_id "${protocol}" 2>/dev/null || printf '%s' "${protocol}")
  base_name=$(normalize_node_name "${base_name}")
  if [[ -z "${base_name}" ]]; then
    return 1
  fi

  case "${protocol}" in
    vless-reality)
      up_mbps="${SB_VLESS_RATE_LIMIT_UP_MBPS:-}"
      down_mbps="${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}"
      ;;
    hy2)
      up_mbps="${SB_HY2_UP_MBPS:-}"
      down_mbps="${SB_HY2_DOWN_MBPS:-}"
      ;;
  esac

  format_node_display_name "${base_name}" '' "${up_mbps}" "${down_mbps}" "${address_label}"
}

vless_reality_display_node_name() {
  local base_name=$1
  local address_label=${2:-}

  display_node_name_for_protocol "vless-reality" "${base_name}" "${address_label}"
}

protocol_inbound_tag() {
  protocol_registry_field "$1" default_tag
}

protocol_registry_record() {
  local requested=${1:-} record
  local fields=() aliases=() alias
  [[ -n "${requested}" ]] || return 1
  for record in "${SB_PROTOCOL_REGISTRY[@]}"; do
    IFS='|' read -r -a fields <<< "${record}"
    if [[ "${requested}" == "${fields[0]}" ]]; then
      printf '%s' "${record}"
      return 0
    fi
    # Bash 4.2 (CentOS 7) treats an empty array as unset under nounset.
    [[ -n "${fields[20]}" ]] || continue
    IFS=',' read -r -a aliases <<< "${fields[20]}"
    for alias in "${aliases[@]}"; do
      if [[ "${requested}" == "${alias}" ]]; then
        printf '%s' "${record}"
        return 0
      fi
    done
  done
  return 1
}

protocol_registry_field() {
  local record index
  local fields=()
  record=$(protocol_registry_record "${1:-}") || return 1
  IFS='|' read -r -a fields <<< "${record}"
  case "${2:-}" in
    state_id) index=0 ;;
    runtime_id) index=1 ;;
    agent_id) index=2 ;;
    family) index=3 ;;
    preset) index=4 ;;
    role) index=5 ;;
    type) index=6 ;;
    display_name) index=7 ;;
    default_tag) index=8 ;;
    menu_order) index=9 ;;
    subman_type) index=11 ;;
    listen_networks) index=12 ;;
    traffic_networks) index=13 ;;
    minimum_project_core) index=14 ;;
    multi_instance) index=15 ;;
    certificate_contract) index=16 ;;
    share_formats) index=17 ;;
    probe) index=18 ;;
    handlers) index=21 ;;
    *) return 1 ;;
  esac
  printf '%s' "${fields[index]}"
}

protocol_registry_static_json() {
  printf '%s\n' "${SB_PROTOCOL_REGISTRY[@]}" | jq -Rn '
    def csv: split(",") | map(select(length > 0));
    [inputs | split("|") | {
      state_id: .[0], runtime_id: .[1], agent_id: .[2], family: .[3],
      preset: .[4], role: .[5], type: .[6], display_name: .[7],
      default_tag: .[8], menu_order: (.[9] | tonumber),
      minimum_project_core: .[14], aliases: (.[20] | csv),
      core_supported: true, implemented: true,
      available: null, availability_reason: "requires_instance_preflight",
      validated: {status: "not_assessed", method: .[18]},
      lifecycle: {deploy: true, takeover: true, edit: true, remove: true},
      subman_type: .[11],
      listen_networks: (.[12] | csv), traffic_networks: (.[13] | csv),
      multi_instance: (.[15] == "true"), certificate_contract: .[16],
      share_formats: (.[17] | csv), probe: .[18],
      legacy_capabilities: (.[19] | fromjson), features: (.[19] | fromjson), handlers: (.[21] | csv)
    }]'
}

# Keep the stable protocol contract separate from a read-only observation of
# the currently installed core.  `available` remains instance-specific and
# nullable for compatibility; `environment` only reports the host/core/build
# prerequisites that can be checked without changing state or starting a
# listener.
protocol_registry_json() {
  local registry environment_registry environment

  registry=$(protocol_registry_static_json) || return 1
  environment_registry=$(jq -c '
    map({
      state_id, role, type, minimum_project_core,
      availability:(if (.role == "inbound" and
        (.type | IN("hysteria","hysteria2","tuic")) and
        .listen_networks == ["udp"]) then "with_quic" else "builtin" end)
    })
  ' <<< "${registry}") || return 1
  environment=$(component_registry_environment_bulk_json "${environment_registry}") || return 1
  jq -c --argjson environment "${environment}" '
    ($environment | map({key:.state_id,value:.}) | from_entries) as $by_id |
    map(. + {environment:$by_id[.state_id]})
  ' <<< "${registry}"
}

component_registry_record() {
  local requested=${1:-} record
  local fields=()
  [[ -n "${requested}" ]] || return 1
  for record in "${SB_COMPONENT_REGISTRY[@]}"; do
    IFS='|' read -r -a fields <<< "${record}"
    if [[ "${requested}" == "${fields[0]}" ]]; then
      printf '%s' "${record}"
      return 0
    fi
  done
  return 1
}

component_registry_resolve_id() {
  local role=${1:-} type=${2:-} record
  local fields=()
  [[ -n "${role}" && -n "${type}" ]] || return 1
  for record in "${SB_COMPONENT_REGISTRY[@]}"; do
    IFS='|' read -r -a fields <<< "${record}"
    if [[ "${role}" == "${fields[1]}" && "${type}" == "${fields[2]}" ]]; then
      printf '%s' "${fields[0]}"
      return 0
    fi
  done
  return 1
}

component_registry_field() {
  local record index
  local fields=()
  record=$(component_registry_record "${1:-}") || return 1
  IFS='|' read -r -a fields <<< "${record}"
  case "${2:-}" in
    state_id) index=0 ;;
    role) index=1 ;;
    type) index=2 ;;
    display_name) index=3 ;;
    minimum_project_core) index=4 ;;
    availability) index=5 ;;
    features) index=6 ;;
    *) return 1 ;;
  esac
  printf '%s' "${fields[index]}"
}

component_environment_dependency_json() {
  local name=${1:-} status=${2:-} reason=${3:-} required=${4:-true}
  jq -cn --arg name "${name}" --arg status "${status}" --arg reason "${reason}" \
    --argjson required "${required}" \
    '{name:$name,status:$status,required:$required} +
      (if $reason == "" then {} else {reason:$reason} end)'
}

namespace_runtime_build_dependency_json() {
  local platform=${1:-} architecture=${2:-} version=${3:-} tags_status=${4:-} tags=${5:-'[]'}
  local status=available reason=''
  # These exact builds reproduce SIGSEGV on locked-thread exit.
  # Unknown tags remain unassessed; do not infer the purego tag from CGO alone.
  if [[ "${platform}" == Linux && ( "${architecture}" == aarch64 || "${architecture}" == arm64 ) &&
        ( "${version}" == 1.14.2 || "${version}" == 1.14.4 ) ]]; then
    if [[ "${tags_status}" != available ]]; then
      status=not_assessed; reason=namespace_runtime_build_not_assessed
    elif jq -en --argjson tags "${tags}" '$tags | index("with_purego") != null' >/dev/null; then
      status=unavailable; reason=namespace_runtime_unsafe_build
    fi
  fi
  component_environment_dependency_json namespace_runtime_build "${status}" "${reason}" true
}

managed_component_record_uses_namespace() {
  jq -e '.enabled == true and
    ((.role == "network_namespace" and (.type == "default" or .type == "unshare")) or
     any([.config.netns?, .config.control_dialer.netns?, .config.tunnel_dialer.netns?,
           .config.http_client.netns?, .config.realm.http_client.netns?][];
       type == "string" and length > 0))' >/dev/null <<< "${1:-}"
}

managed_component_namespace_runtime_safe() {
  local state=${1:-} version tags='[]' tags_status=not_assessed dependency
  if ! jq -e 'any(.components[]; .enabled == true and
      ((.role == "network_namespace" and (.type == "default" or .type == "unshare")) or
       any([.config.netns?, .config.control_dialer.netns?, .config.tunnel_dialer.netns?,
             .config.http_client.netns?, .config.realm.http_client.netns?][];
         type == "string" and length > 0)))' >/dev/null <<< "${state}"; then return 0; fi
  version=$(detect_installed_singbox_version 2>/dev/null || true)
  if tags=$(detect_installed_singbox_build_tags_json 2>/dev/null); then tags_status=available; else tags='[]'; fi
  dependency=$(namespace_runtime_build_dependency_json "$(uname -s)" "$(uname -m)" "${version}" "${tags_status}" "${tags}") || return 1
  case "$(jq -r .status <<< "${dependency}")" in
    unavailable)
      printf '[ERROR] namespace_runtime_unsafe_build: 当前核心构建的 namespace 路径存在已复现崩溃；配置未发布，请使用已验证的兼容构建。\n' >&2
      return 1 ;;
    not_assessed)
      printf '[ERROR] namespace_runtime_build_not_assessed: 无法确认当前核心构建的 namespace 兼容性；配置未发布。\n' >&2
      return 3 ;;
  esac
}

component_runtime_library_available() {
  local search_path candidate managed_library_path
  managed_library_path=$(singbox_library_path) || return 1
  if [[ -f "${managed_library_path}" && ! -L "${managed_library_path}" && -r "${managed_library_path}" ]]; then
    return 0
  fi
  if command -v ldconfig >/dev/null 2>&1 &&
     ldconfig -p 2>/dev/null | grep -Eq '[[:space:]]libcronet\.so([.[:digit:]]*)?[[:space:]]'; then
    return 0
  fi
  IFS=: read -r -a search_paths <<< "${LD_LIBRARY_PATH:-}"
  for search_path in "${search_paths[@]}"; do
    [[ -n "${search_path}" && "${search_path}" != *$'\n'* && "${search_path}" != *$'\r'* ]] || continue
    candidate="${search_path%/}/libcronet.so"
    [[ -f "${candidate}" && ! -L "${candidate}" && -r "${candidate}" ]] && return 0
  done
  return 1
}

# The version command is the only stable, credential-free way for the
# registry to observe build tags at runtime.  Return 2 when an older or
# wrapper binary does not report a Tags line so callers can distinguish
# "not reported" from a known tag mismatch.  No arbitrary version output is
# exposed to the caller; only a validated, sorted tag array is emitted.
detect_installed_singbox_build_tags_json() {
  [[ -x "${SINGBOX_BIN_PATH}" ]] || return 1

  local version_output tags_line tag_status
  version_output=$("${SINGBOX_BIN_PATH}" version 2>/dev/null) || return 1
  if tags_line=$(printf '%s\n' "${version_output}" | awk '
    index($0, "Tags:") == 1 {
      sub(/^Tags:[[:space:]]*/, "")
      print
      found=1
      exit 0
    }
    END {
      if (!found) exit 2
    }
  '); then
    :
  else
    tag_status=$?
    [[ "${tag_status}" -eq 2 ]] && return 2
    return 1
  fi

  jq -cn --arg tags "${tags_line}" '
    ($tags | if . == "" then [] else split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) end) as $values |
    if all($values[]; test("^[A-Za-z0-9][A-Za-z0-9_.+\\-]{0,127}$")) and
       (($values | unique | length) == ($values | length)) then
      ($values | sort)
    else
      error("invalid_build_tags")
    end
  ' || return 1
}

component_registry_environment_probe() {
  local state_id=${1:-} role=${2:-} type=${3:-} minimum=${4:-} availability=${5:-}
  local platform core_version core_status=unavailable core_reason=sing_box_binary_missing
  local namespace_dependency
  local overall=unavailable overall_reason=sing_box_binary_missing dependency_rows=()
  local root_status=available
  local command_status command_reason build_tag build_tags_json='[]'
  local build_tags_status=unavailable build_tags_reason=sing_box_binary_missing tag_status

  platform=$(uname -s 2>/dev/null || printf 'unknown')
  if [[ ! -x "${SINGBOX_BIN_PATH}" ]]; then
    core_version=''
  else
    core_version=$(detect_installed_singbox_version 2>/dev/null || true)
    if [[ ! "${core_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      core_reason=sing_box_version_unavailable
    elif ! singbox_version_at_least "${core_version}" "${minimum}"; then
      core_reason=sing_box_version_too_old
    else
      core_status=available
      core_reason=''
    fi
  fi
  dependency_rows+=("sing_box_binary"$'\t'"${core_status}"$'\t'"${core_reason}"$'\t'"true")
  dependency_rows+=("sing_box_version"$'\t'"$([[ "${core_status}" == available ]] && printf available || printf unavailable)"$'\t'"$([[ "${core_status}" == available ]] && printf '' || printf '%s' "${core_reason}")"$'\t'"true")
  overall_reason=${core_reason}

  if [[ -n "${core_version}" && "${core_reason}" != sing_box_version_unavailable ]]; then
    if build_tags_json=$(detect_installed_singbox_build_tags_json); then
      build_tags_status=available
      build_tags_reason=''
    else
      tag_status=$?
      build_tags_json='[]'
      if [[ "${tag_status}" -eq 2 ]]; then
        build_tags_status=not_assessed
        build_tags_reason=build_tags_not_reported
      else
        build_tags_status=unavailable
        build_tags_reason=sing_box_build_tags_unavailable
      fi
    fi
  elif [[ "${core_reason}" == sing_box_version_unavailable ]]; then
    build_tags_status=not_assessed
    build_tags_reason=sing_box_version_unavailable
  fi

  if [[ "${core_status}" == available ]]; then
    overall=available
    overall_reason=''
  fi

  component_add_dependency() {
    local name=$1 status=$2 reason=${3:-} required=${4:-true} item
    dependency_rows+=("${name}"$'\t'"${status}"$'\t'"${reason}"$'\t'"${required}")
    if [[ "${required}" == true ]]; then
      if [[ "${status}" == unavailable && "${overall}" != unavailable ]]; then
        overall=unavailable
        overall_reason=${reason:-${name}_unavailable}
      elif [[ "${status}" == not_assessed && "${overall}" == available ]]; then
        overall=not_assessed
        overall_reason=${reason:-${name}_not_assessed}
      fi
    fi
  }

  case "${type}" in
    tun|bridge)
      if [[ "${EUID}" -ne 0 ]]; then root_status=unavailable; else root_status=available; fi
      component_add_dependency root "${root_status}" \
        "$([[ "${root_status}" == available ]] && printf '' || printf root_required)" true || return 1
      if command -v ip >/dev/null 2>&1; then
        component_add_dependency iproute2 available '' true || return 1
      else
        component_add_dependency iproute2 unavailable iproute2_missing true || return 1
      fi
      if [[ "${type}" == tun && "${platform}" != Linux ]]; then
        component_add_dependency platform unavailable tun_linux_only true || return 1
      fi
      if [[ "${type}" == bridge ]]; then
        component_add_dependency net_admin available '' false || return 1
      fi
      ;;
    redirect|tproxy)
      if [[ "${EUID}" -ne 0 ]]; then root_status=unavailable; else root_status=available; fi
      component_add_dependency root "${root_status}" \
        "$([[ "${root_status}" == available ]] && printf '' || printf root_required)" true || return 1
      if command -v iptables >/dev/null 2>&1 || command -v nft >/dev/null 2>&1; then
        component_add_dependency transparent_rule_tool available '' true || return 1
      else
        component_add_dependency transparent_rule_tool unavailable transparent_rule_tool_missing true || return 1
      fi
      if [[ "${type}" == tproxy && "${platform}" != Linux ]]; then
        component_add_dependency platform unavailable tproxy_linux_only true || return 1
      fi
      ;;
    cloudflared|tailscale)
      # Both runtimes are embedded in the core behind their build tags.
      component_add_dependency external_auth not_assessed external_auth_required true || return 1
      ;;
    openconnect)
      component_add_dependency external_auth not_assessed external_auth_required true || return 1
      ;;
    openvpn-client|openvpn-server)
      component_add_dependency external_auth not_assessed external_auth_required true || return 1
      ;;
    tor)
      if command -v tor >/dev/null 2>&1; then
        command_status=available; command_reason=''
      else
        command_status=unavailable; command_reason=tor_binary_missing
      fi
      component_add_dependency tor_binary "${command_status}" "${command_reason}" true || return 1
      ;;
    naive)
      if component_runtime_library_available; then
        component_add_dependency libcronet available '' true || return 1
      else
        component_add_dependency libcronet unavailable libcronet_missing true || return 1
      fi
      ;;
    default|unshare)
      if [[ "${role}" == network_namespace ]]; then
        namespace_dependency=$(namespace_runtime_build_dependency_json "${platform}" "$(uname -m)" "${core_version}" "${build_tags_status}" "${build_tags_json}") || return 1
        component_add_dependency namespace_runtime_build "$(jq -r .status <<< "${namespace_dependency}")" \
          "$(jq -r '.reason // ""' <<< "${namespace_dependency}")" true || return 1
      fi
      ;;
    resolved)
      if [[ "${platform}" == Linux ]]; then
        component_add_dependency platform available '' true || return 1
      else
        component_add_dependency platform unavailable resolved_linux_only true || return 1
      fi
      if [[ -S /run/dbus/system_bus_socket || -S /var/run/dbus/system_bus_socket ]]; then
        component_add_dependency dbus_system_bus available '' true || return 1
      else
        component_add_dependency dbus_system_bus unavailable dbus_system_bus_missing true || return 1
      fi
      ;;
  esac

  if [[ "${availability}" == with_* ]]; then
    build_tag=${availability}
    if [[ "${build_tags_status}" == available ]]; then
      if jq -en --arg tag "${build_tag}" --argjson tags "${build_tags_json}" \
        '$tags | index($tag) != null' >/dev/null; then
        component_add_dependency "build_tag_${build_tag}" available '' true || return 1
      else
        component_add_dependency "build_tag_${build_tag}" unavailable \
          "build_tag_missing_${build_tag}" true || return 1
      fi
    elif [[ "${build_tags_status}" == not_assessed ]]; then
      component_add_dependency "build_tag_${build_tag}" not_assessed \
        "${build_tags_reason}" true || return 1
    else
      component_add_dependency "build_tag_${build_tag}" unavailable \
        "${build_tags_reason}" true || return 1
    fi
  fi

  local dependencies
  dependencies=$(printf '%s\n' "${dependency_rows[@]}" | jq -Rsc '
    split("\n") | map(select(length > 0) | split("\t") |
      {name:.[0],status:.[1],required:(.[3] == "true")} +
      (if .[2] == "" then {} else {reason:.[2]} end))
  ') || return 1
  jq -cn --arg state_id "${state_id}" --arg platform "${platform}" \
    --arg overall "${overall}" --arg reason "${overall_reason}" \
    --arg core_status "${core_status}" --arg core_version "${core_version}" \
    --arg minimum "${minimum}" --arg availability "${availability}" \
    --arg tags_status "${build_tags_status}" --arg tags_reason "${build_tags_reason}" \
    --argjson tags "${build_tags_json}" \
    --argjson dependencies "${dependencies}" \
    '{state_id:$state_id,status:$overall,reason:(if $reason == "" then null else $reason end),
      static_availability:$availability,
      platform:{name:$platform},
      core:{status:$core_status,version:(if $core_version == "" then null else $core_version end),minimum:$minimum,
        build_tags:{status:$tags_status,values:$tags,reason:(if $tags_reason == "" then null else $tags_reason end)}},
      dependencies:$dependencies}'
}

component_registry_environment_bulk_json() {
  local static platform core_version core_probe_reason namespace_dependency
  local root_ok=false ip_ok=false transparent_ok=false
  local tor_ok=false libcronet_ok=false
  local dbus_ok=false
  local core_tags_json='[]' core_tags_status=unavailable core_tags_reason=sing_box_binary_missing tag_status

  if [[ -n "${1:-}" ]]; then
    static=${1}
  else
    static=$(component_registry_static_json) || return 1
  fi
  platform=$(uname -s 2>/dev/null || printf 'unknown')
  core_probe_reason=sing_box_binary_missing
  core_version=''
  if [[ -x "${SINGBOX_BIN_PATH}" ]]; then
    core_version=$(detect_installed_singbox_version 2>/dev/null || true)
    if [[ ! "${core_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      core_probe_reason=sing_box_version_unavailable
      core_version=''
      core_tags_status=not_assessed
      core_tags_reason=sing_box_version_unavailable
    else
      core_probe_reason=''
      if core_tags_json=$(detect_installed_singbox_build_tags_json); then
        core_tags_status=available
        core_tags_reason=''
      else
        tag_status=$?
        core_tags_json='[]'
        if [[ "${tag_status}" -eq 2 ]]; then
          core_tags_status=not_assessed
          core_tags_reason=build_tags_not_reported
        else
          core_tags_status=unavailable
          core_tags_reason=sing_box_build_tags_unavailable
        fi
      fi
    fi
  fi
  [[ "${EUID}" -eq 0 ]] && root_ok=true
  command -v ip >/dev/null 2>&1 && ip_ok=true
  (command -v iptables >/dev/null 2>&1 || command -v nft >/dev/null 2>&1) && transparent_ok=true
  command -v tor >/dev/null 2>&1 && tor_ok=true
  component_runtime_library_available && libcronet_ok=true || :
  [[ -S /run/dbus/system_bus_socket || -S /var/run/dbus/system_bus_socket ]] && dbus_ok=true

  namespace_dependency=$(namespace_runtime_build_dependency_json "${platform}" "$(uname -m)" "${core_version}" "${core_tags_status}" "${core_tags_json}") || return 1
  jq -cn --argjson registry "${static}" --arg platform "${platform}" \
    --argjson namespace_dependency "${namespace_dependency}" \
    --arg core_version "${core_version}" --arg core_probe_reason "${core_probe_reason}" \
    --argjson root_ok "${root_ok}" --argjson ip_ok "${ip_ok}" \
    --argjson transparent_ok "${transparent_ok}" --argjson tor_ok "${tor_ok}" \
    --argjson libcronet_ok "${libcronet_ok}" --argjson dbus_ok "${dbus_ok}" \
    --arg tags_status "${core_tags_status}" \
    --arg tags_reason "${core_tags_reason}" --argjson core_tags "${core_tags_json}" '
    def version_parts($value): $value | split(".") | map(tonumber);
    def at_least($value; $minimum):
      (version_parts($value)) as $a | (version_parts($minimum)) as $b |
      ($a[0] > $b[0] or
       ($a[0] == $b[0] and ($a[1] > $b[1] or
        ($a[1] == $b[1] and $a[2] >= $b[2]))));
    def dependency($name; $status; $reason; $required):
      {name:$name,status:$status,required:$required} +
      (if $reason == "" then {} else {reason:$reason} end);
    def unavailable($name; $reason; $required):
      dependency($name; "unavailable"; $reason; $required);
    def available($name; $required):
      dependency($name; "available"; ""; $required);
    def not_assessed($name; $reason; $required):
      dependency($name; "not_assessed"; $reason; $required);
    def build_tag_dependencies:
      if (.availability | startswith("with_")) then
        .availability as $tag |
        ("build_tag_" + $tag) as $name |
        if $tags_status == "available" then
          if ($core_tags | index($tag)) == null then
            [unavailable($name; "build_tag_missing_" + $tag; true)]
          else
            [available($name; true)]
          end
        elif $tags_status == "not_assessed" then
          [not_assessed($name; $tags_reason; true)]
        else
          [unavailable($name; $tags_reason; true)]
        end
      else [] end;
    def core:
      if $core_version == "" then
        {status:"unavailable",reason:$core_probe_reason}
      elif at_least($core_version; .minimum_project_core) then
        {status:"available",reason:""}
      else
        {status:"unavailable",reason:"sing_box_version_too_old"}
      end;
    def extra_dependencies:
      if .type == "tun" then
        (if $root_ok then available("root"; true) else unavailable("root"; "root_required"; true) end),
        (if $ip_ok then available("iproute2"; true) else unavailable("iproute2"; "iproute2_missing"; true) end),
        (if $platform == "Linux" then [] else [unavailable("platform"; "tun_linux_only"; true)] end)
      elif .type == "bridge" then
        (if $root_ok then available("root"; true) else unavailable("root"; "root_required"; true) end),
        (if $ip_ok then available("iproute2"; true) else unavailable("iproute2"; "iproute2_missing"; true) end),
        available("net_admin"; false)
      elif .type == "redirect" or .type == "tproxy" then
        (if $root_ok then available("root"; true) else unavailable("root"; "root_required"; true) end),
        (if $transparent_ok then available("transparent_rule_tool"; true)
         else unavailable("transparent_rule_tool"; "transparent_rule_tool_missing"; true) end),
        (if .type == "tproxy" and $platform != "Linux" then
           [unavailable("platform"; "tproxy_linux_only"; true)] else [] end)
      elif .type == "cloudflared" or .type == "tailscale" then
        not_assessed("external_auth"; "external_auth_required"; true)
      elif .type == "openconnect" or .type == "openvpn-client" or .type == "openvpn-server" then
        not_assessed("external_auth"; "external_auth_required"; true)
      elif .type == "tor" then
        (if $tor_ok then available("tor_binary"; true)
         else unavailable("tor_binary"; "tor_binary_missing"; true) end)
      elif .role == "outbound" and .type == "naive" then
        (if $libcronet_ok then available("libcronet"; true)
         else unavailable("libcronet"; "libcronet_missing"; true) end)
      elif .role == "network_namespace" then
        $namespace_dependency
      elif .type == "resolved" then
        (if $platform == "Linux" then []
         else [unavailable("platform"; "resolved_linux_only"; true)] end),
        (if $dbus_ok then available("dbus_system_bus"; true)
         else unavailable("dbus_system_bus"; "dbus_system_bus_missing"; true) end)
      else [] end;
    def final($core; $dependencies):
      if $core.status == "unavailable" then
        {status:"unavailable",reason:$core.reason}
      elif any($dependencies[]; .required and .status == "unavailable") then
        (first($dependencies[] | select(.required and .status == "unavailable")) |
          {status:"unavailable",reason:(.reason // (.name + "_unavailable"))})
      elif any($dependencies[]; .required and .status == "not_assessed") then
        (first($dependencies[] | select(.required and .status == "not_assessed")) |
          {status:"not_assessed",reason:(.reason // (.name + "_not_assessed"))})
      else {status:"available",reason:null} end;
    $registry | map(
      . as $entry | (core) as $core |
      ([dependency("sing_box_binary"; $core.status; $core.reason; true),
        dependency("sing_box_version"; $core.status; $core.reason; true)] +
       (([extra_dependencies] | flatten) + ($entry | build_tag_dependencies))) as $dependencies |
       (final($core; $dependencies)) as $result |
       {state_id:$entry.state_id,status:$result.status,reason:$result.reason,
       static_availability:$entry.availability,platform:{name:$platform},
       core:{status:$core.status,
             version:(if $core_version == "" then null else $core_version end),
             minimum:$entry.minimum_project_core,
             build_tags:{status:$tags_status,values:$core_tags,
                         reason:(if $tags_reason == "" then null else $tags_reason end)}},
       dependencies:$dependencies}
    )'
}

component_registry_environment_json() {
  component_registry_environment_bulk_json
}

# Refine the registry-level environment observation for one persisted
# component record. The registry cannot know whether an endpoint selected its
# internal gVisor stack or a privileged system interface, so this layer adds
# only configuration-derived requirements. It never performs a login or
# mutates interfaces/routes; missing credentials and external control planes
# remain not_assessed in the base observation.
managed_component_instance_environment_json() {
  local record=${1:-} base=${2:-} role type config state_id registry_record minimum availability
  local namespace_dependency
  local dependencies status reason system_mode=internal requires_root=false
  local requires_tun_device=false requires_gvisor=false tags_status tags_reason tags='[]'
  local dependency_name dependency_status dependency_reason dependency_item requirements
  [[ -n "${record}" ]] || return 1
  jq -e 'type == "object" and (.role | type == "string") and
    (.type | type == "string") and (.config | type == "object")' <<< "${record}" >/dev/null 2>&1 || return 1

  role=$(jq -r '.role' <<< "${record}") || return 1
  type=$(jq -r '.type' <<< "${record}") || return 1
  config=$(jq -c '.config' <<< "${record}") || return 1
  state_id=$(component_registry_resolve_id "${role}" "${type}") || return 1

  if [[ -z "${base}" ]]; then
    registry_record=$(component_registry_record "${state_id}") || return 1
    minimum=$(component_registry_field "${state_id}" minimum_project_core) || return 1
    availability=$(component_registry_field "${state_id}" availability) || return 1
    base=$(component_registry_environment_probe "${state_id}" "${role}" "${type}" \
      "${minimum}" "${availability}") || return 1
  fi
  jq -e 'type == "object" and (.state_id | type == "string") and
    (.dependencies | type == "array") and (.core | type == "object")' <<< "${base}" >/dev/null 2>&1 || return 1
  [[ "$(jq -r '.state_id' <<< "${base}")" == "${state_id}" ]] || return 1

  dependencies=$(jq -c '.dependencies' <<< "${base}") || return 1
  status=$(jq -r '.status // "unavailable"' <<< "${base}") || return 1
  reason=$(jq -r '.reason // ""' <<< "${base}") || return 1
  tags_status=$(jq -r '.core.build_tags.status // "unavailable"' <<< "${base}") || return 1
  tags_reason=$(jq -r '.core.build_tags.reason // ""' <<< "${base}") || return 1
  tags=$(jq -c '.core.build_tags.values // []' <<< "${base}") || return 1

  case "${type}" in
    tun)
      requires_root=true
      requires_tun_device=true
      ;;
    bridge)
      # Bridge uses the host bridge API and requires privilege, but it does
      # not create a TUN character device itself.
      requires_root=true
      ;;
    redirect|tproxy)
      requires_root=true
      ;;
    wireguard|openconnect|openvpn-client|openvpn-server)
      if [[ "$(jq -r 'if .system == true then "system" else "internal" end' <<< "${config}")" == system ]]; then
        system_mode=system
        requires_root=true
        if [[ "${type}" != wireguard ]]; then
          requires_tun_device=true
        fi
      else
        requires_gvisor=true
      fi
      ;;
    tailscale)
      if [[ "$(jq -r 'if .system_interface == true then "system" else "internal" end' <<< "${config}")" == system ]]; then
        system_mode=system
        requires_root=true
        requires_tun_device=true
      else
        requires_gvisor=true
      fi
      ;;
  esac

  instance_add_dependency() {
    dependency_name=${1:-}
    dependency_status=${2:-}
    dependency_reason=${3:-}
    [[ -n "${dependency_name}" && -n "${dependency_status}" ]] || return 1
    if jq -e --arg name "${dependency_name}" 'any(.[]; .name == $name)' <<< "${dependencies}" >/dev/null 2>&1; then
      return 0
    fi
    dependency_item=$(component_environment_dependency_json "${dependency_name}" \
      "${dependency_status}" "${dependency_reason}" true) || return 1
    dependencies=$(jq -c --argjson item "${dependency_item}" '. + [$item]' <<< "${dependencies}") || return 1
    if [[ "${dependency_status}" == unavailable && "${status}" != unavailable ]]; then
      status=unavailable
      reason=${dependency_reason:-${dependency_name}_unavailable}
    elif [[ "${dependency_status}" == not_assessed && "${status}" == available ]]; then
      status=not_assessed
      reason=${dependency_reason:-${dependency_name}_not_assessed}
    fi
  }

  if [[ "${role}" != network_namespace ]] && managed_component_record_uses_namespace "${record}"; then
    namespace_dependency=$(namespace_runtime_build_dependency_json \
      "$(jq -r '.platform.name // "unknown"' <<< "${base}")" "$(uname -m)" \
      "$(jq -r '.core.version // ""' <<< "${base}")" "${tags_status}" "${tags}") || return 1
    instance_add_dependency namespace_runtime_build "$(jq -r .status <<< "${namespace_dependency}")" \
      "$(jq -r '.reason // ""' <<< "${namespace_dependency}")" || return 1
  fi
  if [[ "${requires_root}" == true ]]; then
    if [[ "${EUID}" -eq 0 ]]; then
      instance_add_dependency root available '' || return 1
    else
      instance_add_dependency root unavailable root_required || return 1
    fi
  fi
  if [[ "${requires_tun_device}" == true ]]; then
    if [[ -c /dev/net/tun ]]; then
      instance_add_dependency tun_device available '' || return 1
    else
      instance_add_dependency tun_device unavailable tun_device_missing || return 1
    fi
  fi
  if [[ "${requires_gvisor}" == true ]]; then
    if [[ "${tags_status}" == available ]]; then
      if jq -en --argjson tags "${tags}" '$tags | index("with_gvisor") != null' >/dev/null; then
        instance_add_dependency build_tag_with_gvisor available '' || return 1
      else
        instance_add_dependency build_tag_with_gvisor unavailable build_tag_missing_with_gvisor || return 1
      fi
    elif [[ "${tags_status}" == not_assessed ]]; then
      instance_add_dependency build_tag_with_gvisor not_assessed \
        "${tags_reason:-build_tags_not_reported}" || return 1
    else
      instance_add_dependency build_tag_with_gvisor unavailable \
        "${tags_reason:-sing_box_build_tags_unavailable}" || return 1
    fi
  fi

  if jq -e 'has("host_policy") and (.enabled == true)' <<< "${record}" >/dev/null 2>&1; then
    local host_policy_interface host_policy_type
    host_policy_interface=$(jq -r '.host_policy.ingress_interface' <<< "${record}") || return 1
    host_policy_type=$(jq -r '.type' <<< "${record}") || return 1
    if [[ "$(uname -s 2>/dev/null || printf unknown)" != Linux ]]; then
      instance_add_dependency host_policy_platform unavailable host_policy_linux_only || return 1
    elif [[ "${host_policy_type}" == redirect ]]; then
      if command -v iptables >/dev/null 2>&1 && iptables -t nat -S >/dev/null 2>&1; then
        instance_add_dependency iptables_nat available '' || return 1
      else
        instance_add_dependency iptables_nat unavailable iptables_nat_unavailable || return 1
      fi
    elif [[ "${host_policy_type}" == tproxy ]]; then
      if command -v iptables >/dev/null 2>&1 && iptables -t mangle -S >/dev/null 2>&1; then
        instance_add_dependency iptables_mangle available '' || return 1
      else
        instance_add_dependency iptables_mangle unavailable iptables_mangle_unavailable || return 1
      fi
      if command -v iptables >/dev/null 2>&1 && iptables -j TPROXY -h >/dev/null 2>&1; then
        instance_add_dependency iptables_tproxy_target available '' || return 1
      else
        instance_add_dependency iptables_tproxy_target unavailable iptables_tproxy_target_unavailable || return 1
      fi
      if command -v iptables >/dev/null 2>&1 && iptables -m multiport -h >/dev/null 2>&1; then
        instance_add_dependency iptables_multiport_match available '' || return 1
      else
        instance_add_dependency iptables_multiport_match unavailable iptables_multiport_match_unavailable || return 1
      fi
      if command -v ip >/dev/null 2>&1 && ip -4 rule show >/dev/null 2>&1; then
        instance_add_dependency iproute2_policy_routing available '' || return 1
      else
        instance_add_dependency iproute2_policy_routing unavailable iproute2_policy_routing_unavailable || return 1
      fi
    else
      instance_add_dependency host_policy_type unavailable host_policy_type_unavailable || return 1
    fi
    if command -v ip >/dev/null 2>&1 && ip link show dev "${host_policy_interface}" >/dev/null 2>&1; then
      instance_add_dependency ingress_interface available '' || return 1
    else
      instance_add_dependency ingress_interface unavailable ingress_interface_unavailable || return 1
    fi
  fi

  requirements=$(jq -cn --arg mode "${system_mode}" --argjson root "${requires_root}" \
    --argjson tun "${requires_tun_device}" --argjson gvisor "${requires_gvisor}" \
    --argjson redirect_policy "$(jq -r '.type == "redirect" and has("host_policy") and (.enabled == true)' <<< "${record}")" \
    --argjson tproxy_policy "$(jq -r '.type == "tproxy" and has("host_policy") and (.enabled == true)' <<< "${record}")" \
    '{system_interface:($mode == "system"),system_mode:$mode,requires_root:$root,
      requires_tun_device:$tun,requires_gvisor:$gvisor,
      managed_redirect_host_policy:$redirect_policy,
      redirect_host_policy_scope:(if $redirect_policy then "ipv4_tcp_prerouting" else null end),
      managed_tproxy_host_policy:$tproxy_policy,
      tproxy_host_policy_scope:(if $tproxy_policy then "ipv4_tcp_udp_prerouting_policy_route" else null end)}') || return 1
  jq -cn --argjson base "${base}" --arg status "${status}" --arg reason "${reason}" \
    --argjson dependencies "${dependencies}" --argjson requirements "${requirements}" \
    '$base + {status:$status,reason:(if $reason == "" then null else $reason end),
      dependencies:$dependencies,requirements:$requirements,source:"instance_config"}'
}

component_registry_static_json() {
  printf '%s\n' "${SB_COMPONENT_REGISTRY[@]}" | jq -Rn '
    [inputs | split("|") | {
      state_id: .[0], role: .[1], type: .[2], display_name: .[3],
      minimum_project_core: .[4], availability: .[5],
      features: (.[6] | fromjson),
      implemented: true, available: null, availability_reason: .[5],
      validated: {status: "not_assessed", method: "target_sing_box_check"},
      lifecycle: {
        create: true, replace: true, delete: true, rebuild: true, export: true,
        takeover: (.[1] == "inbound" or .[1] == "endpoint" or .[1] == "outbound" or
                   .[1] == "certificate_provider" or .[1] == "http_client" or
                   .[1] == "service" or .[1] == "network_namespace" or
                   .[1] == "rule_set"), recover: true
      }
    }]'
}

component_registry_json() {
  local environment static
  environment=$(component_registry_environment_json) || return 1
  static=$(component_registry_static_json) || return 1
  jq -cn --argjson static "${static}" --argjson environment "${environment}" '
    $static | map(. as $entry |
      ($environment[] | select(.state_id == $entry.state_id)) as $runtime |
      . + {environment:$runtime})
  '
}

component_registry_inbound_types_json() {
  component_registry_static_json | jq -c '[.[] | select(.role == "inbound") | .type]'
}

list_registered_protocols() {
  local record state_id remainder
  for record in "${SB_PROTOCOL_REGISTRY[@]}"; do
    IFS='|' read -r state_id remainder <<< "${record}"
    printf '%s\n' "${state_id}"
  done
}

protocol_registry_require_handlers() {
  local handler handler_list
  local handlers=()
  handler_list=$(protocol_registry_field "$1" handlers) || return 1
  IFS=',' read -r -a handlers <<< "${handler_list}"
  [[ ${#handlers[@]} -gt 0 ]] || return 1
  for handler in "${handlers[@]}"; do
    if ! declare -F "${handler}" >/dev/null; then
      printf '[ERROR] 协议适配器缺失，未生成配置；请恢复完整的 install.sh。\n' >&2
      return 1
    fi
  done
}

normalize_protocol_id() {
  protocol_registry_field "$1" state_id
}

# Resolve a live core inbound to one managed state adapter.  The core uses the
# same runtime type (`vless`) for ordinary VLESS and VLESS + REALITY, so the
# REALITY TLS material is the discriminator; the historical `vless` alias
# continues to resolve to the REALITY adapter for CLI compatibility.
config_inbound_protocol() {
  local inbound_json=${1:-} inbound_type
  [[ -n "${inbound_json}" ]] || return 1
  inbound_type=$(jq -er '.type' <<< "${inbound_json}") || return 1
  if [[ "${inbound_type}" == "mixed" ]] && [[ "$(jq -r '.tag // empty' <<< "${inbound_json}")" == shadowtls-inner-* ]]; then
    printf 'shadowtls'
    return 0
  fi
  if [[ "${inbound_type}" == "vless" ]]; then
    if jq -e '(.tls.reality? != null)' <<< "${inbound_json}" >/dev/null 2>&1; then
      printf 'vless-reality'
    else
      printf 'vless-plain'
    fi
    return 0
  fi
  normalize_protocol_id "${inbound_type}"
}

config_protocol_jq_filter() {
  local filter protocol=${1:-} config_file=${2:-${SINGBOX_CONFIG_FILE:-}} excluded
  case "${1:-}" in
    vless-reality) filter='.type == "vless" and (.tls.reality? != null)' ;;
    vless-plain) filter='.type == "vless" and (.tls.reality? == null)' ;;
    hy2) filter='.type == "hysteria2"' ;;
    shadowtls) filter='.type == "shadowtls"' ;;
    mixed) filter='.type == "mixed" and ((.tag // "") | startswith("shadowtls-inner-") | not)' ;;
    *) printf -v filter '.type == "%s"' "${1:-}" ;;
  esac
  # Rebuild captures manual ownership before clearing the old state files.
  excluded=${SB_UNMANAGED_CLIENT_TAGS_JSON:-'[]'}
  if [[ -z "${SB_UNMANAGED_CLIENT_TAGS_JSON+x}" && -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    case "${protocol}" in
      mixed|socks|http|hy2)
        excluded=$(unmanaged_client_tags_for_config_json "${config_file}" "${filter}") || return 1 ;;
    esac
  fi
  printf '(%s) and (.tag as $candidate | (%s) | index($candidate) == null)' \
    "${filter}" "${excluded}"
}

unmanaged_client_tags_for_config_json() (
  trap - EXIT ERR RETURN DEBUG
  local config_file=$1 filter=$2 inbounds inbound tag tags='[]'
  [[ -f "${config_file}" && ! -L "${config_file}" ]] || return 1
  inbounds=$(jq -c ".inbounds[]? | select(${filter})" "${config_file}") || return 1
  while IFS= read -r inbound; do
    [[ -n "${inbound}" ]] || continue
    if manual_client_inbound_is_unmanaged "${inbound}"; then
      tag=$(jq -r '.tag' <<< "${inbound}") || return 1
      tags=$(jq -c --arg tag "${tag}" '. + [$tag]' <<< "${tags}") || return 1
    fi
  done <<< "${inbounds}"
  printf '%s\n' "${tags}"
)

# An existing managed inventory does not implicitly adopt a manually named
# local proxy frontend. Reserved default tags and indexed/missing state keep
# their existing fail-closed ownership checks; takeover without an index is
# still an explicit import of the complete live inventory.
manual_client_inbound_is_unmanaged() {
  local inbound=$1 protocol tag default_tag indexed state_file store_file schema owned_tags
  [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]] || return 1
  protocol=$(jq -r '.type' <<< "${inbound}") || return 1
  case "${protocol}" in mixed|socks|http|hysteria2) ;; *) return 1 ;; esac
  tag=$(jq -r '.tag // ""' <<< "${inbound}") || return 1
  [[ -n "${tag}" ]] || return 1
  default_tag=$(protocol_registry_field "${protocol}" default_tag) || return 1
  [[ "${tag}" != "${default_tag}" ]] || return 1
  if [[ "${protocol}" == hysteria2 ]]; then
    hy2_typed_inbound_is_unmanaged "${tag}"
    return $?
  fi
  indexed=$(extract_protocols_from_index) || return 1
  state_file=$(protocol_state_file "${protocol}") || return 1
  if [[ -e "${state_file}" || -L "${state_file}" ]]; then
    [[ -f "${state_file}" && ! -L "${state_file}" && ",${indexed}," == *",${protocol},"* ]] || return 1
    schema=$(protocol_instance_state_schema "${protocol}") || return 1
    store_file=$(plain_proxy_structured_store_file "${protocol}") || return 1
    if [[ "${schema}" == 2 ]]; then
      [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
      owned_tags=$(jq -ce --arg protocol "${protocol}" 'select(.schema_version==1 and .protocol==$protocol) |
        .instances | select(type=="array") | map(.tag) |
        select(all(.[]; type=="string" and length>0) and (unique|length)==length)' "${store_file}") || return 1
      if jq -e --arg tag "${tag}" 'index($tag)!=null' <<< "${owned_tags}" >/dev/null; then return 1; fi
      return 0
    fi
    [[ "${schema}" == 1 && ! -e "${store_file}" && ! -L "${store_file}" ]] || return 1
    return 0
  fi
  [[ ",${indexed}," != *",${protocol},"* ]]
}

# Only a trusted active store or a retained empty revision proves that a live
# HY2 tag was not adopted. Legacy, missing and orphaned state remains managed
# by the existing fail-closed inventory/takeover checks.
hy2_typed_inbound_is_unmanaged() {
  local tag=$1 state_file store_file snapshot
  state_file=$(protocol_state_file hy2) || return 1
  store_file=$(plain_proxy_structured_store_file hy2) || return 1
  snapshot=$(structured_instance_store_snapshot_json hy2 "${store_file}") || return 1
  if plain_proxy_structured_marker_is_valid "${state_file}"; then
    jq -e '.instances | length > 0' <<< "${snapshot}" >/dev/null || return 1
  else
    [[ ! -e "${state_file}" && ! -L "${state_file}" ]] || return 1
    jq -e '.instances==[] and .default_instance_id=="" and .revision>0' \
      <<< "${snapshot}" >/dev/null || return 1
  fi
  jq -e --arg tag "${tag}" 'all(.instances[]; .tag != $tag)' <<< "${snapshot}" >/dev/null
}

config_protocol_inbound_count() {
  local protocol=${1:-} config_file=${2:-${SINGBOX_CONFIG_FILE:-}} filter
  filter=$(config_protocol_jq_filter "${protocol}" "${config_file}") || return 1
  jq -r "[(.inbounds[]? | select(${filter}))] | length" "${config_file}"
}

config_protocol_inbounds_jsonl() {
  local protocol=${1:-} config_file=${2:-${SINGBOX_CONFIG_FILE:-}} filter
  filter=$(config_protocol_jq_filter "${protocol}" "${config_file}") || return 1
  jq -c "[.inbounds[]? | select(${filter})][]" "${config_file}"
}

state_protocol_to_runtime() {
  protocol_registry_field "$1" runtime_id
}

runtime_protocol_to_state() {
  normalize_protocol_id "$1"
}
