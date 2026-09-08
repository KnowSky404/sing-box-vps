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
                 network: (if $transport.type == "quic" then ["udp"] else ["tcp", "udp"] end)
               }
               + (if ($user.flow // "") != "" then {flow: $user.flow} else {} end)
               + (if $transport.type != "none" then {transport: $transport} else {} end)
               + (if $tls.enabled == true then
                    {tls: {enabled: true, server_name: $tls.server_name, insecure: true}}
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
