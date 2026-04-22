#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

PORT_FILE="${TMP_DIR}/port"
UUID_FILE="${TMP_DIR}/uuid"
SNI_FILE="${TMP_DIR}/sni"
CONFIG_PRESENT_FILE="${TMP_DIR}/config-present"
SERVICE_FILE_PRESENT_FILE="${TMP_DIR}/service-file-present"
SBV_PRESENT_FILE="${TMP_DIR}/sbv-present"
SERVICE_ACTIVE_FILE="${TMP_DIR}/service-active"
STATE_FILE="${TMP_DIR}/vless-reality.env"
ASSERT_LOG_FILE="${TMP_DIR}/assert.log"
CALLS_FILE="${TMP_DIR}/calls.log"
PAYLOAD_FILE="${TMP_DIR}/remote-payload.sh"
STDOUT_FILE="${TMP_DIR}/stdout.log"
STDERR_FILE="${TMP_DIR}/stderr.log"
INSTALL_COUNT_FILE="${TMP_DIR}/install-count"
EMBEDDED_INSTALL_SCRIPT="${TMP_DIR}/embedded/install.sh"
EMBEDDED_UNINSTALL_SCRIPT="${TMP_DIR}/embedded/uninstall.sh"

printf '9443\n' > "${PORT_FILE}"
printf '11111111-1111-4111-8111-111111111111\n' > "${UUID_FILE}"
printf 'stale.example.com\n' > "${SNI_FILE}"
printf '1\n' > "${CONFIG_PRESENT_FILE}"
printf '1\n' > "${SERVICE_FILE_PRESENT_FILE}"
printf '1\n' > "${SBV_PRESENT_FILE}"
printf '1\n' > "${SERVICE_ACTIVE_FILE}"
: > "${ASSERT_LOG_FILE}"
: > "${CALLS_FILE}"
printf '0\n' > "${INSTALL_COUNT_FILE}"
cat > "${STATE_FILE}" <<'EOF'
PORT=9443
UUID=11111111-1111-4111-8111-111111111111
SNI=stale.example.com
EOF

cat <<'EOF' > "${PAYLOAD_FILE}"
#!/usr/bin/env bash

write_vless_state() {
  cat > "${STATE_FILE}" <<STATE_EOF
PORT=$(cat "${PORT_FILE}")
UUID=$(cat "${UUID_FILE}")
SNI=$(cat "${SNI_FILE}")
STATE_EOF
}

reset_runtime_artifacts() {
  printf '0\n' > "${CONFIG_PRESENT_FILE}"
  printf '0\n' > "${SERVICE_FILE_PRESENT_FILE}"
  printf '0\n' > "${SBV_PRESENT_FILE}"
  printf '0\n' > "${SERVICE_ACTIVE_FILE}"
  rm -f "${STATE_FILE}"
}

install_runtime_artifacts() {
  printf '1\n' > "${CONFIG_PRESENT_FILE}"
  printf '1\n' > "${SERVICE_FILE_PRESENT_FILE}"
  printf '1\n' > "${SBV_PRESENT_FILE}"
  printf '1\n' > "${SERVICE_ACTIVE_FILE}"
  write_vless_state
}

verification_prepare_remote_local_tree() {
  : "${VERIFY_REMOTE_INSTALL_SCRIPT:?VERIFY_REMOTE_INSTALL_SCRIPT is required}"
  : "${VERIFY_REMOTE_UNINSTALL_SCRIPT:?VERIFY_REMOTE_UNINSTALL_SCRIPT is required}"
}

verification_cleanup_remote_local_tree() {
  :
}

next_install_uuid() {
  local install_count
  install_count=$(cat "${INSTALL_COUNT_FILE}")
  install_count=$((install_count + 1))
  printf '%s\n' "${install_count}" > "${INSTALL_COUNT_FILE}"

  case "${install_count}" in
    1)
      printf '33333333-3333-4333-8333-333333333333\n'
      ;;
    2)
      printf '44444444-4444-4444-8444-444444444444\n'
      ;;
    *)
      printf '55555555-5555-4555-8555-555555555555\n'
      ;;
  esac
}

assert_input_sequence() {
  local target=$1
  shift
  local expected_lines=("$@")
  local actual_lines=()
  local index

  mapfile -t actual_lines

  if [[ "${#actual_lines[@]}" -ne "${#expected_lines[@]}" ]]; then
    printf 'unexpected input count for %s: expected %s, got %s\n' \
      "${target}" "${#expected_lines[@]}" "${#actual_lines[@]}" >&2
    return 1
  fi

  for index in "${!expected_lines[@]}"; do
    if [[ "${actual_lines[$index]}" != "${expected_lines[$index]}" ]]; then
      printf 'unexpected input for %s at line %s: expected <%s>, got <%s>\n' \
        "${target}" "$((index + 1))" "${expected_lines[$index]}" "${actual_lines[$index]}" >&2
      return 1
    fi
  done
}

bash() {
  local target=${1:-}
  shift || true

  printf 'bash:%s %s\n' "${target}" "$*" >> "${CALLS_FILE}"

  case "${target}" in
    "${VERIFY_REMOTE_INSTALL_SCRIPT:-__missing_install__}")
      if [[ "$#" -eq 0 ]]; then
        assert_input_sequence "${target}" \
          "1" "" "1" "443" "www.cloudflare.com" "n" "n" "0"
        printf '443\n' > "${PORT_FILE}"
        next_install_uuid > "${UUID_FILE}"
        printf 'www.cloudflare.com\n' > "${SNI_FILE}"
        install_runtime_artifacts
        return 0
      fi
      if [[ "${1:-}" == "--internal-uninstall-purge" && "${2:-}" == "--yes" ]]; then
        reset_runtime_artifacts
        return 0
      fi
      printf 'unexpected install.sh call: %s\n' "$*" >&2
      return 1
      ;;
    /usr/local/bin/sbv)
      assert_input_sequence "${target}" \
        "3" "1" "8443" "22222222-2222-4222-8222-222222222222" "cdn.cloudflare.com" "0"
      printf '8443\n' > "${PORT_FILE}"
      printf '22222222-2222-4222-8222-222222222222\n' > "${UUID_FILE}"
      printf 'cdn.cloudflare.com\n' > "${SNI_FILE}"
      write_vless_state
      return 0
      ;;
    "${VERIFY_REMOTE_UNINSTALL_SCRIPT:-__missing_uninstall__}")
      reset_runtime_artifacts
      return 0
      ;;
    /root/Clouds/sing-box-vps/install.sh|/root/Clouds/sing-box-vps/uninstall.sh)
      printf 'unexpected stale remote checkout path: %s\n' "${target}" >&2
      return 1
      ;;
  esac

  command bash "${target}" "$@"
}

test() {
  printf 'test:%s|%s|%s\n' "${1:-}" "${2:-}" "${3:-}" >> "${ASSERT_LOG_FILE}"

  if [[ "${1:-}" == "-f" && "${2:-}" == "/root/sing-box-vps/config.json" ]]; then
    [[ $(cat "${CONFIG_PRESENT_FILE}") == "1" ]]
    return
  fi

  if [[ "${1:-}" == "-f" && "${2:-}" == "/etc/systemd/system/sing-box.service" ]]; then
    [[ $(cat "${SERVICE_FILE_PRESENT_FILE}") == "1" ]]
    return
  fi

  if [[ "${1:-}" == "-f" && "${2:-}" == "/root/sing-box-vps/protocols/vless-reality.env" ]]; then
    [[ -f "${STATE_FILE}" ]]
    return
  fi

  if [[ "${1:-}" == "-x" && "${2:-}" == "/usr/local/bin/sbv" ]]; then
    [[ $(cat "${SBV_PRESENT_FILE}") == "1" ]]
    return
  fi

  if [[ "${1:-}" == "!" && "${2:-}" == "-e" && "${3:-}" == "/root/sing-box-vps/config.json" ]]; then
    [[ $(cat "${CONFIG_PRESENT_FILE}") == "0" ]]
    return
  fi

  if [[ "${1:-}" == "!" && "${2:-}" == "-e" && "${3:-}" == "/etc/systemd/system/sing-box.service" ]]; then
    [[ $(cat "${SERVICE_FILE_PRESENT_FILE}") == "0" ]]
    return
  fi

  if [[ "${1:-}" == "!" && "${2:-}" == "-e" && "${3:-}" == "/usr/local/bin/sbv" ]]; then
    [[ $(cat "${SBV_PRESENT_FILE}") == "0" ]]
    return
  fi

  builtin test "$@"
}

jq() {
  printf 'jq:%s|%s|%s\n' "${1:-}" "${2:-}" "${3:-}" >> "${ASSERT_LOG_FILE}"

  if [[ "${1:-}" == "-r" && "${2:-}" == ".inbounds[0].listen_port // empty" ]]; then
    cat "${PORT_FILE}"
    return 0
  fi

  if [[ "${1:-}" == "-r" && "${2:-}" == ".inbounds[0].users[0].uuid // empty" ]]; then
    cat "${UUID_FILE}"
    return 0
  fi

  if [[ "${1:-}" == "-r" && "${2:-}" == ".inbounds[0].tls.server_name // empty" ]]; then
    cat "${SNI_FILE}"
    return 0
  fi

  printf 'unexpected jq call: %s\n' "$*" >&2
  return 1
}

grep() {
  local args=("$@")
  local last_index=$(( $# - 1 ))

  printf 'grep:%s\n' "$*" >> "${ASSERT_LOG_FILE}"

  if [[ "${args[$last_index]}" == "/root/sing-box-vps/protocols/vless-reality.env" ]]; then
    args[$last_index]="${STATE_FILE}"
  fi

  command grep "${args[@]}"
}

systemctl() {
  if [[ "${1:-}" == "is-active" && "${2:-}" == "--quiet" && "${3:-}" == "sing-box" ]]; then
    [[ $(cat "${SERVICE_ACTIVE_FILE}") == "1" ]]
    return
  fi

  if [[ "${1:-}" == "is-active" && "${2:-}" == "sing-box" ]]; then
    printf 'active\n'
    return 0
  fi

  if [[ "${1:-}" == "status" && "${2:-}" == "sing-box" ]]; then
    printf 'status ok\n'
    return 0
  fi

  printf 'unexpected systemctl call: %s\n' "$*" >&2
  return 1
}

sing-box() {
  if [[ "${1:-}" == "check" && "${2:-}" == "-c" && "${3:-}" == "/root/sing-box-vps/config.json" ]]; then
    printf 'config ok\n'
    return 0
  fi

  printf 'unexpected sing-box call: %s\n' "$*" >&2
  return 1
}

journalctl() {
  printf 'journal ok\n'
}

ss() {
  printf 'LISTEN 0 0 127.0.0.1:%s 0.0.0.0:*\n' "$(cat "${PORT_FILE}")"
}
EOF

for scenario_file in "${REPO_ROOT}"/dev/verification/remote/scenarios/*.sh; do
  [[ -f "${scenario_file}" ]] || continue
  cat "${scenario_file}" >> "${PAYLOAD_FILE}"
  printf '\n' >> "${PAYLOAD_FILE}"
done

cat "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" >> "${PAYLOAD_FILE}"

CALLS_FILE="${CALLS_FILE}" \
CONFIG_PRESENT_FILE="${CONFIG_PRESENT_FILE}" \
PORT_FILE="${PORT_FILE}" \
UUID_FILE="${UUID_FILE}" \
SNI_FILE="${SNI_FILE}" \
SERVICE_FILE_PRESENT_FILE="${SERVICE_FILE_PRESENT_FILE}" \
SBV_PRESENT_FILE="${SBV_PRESENT_FILE}" \
SERVICE_ACTIVE_FILE="${SERVICE_ACTIVE_FILE}" \
STATE_FILE="${STATE_FILE}" \
ASSERT_LOG_FILE="${ASSERT_LOG_FILE}" \
INSTALL_COUNT_FILE="${INSTALL_COUNT_FILE}" \
VERIFY_REMOTE_INSTALL_SCRIPT="${EMBEDDED_INSTALL_SCRIPT}" \
VERIFY_REMOTE_UNINSTALL_SCRIPT="${EMBEDDED_UNINSTALL_SCRIPT}" \
  bash "${PAYLOAD_FILE}" \
    fresh_install_vless \
    reconfigure_existing_install \
    uninstall_and_reinstall \
    runtime_smoke \
    > "${STDOUT_FILE}" \
    2> "${STDERR_FILE}"

grep -Fqx 'SCENARIO=fresh_install_vless' "${STDOUT_FILE}"
grep -Fqx 'SCENARIO=reconfigure_existing_install' "${STDOUT_FILE}"
grep -Fqx 'SCENARIO=uninstall_and_reinstall' "${STDOUT_FILE}"
grep -Fqx 'SCENARIO=runtime_smoke' "${STDOUT_FILE}"
grep -Fqx 'test:-f|/root/sing-box-vps/protocols/vless-reality.env|' "${ASSERT_LOG_FILE}"
grep -Fqx 'grep:-Fqx PORT=443 /root/sing-box-vps/protocols/vless-reality.env' "${ASSERT_LOG_FILE}"
grep -Fqx 'grep:-Fqx SNI=www.cloudflare.com /root/sing-box-vps/protocols/vless-reality.env' "${ASSERT_LOG_FILE}"
grep -Fqx 'grep:-Fq stale.example.com /root/sing-box-vps/protocols/vless-reality.env' "${ASSERT_LOG_FILE}"
grep -Fqx 'jq:-r|.inbounds[0].users[0].uuid // empty|/root/sing-box-vps/config.json' "${ASSERT_LOG_FILE}"
grep -Fqx 'jq:-r|.inbounds[0].tls.server_name // empty|/root/sing-box-vps/config.json' "${ASSERT_LOG_FILE}"
grep -Fqx 'grep:-Fqx PORT=8443 /root/sing-box-vps/protocols/vless-reality.env' "${ASSERT_LOG_FILE}"
grep -Fqx 'grep:-Fqx UUID=22222222-2222-4222-8222-222222222222 /root/sing-box-vps/protocols/vless-reality.env' "${ASSERT_LOG_FILE}"
grep -Fqx 'grep:-Fqx SNI=cdn.cloudflare.com /root/sing-box-vps/protocols/vless-reality.env' "${ASSERT_LOG_FILE}"
grep -Fqx 'UUID=44444444-4444-4444-8444-444444444444' "${STATE_FILE}"
grep -Fq "bash:${EMBEDDED_INSTALL_SCRIPT} " "${CALLS_FILE}"
grep -Fq 'bash:/usr/local/bin/sbv ' "${CALLS_FILE}"
grep -Fq "bash:${EMBEDDED_UNINSTALL_SCRIPT} --yes" "${CALLS_FILE}"
! grep -Fq '/root/Clouds/sing-box-vps/install.sh' "${CALLS_FILE}"
! grep -Fq '/root/Clouds/sing-box-vps/uninstall.sh' "${CALLS_FILE}"
