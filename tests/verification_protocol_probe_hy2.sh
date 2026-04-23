#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

ARTIFACT_DIR="${TMP_DIR}/artifacts"
REMOTE_ROOT="${TMP_DIR}/remote-root"
TESTABLE_ENTRYPOINT="${TMP_DIR}/entrypoint-testable.sh"
EXPECTED_CONFIG_PATH="${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/hy2/client.json"
EXPECTED_RESULT_PATH="${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/hy2/result.env"
EXPECTED_STDOUT_PATH="${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/hy2/probe.stdout.txt"
EXPECTED_CLIENT_PATH_ARTIFACT="${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/hy2/client.path.txt"
ESCAPED_DOMAIN='hy2.example.com ${EDGE_HOST}'
ESCAPED_PASSWORD='hy2 password with spaces & $? []'
ESCAPED_OBFS_PASSWORD='obfs password $(echo no) ;|#'

mkdir -p "${REMOTE_ROOT}/root/sing-box-vps/protocols"

write_hy2_state() {
  local domain=$1
  local password=$2
  local obfs_password=${3-}

  {
    printf 'DOMAIN=%q\n' "${domain}"
    printf 'PASSWORD=%q\n' "${password}"
    printf 'OBFS_PASSWORD=%q\n' "${obfs_password}"
  } > "${REMOTE_ROOT}/root/sing-box-vps/protocols/hy2.env"
}

append_hy2_state_assignment() {
  local key=$1
  local value=${2-}

  printf '%s=%q\n' "${key}" "${value}" >> "${REMOTE_ROOT}/root/sing-box-vps/protocols/hy2.env"
}

awk '
  /^if ! mkdir "\$\{LOCK_DIR\}" 2>\/dev\/null; then$/ {
    exit
  }
  { print }
' "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" \
  | perl -0pe 's|/root/sing-box-vps/protocols/hy2.env|'"${REMOTE_ROOT}"'/root/sing-box-vps/protocols/hy2.env|g' \
  > "${TESTABLE_ENTRYPOINT}"

write_hy2_state \
  "${ESCAPED_DOMAIN}" \
  "${ESCAPED_PASSWORD}" \
  "${ESCAPED_OBFS_PASSWORD}"
append_hy2_state_assignment 'UNRELATED_STATE_KEY' 'state value that must not leak'

cat > "${REMOTE_ROOT}/root/sing-box-vps/config.json" <<'EOF'
{
  "inbounds": [
    {
      "type": "mixed",
      "listen_port": 2080
    },
    {
      "type": "hysteria2",
      "listen_port": 8443,
      "users": [
        {
          "name": "hy2-user",
          "password": "password-from-config-should-not-be-used"
        }
      ],
      "tls": {
        "server_name": "config.example.com"
      },
      "obfs": {
        "type": "salamander",
        "password": "config-obfs-should-not-be-used"
      }
    }
  ]
}
EOF

cat > "${TMP_DIR}/run-hy2-generate.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

source "${TESTABLE_ENTRYPOINT}"

VERIFY_ARTIFACT_DIR="${ARTIFACT_DIR}"
VERIFY_CURRENT_SCENARIO="runtime_smoke"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/\${VERIFY_CURRENT_SCENARIO}"

verification_generate_protocol_probe_client_config \
  hy2 \
  "${REMOTE_ROOT}/root/sing-box-vps/config.json"
EOF
chmod +x "${TMP_DIR}/run-hy2-generate.sh"

cat > "${TMP_DIR}/run-hy2-load-state.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

source "${TESTABLE_ENTRYPOINT}"

EXPECTED_PASSWORD=$(printf '%q' "${ESCAPED_PASSWORD}")
EXPECTED_DOMAIN=$(printf '%q' "${ESCAPED_DOMAIN}")
EXPECTED_OBFS_PASSWORD=$(printf '%q' "${ESCAPED_OBFS_PASSWORD}")

password=''
domain=''
obfs_password=''
unset UNRELATED_STATE_KEY || true

verification_load_hy2_probe_state \
  "${REMOTE_ROOT}/root/sing-box-vps/protocols/hy2.env" \
  password \
  domain \
  obfs_password

[[ "\${password}" == "\${EXPECTED_PASSWORD}" ]]
[[ "\${domain}" == "\${EXPECTED_DOMAIN}" ]]
[[ "\${obfs_password}" == "\${EXPECTED_OBFS_PASSWORD}" ]]
[[ -z "\${UNRELATED_STATE_KEY+x}" ]]
EOF
chmod +x "${TMP_DIR}/run-hy2-load-state.sh"

if ! bash "${TMP_DIR}/run-hy2-load-state.sh" 2> "${TMP_DIR}/stderr-hy2-load-state.txt"; then
  cat "${TMP_DIR}/stderr-hy2-load-state.txt" >&2
  exit 1
fi

if ! config_path=$(bash "${TMP_DIR}/run-hy2-generate.sh" 2> "${TMP_DIR}/stderr-hy2-generate.txt"); then
  cat "${TMP_DIR}/stderr-hy2-generate.txt" >&2
  exit 1
fi

[[ "${config_path}" == "${EXPECTED_CONFIG_PATH}" ]]

if ! jq -e '
  .log.disabled == true and
  (.inbounds | length == 1) and
  .inbounds[0].type == "socks" and
  .inbounds[0].tag == "local-socks" and
  .inbounds[0].listen == "127.0.0.1" and
  .inbounds[0].listen_port == 19080 and
  (.outbounds | length == 1) and
  .outbounds[0].type == "hysteria2" and
  .outbounds[0].tag == "proxy" and
  .outbounds[0].server == "127.0.0.1" and
  .outbounds[0].server_port == 8443 and
  .outbounds[0].password == $password and
  .outbounds[0].tls.enabled == true and
  .outbounds[0].tls.server_name == $domain and
  .outbounds[0].obfs.type == "salamander" and
  .outbounds[0].obfs.password == $obfs_password
' --arg domain "${ESCAPED_DOMAIN}" \
  --arg password "${ESCAPED_PASSWORD}" \
  --arg obfs_password "${ESCAPED_OBFS_PASSWORD}" \
  "${EXPECTED_CONFIG_PATH}" >/dev/null; then
  printf 'generated hy2 probe client config did not match expected fields\n' >&2
  exit 1
fi

write_hy2_state \
  "${ESCAPED_DOMAIN}" \
  "${ESCAPED_PASSWORD}" \
  ''

printf 'stale-client\n' > "${EXPECTED_CONFIG_PATH}"

if bash "${TMP_DIR}/run-hy2-generate.sh" \
  > "${TMP_DIR}/stdout-hy2-missing-obfs-password.txt" \
  2> "${TMP_DIR}/stderr-hy2-missing-obfs-password.txt"; then
  printf 'expected hy2 probe client generation to fail when obfs password is blank\n' >&2
  exit 1
fi

grep -Fq 'missing required hy2 probe field: obfs_password' \
  "${TMP_DIR}/stderr-hy2-missing-obfs-password.txt"
grep -Fqx 'stale-client' "${EXPECTED_CONFIG_PATH}"

write_hy2_state \
  "${ESCAPED_DOMAIN}" \
  "${ESCAPED_PASSWORD}" \
  "${ESCAPED_OBFS_PASSWORD}"

rm -rf "${ARTIFACT_DIR}"

cat > "${TMP_DIR}/run-hy2-execute.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

source "${TESTABLE_ENTRYPOINT}"

VERIFY_ARTIFACT_DIR="${ARTIFACT_DIR}"
VERIFY_CURRENT_SCENARIO="runtime_smoke"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/\${VERIFY_CURRENT_SCENARIO}"

verification_execute_single_protocol_probe \
  hy2 \
  "${REMOTE_ROOT}/root/sing-box-vps/config.json"
EOF
chmod +x "${TMP_DIR}/run-hy2-execute.sh"

if ! bash "${TMP_DIR}/run-hy2-execute.sh" > "${TMP_DIR}/stdout-hy2.txt" 2> "${TMP_DIR}/stderr-hy2.txt"; then
  cat "${TMP_DIR}/stderr-hy2.txt" >&2
  exit 1
fi

[[ -f "${EXPECTED_CONFIG_PATH}" ]]
[[ -f "${EXPECTED_RESULT_PATH}" ]]
[[ -f "${EXPECTED_STDOUT_PATH}" ]]
[[ -f "${EXPECTED_CLIENT_PATH_ARTIFACT}" ]]

grep -Fqx "${EXPECTED_CONFIG_PATH}" "${EXPECTED_CLIENT_PATH_ARTIFACT}"
grep -Fqx 'PROTOCOL=hy2' "${EXPECTED_RESULT_PATH}"
grep -Fqx 'RESULT=success' "${EXPECTED_RESULT_PATH}"
grep -Fqx 'sing-box-vps-loopback-ok' "${EXPECTED_STDOUT_PATH}"

write_hy2_state \
  "${ESCAPED_DOMAIN}" \
  "${ESCAPED_PASSWORD}" \
  ''

if bash "${TMP_DIR}/run-hy2-execute.sh" \
  > "${TMP_DIR}/stdout-hy2-execute-failure.txt" \
  2> "${TMP_DIR}/stderr-hy2-execute-failure.txt"; then
  printf 'expected hy2 probe execution to fail when obfs password is blank\n' >&2
  exit 1
fi

grep -Fq 'missing required hy2 probe field: obfs_password' \
  "${TMP_DIR}/stderr-hy2-execute-failure.txt"
[[ ! -f "${EXPECTED_CONFIG_PATH}" ]]
[[ ! -f "${EXPECTED_STDOUT_PATH}" ]]
[[ ! -f "${EXPECTED_CLIENT_PATH_ARTIFACT}" ]]
if [[ -f "${EXPECTED_RESULT_PATH}" ]]; then
  if grep -Fqx 'RESULT=success' "${EXPECTED_RESULT_PATH}"; then
    printf 'expected failed hy2 probe execution to clear stale success result\n' >&2
    exit 1
  fi
fi
