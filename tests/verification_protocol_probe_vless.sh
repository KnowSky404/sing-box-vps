#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

ARTIFACT_DIR="${TMP_DIR}/artifacts"
REMOTE_ROOT="${TMP_DIR}/remote-root"
TESTABLE_ENTRYPOINT="${TMP_DIR}/entrypoint-testable.sh"
EXPECTED_CONFIG_PATH="${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/vless-reality/client.json"

mkdir -p "${REMOTE_ROOT}/root/sing-box-vps/protocols"

awk '
  /^if ! mkdir "\$\{LOCK_DIR\}" 2>\/dev\/null; then$/ {
    exit
  }
  { print }
' "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" \
  | perl -0pe 's|/root/sing-box-vps/protocols/vless-reality.env|'"${REMOTE_ROOT}"'/root/sing-box-vps/protocols/vless-reality.env|g' \
  > "${TESTABLE_ENTRYPOINT}"

cat > "${REMOTE_ROOT}/root/sing-box-vps/protocols/vless-reality.env" <<'EOF'
REALITY_PUBLIC_KEY=public-key-from-state
EOF

cat > "${REMOTE_ROOT}/root/sing-box-vps/config.json" <<'EOF'
{
  "inbounds": [
    {
      "type": "mixed",
      "listen_port": 2080,
      "users": [
        {
          "username": "mixed-user",
          "password": "mixed-pass"
        }
      ]
    },
    {
      "type": "vless",
      "listen_port": 443,
      "users": [
        {
          "uuid": "11111111-1111-4111-8111-111111111111",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "server_name": "www.cloudflare.com",
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

cat > "${TMP_DIR}/run-vless.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

source "${TESTABLE_ENTRYPOINT}"

VERIFY_ARTIFACT_DIR="${ARTIFACT_DIR}"
VERIFY_CURRENT_SCENARIO="runtime_smoke"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/\${VERIFY_CURRENT_SCENARIO}"

verification_generate_protocol_probe_client_config \
  vless-reality \
  "${REMOTE_ROOT}/root/sing-box-vps/config.json"
EOF
chmod +x "${TMP_DIR}/run-vless.sh"

if ! config_path=$(bash "${TMP_DIR}/run-vless.sh" 2> "${TMP_DIR}/stderr-vless.txt"); then
  cat "${TMP_DIR}/stderr-vless.txt" >&2
  exit 1
fi

[[ "${config_path}" == "${EXPECTED_CONFIG_PATH}" ]]
[[ -f "${config_path}" ]]

if ! jq -e '
  .log.disabled == true and
  (.inbounds | length == 1) and
  .inbounds[0].type == "socks" and
  .inbounds[0].tag == "local-socks" and
  .inbounds[0].listen == "127.0.0.1" and
  .inbounds[0].listen_port == 19080 and
  (.outbounds | length == 1) and
  .outbounds[0].type == "vless" and
  .outbounds[0].tag == "proxy" and
  .outbounds[0].server == "127.0.0.1" and
  .outbounds[0].server_port == 443 and
  .outbounds[0].uuid == "11111111-1111-4111-8111-111111111111" and
  .outbounds[0].flow == "xtls-rprx-vision" and
  .outbounds[0].tls.enabled == true and
  .outbounds[0].tls.server_name == "www.cloudflare.com" and
  .outbounds[0].tls.reality.enabled == true and
  .outbounds[0].tls.reality.public_key == "public-key-from-state" and
  .outbounds[0].tls.reality.short_id == "abcd1234"
' "${config_path}" >/dev/null; then
  printf 'generated vless probe client config did not match expected fields\n' >&2
  exit 1
fi

cat > "${TMP_DIR}/run-blank-public-key.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

cat > "${REMOTE_ROOT}/root/sing-box-vps/protocols/vless-reality.env" <<'STATE_EOF'
REALITY_PUBLIC_KEY=
STATE_EOF

source "${TESTABLE_ENTRYPOINT}"

VERIFY_ARTIFACT_DIR="${ARTIFACT_DIR}"
VERIFY_CURRENT_SCENARIO="runtime_smoke"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/\${VERIFY_CURRENT_SCENARIO}"

verification_generate_protocol_probe_client_config \
  vless-reality \
  "${REMOTE_ROOT}/root/sing-box-vps/config.json"
EOF
chmod +x "${TMP_DIR}/run-blank-public-key.sh"

if bash "${TMP_DIR}/run-blank-public-key.sh" > "${TMP_DIR}/stdout-blank-public-key.txt" 2> "${TMP_DIR}/stderr-blank-public-key.txt"; then
  printf 'expected blank REALITY_PUBLIC_KEY to fail probe client generation\n' >&2
  exit 1
fi

grep -Fq 'missing REALITY_PUBLIC_KEY for protocol generator: vless-reality' \
  "${TMP_DIR}/stderr-blank-public-key.txt"

cat > "${TMP_DIR}/run-missing-public-key.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

cat > "${REMOTE_ROOT}/root/sing-box-vps/protocols/vless-reality.env" <<'STATE_EOF'
UUID=unused
STATE_EOF

source "${TESTABLE_ENTRYPOINT}"

VERIFY_ARTIFACT_DIR="${ARTIFACT_DIR}"
VERIFY_CURRENT_SCENARIO="runtime_smoke"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/\${VERIFY_CURRENT_SCENARIO}"

verification_generate_protocol_probe_client_config \
  vless-reality \
  "${REMOTE_ROOT}/root/sing-box-vps/config.json"
EOF
chmod +x "${TMP_DIR}/run-missing-public-key.sh"

if bash "${TMP_DIR}/run-missing-public-key.sh" > "${TMP_DIR}/stdout-missing-public-key.txt" 2> "${TMP_DIR}/stderr-missing-public-key.txt"; then
  printf 'expected missing REALITY_PUBLIC_KEY to fail probe client generation\n' >&2
  exit 1
fi

grep -Fq 'missing REALITY_PUBLIC_KEY for protocol generator: vless-reality' \
  "${TMP_DIR}/stderr-missing-public-key.txt"

cat > "${TMP_DIR}/run-unsupported.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

source "${TESTABLE_ENTRYPOINT}"

VERIFY_ARTIFACT_DIR="${ARTIFACT_DIR}"
VERIFY_CURRENT_SCENARIO="runtime_smoke"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/\${VERIFY_CURRENT_SCENARIO}"

verification_generate_protocol_probe_client_config \
  mystery-protocol \
  "${REMOTE_ROOT}/root/sing-box-vps/config.json"
EOF
chmod +x "${TMP_DIR}/run-unsupported.sh"

if bash "${TMP_DIR}/run-unsupported.sh" > "${TMP_DIR}/stdout-unsupported.txt" 2> "${TMP_DIR}/stderr-unsupported.txt"; then
  printf 'expected unsupported protocol probe generator to fail\n' >&2
  exit 1
fi

grep -Fq 'unsupported protocol generator: mystery-protocol' "${TMP_DIR}/stderr-unsupported.txt"
