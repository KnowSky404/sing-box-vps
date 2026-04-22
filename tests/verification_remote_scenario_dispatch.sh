#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

PORT_FILE="${TMP_DIR}/port"
CONFIG_PRESENT_FILE="${TMP_DIR}/config-present"
SERVICE_ACTIVE_FILE="${TMP_DIR}/service-active"
CALLS_FILE="${TMP_DIR}/calls.log"
PAYLOAD_FILE="${TMP_DIR}/remote-payload.sh"
STDOUT_FILE="${TMP_DIR}/stdout.log"
STDERR_FILE="${TMP_DIR}/stderr.log"

printf '443\n' > "${PORT_FILE}"
printf '0\n' > "${CONFIG_PRESENT_FILE}"
printf '0\n' > "${SERVICE_ACTIVE_FILE}"
: > "${CALLS_FILE}"

cat <<'EOF' > "${PAYLOAD_FILE}"
#!/usr/bin/env bash

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
    /root/Clouds/sing-box-vps/install.sh)
      if [[ "$#" -eq 0 ]]; then
        assert_input_sequence "${target}" \
          "1" "" "1" "443" "www.cloudflare.com" "n" "n" "0"
      fi
      printf '1\n' > "${CONFIG_PRESENT_FILE}"
      printf '1\n' > "${SERVICE_ACTIVE_FILE}"
      printf '443\n' > "${PORT_FILE}"
      return 0
      ;;
    /usr/local/bin/sbv)
      assert_input_sequence "${target}" \
        "3" "1" "8443" "22222222-2222-4222-8222-222222222222" "cdn.cloudflare.com" "0"
      printf '8443\n' > "${PORT_FILE}"
      return 0
      ;;
    /root/Clouds/sing-box-vps/uninstall.sh)
      printf '0\n' > "${CONFIG_PRESENT_FILE}"
      printf '0\n' > "${SERVICE_ACTIVE_FILE}"
      return 0
      ;;
  esac

  command bash "${target}" "$@"
}

test() {
  if [[ "${1:-}" == "-f" && "${2:-}" == "/root/sing-box-vps/config.json" ]]; then
    [[ $(cat "${CONFIG_PRESENT_FILE}") == "1" ]]
    return
  fi

  if [[ "${1:-}" == "!" && "${2:-}" == "-e" && "${3:-}" == "/root/sing-box-vps/config.json" ]]; then
    [[ $(cat "${CONFIG_PRESENT_FILE}") == "0" ]]
    return
  fi

  builtin test "$@"
}

jq() {
  if [[ "${1:-}" == "-r" && "${2:-}" == ".inbounds[0].listen_port // empty" ]]; then
    cat "${PORT_FILE}"
    return 0
  fi

  printf 'unexpected jq call: %s\n' "$*" >&2
  return 1
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
SERVICE_ACTIVE_FILE="${SERVICE_ACTIVE_FILE}" \
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
grep -Fq 'bash:/root/Clouds/sing-box-vps/install.sh ' "${CALLS_FILE}"
grep -Fq 'bash:/usr/local/bin/sbv ' "${CALLS_FILE}"
grep -Fq 'bash:/root/Clouds/sing-box-vps/uninstall.sh --yes' "${CALLS_FILE}"
