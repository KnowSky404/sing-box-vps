#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

ARTIFACT_DIR="${TMP_DIR}/artifacts"
REMOTE_ROOT="${TMP_DIR}/remote-root"
TESTABLE_ENTRYPOINT="${TMP_DIR}/entrypoint-testable.sh"
EXPECTED_CONFIG_PATH="${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/anytls/client.json"
EXPECTED_RESULT_PATH="${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/anytls/result.env"
EXPECTED_STDOUT_PATH="${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/anytls/probe.stdout.txt"
EXPECTED_CLIENT_PATH_ARTIFACT="${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/anytls/client.path.txt"
ESCAPED_DOMAIN='anytls.example.com ${EDGE_HOST}'
ESCAPED_PASSWORD='anytls password with spaces & $? []'

mkdir -p "${REMOTE_ROOT}/root/sing-box-vps/protocols"

write_anytls_state() {
  local domain=$1
  local password=$2

  {
    printf 'DOMAIN=%q\n' "${domain}"
    printf 'PASSWORD=%q\n' "${password}"
  } > "${REMOTE_ROOT}/root/sing-box-vps/protocols/anytls.env"
}

append_anytls_state_assignment() {
  local key=$1
  local value=${2-}

  printf '%s=%q\n' "${key}" "${value}" >> "${REMOTE_ROOT}/root/sing-box-vps/protocols/anytls.env"
}

awk '
  /^if ! mkdir "\$\{LOCK_DIR\}" 2>\/dev\/null; then$/ {
    exit
  }
  { print }
' "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" \
  | perl -0pe 's|/root/sing-box-vps/protocols/anytls.env|'"${REMOTE_ROOT}"'/root/sing-box-vps/protocols/anytls.env|g' \
  > "${TESTABLE_ENTRYPOINT}"

write_anytls_state \
  "${ESCAPED_DOMAIN}" \
  "${ESCAPED_PASSWORD}"
append_anytls_state_assignment 'UNRELATED_STATE_KEY' 'state value that must not leak'

cat > "${REMOTE_ROOT}/root/sing-box-vps/config.json" <<'EOF'
{
  "inbounds": [
    {
      "type": "mixed",
      "listen_port": 2080
    },
    {
      "type": "anytls",
      "listen_port": 9443,
      "users": [
        {
          "name": "anytls-user",
          "password": "config-password-should-not-be-used"
        }
      ],
      "tls": {
        "server_name": "config-domain-should-not-be-used"
      }
    }
  ]
}
EOF

cat > "${TMP_DIR}/run-anytls-generate.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

source "${TESTABLE_ENTRYPOINT}"

VERIFY_ARTIFACT_DIR="${ARTIFACT_DIR}"
VERIFY_CURRENT_SCENARIO="runtime_smoke"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/\${VERIFY_CURRENT_SCENARIO}"

verification_generate_protocol_probe_client_config \
  anytls \
  "${REMOTE_ROOT}/root/sing-box-vps/config.json"
EOF
chmod +x "${TMP_DIR}/run-anytls-generate.sh"

cat > "${TMP_DIR}/run-anytls-load-state.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

source "${TESTABLE_ENTRYPOINT}"

EXPECTED_PASSWORD=$(printf '%q' "${ESCAPED_PASSWORD}")
EXPECTED_DOMAIN=$(printf '%q' "${ESCAPED_DOMAIN}")

password=''
domain=''
unset UNRELATED_STATE_KEY || true

verification_load_anytls_probe_state \
  "${REMOTE_ROOT}/root/sing-box-vps/protocols/anytls.env" \
  password \
  domain

[[ "\${password}" == "\${EXPECTED_PASSWORD}" ]]
[[ "\${domain}" == "\${EXPECTED_DOMAIN}" ]]
[[ -z "\${UNRELATED_STATE_KEY+x}" ]]
EOF
chmod +x "${TMP_DIR}/run-anytls-load-state.sh"

if ! bash "${TMP_DIR}/run-anytls-load-state.sh" 2> "${TMP_DIR}/stderr-anytls-load-state.txt"; then
  cat "${TMP_DIR}/stderr-anytls-load-state.txt" >&2
  exit 1
fi

if ! config_path=$(bash "${TMP_DIR}/run-anytls-generate.sh" 2> "${TMP_DIR}/stderr-anytls-generate.txt"); then
  cat "${TMP_DIR}/stderr-anytls-generate.txt" >&2
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
  .outbounds[0].type == "anytls" and
  .outbounds[0].tag == "proxy" and
  .outbounds[0].server == "127.0.0.1" and
  .outbounds[0].server_port == 9443 and
  .outbounds[0].password == $password and
  .outbounds[0].tls.enabled == true and
  .outbounds[0].tls.server_name == $domain
' --arg domain "${ESCAPED_DOMAIN}" \
  --arg password "${ESCAPED_PASSWORD}" \
  "${EXPECTED_CONFIG_PATH}" >/dev/null; then
  printf 'generated anytls probe client config did not match expected fields\n' >&2
  exit 1
fi

write_anytls_state \
  "${ESCAPED_DOMAIN}" \
  ''

printf 'stale-client\n' > "${EXPECTED_CONFIG_PATH}"

if bash "${TMP_DIR}/run-anytls-generate.sh" \
  > "${TMP_DIR}/stdout-anytls-missing-password.txt" \
  2> "${TMP_DIR}/stderr-anytls-missing-password.txt"; then
  printf 'expected anytls probe client generation to fail when password is blank\n' >&2
  exit 1
fi

grep -Fq 'missing required anytls probe field: password' \
  "${TMP_DIR}/stderr-anytls-missing-password.txt"
grep -Fqx 'stale-client' "${EXPECTED_CONFIG_PATH}"

write_anytls_state \
  "${ESCAPED_DOMAIN}" \
  "${ESCAPED_PASSWORD}"

rm -rf "${ARTIFACT_DIR}"

cat > "${TMP_DIR}/run-anytls-execute.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

source "${TESTABLE_ENTRYPOINT}"

VERIFY_ARTIFACT_DIR="${ARTIFACT_DIR}"
VERIFY_CURRENT_SCENARIO="runtime_smoke"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/\${VERIFY_CURRENT_SCENARIO}"

verification_execute_single_protocol_probe \
  anytls \
  "${REMOTE_ROOT}/root/sing-box-vps/config.json"
EOF
chmod +x "${TMP_DIR}/run-anytls-execute.sh"

if ! bash "${TMP_DIR}/run-anytls-execute.sh" > "${TMP_DIR}/stdout-anytls.txt" 2> "${TMP_DIR}/stderr-anytls.txt"; then
  cat "${TMP_DIR}/stderr-anytls.txt" >&2
  exit 1
fi

[[ -f "${EXPECTED_CONFIG_PATH}" ]]
[[ -f "${EXPECTED_RESULT_PATH}" ]]
[[ -f "${EXPECTED_STDOUT_PATH}" ]]
[[ -f "${EXPECTED_CLIENT_PATH_ARTIFACT}" ]]

grep -Fqx "${EXPECTED_CONFIG_PATH}" "${EXPECTED_CLIENT_PATH_ARTIFACT}"
grep -Fqx 'PROTOCOL=anytls' "${EXPECTED_RESULT_PATH}"
grep -Fqx 'RESULT=success' "${EXPECTED_RESULT_PATH}"
grep -Fqx 'sing-box-vps-loopback-ok' "${EXPECTED_STDOUT_PATH}"

write_anytls_state \
  "${ESCAPED_DOMAIN}" \
  ''

if bash "${TMP_DIR}/run-anytls-execute.sh" \
  > "${TMP_DIR}/stdout-anytls-execute-failure.txt" \
  2> "${TMP_DIR}/stderr-anytls-execute-failure.txt"; then
  printf 'expected anytls probe execution to fail when password is blank\n' >&2
  exit 1
fi

grep -Fq 'missing required anytls probe field: password' \
  "${TMP_DIR}/stderr-anytls-execute-failure.txt"
[[ ! -f "${EXPECTED_CONFIG_PATH}" ]]
[[ ! -f "${EXPECTED_STDOUT_PATH}" ]]
[[ ! -f "${EXPECTED_CLIENT_PATH_ARTIFACT}" ]]
if [[ -f "${EXPECTED_RESULT_PATH}" ]]; then
  if grep -Fqx 'RESULT=success' "${EXPECTED_RESULT_PATH}"; then
    printf 'expected failed anytls probe execution to clear stale success result\n' >&2
    exit 1
  fi
fi
