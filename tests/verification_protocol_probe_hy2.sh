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

mkdir -p "${REMOTE_ROOT}/root/sing-box-vps/protocols"

awk '
  /^if ! mkdir "\$\{LOCK_DIR\}" 2>\/dev\/null; then$/ {
    exit
  }
  { print }
' "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" \
  | perl -0pe 's|/root/sing-box-vps/protocols/hy2.env|'"${REMOTE_ROOT}"'/root/sing-box-vps/protocols/hy2.env|g' \
  > "${TESTABLE_ENTRYPOINT}"

cat > "${REMOTE_ROOT}/root/sing-box-vps/protocols/hy2.env" <<'EOF'
DOMAIN=hy2.example.com
PASSWORD=hy2-password-from-state
OBFS_PASSWORD=obfs-password-from-state
EOF

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
  .outbounds[0].password == "hy2-password-from-state" and
  .outbounds[0].tls.enabled == true and
  .outbounds[0].tls.server_name == "hy2.example.com" and
  .outbounds[0].obfs.type == "salamander" and
  .outbounds[0].obfs.password == "obfs-password-from-state"
' "${EXPECTED_CONFIG_PATH}" >/dev/null; then
  printf 'generated hy2 probe client config did not match expected fields\n' >&2
  exit 1
fi

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
