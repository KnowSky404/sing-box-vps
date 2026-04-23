#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
REAL_BASH=$(command -v bash)
REAL_JQ=$(command -v jq)
trap 'rm -rf "${TMP_DIR}"' EXIT
REMOTE_PORT_FILE="${TMP_DIR}/remote-port"
REMOTE_UUID_FILE="${TMP_DIR}/remote-uuid"
REMOTE_SNI_FILE="${TMP_DIR}/remote-sni"
REMOTE_ROOT_DIR="${TMP_DIR}/remote-root"
REMOTE_CONFIG_FILE="${REMOTE_ROOT_DIR}/root/sing-box-vps/config.json"
REMOTE_PROTOCOLS_DIR="${REMOTE_ROOT_DIR}/root/sing-box-vps/protocols"
REMOTE_CONFIG_PRESENT_FILE="${TMP_DIR}/remote-config-present"
REMOTE_SERVICE_FILE_PRESENT_FILE="${TMP_DIR}/remote-service-file-present"
REMOTE_SBV_PRESENT_FILE="${TMP_DIR}/remote-sbv-present"
REMOTE_SERVICE_ACTIVE_FILE="${TMP_DIR}/remote-service-active"
REMOTE_STATE_FILE="${REMOTE_PROTOCOLS_DIR}/vless-reality.env"
REMOTE_INDEX_FILE="${REMOTE_PROTOCOLS_DIR}/index.env"
REMOTE_ASSERT_LOG_FILE="${TMP_DIR}/remote-assert.log"
INSTALL_COUNT_FILE="${TMP_DIR}/install-count"
INSTALL_VERSION_LINE=$(sed -n 's/^readonly SCRIPT_VERSION=\"[^\"]*\"$/&/p' "${REPO_ROOT}/install.sh" | head -n 1)
UNINSTALL_HELPER_LINE=$(sed -n 's/^resolve_install_script() {$/&/p' "${REPO_ROOT}/uninstall.sh" | head -n 1)

printf '9443\n' > "${REMOTE_PORT_FILE}"
printf '11111111-1111-4111-8111-111111111111\n' > "${REMOTE_UUID_FILE}"
printf 'stale.example.com\n' > "${REMOTE_SNI_FILE}"
printf '1\n' > "${REMOTE_CONFIG_PRESENT_FILE}"
printf '1\n' > "${REMOTE_SERVICE_FILE_PRESENT_FILE}"
printf '1\n' > "${REMOTE_SBV_PRESENT_FILE}"
printf '1\n' > "${REMOTE_SERVICE_ACTIVE_FILE}"
: > "${REMOTE_ASSERT_LOG_FILE}"
printf '0\n' > "${INSTALL_COUNT_FILE}"
mkdir -p "${REMOTE_PROTOCOLS_DIR}"
cat > "${REMOTE_STATE_FILE}" <<'EOF'
PORT=9443
UUID=11111111-1111-4111-8111-111111111111
SNI=stale.example.com
REALITY_PUBLIC_KEY=public-key-from-state
EOF
cat > "${REMOTE_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality
EOF
cat > "${REMOTE_CONFIG_FILE}" <<'EOF'
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

cat > "${TMP_DIR}/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "is-active" && "${2:-}" == "--quiet" && "${3:-}" == "sing-box" ]]; then
  exit 0
fi
if [[ "${1:-}" == "is-active" && "${2:-}" == "sing-box" ]]; then
  printf 'active\n'
  exit 0
fi
if [[ "${1:-}" == "status" && "${2:-}" == "sing-box" ]]; then
  printf 'status ok\n'
  exit 0
fi
exit 0
EOF
chmod +x "${TMP_DIR}/systemctl"

cat > "${TMP_DIR}/journalctl" <<'EOF'
#!/usr/bin/env bash
printf 'journal ok\n'
EOF
chmod +x "${TMP_DIR}/journalctl"

cat > "${TMP_DIR}/sing-box" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "check" && "${2:-}" == "-c" && "${3:-}" == "/root/sing-box-vps/config.json" ]]; then
  if [[ "${VERIFY_FAIL_SINGBOX_CHECK:-0}" == "1" ]]; then
    printf 'config broken\n' >&2
    exit 7
  fi
  printf 'config ok\n'
  exit 0
fi
printf 'unexpected sing-box call: %s\n' "$*" >&2
exit 1
EOF
chmod +x "${TMP_DIR}/sing-box"

cat > "${TMP_DIR}/ss" <<'EOF'
#!/usr/bin/env bash
printf 'LISTEN 0 0 127.0.0.1:%s 0.0.0.0:*\n' "$(cat "${REMOTE_PORT_FILE}")"
EOF
chmod +x "${TMP_DIR}/ss"

cat > "${TMP_DIR}/ssh" <<EOF
#!${REAL_BASH}
remote_host=\${1:-}
shift
script_file="${TMP_DIR}/remote-script.sh"
cat <<'PAYLOAD_PRELUDE' > "\${script_file}"
write_vless_state() {
  mkdir -p "\$(dirname "\${REMOTE_STATE_FILE}")"
  cat > "\${REMOTE_STATE_FILE}" <<STATE_EOF
PORT=\$(cat "\${REMOTE_PORT_FILE}")
UUID=\$(cat "\${REMOTE_UUID_FILE}")
SNI=\$(cat "\${REMOTE_SNI_FILE}")
REALITY_PUBLIC_KEY=public-key-from-state
STATE_EOF
  cat > "\${REMOTE_CONFIG_FILE}" <<CONFIG_EOF
{
  "inbounds": [
    {
      "type": "vless",
      "listen_port": \$(cat "\${REMOTE_PORT_FILE}"),
      "users": [
        {
          "uuid": "\$(cat "\${REMOTE_UUID_FILE}")",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "server_name": "\$(cat "\${REMOTE_SNI_FILE}")",
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

reset_runtime_artifacts() {
  printf '0\n' > "\${REMOTE_CONFIG_PRESENT_FILE}"
  printf '0\n' > "\${REMOTE_SERVICE_FILE_PRESENT_FILE}"
  printf '0\n' > "\${REMOTE_SBV_PRESENT_FILE}"
  printf '0\n' > "\${REMOTE_SERVICE_ACTIVE_FILE}"
  rm -f "\${REMOTE_CONFIG_FILE}"
  rm -rf "\${REMOTE_PROTOCOLS_DIR}"
}

install_runtime_artifacts() {
  printf '1\n' > "\${REMOTE_CONFIG_PRESENT_FILE}"
  printf '1\n' > "\${REMOTE_SERVICE_FILE_PRESENT_FILE}"
  printf '1\n' > "\${REMOTE_SBV_PRESENT_FILE}"
  printf '1\n' > "\${REMOTE_SERVICE_ACTIVE_FILE}"
  write_vless_state
  cat > "\${REMOTE_INDEX_FILE}" <<'INDEX_EOF'
INSTALLED_PROTOCOLS=vless-reality
INDEX_EOF
}

next_install_uuid() {
  local install_count
  install_count=\$(cat "\${INSTALL_COUNT_FILE}")
  install_count=\$((install_count + 1))
  printf '%s\n' "\${install_count}" > "\${INSTALL_COUNT_FILE}"

  case "\${install_count}" in
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
  local target=\$1
  shift
  local expected_lines=("\$@")
  local actual_lines=()
  local index

  mapfile -t actual_lines

  if [[ "\${#actual_lines[@]}" -ne "\${#expected_lines[@]}" ]]; then
    printf 'unexpected input count for %s: expected %s, got %s\n' \
      "\${target}" "\${#expected_lines[@]}" "\${#actual_lines[@]}" >&2
    return 1
  fi

  for index in "\${!expected_lines[@]}"; do
    if [[ "\${actual_lines[\$index]}" != "\${expected_lines[\$index]}" ]]; then
      printf 'unexpected input for %s at line %s: expected <%s>, got <%s>\n' \
        "\${target}" "\$((index + 1))" "\${expected_lines[\$index]}" "\${actual_lines[\$index]}" >&2
      return 1
    fi
  done
}

bash() {
  local target=\${1:-}
  shift || true

  case "\${target}" in
    "\${VERIFY_REMOTE_INSTALL_SCRIPT:-__missing_install__}")
      if [[ "\$#" -eq 0 ]]; then
        assert_input_sequence "\${target}" \
          "1" "" "1" "443" "www.cloudflare.com" "n" "n" "0"
        printf '443\n' > "\${REMOTE_PORT_FILE}"
        next_install_uuid > "\${REMOTE_UUID_FILE}"
        printf 'www.cloudflare.com\n' > "\${REMOTE_SNI_FILE}"
        install_runtime_artifacts
        return 0
      fi
      if [[ "\${1:-}" == "--internal-uninstall-purge" && "\${2:-}" == "--yes" ]]; then
        reset_runtime_artifacts
        return 0
      fi
      printf 'unexpected install.sh call: %s\n' "\$*" >&2
      return 1
      ;;
    /usr/local/bin/sbv)
      mapfile -t actual_lines
      if [[ "\${actual_lines[0]:-}" == "3" ]]; then
        [[ "\${#actual_lines[@]}" -eq 6 ]]
        [[ "\${actual_lines[1]}" == "1" ]]
        [[ "\${actual_lines[2]}" == "8443" ]]
        [[ "\${actual_lines[3]}" == "22222222-2222-4222-8222-222222222222" ]]
        [[ "\${actual_lines[4]}" == "cdn.cloudflare.com" ]]
        [[ "\${actual_lines[5]}" == "0" ]]
        printf '8443\n' > "\${REMOTE_PORT_FILE}"
        printf '22222222-2222-4222-8222-222222222222\n' > "\${REMOTE_UUID_FILE}"
        printf 'cdn.cloudflare.com\n' > "\${REMOTE_SNI_FILE}"
        write_vless_state
        return 0
      fi

      if [[ "\${actual_lines[0]:-}" == "8" && "\${actual_lines[1]:-}" == "0" ]]; then
        printf '服务状态摘要：\n端口: %s\n配置文件: /root/sing-box-vps/config.json\n' "\$(cat "\${REMOTE_PORT_FILE}")"
        return 0
      fi

      printf 'unexpected sbv input: %s\n' "\${actual_lines[*]:-}" >&2
      return 1
      ;;
    "\${VERIFY_REMOTE_UNINSTALL_SCRIPT:-__missing_uninstall__}")
      reset_runtime_artifacts
      return 0
      ;;
    /root/Clouds/sing-box-vps/install.sh|/root/Clouds/sing-box-vps/uninstall.sh)
      printf 'unexpected stale remote checkout path: %s\n' "\${target}" >&2
      return 1
      ;;
  esac

  command bash "\${target}" "\$@"
}

test() {
  printf 'test:%s|%s|%s\n' "\${1:-}" "\${2:-}" "\${3:-}" >> "\${REMOTE_ASSERT_LOG_FILE}"

  if [[ "\${1:-}" == "-f" && "\${2:-}" == "/root/sing-box-vps/config.json" ]]; then
    [[ \$(cat "\${REMOTE_CONFIG_PRESENT_FILE}") == "1" ]]
    return
  fi

  if [[ "\${1:-}" == "-f" && "\${2:-}" == "/etc/systemd/system/sing-box.service" ]]; then
    [[ \$(cat "\${REMOTE_SERVICE_FILE_PRESENT_FILE}") == "1" ]]
    return
  fi

  if [[ "\${1:-}" == "-f" && "\${2:-}" == "/root/sing-box-vps/protocols/vless-reality.env" ]]; then
    [[ -f "\${REMOTE_STATE_FILE}" ]]
    return
  fi

  if [[ "\${1:-}" == "-f" && "\${2:-}" == "/root/sing-box-vps/protocols/index.env" ]]; then
    [[ -f "\${REMOTE_INDEX_FILE}" ]]
    return
  fi

  if [[ "\${1:-}" == "-d" && "\${2:-}" == "/root/sing-box-vps/protocols" ]]; then
    [[ -d "\${REMOTE_PROTOCOLS_DIR}" ]]
    return
  fi

  if [[ "\${1:-}" == "-x" && "\${2:-}" == "/usr/local/bin/sbv" ]]; then
    [[ \$(cat "\${REMOTE_SBV_PRESENT_FILE}") == "1" ]]
    return
  fi

  if [[ "\${1:-}" == "!" && "\${2:-}" == "-e" && "\${3:-}" == "/root/sing-box-vps/config.json" ]]; then
    [[ \$(cat "\${REMOTE_CONFIG_PRESENT_FILE}") == "0" ]]
    return
  fi

  if [[ "\${1:-}" == "!" && "\${2:-}" == "-e" && "\${3:-}" == "/etc/systemd/system/sing-box.service" ]]; then
    [[ \$(cat "\${REMOTE_SERVICE_FILE_PRESENT_FILE}") == "0" ]]
    return
  fi

  if [[ "\${1:-}" == "!" && "\${2:-}" == "-e" && "\${3:-}" == "/usr/local/bin/sbv" ]]; then
    [[ \$(cat "\${REMOTE_SBV_PRESENT_FILE}") == "0" ]]
    return
  fi

  builtin test "\$@"
}

jq() {
  local args=("\$@")
  local last_index=\$(( \$# - 1 ))

  printf 'jq:%s|%s|%s\n' "\${1:-}" "\${2:-}" "\${3:-}" >> "\${REMOTE_ASSERT_LOG_FILE}"

  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/config.json" ]]; then
    args[\$last_index]="\${REMOTE_CONFIG_FILE}"
  fi

  command "\${REAL_JQ}" "\${args[@]}"
}

sed() {
  local args=("\$@")
  local last_index=\$(( \$# - 1 ))

  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/vless-reality.env" ]]; then
    args[\$last_index]="\${REMOTE_STATE_FILE}"
  fi

  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/index.env" ]]; then
    args[\$last_index]="\${REMOTE_INDEX_FILE}"
  fi

  command sed "\${args[@]}"
}

cp() {
  local args=("\$@")
  local source_index=\$(( \${#args[@]} - 2 ))

  if [[ "\${args[\$source_index]}" == "/root/sing-box-vps/config.json" ]]; then
    args[\$source_index]="\${REMOTE_CONFIG_FILE}"
  fi

  if [[ "\${args[\$source_index]}" == "/root/sing-box-vps/protocols/." ]]; then
    args[\$source_index]="\${REMOTE_PROTOCOLS_DIR}/."
  fi

  command cp "\${args[@]}"
}

grep() {
  local args=("\$@")
  local last_index=\$(( \$# - 1 ))

  printf 'grep:%s\n' "\$*" >> "\${REMOTE_ASSERT_LOG_FILE}"

  if [[ "\${args[\$last_index]}" == "/root/sing-box-vps/protocols/vless-reality.env" ]]; then
    args[\$last_index]="\${REMOTE_STATE_FILE}"
  fi

  if [[ "\${args[\$last_index]}" == "/root/sing-box-vps/protocols/index.env" ]]; then
    args[\$last_index]="\${REMOTE_INDEX_FILE}"
  fi

  command grep "\${args[@]}"
}
PAYLOAD_PRELUDE
cat >> "\${script_file}"
perl -0pi -e 's|state_file=/root/sing-box-vps/protocols/vless-reality.env|state_file='"${REMOTE_STATE_FILE}"'|g' "\${script_file}"
printf 'REMOTE_HOST=%s\n' "\${remote_host}"
REMOTE_CONFIG_PRESENT_FILE="${REMOTE_CONFIG_PRESENT_FILE}" \
REMOTE_PORT_FILE="${REMOTE_PORT_FILE}" \
REMOTE_UUID_FILE="${REMOTE_UUID_FILE}" \
REMOTE_SNI_FILE="${REMOTE_SNI_FILE}" \
REMOTE_SERVICE_FILE_PRESENT_FILE="${REMOTE_SERVICE_FILE_PRESENT_FILE}" \
REMOTE_SBV_PRESENT_FILE="${REMOTE_SBV_PRESENT_FILE}" \
REMOTE_SERVICE_ACTIVE_FILE="${REMOTE_SERVICE_ACTIVE_FILE}" \
REMOTE_CONFIG_FILE="${REMOTE_CONFIG_FILE}" \
REMOTE_PROTOCOLS_DIR="${REMOTE_PROTOCOLS_DIR}" \
REMOTE_STATE_FILE="${REMOTE_STATE_FILE}" \
REMOTE_INDEX_FILE="${REMOTE_INDEX_FILE}" \
REMOTE_ASSERT_LOG_FILE="${REMOTE_ASSERT_LOG_FILE}" \
INSTALL_COUNT_FILE="${INSTALL_COUNT_FILE}" \
REAL_JQ="${REAL_JQ}" \
PATH="${TMP_DIR}:\$PATH" "${REAL_BASH}" -lc "\${1:-}" < "\${script_file}"
EOF
chmod +x "${TMP_DIR}/ssh"

PATH="${TMP_DIR}:${PATH}" VERIFY_REMOTE_TARGET_FILE="${TMP_DIR}/missing-target.env" VERIFY_REMOTE_HOST=test.example VERIFY_REMOTE_USER=root VERIFY_SKIP_LOCAL_TESTS=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" --changed-file install.sh > "${TMP_DIR}/stdout.txt"

run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout.txt")
grep -Fq 'runtime_smoke' "${run_dir}/scenarios.txt"
grep -Fq 'REMOTE_HOST=root@test.example' "${run_dir}/remote.stdout.log"
grep -Fq 'remote_target=root@test.example' "${run_dir}/summary.log"
grep -Fq 'SCENARIO=runtime_smoke' "${run_dir}/remote.stdout.log"
grep -Fq 'SERVICE_ACTIVE=active' "${run_dir}/remote.stdout.log"
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/sing-box-check.txt" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/listeners.ss-lntp.txt" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/vless-reality/client.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/vless-reality/probe.stdout.txt" ]]
grep -Fqx 'RESULT=success' "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/vless-reality/result.env"
grep -Fq 'remote_artifacts=extracted' "${run_dir}/summary.log"
grep -Fq "${INSTALL_VERSION_LINE}" "${TMP_DIR}/remote-script.sh"
grep -Fq "${UNINSTALL_HELPER_LINE}" "${TMP_DIR}/remote-script.sh"
grep -Fqx 'grep:-Fqx PORT=443 /root/sing-box-vps/protocols/vless-reality.env' "${REMOTE_ASSERT_LOG_FILE}"
grep -Fqx 'grep:-Fqx SNI=www.cloudflare.com /root/sing-box-vps/protocols/vless-reality.env' "${REMOTE_ASSERT_LOG_FILE}"
grep -Fqx 'jq:-r|.inbounds[0].listen_port // empty|/root/sing-box-vps/config.json' "${REMOTE_ASSERT_LOG_FILE}"
grep -Fqx 'UUID=22222222-2222-4222-8222-222222222222' "${REMOTE_STATE_FILE}"

if PATH="${TMP_DIR}:${PATH}" VERIFY_REMOTE_TARGET_FILE="${TMP_DIR}/missing-target.env" VERIFY_REMOTE_HOST=test.example VERIFY_REMOTE_USER=root VERIFY_SKIP_LOCAL_TESTS=1 VERIFY_FAIL_SINGBOX_CHECK=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" --changed-file install.sh > "${TMP_DIR}/stdout-fail.txt" 2> "${TMP_DIR}/stderr-fail.txt"; then
  printf 'expected runtime smoke to fail when sing-box check fails\n' >&2
  exit 1
fi

run_dir_fail=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout-fail.txt")
[[ -f "${run_dir_fail}/remote-artifacts/scenarios/fresh_install_vless/sing-box-check.txt" ]]
grep -Fq 'config broken' "${run_dir_fail}/remote-artifacts/scenarios/fresh_install_vless/sing-box-check.txt"
grep -Fq 'remote_status=failure' "${run_dir_fail}/summary.log"
