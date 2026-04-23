#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT
REAL_JQ=$(command -v jq)

PORT_FILE="${TMP_DIR}/port"
UUID_FILE="${TMP_DIR}/uuid"
SNI_FILE="${TMP_DIR}/sni"
REMOTE_ROOT_DIR="${TMP_DIR}/remote-root"
CONFIG_FILE="${REMOTE_ROOT_DIR}/root/sing-box-vps/config.json"
PROTOCOLS_DIR="${REMOTE_ROOT_DIR}/root/sing-box-vps/protocols"
CONFIG_PRESENT_FILE="${TMP_DIR}/config-present"
SERVICE_FILE_PRESENT_FILE="${TMP_DIR}/service-file-present"
SBV_PRESENT_FILE="${TMP_DIR}/sbv-present"
SERVICE_ACTIVE_FILE="${TMP_DIR}/service-active"
STATE_FILE="${PROTOCOLS_DIR}/vless-reality.env"
ANYTLS_STATE_FILE="${PROTOCOLS_DIR}/anytls.env"
INDEX_FILE="${PROTOCOLS_DIR}/index.env"
ASSERT_LOG_FILE="${TMP_DIR}/assert.log"
CALLS_FILE="${TMP_DIR}/calls.log"
PAYLOAD_FILE="${TMP_DIR}/remote-payload.sh"
STDOUT_FILE="${TMP_DIR}/stdout.log"
STDERR_FILE="${TMP_DIR}/stderr.log"
ARTIFACT_DIR="${TMP_DIR}/artifacts"
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
mkdir -p "${PROTOCOLS_DIR}"
cat > "${STATE_FILE}" <<'EOF'
PORT=9443
UUID=11111111-1111-4111-8111-111111111111
SNI=stale.example.com
REALITY_PUBLIC_KEY=public-key-from-state
EOF
cat > "${INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality
EOF
cat > "${CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "vless",
      "listen_port": 9443,
      "users": [
        {
          "uuid": "11111111-1111-4111-8111-111111111111",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "server_name": "stale.example.com",
        "reality": {
          "short_id": [
            "abcd1234"
          ]
        }
      }
    }
  ]
}
EOF

cat <<'EOF' > "${PAYLOAD_FILE}"
#!/usr/bin/env bash

write_vless_state() {
  mkdir -p "$(dirname "${STATE_FILE}")"
  cat > "${STATE_FILE}" <<STATE_EOF
PORT=$(cat "${PORT_FILE}")
UUID=$(cat "${UUID_FILE}")
SNI=$(cat "${SNI_FILE}")
REALITY_PUBLIC_KEY=public-key-from-state
STATE_EOF
  cat > "${CONFIG_FILE}" <<CONFIG_EOF
{
  "inbounds": [
    {
      "type": "vless",
      "listen_port": $(cat "${PORT_FILE}"),
      "users": [
        {
          "uuid": "$(cat "${UUID_FILE}")",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "server_name": "$(cat "${SNI_FILE}")",
        "reality": {
          "short_id": [
            "abcd1234"
          ]
        }
      }
    }
  ]
}
CONFIG_EOF
}

write_anytls_state() {
  mkdir -p "$(dirname "${ANYTLS_STATE_FILE}")"
  cat > "${ANYTLS_STATE_FILE}" <<'STATE_EOF'
PORT=9443
DOMAIN=anytls.example.com
PASSWORD=anytls-pass
USER_NAME=anytls-user
TLS_MODE=manual
STATE_EOF
  cat > "${CONFIG_FILE}" <<'CONFIG_EOF'
{
  "inbounds": [
    {
      "type": "anytls",
      "listen_port": 9443,
      "users": [
        {
          "name": "anytls-user",
          "password": "anytls-pass"
        }
      ],
      "tls": {
        "server_name": "anytls.example.com"
      }
    }
  ]
}
CONFIG_EOF
}

reset_runtime_artifacts() {
  printf '0\n' > "${CONFIG_PRESENT_FILE}"
  printf '0\n' > "${SERVICE_FILE_PRESENT_FILE}"
  printf '0\n' > "${SBV_PRESENT_FILE}"
  printf '0\n' > "${SERVICE_ACTIVE_FILE}"
  rm -f "${CONFIG_FILE}"
  rm -rf "${PROTOCOLS_DIR}"
}

install_runtime_artifacts() {
  printf '1\n' > "${CONFIG_PRESENT_FILE}"
  printf '1\n' > "${SERVICE_FILE_PRESENT_FILE}"
  printf '1\n' > "${SBV_PRESENT_FILE}"
  printf '1\n' > "${SERVICE_ACTIVE_FILE}"
  write_vless_state
  cat > "${INDEX_FILE}" <<'INDEX_EOF'
INSTALLED_PROTOCOLS=vless-reality
INDEX_EOF
}

verification_prepare_remote_local_tree() {
  : "${VERIFY_REMOTE_INSTALL_SCRIPT:?VERIFY_REMOTE_INSTALL_SCRIPT is required}"
  : "${VERIFY_REMOTE_UNINSTALL_SCRIPT:?VERIFY_REMOTE_UNINSTALL_SCRIPT is required}"
  VERIFY_REMOTE_LOCAL_TREE_DIR="$(dirname "${CALLS_FILE}")/remote-local-tree"
  mkdir -p "${VERIFY_REMOTE_LOCAL_TREE_DIR}"
  export VERIFY_REMOTE_LOCAL_TREE_DIR
}

verification_cleanup_remote_local_tree() {
  rm -rf "${VERIFY_REMOTE_LOCAL_TREE_DIR:-}"
  unset VERIFY_REMOTE_LOCAL_TREE_DIR
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
        mapfile -t actual_lines
        if [[ "${actual_lines[2]:-}" == "1" ]]; then
          if [[ "${#actual_lines[@]}" -ne 8 ]]; then
            printf 'unexpected vless install input count for %s: %s\n' "${target}" "${#actual_lines[@]}" >&2
            return 1
          fi
          [[ "${actual_lines[0]}" == "1" ]]
          [[ "${actual_lines[2]}" == "1" ]]
          [[ "${actual_lines[3]}" == "443" ]]
          [[ "${actual_lines[4]}" == "www.cloudflare.com" ]]
          [[ "${actual_lines[5]}" == "n" ]]
          [[ "${actual_lines[6]}" == "n" ]]
          [[ "${actual_lines[7]}" == "0" ]]
          printf '443\n' > "${PORT_FILE}"
          next_install_uuid > "${UUID_FILE}"
          printf 'www.cloudflare.com\n' > "${SNI_FILE}"
          install_runtime_artifacts
          return 0
        fi

        if [[ "${actual_lines[2]:-}" == "4" ]]; then
          if [[ "${#actual_lines[@]}" -ne 13 ]]; then
            printf 'unexpected anytls install input count for %s: %s\n' "${target}" "${#actual_lines[@]}" >&2
            return 1
          fi
          [[ "${actual_lines[0]}" == "1" ]]
          [[ "${actual_lines[1]}" == "" ]]
          [[ "${actual_lines[2]}" == "4" ]]
          [[ "${actual_lines[3]}" == "anytls.example.com" ]]
          [[ "${actual_lines[4]}" == "9443" ]]
          [[ "${actual_lines[5]}" == "anytls-user" ]]
          [[ "${actual_lines[6]}" == "anytls-pass" ]]
          [[ "${actual_lines[7]}" == "2" ]]
          [[ -n "${actual_lines[8]}" ]]
          [[ -n "${actual_lines[9]}" ]]
          [[ "${actual_lines[10]}" == "n" ]]
          [[ "${actual_lines[11]}" == "n" ]]
          [[ "${actual_lines[12]}" == "0" ]]
          printf '9443\n' > "${PORT_FILE}"
          printf '1\n' > "${CONFIG_PRESENT_FILE}"
          printf '1\n' > "${SERVICE_FILE_PRESENT_FILE}"
          printf '1\n' > "${SBV_PRESENT_FILE}"
          printf '1\n' > "${SERVICE_ACTIVE_FILE}"
          write_anytls_state
          cat > "${INDEX_FILE}" <<'INDEX_EOF'
INSTALLED_PROTOCOLS=anytls
INDEX_EOF
          return 0
        fi

        printf 'unexpected install input: %s\n' "${actual_lines[*]:-}" >&2
        return 1
      fi
      if [[ "${1:-}" == "--internal-uninstall-purge" && "${2:-}" == "--yes" ]]; then
        reset_runtime_artifacts
        return 0
      fi
      printf 'unexpected install.sh call: %s\n' "$*" >&2
      return 1
      ;;
    /usr/local/bin/sbv)
      mapfile -t actual_lines
      if [[ "${actual_lines[0]:-}" == "3" ]]; then
        if [[ "${#actual_lines[@]}" -ne 6 ]]; then
          printf 'unexpected update input count for %s: %s\n' "${target}" "${#actual_lines[@]}" >&2
          return 1
        fi
        [[ "${actual_lines[1]}" == "1" ]]
        [[ "${actual_lines[2]}" == "8443" ]]
        [[ "${actual_lines[3]}" == "22222222-2222-4222-8222-222222222222" ]]
        [[ "${actual_lines[4]}" == "cdn.cloudflare.com" ]]
        [[ "${actual_lines[5]}" == "0" ]]
        printf '8443\n' > "${PORT_FILE}"
        printf '22222222-2222-4222-8222-222222222222\n' > "${UUID_FILE}"
        printf 'cdn.cloudflare.com\n' > "${SNI_FILE}"
        write_vless_state
        return 0
      fi

      if [[ "${actual_lines[0]:-}" == "8" && "${actual_lines[1]:-}" == "0" ]]; then
        printf '服务状态摘要：\n端口: %s\n配置文件: /root/sing-box-vps/config.json\n' "$(cat "${PORT_FILE}")"
        return 0
      fi

      printf 'unexpected sbv input: %s\n' "${actual_lines[*]:-}" >&2
      return 1
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

  if [[ "${1:-}" == "-f" && "${2:-}" == "/root/sing-box-vps/protocols/anytls.env" ]]; then
    [[ -f "${ANYTLS_STATE_FILE}" ]]
    return
  fi

  if [[ "${1:-}" == "-f" && "${2:-}" == "/root/sing-box-vps/protocols/index.env" ]]; then
    [[ -f "${INDEX_FILE}" ]]
    return
  fi

  if [[ "${1:-}" == "-d" && "${2:-}" == "/root/sing-box-vps/protocols" ]]; then
    [[ -d "${PROTOCOLS_DIR}" ]]
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
  local args=("$@")
  local last_index=$(( $# - 1 ))

  printf 'jq:%s|%s|%s\n' "${1:-}" "${2:-}" "${3:-}" >> "${ASSERT_LOG_FILE}"

  if [[ "${args[$last_index]:-}" == "/root/sing-box-vps/config.json" ]]; then
    args[$last_index]="${CONFIG_FILE}"
  fi

  command "${REAL_JQ}" "${args[@]}"
}

sed() {
  local args=("$@")
  local last_index=$(( $# - 1 ))

  if [[ "${args[$last_index]:-}" == "/root/sing-box-vps/protocols/vless-reality.env" ]]; then
    args[$last_index]="${STATE_FILE}"
  fi

  if [[ "${args[$last_index]:-}" == "/root/sing-box-vps/protocols/anytls.env" ]]; then
    args[$last_index]="${ANYTLS_STATE_FILE}"
  fi

  if [[ "${args[$last_index]:-}" == "/root/sing-box-vps/protocols/index.env" ]]; then
    args[$last_index]="${INDEX_FILE}"
  fi

  command sed "${args[@]}"
}

cp() {
  local args=("$@")
  local source_index=$(( ${#args[@]} - 2 ))

  if [[ "${args[$source_index]}" == "/root/sing-box-vps/config.json" ]]; then
    args[$source_index]="${CONFIG_FILE}"
  fi

  if [[ "${args[$source_index]}" == "/root/sing-box-vps/protocols/." ]]; then
    args[$source_index]="${PROTOCOLS_DIR}/."
  fi

  command cp "${args[@]}"
}

grep() {
  local args=("$@")
  local last_index=$(( $# - 1 ))

  printf 'grep:%s\n' "$*" >> "${ASSERT_LOG_FILE}"

  if [[ "${args[$last_index]}" == "/root/sing-box-vps/protocols/vless-reality.env" ]]; then
    args[$last_index]="${STATE_FILE}"
  fi

  if [[ "${args[$last_index]}" == "/root/sing-box-vps/protocols/anytls.env" ]]; then
    args[$last_index]="${ANYTLS_STATE_FILE}"
  fi

  if [[ "${args[$last_index]}" == "/root/sing-box-vps/protocols/index.env" ]]; then
    args[$last_index]="${INDEX_FILE}"
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
perl -0pi -e 's|state_file=/root/sing-box-vps/protocols/vless-reality.env|state_file='"${STATE_FILE}"'|g' "${PAYLOAD_FILE}"
perl -0pi -e 's|state_file=/root/sing-box-vps/protocols/anytls.env|state_file='"${ANYTLS_STATE_FILE}"'|g' "${PAYLOAD_FILE}"

CALLS_FILE="${CALLS_FILE}" \
CONFIG_PRESENT_FILE="${CONFIG_PRESENT_FILE}" \
PORT_FILE="${PORT_FILE}" \
UUID_FILE="${UUID_FILE}" \
SNI_FILE="${SNI_FILE}" \
CONFIG_FILE="${CONFIG_FILE}" \
PROTOCOLS_DIR="${PROTOCOLS_DIR}" \
SERVICE_FILE_PRESENT_FILE="${SERVICE_FILE_PRESENT_FILE}" \
SBV_PRESENT_FILE="${SBV_PRESENT_FILE}" \
SERVICE_ACTIVE_FILE="${SERVICE_ACTIVE_FILE}" \
STATE_FILE="${STATE_FILE}" \
ANYTLS_STATE_FILE="${ANYTLS_STATE_FILE}" \
INDEX_FILE="${INDEX_FILE}" \
ASSERT_LOG_FILE="${ASSERT_LOG_FILE}" \
INSTALL_COUNT_FILE="${INSTALL_COUNT_FILE}" \
VERIFY_REMOTE_INSTALL_SCRIPT="${EMBEDDED_INSTALL_SCRIPT}" \
VERIFY_REMOTE_UNINSTALL_SCRIPT="${EMBEDDED_UNINSTALL_SCRIPT}" \
REAL_JQ="${REAL_JQ}" \
  bash "${PAYLOAD_FILE}" \
    fresh_install_vless \
    reconfigure_existing_install \
    fresh_install_anytls \
    runtime_smoke \
    uninstall_and_reinstall \
    > "${STDOUT_FILE}" \
    2> "${STDERR_FILE}"

grep -Fqx 'SCENARIO=fresh_install_vless' "${STDOUT_FILE}"
grep -Fqx 'SCENARIO=reconfigure_existing_install' "${STDOUT_FILE}"
grep -Fqx 'SCENARIO=fresh_install_anytls' "${STDOUT_FILE}"
grep -Fqx 'SCENARIO=uninstall_and_reinstall' "${STDOUT_FILE}"
grep -Fqx 'SCENARIO=runtime_smoke' "${STDOUT_FILE}"
grep -Fq '__SING_BOX_VPS_REMOTE_ARTIFACT_BUNDLE_BEGIN__' "${STDOUT_FILE}"
grep -Fq '__SING_BOX_VPS_REMOTE_ARTIFACT_BUNDLE_END__' "${STDOUT_FILE}"
mkdir -p "${ARTIFACT_DIR}"
awk '
  /__SING_BOX_VPS_REMOTE_ARTIFACT_BUNDLE_BEGIN__/ { capture=1; next }
  /__SING_BOX_VPS_REMOTE_ARTIFACT_BUNDLE_END__/ { capture=0; exit }
  capture { print }
' "${STDOUT_FILE}" | base64 -d | tar -xzf - -C "${ARTIFACT_DIR}"
[[ -f "${ARTIFACT_DIR}/meta/scenarios.txt" ]]
[[ -f "${ARTIFACT_DIR}/scenarios/fresh_install_vless/protocols/index.env" ]]
[[ -f "${ARTIFACT_DIR}/scenarios/fresh_install_vless/listeners.ss-lntp.txt" ]]
[[ -f "${ARTIFACT_DIR}/scenarios/fresh_install_vless/sbv-status.txt" ]]
grep -Fqx 'RESULT=success' "${ARTIFACT_DIR}/scenarios/fresh_install_vless/protocol-probes/vless-reality/result.env"
[[ -f "${ARTIFACT_DIR}/scenarios/reconfigure_existing_install/config.diff.txt" ]]
grep -Fqx 'RESULT=success' "${ARTIFACT_DIR}/scenarios/reconfigure_existing_install/protocol-probes/vless-reality/result.env"
grep -Fqx 'RESULT=success' "${ARTIFACT_DIR}/scenarios/fresh_install_anytls/protocol-probes/anytls/result.env"
[[ -f "${ARTIFACT_DIR}/scenarios/runtime_smoke/sing-box-check.txt" ]]
grep -Fqx 'STATUS=success' "${ARTIFACT_DIR}/scenarios/runtime_smoke/result.env"
grep -Fqx 'RESULT=success' "${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/anytls/result.env"
grep -Fqx 'RESULT=success' "${ARTIFACT_DIR}/scenarios/uninstall_and_reinstall/protocol-probes/vless-reality/result.env"
[[ -f "${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/anytls/client.json" ]]
[[ -f "${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/anytls/probe.stdout.txt" ]]
grep -Fq 'verification_run_protocol_probes' "${PAYLOAD_FILE}"
! grep -Fq 'verification_execute_single_protocol_probe vless-reality /root/sing-box-vps/config.json' "${PAYLOAD_FILE}"
grep -Fqx 'test:-f|/root/sing-box-vps/protocols/vless-reality.env|' "${ASSERT_LOG_FILE}"
grep -Fqx 'test:-f|/root/sing-box-vps/protocols/anytls.env|' "${ASSERT_LOG_FILE}"
grep -Fqx 'test:-f|/root/sing-box-vps/protocols/index.env|' "${ASSERT_LOG_FILE}"
grep -Fqx 'grep:-Fqx PORT=443 /root/sing-box-vps/protocols/vless-reality.env' "${ASSERT_LOG_FILE}"
grep -Fqx 'grep:-Fqx SNI=www.cloudflare.com /root/sing-box-vps/protocols/vless-reality.env' "${ASSERT_LOG_FILE}"
grep -Fqx 'grep:-Fq stale.example.com /root/sing-box-vps/protocols/vless-reality.env' "${ASSERT_LOG_FILE}"
grep -Fqx 'jq:-r|.inbounds[0].users[0].uuid // empty|/root/sing-box-vps/config.json' "${ASSERT_LOG_FILE}"
grep -Fqx 'jq:-r|.inbounds[0].tls.server_name // empty|/root/sing-box-vps/config.json' "${ASSERT_LOG_FILE}"
grep -Fqx 'jq:-r|.inbounds[0].listen_port // empty|/root/sing-box-vps/config.json' "${ASSERT_LOG_FILE}"
grep -Fqx 'grep:-Fqx PORT=8443 /root/sing-box-vps/protocols/vless-reality.env' "${ASSERT_LOG_FILE}"
grep -Fqx 'grep:-Fqx UUID=22222222-2222-4222-8222-222222222222 /root/sing-box-vps/protocols/vless-reality.env' "${ASSERT_LOG_FILE}"
grep -Fqx 'grep:-Fqx SNI=cdn.cloudflare.com /root/sing-box-vps/protocols/vless-reality.env' "${ASSERT_LOG_FILE}"
grep -Fqx 'grep:-Fqx PORT=9443 /root/sing-box-vps/protocols/anytls.env' "${ASSERT_LOG_FILE}"
grep -Fqx 'grep:-Fqx DOMAIN=anytls.example.com /root/sing-box-vps/protocols/anytls.env' "${ASSERT_LOG_FILE}"
grep -Fqx 'grep:-Fqx PASSWORD=anytls-pass /root/sing-box-vps/protocols/anytls.env' "${ASSERT_LOG_FILE}"
grep -Fqx 'UUID=44444444-4444-4444-8444-444444444444' "${STATE_FILE}"
grep -Fq "bash:${EMBEDDED_INSTALL_SCRIPT} " "${CALLS_FILE}"
grep -Fq 'bash:/usr/local/bin/sbv ' "${CALLS_FILE}"
grep -Fq "bash:${EMBEDDED_UNINSTALL_SCRIPT} --yes" "${CALLS_FILE}"
! grep -Fq '/root/Clouds/sing-box-vps/install.sh' "${CALLS_FILE}"
! grep -Fq '/root/Clouds/sing-box-vps/uninstall.sh' "${CALLS_FILE}"
