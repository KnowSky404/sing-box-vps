#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
REAL_BASH=$(command -v bash)
trap 'rm -rf "${TMP_DIR}"' EXIT
REMOTE_PORT_FILE="${TMP_DIR}/remote-port"
REMOTE_CONFIG_PRESENT_FILE="${TMP_DIR}/remote-config-present"
REMOTE_SERVICE_ACTIVE_FILE="${TMP_DIR}/remote-service-active"

printf '443\n' > "${REMOTE_PORT_FILE}"
printf '0\n' > "${REMOTE_CONFIG_PRESENT_FILE}"
printf '0\n' > "${REMOTE_SERVICE_ACTIVE_FILE}"

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
remote_host=\${1:-}
shift
script_file="${TMP_DIR}/remote-script.sh"
cat <<'PAYLOAD_PRELUDE' > "\${script_file}"
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
      fi
      printf '1\n' > "\${REMOTE_CONFIG_PRESENT_FILE}"
      printf '1\n' > "\${REMOTE_SERVICE_ACTIVE_FILE}"
      printf '443\n' > "\${REMOTE_PORT_FILE}"
      return 0
      ;;
    /usr/local/bin/sbv)
      assert_input_sequence "\${target}" \
        "3" "1" "8443" "22222222-2222-4222-8222-222222222222" "cdn.cloudflare.com" "0"
      printf '8443\n' > "\${REMOTE_PORT_FILE}"
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

  builtin test "\$@"
}

jq() {
  if [[ "\${1:-}" == "-r" && "\${2:-}" == ".inbounds[0].listen_port // empty" ]]; then
    cat "\${REMOTE_PORT_FILE}"
    return 0
  fi

  printf 'unexpected jq call: %s\n' "\$*" >&2
  return 1
}
PAYLOAD_PRELUDE
cat >> "\${script_file}"
printf 'REMOTE_HOST=%s\n' "\${remote_host}"
REMOTE_CONFIG_PRESENT_FILE="${REMOTE_CONFIG_PRESENT_FILE}" \
REMOTE_PORT_FILE="${REMOTE_PORT_FILE}" \
REMOTE_SERVICE_ACTIVE_FILE="${REMOTE_SERVICE_ACTIVE_FILE}" \
PATH="${TMP_DIR}:\$PATH" "${REAL_BASH}" -lc "\${1:-}" < "\${script_file}"
EOF
chmod +x "${TMP_DIR}/ssh"

PATH="${TMP_DIR}:${PATH}" VERIFY_REMOTE_HOST=test.example VERIFY_REMOTE_USER=root VERIFY_SKIP_LOCAL_TESTS=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" --changed-file install.sh > "${TMP_DIR}/stdout.txt"

run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout.txt")
grep -Fq 'runtime_smoke' "${run_dir}/scenarios.txt"
grep -Fq 'REMOTE_HOST=root@test.example' "${run_dir}/remote.stdout.log"
grep -Fq 'SCENARIO=runtime_smoke' "${run_dir}/remote.stdout.log"
grep -Fq 'SERVICE_ACTIVE=active' "${run_dir}/remote.stdout.log"
