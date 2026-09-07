#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"

sed \
  -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  -e "s|readonly SINGBOX_BIN_PATH=\"/usr/local/bin/sing-box\"|readonly SINGBOX_BIN_PATH=\"${TMP_DIR}/bin/sing-box\"|" \
  -e "s|readonly SINGBOX_SERVICE_FILE=\"/etc/systemd/system/sing-box.service\"|readonly SINGBOX_SERVICE_FILE=\"${TMP_DIR}/sing-box.service\"|" \
  -e 's|main \"\$@\"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project/protocols" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

get_os_info() { :; }
get_arch() { ARCH="amd64"; }
install_dependencies() { :; }
get_latest_version() { :; }
install_binary() { :; }
generate_config() { :; }
check_config_valid() { :; }
setup_service() { :; }
open_firewall_port() { :; }
display_status_summary() { :; }
show_post_config_connection_info() { :; }
systemctl() { :; }
check_port_conflict() { :; }
validate_tls_domain_points_to_server() { return 0; }
save_warp_route_settings() { :; }

cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "::",
      "listen_port": 1080,
      "users": [
        {
          "username": "legacy-user",
          "password": "legacy-pass"
        }
      ]
    }
  ],
  "route": {
    "rules": []
  }
}
EOF

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=mixed
PROTOCOL_STATE_VERSION=1
EOF

cp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/config.before"
cp "${SB_PROTOCOL_INDEX_FILE}" "${TMP_DIR}/index.before"

# Enumeration must preserve an incomplete index rather than erase it to
# trigger recovery. Migration is allowed only by the explicit write workflow.
if list_installed_protocols > "${TMP_DIR}/list.stdout" 2> "${TMP_DIR}/list.stderr"; then
  printf 'expected ordinary enumeration to reject incomplete state\n' >&2
  exit 1
fi
cmp "${SB_PROTOCOL_INDEX_FILE}" "${TMP_DIR}/index.before"
[[ ! -s "${TMP_DIR}/list.stdout" && ! -f "${SB_PROTOCOL_STATE_DIR}/mixed.env" ]]

# Partial recovery must restore the still-present index on state-write failure.
if (
  save_mixed_state() { return 37; }
  migrate_legacy_single_protocol_state_if_needed recover-incomplete-index
) > "${TMP_DIR}/failure.stdout" 2> "${TMP_DIR}/failure.stderr"; then
  printf 'expected legacy recovery to propagate state-write failure\n' >&2
  exit 1
fi
cmp "${SB_PROTOCOL_INDEX_FILE}" "${TMP_DIR}/index.before"
[[ ! -f "${SB_PROTOCOL_STATE_DIR}/mixed.env" ]]

# A different tag, listener, extra user or unrecognized option is not the
# legacy shape. Leave it for explicit takeover rather than discard fields.
for mutation in '.inbounds[0].tag="custom-mixed"' \
  '.inbounds[0].listen="127.0.0.1"' \
  '.inbounds[0].users += [{"username":"second","password":"second-pass"}]' \
  '.inbounds[0].set_system_proxy=true'; do
  jq "${mutation}" "${TMP_DIR}/config.before" > "${SINGBOX_CONFIG_FILE}"
  migrate_legacy_single_protocol_state_if_needed recover-incomplete-index
  cmp "${SB_PROTOCOL_INDEX_FILE}" "${TMP_DIR}/index.before"
  [[ ! -f "${SB_PROTOCOL_STATE_DIR}/mixed.env" ]]
done
cp "${TMP_DIR}/config.before" "${SINGBOX_CONFIG_FILE}"

# An omitted listen uses sing-box's verified loopback default, not the
# machine's public stack bind.  It therefore takes the typed recovery path
# and must publish the explicit loopback address rather than schema-1 state.
jq 'del(.inbounds[0].listen)' "${TMP_DIR}/config.before" > "${SINGBOX_CONFIG_FILE}"
rebuild_protocol_state_from_config
grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "${SB_PROTOCOL_STATE_DIR}/mixed.env"
mixed_store_file=$(mixed_structured_store_file)
jq -e '.instances | length == 1 and .[0].listen.address == "127.0.0.1" and .[0].listen.port == 1080' \
  "${mixed_store_file}" >/dev/null

# Restore the incomplete-index fixture for the existing additional-install
# recovery assertions below.
rm -f -- "${mixed_store_file}" "${SB_PROTOCOL_STATE_DIR}/mixed.env"
if [[ -d "${SB_PROTOCOL_STATE_DIR}/instances" ]]; then
  rmdir -- "${SB_PROTOCOL_STATE_DIR}/instances"
fi
cp "${TMP_DIR}/index.before" "${SB_PROTOCOL_INDEX_FILE}"
cp "${TMP_DIR}/config.before" "${SINGBOX_CONFIG_FILE}"
# The typed omitted-listen probe may have inferred a different stack mode in
# process memory; let the explicit legacy fixture re-infer its :: bind.
SB_INBOUND_STACK_MODE=""
SB_OUTBOUND_STACK_MODE=""

install_protocols_interactive "additional" <<'EOF'
3
hy2.example.com
8443
hy2-pass
hy2-user
100
50
n
2
/etc/ssl/certs/hy2.pem
/etc/ssl/private/hy2.key

EOF

cmp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/config.before"

if [[ ! -f "${SB_PROTOCOL_STATE_DIR}/mixed.env" ]]; then
  printf 'expected mixed protocol state file to be recreated from legacy config\n' >&2
  exit 1
fi

if ! grep -Fq 'AUTH_ENABLED=y' "${SB_PROTOCOL_STATE_DIR}/mixed.env"; then
  printf 'expected mixed state to preserve auth enabled flag, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/mixed.env")" >&2
  exit 1
fi

if ! grep -Fq 'USERNAME=legacy-user' "${SB_PROTOCOL_STATE_DIR}/mixed.env"; then
  printf 'expected mixed state to preserve username, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/mixed.env")" >&2
  exit 1
fi

if ! grep -Fqx 'PASSWORD=legacy-pass' "${SB_PROTOCOL_STATE_DIR}/mixed.env"; then
  printf 'expected legacy Mixed credentials to survive recovery\n' >&2
  exit 1
fi

if ! grep -Fq 'INSTALLED_PROTOCOLS=mixed,hy2' "${SB_PROTOCOL_INDEX_FILE}"; then
  printf 'expected protocol index to keep mixed and add hy2, got:\n%s\n' "$(cat "${SB_PROTOCOL_INDEX_FILE}")" >&2
  exit 1
fi
