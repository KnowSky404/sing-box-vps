#!/usr/bin/env bash

set -euo pipefail

readonly LOCK_DIR=/tmp/sing-box-vps-verification.lock
readonly VERIFY_ARTIFACT_BUNDLE_BEGIN='__SING_BOX_VPS_REMOTE_ARTIFACT_BUNDLE_BEGIN__'
readonly VERIFY_ARTIFACT_BUNDLE_END='__SING_BOX_VPS_REMOTE_ARTIFACT_BUNDLE_END__'

VERIFY_ARTIFACT_DIR=$(mktemp -d /tmp/sing-box-vps-verification-artifacts.XXXXXX)
VERIFY_LOCK_HELD=0
VERIFY_CURRENT_SCENARIO=''
VERIFY_CURRENT_SCENARIO_DIR=''

verification_artifact_path() {
  local relative_path=$1
  local target_path="${VERIFY_ARTIFACT_DIR}/${relative_path}"
  mkdir -p "$(dirname "${target_path}")"
  printf '%s\n' "${target_path}"
}

verification_write_artifact() {
  local relative_path=$1
  shift || true
  printf '%s\n' "$@" > "$(verification_artifact_path "${relative_path}")"
}

verification_append_artifact() {
  local relative_path=$1
  shift || true
  printf '%s\n' "$@" >> "$(verification_artifact_path "${relative_path}")"
}

verification_mark_step() {
  local step_name=$1

  [[ -n "${VERIFY_CURRENT_SCENARIO_DIR}" ]] || return 0
  verification_append_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/steps.txt" "${step_name}"
}

verification_capture_file_if_present() {
  local source_path=$1
  local relative_path=$2
  local target_path

  test -f "${source_path}" || return 0
  target_path=$(verification_artifact_path "${relative_path}")
  cp "${source_path}" "${target_path}"
}

verification_capture_tree_if_present() {
  local source_path=$1
  local relative_path=$2
  local target_path="${VERIFY_ARTIFACT_DIR}/${relative_path}"

  test -d "${source_path}" || return 0
  rm -rf "${target_path}"
  mkdir -p "${target_path}"
  cp -a "${source_path}/." "${target_path}/"
}

verification_capture_command() {
  local relative_path=$1
  shift
  local target_path
  local status=0

  target_path=$(verification_artifact_path "${relative_path}")
  set +e
  "$@" > "${target_path}" 2>&1
  status=$?
  set -e
  if [[ "${status}" == "0" ]]; then
    return 0
  fi

  printf '\n[command_exit_status=%s]\n' "${status}" >> "${target_path}"
  return "${status}"
}

verification_capture_best_effort_command() {
  verification_capture_command "$@" || true
}

verification_ss_output() {
  ss -lntp 2>/dev/null || ss -lnt 2>/dev/null
}

verification_ss_udp_output() {
  ss -lunp 2>/dev/null || ss -lun 2>/dev/null
}

verification_capture_listener_snapshot() {
  local relative_path=${1:-meta/listeners.ss-lntp.txt}
  verification_capture_best_effort_command "${relative_path}" verification_ss_output
}

verification_port_is_listening() {
  local port=$1

  verification_ss_output | awk -v port="${port}" '
    $1 == "LISTEN" && $4 ~ (":" port "$") {
      found = 1
    }
    END {
      exit(found ? 0 : 1)
    }
  '
}

verification_udp_port_is_listening() {
  local port=$1

  verification_ss_udp_output | awk -v port="${port}" '
    ($1 == "UNCONN" || $1 == "LISTEN") && $4 ~ (":" port "$") {
      found = 1
    }
    END {
      exit(found ? 0 : 1)
    }
  '
}

verification_assert_port_listening() {
  local port=$1
  local relative_path=$2

  verification_capture_listener_snapshot "${relative_path}"
  verification_port_is_listening "${port}"
}

verification_assert_udp_port_listening() {
  local port=$1
  local relative_path=$2

  verification_capture_best_effort_command "${relative_path}" verification_ss_udp_output
  verification_udp_port_is_listening "${port}"
}

verification_assert_port_not_listening() {
  local port=$1
  local relative_path=$2

  verification_capture_listener_snapshot "${relative_path}"
  ! verification_port_is_listening "${port}"
}

verification_wait_for_service_active() {
  local service_name=${1:-sing-box}
  local attempts=${2:-20}
  local delay_seconds=${3:-1}
  local attempt=0

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if systemctl is-active --quiet "${service_name}"; then
      return 0
    fi
    sleep "${delay_seconds}"
  done

  systemctl status "${service_name}" --no-pager >&2 || true
  return 1
}

verification_capture_status_menu() {
  local relative_path=$1
  local target_path
  local status=0

  test -x /usr/local/bin/sbv || return 1

  target_path=$(verification_artifact_path "${relative_path}")
  set +e
  bash /usr/local/bin/sbv > "${target_path}" 2>&1 <<'EOF'
9
0
EOF
  status=$?
  set -e
  if [[ "${status}" == "0" ]]; then
    return 0
  fi

  printf '\n[command_exit_status=%s]\n' "${status}" >> "${target_path}"
  return "${status}"
}

verification_capture_common_artifacts() {
  local base_dir=$1

  verification_capture_file_if_present /root/sing-box-vps/config.json "${base_dir}/config.json"
  verification_capture_tree_if_present /root/sing-box-vps/protocols "${base_dir}/protocols"
  verification_capture_best_effort_command "${base_dir}/systemctl.status.txt" systemctl status sing-box --no-pager
  verification_capture_best_effort_command "${base_dir}/journalctl.txt" journalctl -u sing-box -n 100 --no-pager
  verification_capture_listener_snapshot "${base_dir}/listeners.ss-lntp.txt"
}

verification_initialize_run_artifacts() {
  local scenario

  mkdir -p "${VERIFY_ARTIFACT_DIR}/meta" "${VERIFY_ARTIFACT_DIR}/scenarios"
  verification_write_artifact "meta/started-at.txt" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  {
    for scenario in "$@"; do
      printf '%s\n' "${scenario}"
    done
  } > "$(verification_artifact_path meta/scenarios.txt)"
  verification_capture_best_effort_command "meta/uname.txt" uname -a
}

verification_start_scenario() {
  VERIFY_CURRENT_SCENARIO=$1
  VERIFY_CURRENT_SCENARIO_DIR="scenarios/${VERIFY_CURRENT_SCENARIO}"
  mkdir -p "${VERIFY_ARTIFACT_DIR}/${VERIFY_CURRENT_SCENARIO_DIR}"
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/scenario.txt" "${VERIFY_CURRENT_SCENARIO}"
}

verification_finalize_scenario() {
  local status=$1

  verification_capture_common_artifacts "${VERIFY_CURRENT_SCENARIO_DIR}"
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/result.env" \
    "SCENARIO=${VERIFY_CURRENT_SCENARIO}" \
    "STATUS=$([[ "${status}" == "0" ]] && printf 'success' || printf 'failure')" \
    "EXIT_STATUS=${status}"
}

read_installed_protocols() {
  local index_file=/root/sing-box-vps/protocols/index.env
  local protocols=''
  local raw_protocol protocol
  local protocol_entries=()
  local seen=','

  test -f "${index_file}" || return 0
  protocols=$(sed -n 's/^INSTALLED_PROTOCOLS=//p' "${index_file}" | head -n 1) || return $?
  IFS=',' read -r -a protocol_entries <<< "${protocols}"

  for raw_protocol in "${protocol_entries[@]}"; do
    protocol=$(printf '%s' "${raw_protocol}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//') || return $?
    [[ -n "${protocol}" ]] || continue
    protocol=$(verification_protocol_canonical_id "${protocol}") || return $?
    case "${seen}" in
      *,"${protocol}",*) continue ;;
    esac
    printf '%s\n' "${protocol}"
    seen="${seen}${protocol},"
  done
}

verification_protocol_id_is_safe() {
  [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9+._-]*$ ]]
}

verification_protocol_canonical_id() {
  local protocol=${1:-}
  local metadata canonical

  if ! verification_protocol_id_is_safe "${protocol}"; then
    printf 'invalid protocol id in verification index\n' >&2
    return 1
  fi
  if metadata=$(verification_protocol_metadata "${protocol}"); then
    canonical=$(jq -er '.state_id' <<< "${metadata}") || return 1
    if ! verification_protocol_id_is_safe "${canonical}"; then
      printf 'invalid protocol state id in verification registry\n' >&2
      return 1
    fi
    printf '%s\n' "${canonical}"
  else
    # A syntactically valid, unknown ID remains observable as unsupported.
    printf '%s\n' "${protocol}"
  fi
}

verification_protocol_probe_support_status() {
  local metadata
  [[ -n "${VERIFY_PROTOCOL_REGISTRY_JSON:-}" ]] || {
    printf 'protocol registry unavailable for verification\n' >&2
    return 1
  }
  if ! jq -e 'type == "array" and length > 0 and all(.[];
    (.state_id | type == "string" and length > 0) and
    (.probe | type == "string") and (.aliases | type == "array"))' \
    >/dev/null 2>&1 <<< "${VERIFY_PROTOCOL_REGISTRY_JSON}"; then
    printf 'invalid protocol registry for verification\n' >&2
    return 1
  fi
  if metadata=$(verification_protocol_metadata "$1"); then
    if [[ "$(jq -r '.probe' <<< "${metadata}")" == "tcp_loopback" ]]; then
      printf 'supported\n'
      return 0
    fi
  fi
  printf 'unsupported\n'
}

verification_protocol_metadata() {
  jq -ce --arg protocol "$1" '
    .[] | select(.state_id == $protocol or (.aliases | index($protocol) != null))
  ' <<< "${VERIFY_PROTOCOL_REGISTRY_JSON:-null}"
}

verification_record_protocol_probe_result() {
  local protocol=$1
  local result=$2

  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/result.env" \
    "PROTOCOL=${protocol}" \
    "RESULT=${result}"
}

verification_find_config_inbound_index_by_type() {
  local config_file=$1
  local target_type=$2
  local inbound_count=0
  local inbound_index=0
  local inbound_type=''

  inbound_count=$(jq -r '(.inbounds // []) | length' "${config_file}")
  [[ "${inbound_count}" =~ ^[0-9]+$ ]] || return 1

  for ((inbound_index = 0; inbound_index < inbound_count; inbound_index++)); do
    inbound_type=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].type // empty' "${config_file}")
    if [[ "${inbound_type}" == "${target_type}" ]]; then
      printf '%s\n' "${inbound_index}"
      return 0
    fi
  done

  return 1
}

verification_require_protocol_probe_field() {
  local protocol=$1
  local field_name=$2
  local field_value=$3

  if [[ -n "${field_value}" ]]; then
    return 0
  fi

  printf 'missing required %s probe field: %s\n' "${protocol}" "${field_name}" >&2
  return 1
}

verification_load_hy2_probe_state() {
  local state_file=$1
  local password_var=$2
  local domain_var=$3
  local obfs_password_var=$4
  local decoded_assignments=''
  local PASSWORD=''
  local DOMAIN=''
  local OBFS_PASSWORD=''

  decoded_assignments="$(
    # Decode the full state file in a subshell so unrelated assignments cannot
    # pollute the caller shell, then re-emit only the fields this probe needs.
    # shellcheck disable=SC1090
    source "${state_file}"
    printf 'PASSWORD=%q\n' "${PASSWORD-}"
    printf 'DOMAIN=%q\n' "${DOMAIN-}"
    printf 'OBFS_PASSWORD=%q\n' "${OBFS_PASSWORD-}"
  )"

  # shellcheck disable=SC1091
  source /dev/stdin <<<"${decoded_assignments}"

  printf -v "${password_var}" '%s' "${PASSWORD-}"
  printf -v "${domain_var}" '%s' "${DOMAIN-}"
  printf -v "${obfs_password_var}" '%s' "${OBFS_PASSWORD-}"
}

verification_load_anytls_probe_state() {
  local state_file=$1
  local password_var=$2
  local domain_var=$3
  local decoded_assignments=''
  local PASSWORD=''
  local DOMAIN=''

  decoded_assignments="$(
    # Decode the full state file in a subshell so unrelated assignments cannot
    # pollute the caller shell, then re-emit only the fields this probe needs.
    # shellcheck disable=SC1090
    source "${state_file}"
    printf 'PASSWORD=%q\n' "${PASSWORD-}"
    printf 'DOMAIN=%q\n' "${DOMAIN-}"
  )"

  # shellcheck disable=SC1091
  source /dev/stdin <<<"${decoded_assignments}"

  printf -v "${password_var}" '%s' "${PASSWORD-}"
  printf -v "${domain_var}" '%s' "${DOMAIN-}"
}

verification_load_mixed_probe_state() {
  local state_file=$1
  local auth_enabled_var=$2
  local username_var=$3
  local password_var=$4
  local decoded_assignments=''
  local AUTH_ENABLED=''
  local USERNAME=''
  local PASSWORD=''

  decoded_assignments="$(
    # Decode the full state file in a subshell so unrelated assignments cannot
    # pollute the caller shell, then re-emit only the fields this probe needs.
    # shellcheck disable=SC1090
    source "${state_file}"
    printf 'AUTH_ENABLED=%q\n' "${AUTH_ENABLED-}"
    printf 'USERNAME=%q\n' "${USERNAME-}"
    printf 'PASSWORD=%q\n' "${PASSWORD-}"
  )"

  # shellcheck disable=SC1091
  source /dev/stdin <<<"${decoded_assignments}"

  printf -v "${auth_enabled_var}" '%s' "${AUTH_ENABLED-}"
  printf -v "${username_var}" '%s' "${USERNAME-}"
  printf -v "${password_var}" '%s' "${PASSWORD-}"
}

verification_generate_trojan_probe_client() (
  set -euo pipefail
  umask 077
  local config_file=$1 output_path=$2 installer temp_dir selected_tag snapshot
  installer=${VERIFY_REMOTE_INSTALL_SCRIPT:-/usr/local/bin/sbv}
  [[ -f "${installer}" ]] || return 1
  temp_dir=$(mktemp -d "${output_path}.trojan.XXXXXX") || return 1
  trap 'rm -rf -- "${temp_dir}"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  # Use the exact runtime under verification, not a second hand-maintained
  # client template. The isolated runtime test separately covers all users.
  source "${installer}"
  plain_proxy_structured_state_active trojan || return 1
  snapshot=$(structured_instance_store_snapshot_json trojan \
    "$(plain_proxy_structured_store_file trojan)") || return 1
  selected_tag=$(jq -er '[.inbounds[] | select(.type=="trojan")][0].tag' "${config_file}") || return 1
  jq -e --arg tag "${selected_tag}" '
    .instances |= map(select(.tag==$tag)) |
    if (.instances|length)==1 then .default_instance_id=.instances[0].id
    else error("invalid probe inventory") end
  ' <<< "${snapshot}" > "${temp_dir}/store.json" || return 1
  build_trojan_client_outbounds_from_store "${temp_dir}/store.json" 127.0.0.1 \
    > "${temp_dir}/outbounds.jsonl" || return 1
  jq -se '
    if length>0 then
      {log:{disabled:true},
       inbounds:[{type:"socks",tag:"local-socks",listen:"127.0.0.1",listen_port:19080}],
       outbounds:[(.[0] | .tag="proxy")],route:{final:"proxy"}}
    else error("empty probe export") end
  ' "${temp_dir}/outbounds.jsonl" > "${temp_dir}/client.json" || return 1
  chmod 600 "${temp_dir}/client.json" || return 1
  mv -f -- "${temp_dir}/client.json" "${output_path}" || return 1
)

verification_generate_vmess_probe_client() (
  set -euo pipefail
  umask 077
  local config_file=$1 output_path=$2 installer temp_dir selected_tag snapshot
  local state_file store_file record
  installer=${VERIFY_REMOTE_INSTALL_SCRIPT:-/usr/local/bin/sbv}
  [[ -f "${installer}" ]] || return 1
  temp_dir=$(mktemp -d "${output_path}.vmess.XXXXXX") || return 1
  trap 'rm -rf -- "${temp_dir}"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  # Use the exact runtime exporter under verification.  The probe validates
  # the managed VMess store first and then trusts only the public certificate
  # emitted by the exporter; private key material is never copied.
  source "${installer}"
  plain_proxy_structured_state_active vmess || return 1
  state_file=$(protocol_state_file vmess) || return 1
  store_file=$(plain_proxy_structured_store_file vmess) || return 1
  selected_tag=$(jq -er '[.inbounds[] | select(.type=="vmess")][0].tag' "${config_file}") || return 1
  record=$(verification_load_vmess_probe_record "${state_file}" "${store_file}" "${selected_tag}") || return 1
  snapshot=$(structured_instance_store_snapshot_json vmess "${store_file}") || return 1
  jq -e --arg tag "${selected_tag}" --argjson expected "${record}" '
    any(.instances[]; .tag == $tag) and
    any(.instances[]; .tag == $tag and .listen.port == $expected.listen.port)
  ' <<< "${snapshot}" >/dev/null || return 1
  jq -e --arg tag "${selected_tag}" '
    .instances |= map(select(.tag == $tag)) |
    if (.instances|length)==1 then .default_instance_id=.instances[0].id
    else error("invalid probe inventory") end
  ' <<< "${snapshot}" > "${temp_dir}/store.json" || return 1
  build_vmess_client_outbounds_from_store "${temp_dir}/store.json" 127.0.0.1 \
    > "${temp_dir}/outbounds.jsonl" || return 1
  jq -se '
    if length>0 then
      {log:{disabled:true},
       inbounds:[{type:"socks",tag:"local-socks",listen:"127.0.0.1",listen_port:19080}],
       outbounds:[(.[0] | .tag="proxy")],route:{final:"proxy"}}
    else error("empty probe export") end
  ' "${temp_dir}/outbounds.jsonl" > "${temp_dir}/client.json" || return 1
  chmod 600 "${temp_dir}/client.json" || return 1
  mv -f -- "${temp_dir}/client.json" "${output_path}" || return 1
)

verification_generate_snell_probe_client() (
  set -euo pipefail
  umask 077
  local config_file=$1 output_path=$2 installer temp_dir selected_tag snapshot
  local state_file store_file record server_port
  installer=${VERIFY_REMOTE_INSTALL_SCRIPT:-/usr/local/bin/sbv}
  [[ -f "${installer}" ]] || return 1
  temp_dir=$(mktemp -d "${output_path}.snell.XXXXXX") || return 1
  trap 'rm -rf -- "${temp_dir}"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP

  # Snell has no standard share URI.  Build the probe from the exact typed
  # store/exporter used by the runtime, after checking that the rendered
  # inbound still identifies the same managed instance and credentials.
  source "${installer}"
  plain_proxy_structured_state_active snell || return 1
  state_file=$(protocol_state_file snell) || return 1
  store_file=$(plain_proxy_structured_store_file snell) || return 1
  selected_tag=$(jq -er '
    [(.inbounds // [])[] | select(.type == "snell")] |
    if length == 1 and (.[0].tag | type == "string" and length > 0)
    then .[0].tag else error("invalid Snell probe inventory") end
  ' "${config_file}") || return 1
  server_port=$(jq -er --arg tag "${selected_tag}" '
    [(.inbounds // [])[] | select(.type == "snell" and .tag == $tag)] |
    if length == 1 and (.[0].listen_port | type == "number" and floor == .)
    then .[0].listen_port else error("invalid Snell probe listener") end
  ' "${config_file}") || return 1
  record=$(verification_load_snell_probe_record "${state_file}" "${store_file}" "${selected_tag}") || return 1
  snapshot=$(structured_instance_store_snapshot_json snell "${store_file}") || return 1
  jq -e --arg tag "${selected_tag}" --argjson expected "${record}" --argjson port "${server_port}" '
    any(.instances[]; .tag == $tag and .listen == $expected.listen and
      .listen.port == $port and .authentication == $expected.authentication and
      .version == $expected.version and .obfs_mode == $expected.obfs_mode and
      .obfs_host == $expected.obfs_host and .mode == $expected.mode)
  ' <<< "${snapshot}" >/dev/null || return 1
  jq -e --arg tag "${selected_tag}" '
    .instances |= map(select(.tag == $tag)) |
    if (.instances|length)==1 then .default_instance_id=.instances[0].id
    else error("invalid probe inventory") end
  ' <<< "${snapshot}" > "${temp_dir}/store.json" || return 1
  build_client_snell_outbounds 127.0.0.1 "${temp_dir}/store.json" \
    > "${temp_dir}/outbounds.jsonl" || return 1
  jq -se '
    if length == 1 then
      {log:{disabled:true},
       inbounds:[{type:"socks",tag:"local-socks",listen:"127.0.0.1",listen_port:19080}],
       outbounds:[(.[0] | .tag="proxy")],route:{final:"proxy"}}
    else error("invalid Snell probe export") end
  ' "${temp_dir}/outbounds.jsonl" > "${temp_dir}/client.json" || return 1
  chmod 600 "${temp_dir}/client.json" || return 1
  mv -f -- "${temp_dir}/client.json" "${output_path}" || return 1
)

verification_generate_naive_probe_client() (
  set -euo pipefail
  umask 077
  local config_file=$1 output_path=$2 installer temp_dir selected_tag snapshot record store_file state_file
  local server_port outbounds_json
  installer=${VERIFY_REMOTE_INSTALL_SCRIPT:-/usr/local/bin/sbv}
  [[ -f "${installer}" ]] || return 1
  temp_dir=$(mktemp -d "${output_path}.naive.XXXXXX") || return 1
  trap 'rm -rf -- "${temp_dir}"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP

  # NaiveProxy's runtime is provided by the official with_naive_outbound
  # build and libcronet.so.  Reuse the production exporter after checking the
  # typed store and rendered listener, so this probe never silently falls back
  # to an incomplete or plaintext client.
  source "${installer}"
  plain_proxy_structured_state_active naive || return 1
  state_file=$(protocol_state_file naive) || return 1
  store_file=$(plain_proxy_structured_store_file naive) || return 1
  selected_tag=$(jq -er '
    [(.inbounds // [])[] | select(.type == "naive")] |
    if length == 1 and (.[0].tag | type == "string" and length > 0)
    then .[0].tag else error("invalid NaiveProxy probe inventory") end
  ' "${config_file}") || return 1
  server_port=$(jq -er --arg tag "${selected_tag}" '
    [(.inbounds // [])[] | select(.type == "naive" and .tag == $tag)] |
    if length == 1 and (.[0].listen_port | type == "number" and floor == .)
    then .[0].listen_port else error("invalid NaiveProxy probe listener") end
  ' "${config_file}") || return 1
  record=$(verification_load_naive_probe_record "${state_file}" "${store_file}" "${selected_tag}") || return 1
  snapshot=$(structured_instance_store_snapshot_json naive "${store_file}") || return 1
  jq -e --arg tag "${selected_tag}" --argjson expected "${record}" --argjson port "${server_port}" '
    any(.instances[]; .tag == $tag and .listen.port == $port and
      .listen == $expected.listen and
      .authentication == $expected.authentication and .tls == $expected.tls and
      .client_trust == $expected.client_trust and .naive == $expected.naive and
      .outbound_policy == $expected.outbound_policy and .dependencies == $expected.dependencies)
  ' <<< "${snapshot}" >/dev/null || return 1
  jq -e --arg tag "${selected_tag}" --argjson expected "${record}" --argjson port "${server_port}" '
    any((.inbounds // [])[];
      .type == "naive" and .tag == $tag and .listen_port == $port and
      .listen == $expected.listen.address and
      (((.network // ["tcp"]) | if type == "string" then [.] else . end) == $expected.listen.network) and
      ([.users[] | {name: .username, username: .username, password: .password}] == $expected.authentication.users) and
      .tls == $expected.tls)
  ' "${config_file}" >/dev/null || return 1
  jq -e --arg tag "${selected_tag}" '
    .instances |= map(select(.tag == $tag)) |
    if (.instances | length) == 1 then .default_instance_id = .instances[0].id
    else error("invalid probe inventory") end
  ' <<< "${snapshot}" > "${temp_dir}/store.json" || return 1
  build_client_naive_outbounds 127.0.0.1 "${temp_dir}/store.json" \
    > "${temp_dir}/outbounds.jsonl" || return 1
  outbounds_json=$(jq -se '
    if length == 1 and .[0].type == "naive" then
      (.[0] | .tag = "proxy") as $outbound |
      {log:{disabled:true},
       inbounds:[{type:"socks",tag:"local-socks",listen:"127.0.0.1",listen_port:19080}],
       outbounds:[$outbound],route:{final:"proxy"}}
    else error("invalid NaiveProxy probe export") end
  ' "${temp_dir}/outbounds.jsonl") || return 1
  printf '%s\n' "${outbounds_json}" > "${temp_dir}/client.json" || return 1
  chmod 600 "${temp_dir}/client.json" || return 1
  mv -f -- "${temp_dir}/client.json" "${output_path}" || return 1
)

verification_generate_shadowtls_probe_client() (
  set -euo pipefail
  umask 077
  local config_file=$1 output_path=$2 installer temp_dir selected_tag snapshot record store_file state_file
  local server_port detour_tag outbounds_json
  installer=${VERIFY_REMOTE_INSTALL_SCRIPT:-/usr/local/bin/sbv}
  [[ -f "${installer}" ]] || return 1
  temp_dir=$(mktemp -d "${output_path}.shadowtls.XXXXXX") || return 1
  trap 'rm -rf -- "${temp_dir}"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP

  # ShadowTLS is a transport wrapper around the managed inner Mixed listener.
  # Generate both outbounds from the production composite exporter and route
  # the probe's HTTP proxy through the transport dependency.
  source "${installer}"
  plain_proxy_structured_state_active shadowtls || return 1
  state_file=$(protocol_state_file shadowtls) || return 1
  store_file=$(plain_proxy_structured_store_file shadowtls) || return 1
  selected_tag=$(jq -er '
    [(.inbounds // [])[] | select(.type == "shadowtls")] |
    if length == 1 and (.[0].tag | type == "string" and length > 0)
    then .[0].tag else error("invalid ShadowTLS probe inventory") end
  ' "${config_file}") || return 1
  server_port=$(jq -er --arg tag "${selected_tag}" '
    [(.inbounds // [])[] | select(.type == "shadowtls" and .tag == $tag)] |
    if length == 1 and (.[0].listen_port | type == "number" and floor == .)
    then .[0].listen_port else error("invalid ShadowTLS probe listener") end
  ' "${config_file}") || return 1
  detour_tag=$(jq -er --arg tag "${selected_tag}" '
    [(.inbounds // [])[] | select(.type == "shadowtls" and .tag == $tag)] |
    if length == 1 and (.[0].detour | type == "string" and length > 0)
    then .[0].detour else error("invalid ShadowTLS probe detour") end
  ' "${config_file}") || return 1
  record=$(verification_load_shadowtls_probe_record "${state_file}" "${store_file}" "${selected_tag}") || return 1
  snapshot=$(structured_instance_store_snapshot_json shadowtls "${store_file}") || return 1
  jq -e --arg tag "${selected_tag}" --arg detour "${detour_tag}" --argjson port "${server_port}" --argjson expected "${record}" '
    any(.instances[]; .tag == $tag and .listen.port == $port and
      .authentication == $expected.authentication and .version == $expected.version and
      .handshake == $expected.handshake and .detour == $expected.detour and
      .client_trust == $expected.client_trust and .client_tls == $expected.client_tls and
      .detour.tag == $detour)
  ' <<< "${snapshot}" >/dev/null || return 1
  jq -e --arg tag "${selected_tag}" '
    .instances |= map(select(.tag == $tag)) |
    if (.instances | length) == 1 then .default_instance_id = .instances[0].id
    else error("invalid probe inventory") end
  ' <<< "${snapshot}" > "${temp_dir}/store.json" || return 1
  build_client_shadowtls_outbounds 127.0.0.1 "${temp_dir}/store.json" \
    > "${temp_dir}/outbounds.jsonl" || return 1
  outbounds_json=$(jq -se '
    if length == 2 and
       ([.[] | select(.type == "shadowtls")] | length) == 1 and
       ([.[] | select(.type == "http" and (.detour | type == "string"))] | length) == 1 then
      map(
        if .type == "shadowtls" then
          .tag = "shadowtls-transport"
        elif .type == "http" then
          .tag = "proxy" | .detour = "shadowtls-transport"
        else . end
      ) as $outbounds |
      if ($outbounds | map(select(.type == "http" and .tag == "proxy" and .server_port > 0)) | length) == 1 then
        {log:{disabled:true},
         inbounds:[{type:"socks",tag:"local-socks",listen:"127.0.0.1",listen_port:19080}],
         outbounds:$outbounds,route:{final:"proxy"}}
      else error("invalid ShadowTLS composite export") end
    else error("invalid ShadowTLS composite export") end
  ' "${temp_dir}/outbounds.jsonl") || return 1
  printf '%s\n' "${outbounds_json}" > "${temp_dir}/client.json" || return 1
  chmod 600 "${temp_dir}/client.json" || return 1
  mv -f -- "${temp_dir}/client.json" "${output_path}" || return 1
)

verification_generate_hysteria_probe_client() (
  set -euo pipefail
  umask 077
  local config_file=$1 output_path=$2 installer temp_dir selected_tag snapshot
  local state_file store_file record
  installer=${VERIFY_REMOTE_INSTALL_SCRIPT:-/usr/local/bin/sbv}
  [[ -f "${installer}" ]] || return 1
  temp_dir=$(mktemp -d "${output_path}.hysteria.XXXXXX") || return 1
  trap 'rm -rf -- "${temp_dir}"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  # Hysteria v1 has a distinct auth_str/bandwidth/QUIC contract.  Use the
  # exact runtime exporter after validating the selected typed record so the
  # probe cannot silently fall back to Hysteria2 fields or stale credentials.
  source "${installer}"
  plain_proxy_structured_state_active hysteria || return 1
  state_file=$(protocol_state_file hysteria) || return 1
  store_file=$(plain_proxy_structured_store_file hysteria) || return 1
  selected_tag=$(jq -er '[.inbounds[] | select(.type=="hysteria")][0].tag' "${config_file}") || return 1
  record=$(verification_load_hysteria_probe_record "${state_file}" "${store_file}" "${selected_tag}") || return 1
  snapshot=$(structured_instance_store_snapshot_json hysteria "${store_file}") || return 1
  jq -e --arg tag "${selected_tag}" --argjson expected "${record}" '
    any(.instances[]; .tag == $tag and .listen.port == $expected.listen.port and
      .bandwidth == $expected.bandwidth and
      .authentication.users[0].auth_str == $expected.authentication.users[0].auth_str)
  ' <<< "${snapshot}" >/dev/null || return 1
  jq -e --arg tag "${selected_tag}" '
    .instances |= map(select(.tag == $tag)) |
    if (.instances|length)==1 then .default_instance_id=.instances[0].id
    else error("invalid probe inventory") end
  ' <<< "${snapshot}" > "${temp_dir}/store.json" || return 1
  build_client_hysteria_outbounds 127.0.0.1 "${temp_dir}/store.json" \
    > "${temp_dir}/outbounds.jsonl" || return 1
  jq -se '
    if length>0 then
      {log:{disabled:true},
       inbounds:[{type:"socks",tag:"local-socks",listen:"127.0.0.1",listen_port:19080}],
       outbounds:[(.[0] | .tag="proxy" | .tls.alpn=["h3"])],route:{final:"proxy"}}
    else error("empty probe export") end
  ' "${temp_dir}/outbounds.jsonl" > "${temp_dir}/client.json" || return 1
  chmod 600 "${temp_dir}/client.json" || return 1
  mv -f -- "${temp_dir}/client.json" "${output_path}" || return 1
)

verification_generate_tuic_probe_client() (
  set -euo pipefail
  umask 077
  local protocol=tuic
  local config_file=$1 output_path=$2 installer temp_dir selected_tag snapshot
  local state_file store_file record
  installer=${VERIFY_REMOTE_INSTALL_SCRIPT:-/usr/local/bin/sbv}
  [[ -f "${installer}" ]] || return 1
  temp_dir=$(mktemp -d "${output_path}.tuic.XXXXXX") || return 1
  trap 'rm -rf -- "${temp_dir}"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP

  # TUIC is represented by the structured store rather than the rendered
  # inbound alone.  Reuse the exact runtime exporter so credentials,
  # certificate trust and UDP relay options cannot drift from production
  # client exports.
  source "${installer}"
  plain_proxy_structured_state_active tuic || return 1
  state_file=$(protocol_state_file tuic) || return 1
  store_file=$(plain_proxy_structured_store_file tuic) || return 1
  selected_tag=$(jq -er '[.inbounds[] | select(.type=="tuic")][0].tag' "${config_file}") || return 1
  record=$(verification_load_tuic_probe_record "${state_file}" "${store_file}" "${selected_tag}") || {
    printf 'missing or invalid TUIC structured state for protocol generator: %s\n' "${protocol}" >&2
    return 1
  }
  snapshot=$(structured_instance_store_snapshot_json tuic "${store_file}") || return 1
  jq -e --arg tag "${selected_tag}" --argjson expected "${record}" '
    any(.instances[]; .tag == $tag and .listen.port == $expected.listen.port and
      .authentication.users == $expected.authentication.users and
      .tls == $expected.tls and .client_trust == $expected.client_trust and
      .tuic == $expected.tuic)
  ' <<< "${snapshot}" >/dev/null || return 1
  jq -e --arg tag "${selected_tag}" '
    .instances |= map(select(.tag == $tag)) |
    if (.instances|length)==1 then .default_instance_id=.instances[0].id
    else error("invalid probe inventory") end
  ' <<< "${snapshot}" > "${temp_dir}/store.json" || return 1
  build_client_tuic_outbounds 127.0.0.1 "${temp_dir}/store.json" \
    > "${temp_dir}/outbounds.jsonl" || return 1
  jq -se '
    if length>0 then
      {log:{disabled:true},
       inbounds:[{type:"socks",tag:"local-socks",listen:"127.0.0.1",listen_port:19080}],
       outbounds:[(.[0] | .tag="proxy")],route:{final:"proxy"}}
    else error("empty probe export") end
  ' "${temp_dir}/outbounds.jsonl" > "${temp_dir}/client.json" || return 1
  chmod 600 "${temp_dir}/client.json" || return 1
  mv -f -- "${temp_dir}/client.json" "${output_path}" || return 1
)

verification_load_http_probe_record() {
  local state_file=$1
  local store_file=$2
  local tag=$3
  local record

  [[ -f "${state_file}" && ! -L "${state_file}" ]] || return 1
  grep -Eq '^[[:space:]]*CONFIG_SCHEMA_VERSION=2([[:space:]]*)$' "${state_file}" || return 1
  [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  record=$(jq -ce --arg tag "${tag}" '
    if .schema_version == 1 and .protocol == "http" and
       ([.instances[] | select(.tag == $tag)] | length) == 1 then
      ([.instances[] | select(.tag == $tag)][0] | {
        authentication: .authentication,
        tls: .tls
      })
    else
      error("invalid HTTP structured state")
    end
  ' "${store_file}") || return 1
  printf '%s\n' "${record}"
}

verification_load_shadowsocks_probe_record() {
  local state_file=$1
  local store_file=$2
  local tag=$3
  local record

  [[ -f "${state_file}" && ! -L "${state_file}" ]] || return 1
  grep -Eq '^[[:space:]]*CONFIG_SCHEMA_VERSION=2([[:space:]]*)$' "${state_file}" || return 1
  [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  record=$(jq -ce --arg tag "${tag}" '
    if .schema_version == 1 and .protocol == "shadowsocks" and
       ([.instances[] | select(.tag == $tag)] | length) == 1 then
      ([.instances[] | select(.tag == $tag)][0] |
        select(
          (.listen.address | type == "string" and length > 0) and
          (.listen.port | type == "number" and floor == . and . >= 1 and . <= 65535) and
          (.listen.network | type == "array" and length > 0 and
             all(.[]; . == "tcp" or . == "udp") and . == (sort | unique)) and
          (.authentication | type == "object") and
          (.authentication.method | type == "string" and length > 0) and
          (.authentication.password | type == "string") and
          (.authentication.users | type == "array" and length <= 128 and
             all(.[]; type == "object" and
               (.name | type == "string" and length > 0) and
               (.password | type == "string" and length > 0)))
        )
      )
    else error("invalid Shadowsocks structured state")
    end
  ' "${store_file}") || return 1
  printf '%s\n' "${record}"
}

verification_load_vmess_probe_record() {
  local state_file=$1
  local store_file=$2
  local tag=$3
  local record

  [[ -f "${state_file}" && ! -L "${state_file}" ]] || return 1
  grep -Eq '^[[:space:]]*CONFIG_SCHEMA_VERSION=2([[:space:]]*)$' "${state_file}" || return 1
  [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  record=$(jq -ce --arg tag "${tag}" '
    if .schema_version == 1 and .protocol == "vmess" and
       ([.instances[] | select(.tag == $tag)] | length) == 1 then
      ([.instances[] | select(.tag == $tag)][0] |
        select(
          (.listen.address | type == "string" and length > 0) and
          (.listen.port | type == "number" and floor == . and . >= 1 and . <= 65535) and
          (.authentication.users | type == "array" and length >= 1 and length <= 128 and
            all(.[]; type == "object" and
              (.name | type == "string" and length > 0) and
              (.uuid | type == "string" and test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89a-fA-F][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$")) and
              (.alter_id | type == "number" and floor == . and . >= 0 and . <= 65535) and
              (.security | type == "string" and IN("auto","none","zero","aes-128-cfb","aes-128-gcm","chacha20-poly1305")))) and
          (.tls | type == "object") and
          (.transport | type == "object") and
          (.client_trust | IN("certificate","system"))
        ) | {
          listen: .listen,
          authentication: .authentication,
          tls: .tls,
          transport: .transport,
          client_trust: .client_trust
        }
      )
    else error("invalid VMess structured state")
    end
  ' "${store_file}") || return 1
  printf '%s\n' "${record}"
}

verification_load_snell_probe_record() {
  local state_file=$1
  local store_file=$2
  local tag=$3
  local record

  [[ -f "${state_file}" && ! -L "${state_file}" ]] || return 1
  grep -Eq '^[[:space:]]*CONFIG_SCHEMA_VERSION=2([[:space:]]*)$' "${state_file}" || return 1
  [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  record=$(jq -ce --arg tag "${tag}" '
    def safe_text:
      type == "string" and length > 0 and
      (test("[[:cntrl:]]") | not);
    def safe_address:
      type == "string" and length > 0 and
      (test("[[:cntrl:][:space:]]") | not);
    if .schema_version == 1 and .protocol == "snell" and
       (.instances | type == "array") and
       ([.instances[] | select(.tag == $tag)] | length) == 1 then
      ([.instances[] | select(.tag == $tag)][0] |
        select(
          (.listen | type == "object" and (keys | sort) == ["address","port"] and
            (.address | safe_address) and
            (.port | type == "number" and floor == . and . >= 1 and . <= 65535)) and
          (.authentication | type == "object" and (keys | sort) == ["psk","users"] and
            (.psk | safe_text and utf8bytelength <= 255) and
            (.users | type == "array" and length <= 128 and
              all(.[]; type == "object" and (keys | sort) == ["name","userkey"] and
                (.name | safe_text and utf8bytelength <= 256) and
                (.userkey | safe_text and utf8bytelength <= 255)) and
              (map(.name) | unique | length) == length and
              (map(.userkey) | unique | length) == length)) and
          (.version | type == "number" and floor == . and IN(5,6)) and
          (.obfs_mode | type == "string") and
          (.obfs_host | type == "string") and
          (.mode | type == "string") and
          (if .version == 5 then
             .mode == "" and (.obfs_mode | IN("none","http")) and
             (if .obfs_mode == "none" then .obfs_host == ""
              else (.obfs_host | safe_text and utf8bytelength <= 255) end)
           else
             .obfs_mode == "" and .obfs_host == "" and
             (.mode | IN("","default","unshaped","unsafe-raw")) and
             (.authentication.psk | utf8bytelength >= 12)
           end) and
          (.outbound_policy | IN("default","direct","warp")) and
          (.dependencies | type == "array" and length == 0)
        ) | {
          listen: .listen,
          authentication: .authentication,
          version: .version,
          obfs_mode: .obfs_mode,
          obfs_host: .obfs_host,
          mode: .mode
        }
      )
    else error("invalid Snell structured state")
    end
  ' "${store_file}") || return 1
  printf '%s\n' "${record}"
}

verification_load_shadowtls_probe_record() {
  local state_file=$1
  local store_file=$2
  local tag=$3
  local record

  [[ -f "${state_file}" && ! -L "${state_file}" ]] || return 1
  grep -Eq '^[[:space:]]*CONFIG_SCHEMA_VERSION=2([[:space:]]*)$' "${state_file}" || return 1
  [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  record=$(jq -ce --arg tag "${tag}" '
    def safe_text:
      type == "string" and length > 0 and utf8bytelength <= 4096 and
      (test("[\u0000-\u001F\u007F]") | not);
    def safe_address:
      type == "string" and length > 0 and
      (test("[\u0000-\u0020\u007F]") | not);
    if .schema_version == 1 and .protocol == "shadowtls" and
       (.instances | type == "array") and
       ([.instances[] | select(.tag == $tag)] | length) == 1 then
      ([.instances[] | select(.tag == $tag)][0] | . as $instance |
        select(
          (.listen | type == "object" and (keys | sort) == ["address","port"] and
            (.address | safe_address) and
            (.port | type == "number" and floor == . and . >= 1 and . <= 65535)) and
          (.version | type == "number" and floor == . and IN(1,2,3)) and
          (.authentication | type == "object" and (keys | sort) == ["password","users"] and
            (.password | type == "string" and utf8bytelength <= 4096 and
              (test("[\u0000-\u001F\u007F]") | not)) and
            (.users | type == "array" and length <= 128 and
              all(.[]; type == "object" and (keys | sort) == ["name","password"] and
                (.name | safe_text) and (.password | safe_text)) and
              (map(.name) | unique | length) == length and
              (map(.password) | unique | length) == length) and
            (if $instance.version == 1 then .password == "" and .users == []
             elif $instance.version == 2 then (.password | safe_text) and .users == []
             else .password == "" and (.users | length) > 0 end)) and
          (.handshake | type == "object" and (keys | sort) == ["server","server_port"] and
            (.server | safe_text) and
            (.server_port | type == "number" and floor == . and . >= 1 and . <= 65535)) and
          (.detour | type == "object" and (keys | sort) == ["listen","tag"] and
            .tag == ("shadowtls-inner-" + $instance.id) and
            (.listen | type == "object" and (keys | sort) == ["address","port"] and
              .address == "127.0.0.1" and
              (.port | type == "number" and floor == . and . >= 1 and . <= 65535))) and
          (.client_trust | type == "string" and IN("certificate","system")) and
          (.client_tls | type == "object" and (keys | sort) == ["certificate_path","server_name"] and
            (.server_name | safe_text) and
            (.certificate_path | type == "string" and
              (test("[\u0000-\u001F\u007F]") | not)) and
            (if $instance.client_trust == "certificate" then (.certificate_path | startswith("/"))
             else .certificate_path == "" end)) and
          (.dependencies | type == "array" and . == [$instance.detour.tag])
        ) | {
          id: $instance.id,
          listen: $instance.listen,
          version: $instance.version,
          authentication: $instance.authentication,
          handshake: $instance.handshake,
          detour: $instance.detour,
          client_trust: $instance.client_trust,
          client_tls: $instance.client_tls
        }
      )
    else error("invalid ShadowTLS structured state")
    end
  ' "${store_file}") || return 1
  printf '%s\n' "${record}"
}

verification_load_naive_probe_record() {
  local state_file=$1
  local store_file=$2
  local tag=$3
  local record

  [[ -f "${state_file}" && ! -L "${state_file}" ]] || return 1
  grep -Eq '^[[:space:]]*CONFIG_SCHEMA_VERSION=2([[:space:]]*)$' "${state_file}" || return 1
  [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  record=$(jq -ce --arg tag "${tag}" '
    def safe_text:
      type == "string" and length > 0 and utf8bytelength <= 4096 and
      (test("[\u0000-\u001F\u007F]") | not);
    def safe_address:
      type == "string" and length > 0 and
      (test("[\u0000-\u0020\u007F]") | not);
    if .schema_version == 1 and .protocol == "naive" and
       (.instances | type == "array") and
       ([.instances[] | select(.tag == $tag)] | length) == 1 then
      ([.instances[] | select(.tag == $tag)][0] | . as $instance |
        select(
          (.id | type == "string" and test("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$")) and
          (.listen | type == "object" and (keys | sort) == ["address","network","port"] and
            (.address | safe_address) and
            (.port | type == "number" and floor == . and . >= 1 and . <= 65535) and
            (.network | type == "array" and . == ["tcp"])) and
          (.authentication | type == "object" and (keys | sort) == ["users"] and
            (.users | type == "array" and length >= 1 and length <= 128 and
              all(.[]; type == "object" and (keys | sort) == ["name","password","username"] and
                (.name | safe_text) and
                (.username | safe_text and (contains(":") | not)) and
                (.password | safe_text)) and
              (map(.name) | unique | length) == length and
              (map(.username) | unique | length) == length)) and
          (.tls | type == "object" and (keys | sort) == ["certificate_path","enabled","key_path","server_name"] and
            .enabled == true and
            (.server_name | safe_text) and
            (.certificate_path | type == "string" and startswith("/") and
              (test("[\u0000-\u001F\u007F]") | not)) and
            (.key_path | type == "string" and startswith("/") and
              (test("[\u0000-\u001F\u007F]") | not))) and
          (.client_trust | type == "string" and IN("certificate","system")) and
          (.naive | type == "object" and
            (keys | sort) == ["extra_headers","insecure_concurrency","quic","quic_congestion_control","quic_session_receive_window","stream_receive_window"] and
            (.extra_headers | type == "object" and length <= 64 and
              all(to_entries[];
                (.key | type == "string" and length > 0 and length <= 128 and
                  test("^[!#$%&\u0027*+.^_\u0060|~0-9A-Za-z-]+$")) and
                (.value | type == "string" and utf8bytelength <= 4096 and
                  (test("[\u0000-\u001F\u007F]") | not)))) and
            (.insecure_concurrency | type == "number" and floor == . and . >= 0 and . <= 1024) and
            .quic == false and
            (.quic_congestion_control | type == "string" and IN("bbr","cubic","reno")) and
            (.quic_session_receive_window | type == "string" and length <= 64 and
              test("^$|^[0-9]+( ?(B|KB|MB|GB))$")) and
            (.stream_receive_window | type == "string" and length <= 64 and
              test("^$|^[0-9]+( ?(B|KB|MB|GB))$"))) and
          (.outbound_policy | IN("default","direct","warp")) and
          (.dependencies | type == "array" and length == 0)
        ) | {
          id: $instance.id,
          listen: $instance.listen,
          authentication: $instance.authentication,
          tls: $instance.tls,
          client_trust: $instance.client_trust,
          naive: $instance.naive,
          outbound_policy: $instance.outbound_policy,
          dependencies: $instance.dependencies
        }
      )
    else error("invalid NaiveProxy structured state")
    end
  ' "${store_file}") || return 1
  printf '%s\n' "${record}"
}

verification_load_hysteria_probe_record() {
  local state_file=$1
  local store_file=$2
  local tag=$3
  local record

  [[ -f "${state_file}" && ! -L "${state_file}" ]] || return 1
  grep -Eq '^[[:space:]]*CONFIG_SCHEMA_VERSION=2([[:space:]]*)$' "${state_file}" || return 1
  [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  record=$(jq -ce --arg tag "${tag}" '
    if .schema_version == 1 and .protocol == "hysteria" and
       (.instances | type == "array") and
       ([.instances[] | select(.tag == $tag)] | length) == 1 then
      ([.instances[] | select(.tag == $tag)][0] |
        select(
          (.listen.address | type == "string" and length > 0) and
          (.listen.port | type == "number" and floor == . and . >= 1 and . <= 65535) and
          (.authentication.users | type == "array" and length >= 1 and length <= 128 and
            all(.[]; type == "object" and
              (keys | sort) == ["auth_str","name"] and
              (.name | type == "string" and length > 0 and
                (test("[\u0000-\u001F\u007F]") | not)) and
              (.auth_str | type == "string" and length > 0 and
                (test("[\u0000-\u001F\u007F]") | not))) and
            (map(.name) | unique | length) == length and
            (map(.auth_str) | unique | length) == length) and
          (.tls | type == "object" and .enabled == true and
            (.server_name | type == "string" and length > 0) and
            (.certificate_path | type == "string" and startswith("/")) and
            (.key_path | type == "string" and startswith("/"))) and
          (.client_trust | IN("certificate","system")) and
          (.bandwidth | type == "object" and
            (.up_mbps | type == "number" and floor == . and . >= 1 and . <= 1000000) and
            (.down_mbps | type == "number" and floor == . and . >= 1 and . <= 1000000)) and
          (.obfs | type == "object" and (.enabled | type == "boolean")) and
          (.hysteria | type == "object")
        ) | {
          listen: .listen,
          authentication: .authentication,
          tls: .tls,
          client_trust: .client_trust,
          bandwidth: .bandwidth,
          obfs: .obfs,
          hysteria: .hysteria
        }
      )
    else error("invalid Hysteria structured state")
    end
  ' "${store_file}") || return 1
  printf '%s\n' "${record}"
}

verification_load_tuic_probe_record() {
  local state_file=$1
  local store_file=$2
  local tag=$3
  local record

  [[ -f "${state_file}" && ! -L "${state_file}" ]] || return 1
  grep -Eq '^[[:space:]]*CONFIG_SCHEMA_VERSION=2([[:space:]]*)$' "${state_file}" || return 1
  [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  record=$(jq -ce --arg tag "${tag}" '
    if .schema_version == 1 and .protocol == "tuic" and
       (.instances | type == "array") and
       ([.instances[] | select(.tag == $tag)] | length) == 1 then
      ([.instances[] | select(.tag == $tag)][0] |
        select(
          (.listen | type == "object" and (keys | sort) == ["address","port"] and
            (.address | type == "string" and length > 0 and
              (test("[\u0000-\u0020\u007F]") | not))) and
          (.listen.port | type == "number" and floor == . and . >= 1 and . <= 65535) and
          (.authentication | type == "object" and (keys | sort) == ["users"] and
            (.users | type == "array" and length >= 1 and length <= 128 and
              all(.[]; type == "object" and (keys | sort) == ["name","password","uuid"] and
                (.name | type == "string" and length > 0 and utf8bytelength <= 256 and
                  (test("[\u0000-\u001F\u007F]") | not)) and
                (.password | type == "string" and length > 0 and utf8bytelength <= 4096 and
                  index("\u0000") == null) and
                (.uuid | type == "string" and
                  test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"))) and
              (map(.name) | unique | length) == length and
              (map(.uuid) | unique | length) == length and
              (map(.password) | unique | length) == length)) and
          (.tls | type == "object" and (keys | sort) == ["certificate_path","enabled","key_path","server_name"] and
            .enabled == true and
            (.server_name | type == "string" and length > 0 and
              (test("[\u0000-\u001F\u007F]") | not)) and
            (.certificate_path | type == "string" and startswith("/") and
              (test("[\u0000-\u001F\u007F]") | not)) and
            (.key_path | type == "string" and startswith("/") and
              (test("[\u0000-\u001F\u007F]") | not))) and
          (.client_trust | type == "string" and IN("certificate","system")) and
          (.tuic | type == "object" and
            (keys | sort) == ["auth_timeout_seconds","congestion_control","heartbeat_seconds","udp_over_stream","udp_relay_mode","zero_rtt_handshake"] and
            (.auth_timeout_seconds | type == "number" and floor == . and . >= 0 and . <= 86400) and
            (.heartbeat_seconds | type == "number" and floor == . and . >= 0 and . <= 86400) and
            (.congestion_control | type == "string" and IN("cubic","new_reno","bbr")) and
            (.udp_over_stream | type == "boolean") and
            (.zero_rtt_handshake | type == "boolean") and
            (.udp_relay_mode | type == "string" and IN("","native","quic")) and
            (if .udp_over_stream then .udp_relay_mode == "" else .udp_relay_mode != "" end)) and
          (.outbound_policy | IN("default","direct","warp")) and
          (.dependencies | type == "array" and length == 0)
        ) | {
          listen: .listen,
          authentication: .authentication,
          tls: .tls,
          client_trust: .client_trust,
          tuic: .tuic
        }
      )
    else error("invalid TUIC structured state")
    end
  ' "${store_file}") || return 1
  printf '%s\n' "${record}"
}

verification_load_vless_plain_probe_record() {
  local state_file=$1
  local store_file=$2
  local tag=$3
  local record

  [[ -f "${state_file}" && ! -L "${state_file}" ]] || return 1
  grep -Eq '^[[:space:]]*CONFIG_SCHEMA_VERSION=2([[:space:]]*)$' "${state_file}" || return 1
  [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  record=$(jq -ce --arg tag "${tag}" '
    if .schema_version == 1 and .protocol == "vless-plain" and
       ([.instances[] | select(.tag == $tag)] | length) == 1 then
      ([.instances[] | select(.tag == $tag)][0] |
        select(
          (.listen.address | type == "string" and length > 0) and
          (.listen.port | type == "number" and floor == . and . >= 1 and . <= 65535) and
          (.authentication.users | type == "array" and length >= 1 and length <= 128 and
            all(.[]; type == "object" and
              (.name | type == "string" and length > 0) and
              (.uuid | type == "string" and test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89a-fA-F][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$")) and
              ((.flow // "") | IN("", "xtls-rprx-vision")))) and
          (.tls | type == "object") and
          (.transport | type == "object" and (.type | IN("none", "http", "ws", "grpc", "quic"))) and
          (.client_trust | IN("certificate", "system"))
        ) | {
          listen: .listen,
          authentication: .authentication,
          tls: .tls,
          transport: .transport,
          client_trust: .client_trust
        }
      )
    else error("invalid VLESS plain structured state")
    end
  ' "${store_file}") || return 1
  printf '%s\n' "${record}"
}

verification_generate_protocol_probe_client_config() {
  local protocol=$1
  local config_file=$2
  local output_path=''
  local temp_output_path=''
  local inbound_index=''
  local server_port=''
  local uuid=''
  local server_name=''
  local public_key=''
  local short_id=''
  local flow=''
  local state_file=''
  local password=''
  local domain=''
  local auth_enabled=''
  local username=''
  local obfs_password=''
  local obfs_type=''
  local http_tls_json=''
  local http_record=''
  local http_tag=''
  local shadowsocks_tag=''
  local store_file=''
  local shadowsocks_record=''
  local shadowsocks_method=''
  local shadowsocks_password=''
  local shadowsocks_network_json=''
  local shadowsocks_user_password=''
  local vmess_state_file=''
  local vmess_store_file=''
  local vmess_tag=''
  local vmess_record=''
  local vmess_server_port=''
  local vmess_user_uuid=''
  local vmess_security=''
  local vmess_alter_id=''
  local vmess_transport_json=''
  local vmess_tls_json=''
  local snell_state_file=''
  local snell_store_file=''
  local snell_tag=''
  local snell_record=''
  local vless_plain_state_file=''
  local vless_plain_store_file=''
  local vless_plain_tag=''
  local vless_plain_record=''

  case "${protocol}" in
    vless-reality)
      state_file=/root/sing-box-vps/protocols/vless-reality.env
      output_path=$(verification_artifact_path \
        "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.json")
      temp_output_path="${output_path}.tmp.$$"
      rm -f "${temp_output_path}"

      inbound_index=$(verification_find_config_inbound_index_by_type "${config_file}" vless) || {
        printf 'missing inbound for protocol generator: %s\n' "${protocol}" >&2
        return 1
      }
      server_port=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].listen_port // empty' "${config_file}")
      uuid=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].uuid // empty' "${config_file}")
      server_name=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.server_name // empty' "${config_file}")
      short_id=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.reality.short_id[0] // empty' "${config_file}")
      flow=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].flow // empty' "${config_file}")
      verification_require_protocol_probe_field "${protocol}" server_port "${server_port}" || return 1
      verification_require_protocol_probe_field "${protocol}" uuid "${uuid}" || return 1
      verification_require_protocol_probe_field "${protocol}" server_name "${server_name}" || return 1
      verification_require_protocol_probe_field "${protocol}" short_id "${short_id}" || return 1
      if [[ ! -f "${state_file}" ]]; then
        printf 'missing protocol state file for protocol generator: %s\n' "${protocol}" >&2
        return 1
      fi
      public_key=$(sed -n 's/^REALITY_PUBLIC_KEY=//p' "${state_file}" | head -n 1)
      if [[ -z "${public_key}" ]]; then
        printf 'missing REALITY_PUBLIC_KEY for protocol generator: %s\n' "${protocol}" >&2
        return 1
      fi

      if jq -n \
        --arg server_port "${server_port}" \
        --arg uuid "${uuid}" \
        --arg server_name "${server_name}" \
        --arg public_key "${public_key}" \
        --arg short_id "${short_id}" \
        --arg flow "${flow}" \
        '{
          log: {
            disabled: true
          },
          inbounds: [
            {
              type: "socks",
              tag: "local-socks",
              listen: "127.0.0.1",
              listen_port: 19080
            }
          ],
          outbounds: [
            {
              type: "vless",
              tag: "proxy",
              server: "127.0.0.1",
              server_port: ($server_port | tonumber),
              uuid: $uuid,
              tls: {
                enabled: true,
                server_name: $server_name,
                utls: {
                  enabled: true,
                  fingerprint: "chrome"
                },
                reality: {
                  enabled: true,
                  public_key: $public_key,
                  short_id: $short_id
                }
              }
            } + (if $flow != "" then {flow: $flow} else {} end)
          ]
        }' > "${temp_output_path}"; then
        mv "${temp_output_path}" "${output_path}"
      else
        rm -f "${temp_output_path}"
        return 1
      fi
      ;;
    hy2)
      state_file=/root/sing-box-vps/protocols/hy2.env
      output_path=$(verification_artifact_path \
        "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.json")
      temp_output_path="${output_path}.tmp.$$"
      rm -f "${temp_output_path}"

      inbound_index=$(verification_find_config_inbound_index_by_type "${config_file}" hysteria2) || {
        printf 'missing inbound for protocol generator: %s\n' "${protocol}" >&2
        return 1
      }
      server_port=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].listen_port // empty' "${config_file}")
      obfs_type=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].obfs.type // empty' "${config_file}")
      verification_require_protocol_probe_field "${protocol}" server_port "${server_port}" || return 1
      if [[ ! -f "${state_file}" ]]; then
        printf 'missing protocol state file for protocol generator: %s\n' "${protocol}" >&2
        return 1
      fi
      verification_load_hy2_probe_state \
        "${state_file}" \
        password \
        domain \
        obfs_password
      verification_require_protocol_probe_field "${protocol}" password "${password}" || return 1
      verification_require_protocol_probe_field "${protocol}" domain "${domain}" || return 1
      if [[ -n "${obfs_type}" ]]; then
        verification_require_protocol_probe_field "${protocol}" obfs_password "${obfs_password}" || return 1
      fi

      if jq -n \
        --arg server_port "${server_port}" \
        --arg password "${password}" \
        --arg domain "${domain}" \
        --arg obfs_type "${obfs_type}" \
        --arg obfs_password "${obfs_password}" \
        '{
          log: {
            disabled: true
          },
          inbounds: [
            {
              type: "socks",
              tag: "local-socks",
              listen: "127.0.0.1",
              listen_port: 19080
            }
          ],
          outbounds: [
            (
              {
                type: "hysteria2",
                tag: "proxy",
                server: "127.0.0.1",
                server_port: ($server_port | tonumber),
                password: $password,
                tls: {
                  enabled: true,
                  server_name: $domain,
                  insecure: true
                }
              } + (
                if $obfs_type != "" and $obfs_password != "" then
                  {
                    obfs: {
                      type: $obfs_type,
                      password: $obfs_password
                    }
                  }
                else
                  {}
                end
              )
            )
          ]
        }' > "${temp_output_path}"; then
        mv "${temp_output_path}" "${output_path}"
      else
        rm -f "${temp_output_path}"
        return 1
      fi
      ;;
    socks)
      output_path=$(verification_artifact_path \
        "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.json")
      temp_output_path="${output_path}.tmp.$$"
      inbound_index=$(verification_find_config_inbound_index_by_type "${config_file}" socks) || return 1
      if jq --argjson idx "${inbound_index}" '
        .inbounds[$idx] as $server |
        if ($server.listen_port | type) != "number" or (($server.users // []) | length) > 1
        then error("unrepresentable SOCKS probe input") else
        {log:{disabled:true},
         inbounds:[{type:"socks",tag:"local-socks",listen:"127.0.0.1",listen_port:19080}],
         outbounds:[({type:"socks",version:"5",tag:"proxy",server:"127.0.0.1",
          server_port:$server.listen_port,udp_over_tcp:{enabled:true,version:2}} +
          (if (($server.users // [])|length)==1 then
            {username:$server.users[0].username,password:$server.users[0].password} else {} end))]}
        end
      ' "${config_file}" > "${temp_output_path}"; then
        chmod 600 "${temp_output_path}" && mv "${temp_output_path}" "${output_path}"
      else
        rm -f "${temp_output_path}"
        return 1
      fi
      ;;
    http)
      state_file=/root/sing-box-vps/protocols/http.env
      store_file=/root/sing-box-vps/protocols/instances/http.json
      output_path=$(verification_artifact_path \
        "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.json")
      temp_output_path="${output_path}.tmp.$$"
      rm -f "${temp_output_path}"

      inbound_index=$(verification_find_config_inbound_index_by_type "${config_file}" http) || {
        printf 'missing inbound for protocol generator: %s\n' "${protocol}" >&2
        return 1
      }
      server_port=$(jq -r --argjson idx "${inbound_index}" \
        '.inbounds[$idx].listen_port // empty' "${config_file}")
      http_tag=$(jq -r --argjson idx "${inbound_index}" \
        '.inbounds[$idx].tag // empty' "${config_file}")
      verification_require_protocol_probe_field "${protocol}" server_port "${server_port}" || return 1
      verification_require_protocol_probe_field "${protocol}" inbound_tag "${http_tag}" || return 1
      http_record=$(verification_load_http_probe_record "${state_file}" "${store_file}" "${http_tag}") || {
        printf 'missing or invalid HTTP structured state for protocol generator: %s\n' "${protocol}" >&2
        return 1
      }
      auth_enabled=$(jq -r '.authentication.enabled | if . == true then "y" elif . == false then "n" else empty end' <<< "${http_record}") || return 1
      username=$(jq -r '.authentication.username // empty' <<< "${http_record}") || return 1
      password=$(jq -r '.authentication.password // empty' <<< "${http_record}") || return 1
      http_tls_json=$(jq -c '.tls' <<< "${http_record}") || return 1
      jq -e 'type == "object" and
        ((keys_unsorted | sort) == ["enabled"] or
         (keys_unsorted | sort) == ["certificate_path", "enabled", "key_path", "server_name"]) and
        (.enabled | type == "boolean") and
        (if .enabled then (.server_name | type == "string" and length > 0) else true end)' \
        <<< "${http_tls_json}" >/dev/null || return 1
      if [[ "${auth_enabled}" == "y" ]]; then
        verification_require_protocol_probe_field "${protocol}" username "${username}" || return 1
        verification_require_protocol_probe_field "${protocol}" password "${password}" || return 1
      elif [[ "${auth_enabled}" != "n" ]]; then
        printf 'invalid HTTP probe field: auth_enabled\n' >&2
        return 1
      fi

      if jq -n \
        --arg server_port "${server_port}" \
        --arg auth_enabled "${auth_enabled}" \
        --arg username "${username}" \
        --arg password "${password}" \
        --argjson tls "${http_tls_json}" \
        '{
          log: {disabled: true},
          inbounds: [{type:"socks",tag:"local-socks",listen:"127.0.0.1",listen_port:19080}],
          outbounds: [
            ({type:"http",tag:"proxy",server:"127.0.0.1",server_port:($server_port|tonumber)}
             + (if $auth_enabled == "y" then {username:$username,password:$password} else {} end)
             + (if $tls.enabled == true then
                  {tls:{enabled:true,server_name:$tls.server_name,insecure:true}}
                else {} end))
          ]
        }' > "${temp_output_path}"; then
        chmod 600 "${temp_output_path}" && mv "${temp_output_path}" "${output_path}"
      else
        rm -f "${temp_output_path}"
        return 1
      fi
      ;;
    trojan)
      output_path=$(verification_artifact_path \
        "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.json")
      verification_generate_trojan_probe_client "${config_file}" "${output_path}" || return 1
      ;;
    vmess)
      output_path=$(verification_artifact_path \
        "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.json")
      verification_generate_vmess_probe_client "${config_file}" "${output_path}" || return 1
      ;;
    snell)
      output_path=$(verification_artifact_path \
        "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.json")
      verification_generate_snell_probe_client "${config_file}" "${output_path}" || return 1
      ;;
    naive)
      output_path=$(verification_artifact_path \
        "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.json")
      verification_generate_naive_probe_client "${config_file}" "${output_path}" || return 1
      ;;
    shadowtls)
      output_path=$(verification_artifact_path \
        "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.json")
      verification_generate_shadowtls_probe_client "${config_file}" "${output_path}" || return 1
      ;;
    hysteria)
      output_path=$(verification_artifact_path \
        "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.json")
      verification_generate_hysteria_probe_client "${config_file}" "${output_path}" || return 1
      ;;
    tuic)
      output_path=$(verification_artifact_path \
        "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.json")
      verification_generate_tuic_probe_client "${config_file}" "${output_path}" || return 1
      ;;
    vless-plain)
      vless_plain_state_file=/root/sing-box-vps/protocols/vless-plain.env
      vless_plain_store_file=/root/sing-box-vps/protocols/instances/vless-plain.json
      output_path=$(verification_artifact_path \
        "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.json")
      temp_output_path="${output_path}.tmp.${BASHPID}"
      rm -f "${temp_output_path}"

      inbound_index=$(jq -r '
        [(.inbounds // []) | to_entries[] |
          select(.value.type == "vless" and (.value.tls.reality? == null))][0].key // empty
      ' "${config_file}") || return 1
      [[ "${inbound_index}" =~ ^[0-9]+$ ]] || {
        printf 'missing inbound for protocol generator: %s\n' "${protocol}" >&2
        return 1
      }
      server_port=$(jq -r --argjson idx "${inbound_index}" \
        '.inbounds[$idx].listen_port // empty' "${config_file}")
      vless_plain_tag=$(jq -r --argjson idx "${inbound_index}" \
        '.inbounds[$idx].tag // empty' "${config_file}")
      verification_require_protocol_probe_field "${protocol}" server_port "${server_port}" || return 1
      verification_require_protocol_probe_field "${protocol}" inbound_tag "${vless_plain_tag}" || return 1
      vless_plain_record=$(verification_load_vless_plain_probe_record \
        "${vless_plain_state_file}" "${vless_plain_store_file}" "${vless_plain_tag}") || {
        printf 'missing or invalid VLESS plain structured state for protocol generator: %s\n' "${protocol}" >&2
        return 1
      }

      if jq -n \
        --arg server_port "${server_port}" \
        --argjson record "${vless_plain_record}" \
        '($record.authentication.users[0]) as $user |
         ($record.transport) as $transport |
         ($record.tls) as $tls |
         {
           log: {disabled: true},
           inbounds: [
             {
               type: "socks",
               tag: "local-socks",
               listen: "127.0.0.1",
               listen_port: 19080
             }
           ],
           outbounds: [
             (
               {
                 type: "vless",
                 tag: "proxy",
                 server: "127.0.0.1",
                 server_port: ($server_port | tonumber),
                 uuid: $user.uuid,
                 network: ["tcp", "udp"]
               }
               + (if ($user.flow // "") != "" then {flow: $user.flow} else {} end)
               + (if $transport.type != "none" then {transport: $transport} else {} end)
               + (if $tls.enabled == true then
                    {tls: ({enabled: true, server_name: $tls.server_name, insecure: true} +
                      (if $transport.type == "quic" then {alpn: ["h3"]} else {} end))}
                  else
                    {}
                  end)
             )
           ]
         }' > "${temp_output_path}"; then
        chmod 600 "${temp_output_path}" && mv "${temp_output_path}" "${output_path}"
      else
        rm -f "${temp_output_path}"
        return 1
      fi
      ;;
    shadowsocks)
      state_file=/root/sing-box-vps/protocols/shadowsocks.env
      store_file=/root/sing-box-vps/protocols/instances/shadowsocks.json
      output_path=$(verification_artifact_path \
        "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.json")
      temp_output_path="${output_path}.tmp.${BASHPID}"
      rm -f "${temp_output_path}"

      inbound_index=$(verification_find_config_inbound_index_by_type "${config_file}" shadowsocks) || {
        printf 'missing inbound for protocol generator: %s\n' "${protocol}" >&2
        return 1
      }
      server_port=$(jq -r --argjson idx "${inbound_index}" \
        '.inbounds[$idx].listen_port // empty' "${config_file}")
      shadowsocks_tag=$(jq -r --argjson idx "${inbound_index}" \
        '.inbounds[$idx].tag // empty' "${config_file}")
      verification_require_protocol_probe_field "${protocol}" server_port "${server_port}" || return 1
      verification_require_protocol_probe_field "${protocol}" inbound_tag "${shadowsocks_tag}" || return 1
      shadowsocks_record=$(verification_load_shadowsocks_probe_record \
        "${state_file}" "${store_file}" "${shadowsocks_tag}") || {
        printf 'missing or invalid Shadowsocks structured state for protocol generator: %s\n' "${protocol}" >&2
        return 1
      }
      shadowsocks_method=$(jq -r '.authentication.method' <<< "${shadowsocks_record}") || return 1
      shadowsocks_password=$(jq -r '.authentication.password' <<< "${shadowsocks_record}") || return 1
      shadowsocks_network_json=$(jq -c '.listen.network' <<< "${shadowsocks_record}") || return 1
      if jq -e '(.authentication.users | length) > 0' <<< "${shadowsocks_record}" >/dev/null; then
        shadowsocks_user_password=$(jq -r '.authentication.users[0].password' <<< "${shadowsocks_record}") || return 1
        if [[ "${shadowsocks_method}" == 2022-* ]]; then
          shadowsocks_password="${shadowsocks_password}:${shadowsocks_user_password}"
        else
          shadowsocks_password="${shadowsocks_user_password}"
        fi
      fi
      verification_require_protocol_probe_field "${protocol}" method "${shadowsocks_method}" || return 1
      verification_require_protocol_probe_field "${protocol}" password "${shadowsocks_password}" || return 1
      jq -n \
        --arg server_port "${server_port}" \
        --arg method "${shadowsocks_method}" \
        --arg password "${shadowsocks_password}" \
        --argjson network "${shadowsocks_network_json}" \
        '{
          log: {disabled: true},
          inbounds: [{type:"socks",tag:"local-socks",listen:"127.0.0.1",listen_port:19080}],
          outbounds: [{
            type:"shadowsocks", tag:"proxy", server:"127.0.0.1",
            server_port:($server_port|tonumber), method:$method,
            password:$password, network:$network
          }]
        }' > "${temp_output_path}" || {
        rm -f "${temp_output_path}"
        return 1
      }
      chmod 600 "${temp_output_path}" && mv "${temp_output_path}" "${output_path}"
      ;;
    mixed)
      state_file=/root/sing-box-vps/protocols/mixed.env
      output_path=$(verification_artifact_path \
        "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.json")
      temp_output_path="${output_path}.tmp.$$"
      rm -f "${temp_output_path}"

      inbound_index=$(verification_find_config_inbound_index_by_type "${config_file}" mixed) || {
        printf 'missing inbound for protocol generator: %s\n' "${protocol}" >&2
        return 1
      }
      server_port=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].listen_port // empty' "${config_file}")
      verification_require_protocol_probe_field "${protocol}" server_port "${server_port}" || return 1
      if [[ ! -f "${state_file}" ]]; then
        printf 'missing protocol state file for protocol generator: %s\n' "${protocol}" >&2
        return 1
      fi
      verification_load_mixed_probe_state \
        "${state_file}" \
        auth_enabled \
        username \
        password
      if [[ "${auth_enabled}" == "y" ]]; then
        verification_require_protocol_probe_field "${protocol}" username "${username}" || return 1
        verification_require_protocol_probe_field "${protocol}" password "${password}" || return 1
      elif [[ "${auth_enabled}" != "n" ]]; then
        printf 'invalid mixed probe field: auth_enabled\n' >&2
        return 1
      fi

      if jq -n \
        --arg server_port "${server_port}" \
        --arg auth_enabled "${auth_enabled}" \
        --arg username "${username}" \
        --arg password "${password}" \
        '{
          log: {
            disabled: true
          },
          inbounds: [
            {
              type: "socks",
              tag: "local-socks",
              listen: "127.0.0.1",
              listen_port: 19080
            }
          ],
          outbounds: [
            (
              {
                type: "socks",
                version: "5",
                tag: "proxy",
                server: "127.0.0.1",
                server_port: ($server_port | tonumber)
              } + (
                if $auth_enabled == "y" then
                  {
                    username: $username,
                    password: $password
                  }
                else
                  {}
                end
              )
            )
          ]
        }' > "${temp_output_path}"; then
        mv "${temp_output_path}" "${output_path}"
      else
        rm -f "${temp_output_path}"
        return 1
      fi
      ;;
    anytls)
      state_file=/root/sing-box-vps/protocols/anytls.env
      output_path=$(verification_artifact_path \
        "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.json")
      temp_output_path="${output_path}.tmp.$$"
      rm -f "${temp_output_path}"

      inbound_index=$(verification_find_config_inbound_index_by_type "${config_file}" anytls) || {
        printf 'missing inbound for protocol generator: %s\n' "${protocol}" >&2
        return 1
      }
      server_port=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].listen_port // empty' "${config_file}")
      verification_require_protocol_probe_field "${protocol}" server_port "${server_port}" || return 1
      if [[ ! -f "${state_file}" ]]; then
        printf 'missing protocol state file for protocol generator: %s\n' "${protocol}" >&2
        return 1
      fi
      verification_load_anytls_probe_state \
        "${state_file}" \
        password \
        domain
      verification_require_protocol_probe_field "${protocol}" password "${password}" || return 1
      verification_require_protocol_probe_field "${protocol}" domain "${domain}" || return 1

      if jq -n \
        --arg server_port "${server_port}" \
        --arg password "${password}" \
        --arg domain "${domain}" \
        '{
          log: {
            disabled: true
          },
          inbounds: [
            {
              type: "socks",
              tag: "local-socks",
              listen: "127.0.0.1",
              listen_port: 19080
            }
          ],
          outbounds: [
            {
              type: "anytls",
              tag: "proxy",
              server: "127.0.0.1",
              server_port: ($server_port | tonumber),
              password: $password,
              tls: {
                enabled: true,
                server_name: $domain,
                insecure: true
              }
            }
          ]
        }' > "${temp_output_path}"; then
        mv "${temp_output_path}" "${output_path}"
      else
        rm -f "${temp_output_path}"
        return 1
      fi
      ;;
    *)
      printf 'unsupported protocol generator: %s\n' "${protocol}" >&2
      return 1
      ;;
  esac

  printf '%s\n' "${output_path}"
}

verification_execute_protocol_udp_probe() (
  set -euo pipefail
  local protocol=$1 config_file=$2
  local probe_dir client_config_path check_artifact
  local response_artifact stdout_artifact stderr_artifact server_stdout_artifact server_stderr_artifact
  local result_artifact path_artifact
  local temp_dir port_file marker udp_port
  local server_pid='' client_pid='' check_status=0 udp_status=1

  verification_protocol_id_is_safe "${protocol}" || return 1
  probe_dir="${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}"
  check_artifact=$(verification_artifact_path "${probe_dir}/udp-client.check.txt")
  response_artifact=$(verification_artifact_path "${probe_dir}/udp-response.txt")
  stdout_artifact=$(verification_artifact_path "${probe_dir}/udp-probe.stdout.txt")
  stderr_artifact=$(verification_artifact_path "${probe_dir}/udp-client.stderr.txt")
  server_stdout_artifact=$(verification_artifact_path "${probe_dir}/udp-server.stdout.txt")
  server_stderr_artifact=$(verification_artifact_path "${probe_dir}/udp-server.stderr.txt")
  result_artifact=$(verification_artifact_path "${probe_dir}/udp.result.env")
  path_artifact=$(verification_artifact_path "${probe_dir}/udp-client.path.txt")
  rm -f -- "${check_artifact}" "${response_artifact}" "${stdout_artifact}" \
    "${stderr_artifact}" "${server_stdout_artifact}" "${server_stderr_artifact}" \
    "${result_artifact}" "${path_artifact}"

  cleanup_udp_probe() {
    local pid

    set +e
    for pid in "${server_pid}" "${client_pid}"; do
      [[ -n "${pid}" ]] || continue
      if kill -0 "${pid}" 2>/dev/null; then
        kill "${pid}" 2>/dev/null || true
      fi
      wait "${pid}" 2>/dev/null || true
    done
    [[ -n "${temp_dir:-}" ]] && rm -rf -- "${temp_dir}"
  }

  finalize_udp_probe() {
    local status=$?

    cleanup_udp_probe
    if [[ "${udp_status}" == "0" && "${status}" == "0" ]]; then
      verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/udp.result.env" \
        "PROTOCOL=${protocol}" "RESULT=success"
    else
      verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/udp.result.env" \
        "PROTOCOL=${protocol}" "RESULT=failure"
    fi
    return "${status}"
  }
  trap 'finalize_udp_probe; exit $?' EXIT

  client_config_path=$(verification_generate_protocol_probe_client_config "${protocol}" "${config_file}")
  verification_write_artifact "${probe_dir}/udp-client.path.txt" "${client_config_path}"
  set +e
  sing-box check -c "${client_config_path}" > "${check_artifact}" 2>&1
  check_status=$?
  set -e
  [[ "${check_status}" == "0" ]] || return "${check_status}"

  temp_dir=$(mktemp -d /tmp/sing-box-vps-udp-probe.XXXXXX)
  port_file="${temp_dir}/port"
  marker="sing-box-vps-udp-loopback-ok-${protocol}-$(date +%s)-$$"
  python3 - "${port_file}" "${marker}" \
    > "${server_stdout_artifact}" \
    2> "${server_stderr_artifact}" <<'PY' &
import pathlib
import socket
import sys

port_file, _marker = sys.argv[1:]
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(("127.0.0.1", 0))
pathlib.Path(port_file).write_text(str(sock.getsockname()[1]), encoding="ascii")
while True:
    payload, address = sock.recvfrom(65535)
    sock.sendto(payload, address)
PY
  server_pid=$!

  for _ in {1..50}; do
    [[ -s "${port_file}" ]] && break
    kill -0 "${server_pid}" 2>/dev/null || return 1
    sleep 0.1
  done
  [[ -s "${port_file}" ]]
  udp_port=$(cat "${port_file}")
  [[ "${udp_port}" =~ ^[0-9]+$ && "${udp_port}" -ge 1 && "${udp_port}" -le 65535 ]]

  sing-box run -c "${client_config_path}" \
    > "${stdout_artifact}" \
    2> "${stderr_artifact}" &
  client_pid=$!
  for _ in {1..50}; do
    if verification_ss_output | awk '$1 == "LISTEN" && $4 ~ /:19080$/ { found = 1 } END { exit(found ? 0 : 1) }'; then
      break
    fi
    kill -0 "${client_pid}" 2>/dev/null || return 1
    sleep 0.1
  done
  verification_ss_output | awk '$1 == "LISTEN" && $4 ~ /:19080$/ { found = 1 } END { exit(found ? 0 : 1) }'

  set +e
  python3 - "19080" "${udp_port}" "${marker}" \
    > "${response_artifact}" \
    2>> "${stderr_artifact}" <<'PY'
import socket
import struct
import sys

socks_port, target_port, marker = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3].encode()

def recv_exact(conn, size):
    chunks = []
    received = 0
    while received < size:
        chunk = conn.recv(size - received)
        if not chunk:
            raise RuntimeError("SOCKS control connection closed")
        chunks.append(chunk)
        received += len(chunk)
    return b"".join(chunks)

def read_address(conn, atyp):
    if atyp == 1:
        return socket.inet_ntoa(recv_exact(conn, 4))
    if atyp == 3:
        size = recv_exact(conn, 1)[0]
        return recv_exact(conn, size).decode("ascii")
    if atyp == 4:
        return socket.inet_ntop(socket.AF_INET6, recv_exact(conn, 16))
    raise RuntimeError("unsupported SOCKS address type")

def read_reply(conn):
    header = recv_exact(conn, 4)
    if header[0] != 5 or header[1] != 0:
        raise RuntimeError("SOCKS UDP ASSOCIATE failed")
    address = read_address(conn, header[3])
    port = struct.unpack("!H", recv_exact(conn, 2))[0]
    return address, port

with socket.create_connection(("127.0.0.1", socks_port), timeout=5) as control:
    control.settimeout(5)
    control.sendall(b"\x05\x01\x00")
    if recv_exact(control, 2) != b"\x05\x00":
        raise RuntimeError("SOCKS no-auth negotiation failed")
    control.sendall(b"\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00")
    relay_address, relay_port = read_reply(control)
    if relay_address in ("0.0.0.0", "::"):
        relay_address = "127.0.0.1"
    request = b"\x00\x00\x00\x01" + socket.inet_aton("127.0.0.1") + struct.pack("!H", target_port) + marker
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
        udp.settimeout(5)
        udp.sendto(request, (relay_address, relay_port))
        response, _source = udp.recvfrom(65535)
    if len(response) < 10 or response[:3] != b"\x00\x00\x00":
        raise RuntimeError("invalid SOCKS UDP response header")
    offset = 4
    if response[3] == 1:
        offset += 4
    elif response[3] == 3:
        offset += 1 + response[4]
    elif response[3] == 4:
        offset += 16
    else:
        raise RuntimeError("invalid SOCKS UDP response address type")
    offset += 2
    payload = response[offset:]
    if payload != marker:
        raise RuntimeError("UDP marker mismatch")
    sys.stdout.buffer.write(payload)
PY
  udp_status=$?
  set -e
  if [[ -f "${response_artifact}" ]]; then
    cp "${response_artifact}" "${stdout_artifact}" || return 1
  fi
  [[ "${udp_status}" == "0" ]] || return "${udp_status}"
  grep -Fqx "${marker}" "${response_artifact}"
  udp_status=0
)

# Exercise a redirect inbound with a disposable OUTPUT REDIRECT rule. The
# rule is owner-scoped to uid 65534, so the sing-box service and marker server
# cannot recurse through it. This is verification-only host policy: it never
# enters the installer firewall ledger.
verification_execute_redirect_probe() (
  set -euo pipefail
  local config_file=$1 listener_port=$2
  local probe_dir="${VERIFY_CURRENT_SCENARIO_DIR}/transparent/redirect"
  local check_artifact response_artifact client_stderr_artifact marker_stdout_artifact
  local marker_stderr_artifact rule_before_artifact rule_after_artifact
  local result_artifact port_file temp_dir marker marker_port
  local marker_pid='' rule_added=false probe_status=1

  check_artifact=$(verification_artifact_path "${probe_dir}/sing-box-check.txt")
  response_artifact=$(verification_artifact_path "${probe_dir}/response.txt")
  client_stderr_artifact=$(verification_artifact_path "${probe_dir}/client.stderr.txt")
  marker_stdout_artifact=$(verification_artifact_path "${probe_dir}/marker.stdout.txt")
  marker_stderr_artifact=$(verification_artifact_path "${probe_dir}/marker.stderr.txt")
  rule_before_artifact=$(verification_artifact_path "${probe_dir}/iptables.before.txt")
  rule_after_artifact=$(verification_artifact_path "${probe_dir}/iptables.after.txt")
  result_artifact=$(verification_artifact_path "${probe_dir}/result.env")
  rm -f -- "${check_artifact}" "${response_artifact}" "${client_stderr_artifact}" \
    "${marker_stdout_artifact}" "${marker_stderr_artifact}" "${rule_before_artifact}" \
    "${rule_after_artifact}" "${result_artifact}"

  cleanup_redirect_probe() {
    local status=$? cleanup_status=0
    set +e
    if [[ -n "${marker_pid}" ]]; then
      kill "${marker_pid}" 2>/dev/null || true
      wait "${marker_pid}" 2>/dev/null || true
      marker_pid=''
    fi
    if [[ "${rule_added}" == true ]]; then
      if ! iptables -t nat -D OUTPUT -m owner --uid-owner 65534 -p tcp \
        -d 127.0.0.1 --dport "${marker_port}" -j REDIRECT --to-ports "${listener_port}"; then
        cleanup_status=1
      fi
      rule_added=false
    fi
    verification_capture_best_effort_command "${probe_dir}/iptables.after-cleanup.txt" \
      iptables-save -t nat
    rm -rf -- "${temp_dir:-}"
    if [[ "${status}" == 0 && "${cleanup_status}" != 0 ]]; then
      status=1
    fi
    if [[ "${status}" == 0 && "${probe_status}" == 0 ]]; then
      verification_write_artifact "${probe_dir}/result.env" \
        'COMPONENT=redirect-inbound' 'RESULT=success' \
        'DATA_PLANE=redirect_tcp_loopback' \
        'POLICY_SCOPE=verification_container_only' \
        'POLICY_OWNERSHIP=not_managed'
    else
      verification_write_artifact "${probe_dir}/result.env" \
        'COMPONENT=redirect-inbound' 'RESULT=failure' \
        'DATA_PLANE=redirect_tcp_loopback' \
        'POLICY_SCOPE=verification_container_only' \
        'POLICY_OWNERSHIP=not_managed'
    fi
    exit "${status}"
  }
  trap 'cleanup_redirect_probe' EXIT

  verification_capture_command "${probe_dir}/sing-box-check.txt" \
    sing-box check -c "${config_file}"
  verification_capture_best_effort_command "${probe_dir}/iptables.before.txt" \
    iptables-save -t nat
  temp_dir=$(mktemp -d /tmp/sing-box-vps-redirect-probe.XXXXXX)
  port_file="${temp_dir}/port"
  marker="sing-box-vps-redirect-loopback-ok-$(date +%s)-$$"
  python3 - "${port_file}" "${marker}" \
    > "${marker_stdout_artifact}" 2> "${marker_stderr_artifact}" <<'PY' &
import http.server
import pathlib
import socketserver
import sys

port_file, marker = sys.argv[1:]

class MarkerHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = (marker + "\n").encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        return

class ReusableServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

with ReusableServer(("127.0.0.1", 0), MarkerHandler) as server:
    pathlib.Path(port_file).write_text(str(server.server_address[1]), encoding="ascii")
    server.serve_forever()
PY
  marker_pid=$!
  for _ in {1..50}; do
    [[ -s "${port_file}" ]] && break
    kill -0 "${marker_pid}" 2>/dev/null || exit 1
    sleep 0.1
  done
  [[ -s "${port_file}" ]]
  marker_port=$(cat "${port_file}")
  [[ "${marker_port}" =~ ^[0-9]+$ && "${marker_port}" -ge 1 && "${marker_port}" -le 65535 ]]

  iptables -t nat -A OUTPUT -m owner --uid-owner 65534 -p tcp \
    -d 127.0.0.1 --dport "${marker_port}" -j REDIRECT --to-ports "${listener_port}"
  rule_added=true
  verification_capture_command "${probe_dir}/iptables.with-redirect.txt" \
    iptables-save -t nat

  set +e
  python3 - "${marker_port}" "${marker}" \
    > "${response_artifact}" 2> "${client_stderr_artifact}" <<'PY'
import os
import socket
import sys

target_port, marker = int(sys.argv[1]), sys.argv[2].encode()
os.setgroups([])
os.setgid(65534)
os.setuid(65534)
with socket.create_connection(("127.0.0.1", target_port), timeout=5) as conn:
    conn.settimeout(5)
    conn.sendall(b"GET / HTTP/1.1\r\nHost: redirect.invalid\r\nConnection: close\r\n\r\n")
    payload = b""
    while True:
        chunk = conn.recv(65535)
        if not chunk:
            break
        payload += chunk
body = payload.split(b"\r\n\r\n", 1)[1]
sys.stdout.buffer.write(body)
if body != marker + b"\n":
    raise RuntimeError("redirect marker mismatch")
PY
  local client_status=$?
  set -e
  [[ "${client_status}" == 0 ]]
  grep -Fqx "${marker}" "${response_artifact}"
  probe_status=0
)

# Exercise a TProxy inbound from an isolated network namespace. The veth,
# policy route, mark and mangle rules are disposable and are never treated as
# installer-owned firewall state. TCP and UDP clients both cross PREROUTING.
verification_execute_tproxy_probe() (
  set -euo pipefail
  local config_file=$1 listener_port=$2
  local probe_dir="${VERIFY_CURRENT_SCENARIO_DIR}/transparent/tproxy"
  local check_artifact tcp_response_artifact udp_response_artifact client_stderr_artifact
  local tcp_marker_stdout_artifact tcp_marker_stderr_artifact udp_marker_stdout_artifact
  local udp_marker_stderr_artifact marker_before_artifact marker_after_artifact
  local rule_before_artifact rule_after_artifact result_artifact temp_dir
  local netns host_veth peer_veth host_ip='198.18.0.1' peer_ip='198.18.0.2'
  local table mark mark_mask='255' tcp_port udp_port marker tcp_marker udp_marker
  local port_file marker_pid='' tcp_rule_added=false udp_rule_added=false
  local netns_added=false veth_added=false policy_added=false probe_status=1

  probe_dir="${VERIFY_CURRENT_SCENARIO_DIR}/transparent/tproxy"
  check_artifact=$(verification_artifact_path "${probe_dir}/sing-box-check.txt")
  tcp_response_artifact=$(verification_artifact_path "${probe_dir}/tcp-response.txt")
  udp_response_artifact=$(verification_artifact_path "${probe_dir}/udp-response.txt")
  client_stderr_artifact=$(verification_artifact_path "${probe_dir}/client.stderr.txt")
  tcp_marker_stdout_artifact=$(verification_artifact_path "${probe_dir}/tcp-marker.stdout.txt")
  tcp_marker_stderr_artifact=$(verification_artifact_path "${probe_dir}/tcp-marker.stderr.txt")
  udp_marker_stdout_artifact=$(verification_artifact_path "${probe_dir}/udp-marker.stdout.txt")
  udp_marker_stderr_artifact=$(verification_artifact_path "${probe_dir}/udp-marker.stderr.txt")
  marker_before_artifact=$(verification_artifact_path "${probe_dir}/resources.before.txt")
  marker_after_artifact=$(verification_artifact_path "${probe_dir}/resources.after.txt")
  rule_before_artifact=$(verification_artifact_path "${probe_dir}/iptables.before.txt")
  rule_after_artifact=$(verification_artifact_path "${probe_dir}/iptables.with-tproxy.txt")
  result_artifact=$(verification_artifact_path "${probe_dir}/result.env")
  rm -f -- "${check_artifact}" "${tcp_response_artifact}" "${udp_response_artifact}" \
    "${client_stderr_artifact}" "${tcp_marker_stdout_artifact}" "${tcp_marker_stderr_artifact}" \
    "${udp_marker_stdout_artifact}" "${udp_marker_stderr_artifact}" "${marker_before_artifact}" \
    "${marker_after_artifact}" "${rule_before_artifact}" "${rule_after_artifact}" \
    "${result_artifact}"

  cleanup_tproxy_probe() {
    local status=$? cleanup_status=0
    set +e
    if [[ -n "${marker_pid}" ]]; then
      kill "${marker_pid}" 2>/dev/null || true
      wait "${marker_pid}" 2>/dev/null || true
      marker_pid=''
    fi
    if [[ "${tcp_rule_added}" == true ]]; then
      if ! iptables -t mangle -D PREROUTING -i "${host_veth}" -p tcp \
        -j TPROXY --on-ip 0.0.0.0 --on-port "${listener_port}" \
        --tproxy-mark "${mark}/${mark_mask}"; then cleanup_status=1; fi
      tcp_rule_added=false
    fi
    if [[ "${udp_rule_added}" == true ]]; then
      if ! iptables -t mangle -D PREROUTING -i "${host_veth}" -p udp \
        -j TPROXY --on-ip 0.0.0.0 --on-port "${listener_port}" \
        --tproxy-mark "${mark}/${mark_mask}"; then cleanup_status=1; fi
      udp_rule_added=false
    fi
    if [[ "${policy_added}" == true ]]; then
      ip route flush table "${table}" || cleanup_status=1
      ip rule del fwmark "${mark}/${mark_mask}" table "${table}" || cleanup_status=1
      policy_added=false
    fi
    if [[ "${veth_added}" == true ]]; then
      ip link del "${host_veth}" || cleanup_status=1
      veth_added=false
    fi
    if [[ "${netns_added}" == true ]]; then
      ip netns del "${netns}" || cleanup_status=1
      netns_added=false
    fi
    verification_capture_best_effort_command "${probe_dir}/iptables.after-cleanup.txt" \
      iptables-save -t mangle
    verification_capture_best_effort_command "${probe_dir}/resources.after-cleanup.txt" \
      ip rule show
    rm -rf -- "${temp_dir:-}"
    if [[ "${status}" == 0 && "${cleanup_status}" != 0 ]]; then status=1; fi
    if [[ "${status}" == 0 && "${probe_status}" == 0 ]]; then
      verification_write_artifact "${probe_dir}/result.env" \
        'COMPONENT=tproxy-inbound' 'RESULT=success' \
        'DATA_PLANE=tproxy_tcp_udp_netns' \
        'POLICY_SCOPE=verification_container_only' \
        'POLICY_OWNERSHIP=not_managed'
    else
      verification_write_artifact "${probe_dir}/result.env" \
        'COMPONENT=tproxy-inbound' 'RESULT=failure' \
        'DATA_PLANE=tproxy_tcp_udp_netns' \
        'POLICY_SCOPE=verification_container_only' \
        'POLICY_OWNERSHIP=not_managed'
    fi
    exit "${status}"
  }
  trap 'cleanup_tproxy_probe' EXIT

  verification_capture_command "${probe_dir}/sing-box-check.txt" \
    sing-box check -c "${config_file}"
  command -v iptables-save >/dev/null 2>&1
  temp_dir=$(mktemp -d /tmp/sing-box-vps-tproxy-probe.XXXXXX)
  netns="sbvtns-${BASHPID}"
  host_veth="sbvth${BASHPID}"
  peer_veth="sbvtp${BASHPID}"
  table=$((1000 + (BASHPID % 2000)))
  mark=$((1 + (BASHPID % 200)))
  ip netns add "${netns}"
  netns_added=true
  ip link add "${host_veth}" type veth peer name "${peer_veth}"
  ip link set "${peer_veth}" netns "${netns}"
  veth_added=true
  ip addr add "${host_ip}/24" dev "${host_veth}"
  ip link set "${host_veth}" up
  ip netns exec "${netns}" ip addr add "${peer_ip}/24" dev "${peer_veth}"
  ip netns exec "${netns}" ip link set lo up
  ip netns exec "${netns}" ip link set "${peer_veth}" up
  verification_capture_best_effort_command "${probe_dir}/resources.before.txt" \
    ip -j addr show "${host_veth}"
  verification_capture_best_effort_command "${probe_dir}/iptables.before.txt" \
    iptables-save -t mangle

  ip rule add fwmark "${mark}/${mark_mask}" table "${table}"
  policy_added=true
  ip route add local 0.0.0.0/0 dev lo table "${table}"
  iptables -t mangle -A PREROUTING -i "${host_veth}" -p tcp \
    -j TPROXY --on-ip 0.0.0.0 --on-port "${listener_port}" \
    --tproxy-mark "${mark}/${mark_mask}"
  tcp_rule_added=true
  iptables -t mangle -A PREROUTING -i "${host_veth}" -p udp \
    -j TPROXY --on-ip 0.0.0.0 --on-port "${listener_port}" \
    --tproxy-mark "${mark}/${mark_mask}"
  udp_rule_added=true
  verification_capture_command "${probe_dir}/iptables.with-tproxy.txt" \
    iptables-save -t mangle
  verification_capture_best_effort_command "${probe_dir}/resources.with-tproxy.txt" \
    sh -c 'ip rule show; ip route show table '"${table}"

  tcp_marker="sing-box-vps-tproxy-tcp-ok-$(date +%s)-$$"
  port_file="${temp_dir}/tcp.port"
  python3 - "${port_file}" "${host_ip}" "${tcp_marker}" \
    > "${tcp_marker_stdout_artifact}" 2> "${tcp_marker_stderr_artifact}" <<'PY' &
import http.server
import pathlib
import socketserver
import sys

port_file, bind_address, marker = sys.argv[1:]

class MarkerHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = (marker + "\n").encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        return

class ReusableServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

with ReusableServer((bind_address, 0), MarkerHandler) as server:
    pathlib.Path(port_file).write_text(str(server.server_address[1]), encoding="ascii")
    server.serve_forever()
PY
  marker_pid=$!
  for _ in {1..50}; do
    [[ -s "${port_file}" ]] && break
    kill -0 "${marker_pid}" 2>/dev/null || exit 1
    sleep 0.1
  done
  [[ -s "${port_file}" ]]
  tcp_port=$(cat "${port_file}")
  [[ "${tcp_port}" =~ ^[0-9]+$ && "${tcp_port}" -ge 1 && "${tcp_port}" -le 65535 ]]
  set +e
  ip netns exec "${netns}" python3 - "${tcp_port}" "${tcp_marker}" \
    > "${tcp_response_artifact}" 2> "${client_stderr_artifact}" <<'PY'
import socket
import sys

port, marker = int(sys.argv[1]), sys.argv[2].encode()
with socket.create_connection(("198.18.0.1", port), timeout=5) as conn:
    conn.settimeout(5)
    conn.sendall(b"GET / HTTP/1.1\r\nHost: tproxy.invalid\r\nConnection: close\r\n\r\n")
    payload = b""
    while True:
        chunk = conn.recv(65535)
        if not chunk:
            break
        payload += chunk
body = payload.split(b"\r\n\r\n", 1)[1]
sys.stdout.buffer.write(body)
if body != marker + b"\n":
    raise RuntimeError("tproxy TCP marker mismatch")
PY
  local tcp_status=$?
  set -e
  [[ "${tcp_status}" == 0 ]]
  grep -Fqx "${tcp_marker}" "${tcp_response_artifact}"
  kill "${marker_pid}" 2>/dev/null || true
  wait "${marker_pid}" 2>/dev/null || true
  marker_pid=''

  udp_marker="sing-box-vps-tproxy-udp-ok-$(date +%s)-$$"
  port_file="${temp_dir}/udp.port"
  python3 - "${port_file}" "${host_ip}" \
    > "${udp_marker_stdout_artifact}" 2> "${udp_marker_stderr_artifact}" <<'PY' &
import pathlib
import socket
import sys

port_file, bind_address = sys.argv[1:]
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as server:
    server.bind((bind_address, 0))
    pathlib.Path(port_file).write_text(str(server.getsockname()[1]), encoding="ascii")
    payload, address = server.recvfrom(65535)
    server.sendto(payload, address)
PY
  marker_pid=$!
  for _ in {1..50}; do
    [[ -s "${port_file}" ]] && break
    kill -0 "${marker_pid}" 2>/dev/null || exit 1
    sleep 0.1
  done
  [[ -s "${port_file}" ]]
  udp_port=$(cat "${port_file}")
  [[ "${udp_port}" =~ ^[0-9]+$ && "${udp_port}" -ge 1 && "${udp_port}" -le 65535 ]]
  set +e
  ip netns exec "${netns}" python3 - "${udp_port}" "${udp_marker}" \
    > "${udp_response_artifact}" 2>> "${client_stderr_artifact}" <<'PY'
import socket
import sys

port, marker = int(sys.argv[1]), sys.argv[2].encode()
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
    client.settimeout(5)
    client.sendto(marker, ("198.18.0.1", port))
    payload, _ = client.recvfrom(65535)
sys.stdout.buffer.write(payload)
if payload != marker:
    raise RuntimeError("tproxy UDP marker mismatch")
PY
  local udp_status=$?
  set -e
  [[ "${udp_status}" == 0 ]]
  grep -Fqx "${udp_marker}" "${udp_response_artifact}"
  kill "${marker_pid}" 2>/dev/null || true
  wait "${marker_pid}" 2>/dev/null || true
  marker_pid=''
  probe_status=0
)

verification_execute_single_protocol_probe() {
  local protocol=$1
  local config_file=$2

  # Keep the process lifecycle in a subshell.  The EXIT trap only knows the
  # PIDs started by this probe, so a failed probe cannot stop the service
  # process managed by systemd.
  (
    set -e
    local client_config_path=''
    local client_config_artifact=''
    local check_artifact=''
    local client_stdout_artifact=''
    local client_stderr_artifact=''
    local stdout_artifact=''
    local http_response_artifact=''
    local http_server_stdout_artifact=''
    local http_server_stderr_artifact=''
    local result_artifact=''
    local client_path_artifact=''
    local http_tmp_dir=''
    local http_port_file=''
    local http_marker=''
    local http_pid=''
    local client_pid=''
    local http_port=''
    local check_status=0
    local curl_status=0
    local probe_status=1

    client_config_artifact=$(verification_artifact_path \
      "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.json")
    check_artifact=$(verification_artifact_path \
      "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.check.txt")
    client_stdout_artifact=$(verification_artifact_path \
      "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.stdout.txt")
    client_stderr_artifact=$(verification_artifact_path \
      "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.stderr.txt")
    stdout_artifact=$(verification_artifact_path \
      "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/probe.stdout.txt")
    http_response_artifact=$(verification_artifact_path \
      "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/http-response.txt")
    http_server_stdout_artifact=$(verification_artifact_path \
      "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/http-server.stdout.txt")
    http_server_stderr_artifact=$(verification_artifact_path \
      "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/http-server.stderr.txt")
    result_artifact=$(verification_artifact_path \
      "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/result.env")
    client_path_artifact=$(verification_artifact_path \
      "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.path.txt")
    rm -f \
      "${client_config_artifact}" \
      "${check_artifact}" \
      "${client_stdout_artifact}" \
      "${client_stderr_artifact}" \
      "${stdout_artifact}" \
      "${http_response_artifact}" \
      "${http_server_stdout_artifact}" \
      "${http_server_stderr_artifact}" \
      "${result_artifact}" \
      "${client_path_artifact}"

    cleanup_probe_processes() {
      local pid

      set +e
      for pid in "${client_pid}" "${http_pid}"; do
        [[ -n "${pid}" ]] || continue
        if kill -0 "${pid}" 2>/dev/null; then
          kill "${pid}" 2>/dev/null || true
        fi
        wait "${pid}" 2>/dev/null || true
      done
      [[ -n "${http_tmp_dir}" ]] && rm -rf "${http_tmp_dir}"
    }

    finalize_probe() {
      local status=$?

      cleanup_probe_processes
      if [[ "${probe_status}" == "0" && "${status}" == "0" ]]; then
        verification_record_protocol_probe_result "${protocol}" success
      else
        verification_record_protocol_probe_result "${protocol}" failure
      fi
      return "${status}"
    }
    trap 'finalize_probe; exit $?' EXIT

    client_config_path=$(verification_generate_protocol_probe_client_config "${protocol}" "${config_file}")
    verification_write_artifact \
      "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.path.txt" \
      "${client_config_path}"

    set +e
    sing-box check -c "${client_config_path}" > "${check_artifact}" 2>&1
    check_status=$?
    set -e
    if [[ "${check_status}" != "0" ]]; then
      return "${check_status}"
    fi

    http_tmp_dir=$(mktemp -d /tmp/sing-box-vps-probe.XXXXXX)
    http_port_file="${http_tmp_dir}/port"
    http_marker="sing-box-vps-loopback-ok-${protocol}-$(date +%s)-$$"
    export VERIFY_PROTOCOL_PROBE_EXPECTED_MARKER="${http_marker}"
    python3 - "${http_port_file}" "${http_marker}" \
      > "${http_server_stdout_artifact}" \
      2> "${http_server_stderr_artifact}" <<'PY' &
import http.server
import pathlib
import socketserver
import sys

port_file, marker = sys.argv[1:]

class MarkerHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = (marker + "\n").encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        return

with socketserver.TCPServer(("127.0.0.1", 0), MarkerHandler) as server:
    pathlib.Path(port_file).write_text(str(server.server_address[1]), encoding="ascii")
    server.serve_forever()
PY
    http_pid=$!

    for _ in {1..50}; do
      [[ -s "${http_port_file}" ]] && break
      kill -0 "${http_pid}" 2>/dev/null || return 1
      sleep 0.1
    done
    [[ -s "${http_port_file}" ]]
    http_port=$(cat "${http_port_file}")
    [[ "${http_port}" =~ ^[0-9]+$ ]]

    sing-box run -c "${client_config_path}" \
      > "${client_stdout_artifact}" \
      2> "${client_stderr_artifact}" &
    client_pid=$!

    for _ in {1..50}; do
      if verification_ss_output | awk '$1 == "LISTEN" && $4 ~ /:19080$/ { found = 1 } END { exit(found ? 0 : 1) }'; then
        break
      fi
      kill -0 "${client_pid}" 2>/dev/null || return 1
      sleep 0.1
    done
    verification_ss_output | awk '$1 == "LISTEN" && $4 ~ /:19080$/ { found = 1 } END { exit(found ? 0 : 1) }'

    set +e
    curl --fail --silent --show-error --noproxy '' \
      --proxy "socks5h://127.0.0.1:19080" \
      "http://127.0.0.1:${http_port}/" \
      > "${http_response_artifact}" 2>> "${client_stderr_artifact}"
    curl_status=$?
    set -e
    cp "${http_response_artifact}" "${stdout_artifact}"
    if [[ "${curl_status}" != "0" ]]; then
      return "${curl_status}"
    fi
    grep -Fqx "${http_marker}" "${http_response_artifact}"
    probe_status=0
  )
}

verification_run_protocol_probes() {
  local config_file=/root/sing-box-vps/config.json
  local protocol
  local protocols_output=''
  local discovery_status=0
  local support_status=''
  local probe_status=0
  local overall_status=0

  set +e
  protocols_output=$(read_installed_protocols)
  discovery_status=$?
  set -e
  if [[ "${discovery_status}" != "0" ]]; then
    return "${discovery_status}"
  fi

  while IFS= read -r protocol; do
    [[ -n "${protocol}" ]] || continue
    support_status=$(verification_protocol_probe_support_status "${protocol}")
    if [[ "${support_status}" == "unsupported" ]]; then
      verification_record_protocol_probe_result "${protocol}" unsupported
      continue
    fi

    set +e
    (
      set -e
      verification_execute_single_protocol_probe "${protocol}" "${config_file}"
    )
    probe_status=$?
    set -e
    if [[ "${probe_status}" != "0" ]]; then
      verification_record_protocol_probe_result "${protocol}" failure
      overall_status=1
    fi
  done <<< "${protocols_output}"

  return "${overall_status}"
}

verification_emit_artifact_bundle() {
  printf '%s\n' "${VERIFY_ARTIFACT_BUNDLE_BEGIN}"
  tar -C "${VERIFY_ARTIFACT_DIR}" -czf - . | base64
  printf '%s\n' "${VERIFY_ARTIFACT_BUNDLE_END}"
}

verification_cleanup() {
  local status=$1

  verification_write_artifact "meta/exit-status.txt" "${status}"
  verification_capture_best_effort_command "meta/final-systemctl.status.txt" systemctl status sing-box --no-pager
  verification_capture_best_effort_command "meta/final-journalctl.txt" journalctl -u sing-box -n 100 --no-pager
  verification_capture_listener_snapshot "meta/final-listeners.ss-lntp.txt"
  verification_emit_artifact_bundle || true
  if declare -F verification_cleanup_remote_local_tree >/dev/null; then
    verification_cleanup_remote_local_tree || true
  fi
  if [[ "${VERIFY_LOCK_HELD}" == "1" ]]; then
    rmdir "${LOCK_DIR}" || true
  fi
  rm -rf "${VERIFY_ARTIFACT_DIR}"
}

run_verification_scenario() {
  local scenario_name=$1
  local function_name=$2
  local status=0

  verification_start_scenario "${scenario_name}"
  if ! declare -F "${function_name}" >/dev/null; then
    printf 'missing scenario function: %s\n' "${function_name}" >&2
    status=2
    verification_finalize_scenario "${status}"
    return "${status}"
  fi

  set +e
  (
    set -e
    "${function_name}"
  )
  status=$?
  set -e

  verification_finalize_scenario "${status}"
  return "${status}"
}

if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  rm -rf "${VERIFY_ARTIFACT_DIR}"
  printf 'verification host is busy\n' >&2
  exit 32
fi
VERIFY_LOCK_HELD=1
verification_initialize_run_artifacts "$@"
trap 'verification_cleanup "$?"' EXIT

for scenario in "$@"; do
  case "${scenario}" in
    fresh_install_vless)
      run_verification_scenario fresh_install_vless verification_scenario_fresh_install_vless
      ;;
    reconfigure_existing_install)
      run_verification_scenario reconfigure_existing_install verification_scenario_reconfigure_existing_install
      ;;
    legacy_takeover_export)
      run_verification_scenario legacy_takeover_export verification_scenario_legacy_takeover_export
      ;;
    fresh_install_anytls)
      run_verification_scenario fresh_install_anytls verification_scenario_fresh_install_anytls
      ;;
    fresh_install_socks)
      run_verification_scenario fresh_install_socks verification_scenario_fresh_install_socks
      ;;
    fresh_install_http)
      run_verification_scenario fresh_install_http verification_scenario_fresh_install_http
      ;;
    fresh_install_shadowsocks)
      run_verification_scenario fresh_install_shadowsocks verification_scenario_fresh_install_shadowsocks
      ;;
    fresh_install_trojan)
      run_verification_scenario fresh_install_trojan verification_scenario_fresh_install_trojan
      ;;
    fresh_install_vmess)
      run_verification_scenario fresh_install_vmess verification_scenario_fresh_install_vmess
      ;;
    fresh_install_hysteria)
      run_verification_scenario fresh_install_hysteria verification_scenario_fresh_install_hysteria
      ;;
    fresh_install_vless_plain)
      run_verification_scenario fresh_install_vless_plain verification_scenario_fresh_install_vless_plain
      ;;
    multi_protocol_coexistence)
      run_verification_scenario multi_protocol_coexistence verification_scenario_multi_protocol_coexistence
      ;;
    uninstall_and_reinstall)
      run_verification_scenario uninstall_and_reinstall verification_scenario_uninstall_and_reinstall
      ;;
    runtime_smoke)
      run_verification_scenario runtime_smoke verification_scenario_runtime_smoke
      ;;
    upgrade_1_13_to_1_14)
      run_verification_scenario upgrade_1_13_to_1_14 verification_scenario_upgrade_1_13_to_1_14
      ;;
    upgrade_rollback_1_13_to_1_14)
      run_verification_scenario upgrade_rollback_1_13_to_1_14 verification_scenario_upgrade_rollback_1_13_to_1_14
      ;;
    *)
      printf 'unknown scenario: %s\n' "${scenario}" >&2
      exit 2
      ;;
  esac
done
