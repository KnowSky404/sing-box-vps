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

verification_capture_listener_snapshot() {
  local relative_path=${1:-meta/listeners.ss-lntp.txt}
  verification_capture_best_effort_command "${relative_path}" verification_ss_output
}

verification_port_is_listening() {
  local port=$1

  verification_ss_output | awk -v port=":${port}" '
    $1 == "LISTEN" && index($4, port) {
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

verification_assert_port_not_listening() {
  local port=$1
  local relative_path=$2

  verification_capture_listener_snapshot "${relative_path}"
  ! verification_port_is_listening "${port}"
}

verification_capture_status_menu() {
  local relative_path=$1
  local target_path
  local status=0

  test -x /usr/local/bin/sbv || return 1

  target_path=$(verification_artifact_path "${relative_path}")
  set +e
  bash /usr/local/bin/sbv > "${target_path}" 2>&1 <<'EOF'
8
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
  local protocol

  test -f "${index_file}" || return 0
  protocols=$(sed -n 's/^INSTALLED_PROTOCOLS=//p' "${index_file}" | head -n 1)
  protocols=${protocols//,/ }

  for protocol in ${protocols}; do
    [[ -n "${protocol}" ]] || continue
    printf '%s\n' "${protocol}"
  done
}

verification_protocol_probe_support_status() {
  case "${1}" in
    vless-reality|hy2)
      printf 'supported\n'
      ;;
    *)
      printf 'unsupported\n'
      ;;
  esac
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
  local state_file=/root/sing-box-vps/protocols/vless-reality.env

  case "${protocol}" in
    vless-reality)
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
      verification_require_protocol_probe_field "${protocol}" flow "${flow}" || return 1
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
              flow: $flow,
              tls: {
                enabled: true,
                server_name: $server_name,
                reality: {
                  enabled: true,
                  public_key: $public_key,
                  short_id: $short_id
                }
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

verification_run_protocol_probes() {
  local protocol
  local protocols_output=''
  local discovery_status=0
  local support_status
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

    verification_record_protocol_probe_result "${protocol}" failure
    overall_status=1
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
    uninstall_and_reinstall)
      run_verification_scenario uninstall_and_reinstall verification_scenario_uninstall_and_reinstall
      ;;
    runtime_smoke)
      run_verification_scenario runtime_smoke verification_scenario_runtime_smoke
      ;;
    *)
      printf 'unknown scenario: %s\n' "${scenario}" >&2
      exit 2
      ;;
  esac
done
