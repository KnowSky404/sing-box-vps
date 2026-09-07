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
export SINGBOX_CONFIG_FILE SB_PROJECT_DIR
get_public_ip() {
  printf '203.0.113.10\n'
}

mkdir -p "${SB_PROTOCOL_STATE_DIR}"
cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF_INDEX'
INSTALLED_PROTOCOLS=mixed
PROTOCOL_STATE_VERSION=1
EOF_INDEX

write_mixed_state() {
  local auth_enabled=$1
  local port=$2
  local username=$3
  local password=$4

  {
    printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=1\nNODE_NAME=mixed_auth-host\n'
    printf 'PORT=%q\n' "${port}"
    printf 'AUTH_ENABLED=%q\nUSERNAME=%q\nPASSWORD=%q\n' \
      "${auth_enabled}" "${username}" "${password}"
  } > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
}

assert_mixed_outbound() {
  local output=$1
  local expected_username=${2:-}
  local expected_password=${3:-}

  jq -e \
    --arg username "${expected_username}" \
    --arg password "${expected_password}" '
      .type == "socks"
      and .tag == "mixed_auth-host"
      and .server == "203.0.113.10"
      and .server_port == 2080
      and .version == "5"
      and .udp_over_tcp.enabled == true
      and .udp_over_tcp.version == 2
      and (if ($username | length) > 0 then (.username == $username and .password == $password)
           else (.username? == null and .password? == null) end)
    ' <<< "${output}" >/dev/null
}

USERNAME='u$();|&'
PASSWORD='密码 😀 $();|&'
write_mixed_state y 2080 "${USERNAME}" "${PASSWORD}"
state_hash_before=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env" | awk '{print $1}')

# Export must use the persisted credentials verbatim and must not generate or
# rewrite credentials as a side effect of the read-only instance adapter.
AUTH_GENERATION_MARKER="${TMP_DIR}/mixed-auth-generation-called"
original_ensure_mixed_auth_credentials=$(declare -f ensure_mixed_auth_credentials)
ensure_mixed_auth_credentials() {
  : > "${AUTH_GENERATION_MARKER}"
  return 97
}
auth_outbound=$(build_client_outbound_json_for_protocol mixed 203.0.113.10)
eval "${original_ensure_mixed_auth_credentials}"
assert_mixed_outbound "${auth_outbound}" "${USERNAME}" "${PASSWORD}"
[[ ! -e "${AUTH_GENERATION_MARKER}" ]]
state_hash_after=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env" | awk '{print $1}')
[[ "${state_hash_after}" == "${state_hash_before}" ]]

valid_255_username=$(printf 'u%.0s' {1..255})
valid_255_password=$(printf 'p%.0s' {1..255})
write_mixed_state y 2080 "${valid_255_username}" "${valid_255_password}"
boundary_outbound=$(build_client_outbound_json_for_protocol mixed 203.0.113.10)
assert_mixed_outbound "${boundary_outbound}" "${valid_255_username}" "${valid_255_password}"

# Unauthenticated Mixed is a valid SOCKS5 export, but must not carry stale
# persisted credentials or acquire them from loader defaults.
write_mixed_state n 2080 stale-user stale-password
SB_MIXED_AUTH_ENABLED=y
SB_MIXED_USERNAME=stale-global-user
SB_MIXED_PASSWORD=stale-global-password
unauth_outbound=$(build_client_outbound_json_for_protocol mixed 203.0.113.10)
assert_mixed_outbound "${unauth_outbound}"

assert_invalid_mixed_state() {
  local description=$1
  shift
  write_mixed_state "$@"
  local output=''
  if output=$(build_client_outbound_json_for_protocol mixed 203.0.113.10 2>"${TMP_DIR}/invalid-mixed.stderr"); then
    printf 'expected invalid Mixed state to be rejected (%s), output=%s\n' "${description}" "${output}" >&2
    exit 1
  fi
  [[ -z "${output}" ]]
  for credential in "${3:-}" "${4:-}"; do
    [[ -n "${credential}" ]] || continue
    if grep -Fq -- "${credential}" "${TMP_DIR}/invalid-mixed.stderr"; then
      printf 'invalid Mixed state leaked a credential to stderr (%s)\n' "${description}" >&2
      exit 1
    fi
  done
}

assert_invalid_mixed_state 'missing auth flag' '' 2080 '' ''
assert_invalid_mixed_state 'invalid auth flag' maybe 2080 '' ''
assert_invalid_mixed_state 'missing port' y '' "${USERNAME}" "${PASSWORD}"
assert_invalid_mixed_state 'zero port' y 0 "${USERNAME}" "${PASSWORD}"
assert_invalid_mixed_state 'port above range' y 65536 "${USERNAME}" "${PASSWORD}"
assert_invalid_mixed_state 'auth username missing' y 2080 '' "${PASSWORD}"
assert_invalid_mixed_state 'auth password missing' y 2080 "${USERNAME}" ''
overflow=$(printf 'x%.0s' {1..256})
assert_invalid_mixed_state 'username over 255 UTF-8 bytes' y 2080 "${overflow}" "${PASSWORD}"
assert_invalid_mixed_state 'password over 255 bytes' y 2080 "${USERNAME}" "${overflow}"
unicode_overflow=$(printf 'é%.0s' {1..128})
assert_invalid_mixed_state 'username over 255 UTF-8 bytes (multibyte)' y 2080 "${unicode_overflow}" "${PASSWORD}"
assert_invalid_mixed_state 'password over 255 UTF-8 bytes (multibyte)' y 2080 "${USERNAME}" "${unicode_overflow}"

# Missing raw keys must not fall back to stale process globals or loader
# defaults, and any rejected credential must stay out of diagnostics.
stale_secret='stale-secret-must-not-leak'
SB_MIXED_AUTH_ENABLED=y
SB_MIXED_USERNAME=stale-user
SB_MIXED_PASSWORD="${stale_secret}"
cat > "${SB_PROTOCOL_STATE_DIR}/mixed.env" <<'EOF_ABSENT'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=mixed_auth-host
PORT=2080
EOF_ABSENT
absent_output=''
if absent_output=$(build_client_outbound_json_for_protocol mixed 203.0.113.10 2>"${TMP_DIR}/invalid-mixed.stderr"); then
  printf 'expected absent Mixed auth keys to be rejected, output=%s\n' "${absent_output}" >&2
  exit 1
fi
[[ -z "${absent_output}" ]]
if grep -Fq -- "${stale_secret}" "${TMP_DIR}/invalid-mixed.stderr"; then
  printf 'absent Mixed credentials leaked stale password to stderr\n' >&2
  exit 1
fi

# A state replacement after loading cannot validate a different snapshot and
# accidentally authorize the default port from an incomplete old snapshot.
write_mixed_state y 2080 snapshot-user snapshot-password
sed -i '/^PORT=/d' "${SB_PROTOCOL_STATE_DIR}/mixed.env"
eval "$(declare -f load_protocol_instance_state | sed '1s/load_protocol_instance_state/load_protocol_instance_state_before_snapshot_test/')"
load_protocol_instance_state() {
  load_protocol_instance_state_before_snapshot_test "$@" || return $?
  if [[ "$1" == mixed ]]; then
    write_mixed_state y 2081 replacement-user replacement-password
  fi
}
if build_client_outbound_json_for_protocol mixed 203.0.113.10 >"${TMP_DIR}/snapshot.stdout" 2>"${TMP_DIR}/snapshot.stderr"; then
  printf 'expected missing port in loaded snapshot to remain rejected after file replacement\n' >&2
  exit 1
fi
[[ ! -s "${TMP_DIR}/snapshot.stdout" ]]
eval "$(declare -f load_protocol_instance_state_before_snapshot_test | sed '1s/load_protocol_instance_state_before_snapshot_test/load_protocol_instance_state/')"
unset -f load_protocol_instance_state_before_snapshot_test

# A failed Mixed export is fail-closed: no partial stdout and no replacement
# of an existing export or its backup. Agent output remains an error envelope.
write_mixed_state y 2080 "${USERNAME}" "${PASSWORD}"
export_singbox_client_config >/dev/null 2>"${TMP_DIR}/initial-export.err"
EXPORT_PATH="${SB_PROJECT_DIR}/client/sing-box-client.json"
cp "${EXPORT_PATH}" "${TMP_DIR}/export.before"
printf '%s\n' '{"keep":"mixed-backup"}' > "${EXPORT_PATH}.bak"
cp "${EXPORT_PATH}.bak" "${TMP_DIR}/backup.before"

write_mixed_state y 2080 "${USERNAME}" ''
if export_singbox_client_config >"${TMP_DIR}/failed.stdout" 2>"${TMP_DIR}/failed.stderr"; then
  printf 'expected invalid Mixed export to fail\n' >&2
  exit 1
fi
[[ ! -s "${TMP_DIR}/failed.stdout" ]]
cmp "${TMP_DIR}/export.before" "${EXPORT_PATH}"
cmp "${TMP_DIR}/backup.before" "${EXPORT_PATH}.bak"

if agent_cli export-client --json >"${TMP_DIR}/agent-failed.json" 2>"${TMP_DIR}/agent-failed.stderr"; then
  printf 'expected Agent Mixed export to fail for missing password\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "client_config_generation_failed" and (.data | type == "object")' \
  "${TMP_DIR}/agent-failed.json" >/dev/null
cmp "${TMP_DIR}/export.before" "${EXPORT_PATH}"
cmp "${TMP_DIR}/backup.before" "${EXPORT_PATH}.bak"

# Exercise the dispatcher directly in this shell: the outer export wrapper's
# command substitution would otherwise hide a failed runtime-state restoration.
cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF_VLESS'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=vless_restore-host
PORT=443
UUID=11111111-1111-1111-1111-111111111111
SNI=www.cloudflare.com
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
EOF_VLESS
printf 'INSTALLED_PROTOCOLS=vless-reality,mixed\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
load_protocol_instance_state vless-reality main
original_protocol=${SB_PROTOCOL}
original_node=${SB_NODE_NAME}
original_port=${SB_PORT}
write_mixed_state y 2080 mixed-failure-user ''
if build_client_outbound_json_for_protocol mixed 203.0.113.10 >"${TMP_DIR}/cross-failed.stdout" 2>"${TMP_DIR}/cross-failed.stderr"; then
  printf 'expected cross-protocol export to fail for invalid Mixed state\n' >&2
  exit 1
fi
[[ ! -s "${TMP_DIR}/cross-failed.stdout" ]]
[[ "${SB_PROTOCOL}" == "${original_protocol}" ]]
[[ "${SB_NODE_NAME}" == "${original_node}" ]]
[[ "${SB_PORT}" == "${original_port}" ]]
[[ "${SB_INSTANCE_ID}" == main && "${SB_UUID}" == 11111111-1111-1111-1111-111111111111 ]]
[[ -z "${SB_MIXED_USERNAME}" && -z "${SB_MIXED_PASSWORD}" ]]

printf 'mixed authenticated and fail-closed export checks passed\n'
