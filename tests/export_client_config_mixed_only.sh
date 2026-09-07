#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"

perl -0pe '
  s/^\s*main "\$@"\s*$//m;
  s|readonly SB_PROJECT_DIR="/root/sing-box-vps"|readonly SB_PROJECT_DIR="'"${TMP_DIR}"'/project"|;
  s|readonly SINGBOX_BIN_PATH="/usr/local/bin/sing-box"|readonly SINGBOX_BIN_PATH="'"${TMP_DIR}"'/bin/sing-box"|;
  s|readonly SBV_BIN_PATH="/usr/local/bin/sbv"|readonly SBV_BIN_PATH="'"${TMP_DIR}"'/bin/sbv"|;
  s|readonly SINGBOX_SERVICE_FILE="/etc/systemd/system/sing-box.service"|readonly SINGBOX_SERVICE_FILE="'"${TMP_DIR}"'/sing-box.service"|;
' "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF_HOSTNAME'
#!/usr/bin/env bash
printf 'test-host\n'
EOF_HOSTNAME
chmod +x "${TMP_DIR}/bin/hostname"

cat > "${TMP_DIR}/bin/sing-box" <<'EOF_SINGBOX'
#!/usr/bin/env bash
if [[ "${1:-}" == "check" ]]; then
  exit 0
fi
exit 0
EOF_SINGBOX
chmod +x "${TMP_DIR}/bin/sing-box"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
export SB_PROJECT_DIR

mkdir -p "${SB_PROTOCOL_STATE_DIR}"
cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF_INDEX'
INSTALLED_PROTOCOLS=mixed
PROTOCOL_STATE_VERSION=1
EOF_INDEX
cat > "${SB_PROTOCOL_STATE_DIR}/mixed.env" <<'EOF_STATE'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=mixed_test-host
PORT=2080
AUTH_ENABLED=n
USERNAME=
PASSWORD=
EOF_STATE

get_public_ip() {
  printf '203.0.113.10\n'
}

state_hash_before=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env" | awk '{print $1}')
outbound_json=$(build_client_outbound_json_for_protocol mixed 203.0.113.10)
jq -e '
  .type == "socks"
  and .tag == "mixed_test-host"
  and .server == "203.0.113.10"
  and .server_port == 2080
  and .version == "5"
  and .udp_over_tcp.enabled == true
  and .udp_over_tcp.version == 2
  and (.username? == null)
  and (.password? == null)
' <<< "${outbound_json}" >/dev/null
state_hash_after=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env" | awk '{print $1}')
[[ "${state_hash_after}" == "${state_hash_before}" ]]

EXPORT_STDOUT="${TMP_DIR}/export.stdout"
EXPORT_STDERR="${TMP_DIR}/export.stderr"
export_singbox_client_config >"${EXPORT_STDOUT}" 2>"${EXPORT_STDERR}"
EXPORT_PATH="${SB_PROJECT_DIR}/client/sing-box-client.json"
[[ -f "${EXPORT_PATH}" ]]
[[ "$(stat -c '%a' "${EXPORT_PATH}")" == 600 ]]
jq -e '
  any(.outbounds[]?;
    .type == "socks"
    and .tag == "mixed_test-host"
    and .server == "203.0.113.10"
    and .server_port == 2080
    and .version == "5"
    and .udp_over_tcp.enabled == true
    and .udp_over_tcp.version == 2
    and (.username? == null)
    and (.password? == null))
' "${EXPORT_PATH}" >/dev/null
if ! grep -Fq '明文 SOCKS5' "${EXPORT_STDOUT}" "${EXPORT_STDERR}"; then
  printf 'expected interactive export to warn about plaintext Mixed transport\n' >&2
  exit 1
fi

agent_json=$(agent_cli export-client --json)
jq -e '
  .ok == true
  and .path == (env.SB_PROJECT_DIR + "/client/sing-box-client.json")
  and any(.config.outbounds[]?; .type == "socks" and .tag == "mixed_test-host" and .server_port == 2080)
  and any(.warnings[]?; .code == "mixed_plaintext_transport")
  and all(.warnings[]?; .code != "socks_plaintext_transport")
' <<< "${agent_json}" >/dev/null

printf 'mixed-only client export checks passed\n'
