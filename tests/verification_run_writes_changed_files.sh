#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
REAL_BASH=$(command -v bash)
trap 'rm -rf "${TMP_DIR}"' EXIT
REMOTE_PORT_FILE="${TMP_DIR}/remote-port"
REMOTE_UUID_FILE="${TMP_DIR}/remote-uuid"
REMOTE_SNI_FILE="${TMP_DIR}/remote-sni"
REMOTE_CONFIG_PRESENT_FILE="${TMP_DIR}/remote-config-present"
REMOTE_SERVICE_FILE_PRESENT_FILE="${TMP_DIR}/remote-service-file-present"
REMOTE_SBV_PRESENT_FILE="${TMP_DIR}/remote-sbv-present"
REMOTE_SERVICE_ACTIVE_FILE="${TMP_DIR}/remote-service-active"
REMOTE_STATE_FILE="${TMP_DIR}/remote-vless-reality.env"

printf '9443\n' > "${REMOTE_PORT_FILE}"
printf '11111111-1111-4111-8111-111111111111\n' > "${REMOTE_UUID_FILE}"
printf 'stale.example.com\n' > "${REMOTE_SNI_FILE}"
printf '1\n' > "${REMOTE_CONFIG_PRESENT_FILE}"
printf '1\n' > "${REMOTE_SERVICE_FILE_PRESENT_FILE}"
printf '1\n' > "${REMOTE_SBV_PRESENT_FILE}"
printf '1\n' > "${REMOTE_SERVICE_ACTIVE_FILE}"
cat > "${REMOTE_STATE_FILE}" <<'EOF'
PORT=9443
UUID=11111111-1111-4111-8111-111111111111
SNI=stale.example.com
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
printf 'LISTEN 0 0 127.0.0.1:443 0.0.0.0:*\n'
EOF
chmod +x "${TMP_DIR}/ss"

cat > "${TMP_DIR}/ssh" <<EOF
#!${REAL_BASH}
remote_host="\${1:-}"
shift
script_file="${TMP_DIR}/remote-script.sh"
cat <<'PAYLOAD_PRELUDE' > "\${script_file}"
write_vless_state() {
  cat > "\${REMOTE_STATE_FILE}" <<STATE_EOF
PORT=\$(cat "\${REMOTE_PORT_FILE}")
UUID=\$(cat "\${REMOTE_UUID_FILE}")
SNI=\$(cat "\${REMOTE_SNI_FILE}")
STATE_EOF
}

reset_runtime_artifacts() {
  printf '0\n' > "\${REMOTE_CONFIG_PRESENT_FILE}"
  printf '0\n' > "\${REMOTE_SERVICE_FILE_PRESENT_FILE}"
  printf '0\n' > "\${REMOTE_SBV_PRESENT_FILE}"
  printf '0\n' > "\${REMOTE_SERVICE_ACTIVE_FILE}"
  rm -f "\${REMOTE_STATE_FILE}"
}

install_runtime_artifacts() {
  printf '1\n' > "\${REMOTE_CONFIG_PRESENT_FILE}"
  printf '1\n' > "\${REMOTE_SERVICE_FILE_PRESENT_FILE}"
  printf '1\n' > "\${REMOTE_SBV_PRESENT_FILE}"
  printf '1\n' > "\${REMOTE_SERVICE_ACTIVE_FILE}"
  write_vless_state
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
    /root/Clouds/sing-box-vps/install.sh)
      if [[ "\$#" -eq 0 ]]; then
        assert_input_sequence "\${target}" \
          "1" "" "1" "443" "www.cloudflare.com" "n" "n" "0"
        printf '443\n' > "\${REMOTE_PORT_FILE}"
        printf '11111111-1111-4111-8111-111111111111\n' > "\${REMOTE_UUID_FILE}"
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
      assert_input_sequence "\${target}" \
        "3" "1" "8443" "22222222-2222-4222-8222-222222222222" "cdn.cloudflare.com" "0"
      printf '8443\n' > "\${REMOTE_PORT_FILE}"
      printf '22222222-2222-4222-8222-222222222222\n' > "\${REMOTE_UUID_FILE}"
      printf 'cdn.cloudflare.com\n' > "\${REMOTE_SNI_FILE}"
      write_vless_state
      return 0
      ;;
    /root/Clouds/sing-box-vps/uninstall.sh)
      reset_runtime_artifacts
      return 0
      ;;
  esac

  command bash "\${target}" "\$@"
}

test() {
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
  if [[ "\${1:-}" == "-r" && "\${2:-}" == ".inbounds[0].listen_port // empty" ]]; then
    cat "\${REMOTE_PORT_FILE}"
    return 0
  fi

  if [[ "\${1:-}" == "-r" && "\${2:-}" == ".inbounds[0].users[0].uuid // empty" ]]; then
    cat "\${REMOTE_UUID_FILE}"
    return 0
  fi

  if [[ "\${1:-}" == "-r" && "\${2:-}" == ".inbounds[0].tls.server_name // empty" ]]; then
    cat "\${REMOTE_SNI_FILE}"
    return 0
  fi

  printf 'unexpected jq call: %s\n' "\$*" >&2
  return 1
}

grep() {
  local args=("\$@")
  local last_index=\$(( \$# - 1 ))

  if [[ "\${args[\$last_index]}" == "/root/sing-box-vps/protocols/vless-reality.env" ]]; then
    args[\$last_index]="\${REMOTE_STATE_FILE}"
  fi

  command grep "\${args[@]}"
}
PAYLOAD_PRELUDE
cat >> "\${script_file}"
printf 'REMOTE_HOST=%s\n' "\${remote_host}"
REMOTE_CONFIG_PRESENT_FILE="${REMOTE_CONFIG_PRESENT_FILE}" \
REMOTE_PORT_FILE="${REMOTE_PORT_FILE}" \
REMOTE_UUID_FILE="${REMOTE_UUID_FILE}" \
REMOTE_SNI_FILE="${REMOTE_SNI_FILE}" \
REMOTE_SERVICE_FILE_PRESENT_FILE="${REMOTE_SERVICE_FILE_PRESENT_FILE}" \
REMOTE_SBV_PRESENT_FILE="${REMOTE_SBV_PRESENT_FILE}" \
REMOTE_SERVICE_ACTIVE_FILE="${REMOTE_SERVICE_ACTIVE_FILE}" \
REMOTE_STATE_FILE="${REMOTE_STATE_FILE}" \
PATH="${TMP_DIR}:\$PATH" "${REAL_BASH}" -lc "\${1:-}" < "\${script_file}"
EOF
chmod +x "${TMP_DIR}/ssh"

PATH="${TMP_DIR}:${PATH}" VERIFY_REMOTE_HOST=test.example VERIFY_REMOTE_USER=root \
  bash "${REPO_ROOT}/dev/verification/run.sh" > "${TMP_DIR}/stdout.txt"

run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout.txt")
grep -Fqx 'install.sh' "${run_dir}/changed-files.txt"
grep -Fqx 'README.md' "${run_dir}/changed-files.txt"
grep -Fqx 'tests/new_untracked_case.sh' "${run_dir}/changed-files.txt"
scenarios=$(paste -sd, "${run_dir}/scenarios.txt")
[[ "${scenarios}" == "fresh_install_vless,reconfigure_existing_install,runtime_smoke" ]] || {
  printf 'unexpected scenarios: %s\n' "${scenarios}" >&2
  exit 1
}
grep -Fq 'SCENARIO=runtime_smoke' "${run_dir}/remote.stdout.log"
grep -Fq 'REMOTE_HOST=root@test.example' "${run_dir}/remote.stdout.log"
grep -Fqx 'tests/verification_trigger_rules.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_artifact_dir_layout.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_remote_scenario_dispatch.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_run_writes_changed_files.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_scenario_mapping.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_requires_remote_env.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_runtime_smoke_artifacts.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_stops_on_remote_failure.sh|1' "${TMP_DIR}/local-tests.log"
[[ $(wc -l < "${TMP_DIR}/local-tests.log") -eq 8 ]] || {
  printf 'expected only verification workflow tests to run locally\n' >&2
  exit 1
}
default_local_test_count=$(wc -l < "${TMP_DIR}/local-tests.log")

PATH="${TMP_DIR}:${PATH}" VERIFY_REMOTE_HOST=test.example VERIFY_REMOTE_USER=root VERIFY_SKIP_LOCAL_TESTS=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" > "${TMP_DIR}/stdout-skip.txt"

run_dir_skip=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout-skip.txt")
grep -Fqx 'install.sh' "${run_dir_skip}/changed-files.txt"
grep -Fqx 'README.md' "${run_dir_skip}/changed-files.txt"
grep -Fqx 'tests/new_untracked_case.sh' "${run_dir_skip}/changed-files.txt"
scenarios_skip=$(paste -sd, "${run_dir_skip}/scenarios.txt")
[[ "${scenarios_skip}" == "fresh_install_vless,reconfigure_existing_install,runtime_smoke" ]] || {
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
