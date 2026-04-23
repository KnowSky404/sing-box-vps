#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
REAL_BASH=$(command -v bash)
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
REMOTE_ANYTLS_STATE_FILE="${REMOTE_PROTOCOLS_DIR}/anytls.env"
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

cat > "${TMP_DIR}/git" <<EOF
#!${REAL_BASH}
if [[ "\$#" -eq 0 ]]; then
  exit 0
fi
if [[ "\${1:-}" == "diff" && "\${2:-}" == "--name-only" ]]; then
  if [[ -n "\${VERIFY_EMPTY_CHANGES:-}" ]]; then
    exit 0
  fi
  printf 'install.sh\nREADME.md\n'
  exit 0
fi
if [[ "\${1:-}" == "ls-files" && "\${2:-}" == "--others" && "\${3:-}" == "--exclude-standard" ]]; then
  if [[ -n "\${VERIFY_EMPTY_CHANGES:-}" ]]; then
    exit 0
  fi
  printf 'tests/new_untracked_case.sh\n'
  exit 0
fi
printf 'unexpected git call: %s\n' "\$*" >&2
exit 1
EOF
chmod +x "${TMP_DIR}/git"

cat > "${TMP_DIR}/bash" <<EOF
#!${REAL_BASH}
if [[ "\${1:-}" == "${REPO_ROOT}/dev/verification/run.sh" ]]; then
  exec "${REAL_BASH}" "\$@"
fi
if [[ "\${1:-}" == tests/*.sh ]]; then
  printf '%s|%s\n' "\$1" "\${VERIFY_SKIP_LOCAL_TESTS:-unset}" >> "${TMP_DIR}/local-tests.log"
  exit 0
fi
exec "${REAL_BASH}" "\$@"
EOF
chmod +x "${TMP_DIR}/bash"

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
remote_host="\${1:-}"
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

write_anytls_state() {
  mkdir -p "\$(dirname "\${REMOTE_ANYTLS_STATE_FILE}")"
  cat > "\${REMOTE_ANYTLS_STATE_FILE}" <<'STATE_EOF'
PORT=9443
DOMAIN=anytls.example.com
PASSWORD=anytls-pass
USER_NAME=anytls-user
TLS_MODE=manual
STATE_EOF
  cat > "\${REMOTE_CONFIG_FILE}" <<'CONFIG_EOF'
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
        mapfile -t actual_lines
        if [[ "\${actual_lines[2]:-}" == "1" ]]; then
          [[ "\${#actual_lines[@]}" -eq 8 ]]
          [[ "\${actual_lines[0]}" == "1" ]]
          [[ "\${actual_lines[1]}" == "" ]]
          [[ "\${actual_lines[2]}" == "1" ]]
          [[ "\${actual_lines[3]}" == "443" ]]
          [[ "\${actual_lines[4]}" == "www.cloudflare.com" ]]
          [[ "\${actual_lines[5]}" == "n" ]]
          [[ "\${actual_lines[6]}" == "n" ]]
          [[ "\${actual_lines[7]}" == "0" ]]
          printf '443\n' > "\${REMOTE_PORT_FILE}"
          next_install_uuid > "\${REMOTE_UUID_FILE}"
          printf 'www.cloudflare.com\n' > "\${REMOTE_SNI_FILE}"
          install_runtime_artifacts
          return 0
        fi

        if [[ "\${actual_lines[2]:-}" == "4" ]]; then
          [[ "\${#actual_lines[@]}" -eq 13 ]]
          [[ "\${actual_lines[0]}" == "1" ]]
          [[ "\${actual_lines[1]}" == "" ]]
          [[ "\${actual_lines[2]}" == "4" ]]
          [[ "\${actual_lines[3]}" == "anytls.example.com" ]]
          [[ "\${actual_lines[4]}" == "9443" ]]
          [[ "\${actual_lines[5]}" == "anytls-user" ]]
          [[ "\${actual_lines[6]}" == "anytls-pass" ]]
          [[ "\${actual_lines[7]}" == "2" ]]
          [[ -n "\${actual_lines[8]}" ]]
          [[ -n "\${actual_lines[9]}" ]]
          [[ "\${actual_lines[10]}" == "n" ]]
          [[ "\${actual_lines[11]}" == "n" ]]
          [[ "\${actual_lines[12]}" == "0" ]]
          printf '9443\n' > "\${REMOTE_PORT_FILE}"
          printf '1\n' > "\${REMOTE_CONFIG_PRESENT_FILE}"
          printf '1\n' > "\${REMOTE_SERVICE_FILE_PRESENT_FILE}"
          printf '1\n' > "\${REMOTE_SBV_PRESENT_FILE}"
          printf '1\n' > "\${REMOTE_SERVICE_ACTIVE_FILE}"
          write_anytls_state
          cat > "\${REMOTE_INDEX_FILE}" <<'INDEX_EOF'
INSTALLED_PROTOCOLS=anytls
INDEX_EOF
          return 0
        fi

        printf 'unexpected install input: %s\n' "\${actual_lines[*]:-}" >&2
        return 1
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

  if [[ "\${1:-}" == "-f" && "\${2:-}" == "/root/sing-box-vps/protocols/anytls.env" ]]; then
    [[ -f "\${REMOTE_ANYTLS_STATE_FILE}" ]]
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

  command jq "\${args[@]}"
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

sed() {
  local args=("\$@")
  local last_index=\$(( \$# - 1 ))

  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/vless-reality.env" ]]; then
    args[\$last_index]="\${REMOTE_STATE_FILE}"
  fi

  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/anytls.env" ]]; then
    args[\$last_index]="\${REMOTE_ANYTLS_STATE_FILE}"
  fi

  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/index.env" ]]; then
    args[\$last_index]="\${REMOTE_INDEX_FILE}"
  fi

  command sed "\${args[@]}"
}

grep() {
  local args=("\$@")
  local last_index=\$(( \$# - 1 ))

  printf 'grep:%s\n' "\$*" >> "\${REMOTE_ASSERT_LOG_FILE}"

  if [[ "\${args[\$last_index]}" == "/root/sing-box-vps/protocols/vless-reality.env" ]]; then
    args[\$last_index]="\${REMOTE_STATE_FILE}"
  fi

  if [[ "\${args[\$last_index]}" == "/root/sing-box-vps/protocols/anytls.env" ]]; then
    args[\$last_index]="\${REMOTE_ANYTLS_STATE_FILE}"
  fi

  if [[ "\${args[\$last_index]}" == "/root/sing-box-vps/protocols/index.env" ]]; then
    args[\$last_index]="\${REMOTE_INDEX_FILE}"
  fi

  command grep "\${args[@]}"
}
PAYLOAD_PRELUDE
cat >> "\${script_file}"
perl -0pi -e 's|state_file=/root/sing-box-vps/protocols/vless-reality.env|state_file='"${REMOTE_STATE_FILE}"'|g' "\${script_file}"
perl -0pi -e 's|state_file=/root/sing-box-vps/protocols/anytls.env|state_file='"${REMOTE_ANYTLS_STATE_FILE}"'|g' "\${script_file}"
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
REMOTE_ANYTLS_STATE_FILE="${REMOTE_ANYTLS_STATE_FILE}" \
REMOTE_INDEX_FILE="${REMOTE_INDEX_FILE}" \
REMOTE_ASSERT_LOG_FILE="${REMOTE_ASSERT_LOG_FILE}" \
INSTALL_COUNT_FILE="${INSTALL_COUNT_FILE}" \
PATH="${TMP_DIR}:\$PATH" "${REAL_BASH}" -lc "\${1:-}" < "\${script_file}"
EOF
chmod +x "${TMP_DIR}/ssh"

env -u VERIFY_SKIP_LOCAL_TESTS \
  PATH="${TMP_DIR}:${PATH}" VERIFY_REMOTE_TARGET_FILE="${TMP_DIR}/missing-target.env" VERIFY_REMOTE_HOST=test.example VERIFY_REMOTE_USER=root \
  bash "${REPO_ROOT}/dev/verification/run.sh" > "${TMP_DIR}/stdout.txt"

run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout.txt")
grep -Fqx 'install.sh' "${run_dir}/changed-files.txt"
grep -Fqx 'README.md' "${run_dir}/changed-files.txt"
grep -Fqx 'tests/new_untracked_case.sh' "${run_dir}/changed-files.txt"
scenarios=$(paste -sd, "${run_dir}/scenarios.txt")
[[ "${scenarios}" == "fresh_install_vless,reconfigure_existing_install,fresh_install_anytls,runtime_smoke" ]] || {
  printf 'unexpected scenarios: %s\n' "${scenarios}" >&2
  exit 1
}
grep -Fq 'SCENARIO=runtime_smoke' "${run_dir}/remote.stdout.log"
grep -Fq 'REMOTE_HOST=root@test.example' "${run_dir}/remote.stdout.log"
grep -Fq 'remote_target=root@test.example' "${run_dir}/summary.log"
[[ -d "${run_dir}/remote-artifacts/scenarios/fresh_install_vless" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_vless/protocols/index.env" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_vless/listeners.ss-lntp.txt" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/reconfigure_existing_install/config.diff.txt" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_anytls/sing-box-check.txt" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/sing-box-check.txt" ]]
grep -Fq "${INSTALL_VERSION_LINE}" "${TMP_DIR}/remote-script.sh"
grep -Fq "${UNINSTALL_HELPER_LINE}" "${TMP_DIR}/remote-script.sh"
grep -Fq 'remote_artifacts=extracted' "${run_dir}/summary.log"
grep -Fqx 'grep:-Fqx PORT=443 /root/sing-box-vps/protocols/vless-reality.env' "${REMOTE_ASSERT_LOG_FILE}"
grep -Fqx 'grep:-Fqx SNI=www.cloudflare.com /root/sing-box-vps/protocols/vless-reality.env' "${REMOTE_ASSERT_LOG_FILE}"
grep -Fqx 'grep:-Fqx DOMAIN=anytls.example.com /root/sing-box-vps/protocols/anytls.env' "${REMOTE_ASSERT_LOG_FILE}"
grep -Fqx 'PASSWORD=anytls-pass' "${REMOTE_ANYTLS_STATE_FILE}"
grep -Fqx 'tests/verification_protocol_probe_matrix.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_protocol_probe_vless.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_protocol_probe_hy2.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_protocol_probe_anytls.sh|1' "${TMP_DIR}/local-tests.log"
[[ $(wc -l < "${TMP_DIR}/local-tests.log") -eq 4 ]] || {
  printf 'expected only fast protocol probe tests for install changes\n' >&2
  exit 1
}
default_local_test_count=$(wc -l < "${TMP_DIR}/local-tests.log")

PATH="${TMP_DIR}:${PATH}" VERIFY_REMOTE_TARGET_FILE="${TMP_DIR}/missing-target.env" VERIFY_REMOTE_HOST=test.example VERIFY_REMOTE_USER=root VERIFY_SKIP_LOCAL_TESTS=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" > "${TMP_DIR}/stdout-skip.txt"

run_dir_skip=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout-skip.txt")
grep -Fqx 'install.sh' "${run_dir_skip}/changed-files.txt"
grep -Fqx 'README.md' "${run_dir_skip}/changed-files.txt"
grep -Fqx 'tests/new_untracked_case.sh' "${run_dir_skip}/changed-files.txt"
scenarios_skip=$(paste -sd, "${run_dir_skip}/scenarios.txt")
[[ "${scenarios_skip}" == "fresh_install_vless,reconfigure_existing_install,fresh_install_anytls,runtime_smoke" ]] || {
  printf 'unexpected scenarios for skip run: %s\n' "${scenarios_skip}" >&2
  exit 1
}
[[ "${default_local_test_count}" -gt 0 ]] || {
  printf 'expected default run to execute local tests\n' >&2
  exit 1
}
skip_local_test_count=$(wc -l < "${TMP_DIR}/local-tests.log")
[[ "${skip_local_test_count}" -eq "${default_local_test_count}" ]] || {
  printf 'expected skip run to avoid local tests: before=%s after=%s\n' "${default_local_test_count}" "${skip_local_test_count}" >&2
  exit 1
}

env -u VERIFY_SKIP_LOCAL_TESTS \
  PATH="${TMP_DIR}:${PATH}" VERIFY_REMOTE_TARGET_FILE="${TMP_DIR}/missing-target.env" VERIFY_SKIP_REMOTE=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" \
  --changed-file dev/verification/remote/entrypoint.sh > "${TMP_DIR}/stdout-remote-framework.txt"

run_dir_remote_framework=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout-remote-framework.txt")
scenarios_remote_framework=$(paste -sd, "${run_dir_remote_framework}/scenarios.txt")
[[ "${scenarios_remote_framework}" == "runtime_smoke" ]] || {
  printf 'unexpected scenarios for remote framework change: %s\n' "${scenarios_remote_framework}" >&2
  exit 1
}
grep -Fqx 'tests/verification_protocol_probe_matrix.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_protocol_probe_vless.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_protocol_probe_hy2.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_protocol_probe_anytls.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_artifact_dir_layout.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_trigger_rules.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_scenario_mapping.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_requires_remote_env.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_remote_target_file_alias.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_stops_on_remote_failure.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_run_writes_changed_files.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_tests_only_stays_local.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_runtime_smoke_artifacts.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_remote_scenario_dispatch.sh|1' "${TMP_DIR}/local-tests.log"

PATH="${TMP_DIR}:${PATH}" VERIFY_SKIP_LOCAL_TESTS=1 VERIFY_EMPTY_CHANGES=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" > "${TMP_DIR}/stdout-empty.txt"

run_dir_empty=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout-empty.txt")
[[ ! -s "${run_dir_empty}/changed-files.txt" ]] || {
  printf 'expected empty change snapshot for empty change set\n' >&2
  exit 1
}
[[ ! -e "${run_dir_empty}/scenarios.txt" ]] || {
  printf 'did not expect scenarios.txt for local mode empty change set\n' >&2
  exit 1
}
