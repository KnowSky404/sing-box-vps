#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
source "$TESTS_DIR/menu_test_helper.sh"
setup_menu_test_env 120
# Source at file scope so Bash 4.2 keeps readonly registry arrays alive.
source "${TESTABLE_INSTALL}"
trap 'printf "mixed structured takeover failed at line %s\n" "$LINENO" >&2' ERR

mkdir -p "$SB_PROTOCOL_STATE_DIR"
cat > "$SB_PROTOCOL_INDEX_FILE" <<'EOF'
INSTALLED_PROTOCOLS=mixed
PROTOCOL_STATE_VERSION=1
EOF
legacy_name=$'legacy-singleton-name\n'
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=1\nNODE_NAME=%q\nPORT=1080\nAUTH_ENABLED=y\nUSERNAME=legacy-user\nPASSWORD=legacy-password\n' \
  "$legacy_name" > "$SB_PROTOCOL_STATE_DIR/mixed.env"
cat > "$SINGBOX_CONFIG_FILE" <<'EOF'
{
  "inbounds": [
    {"type":"mixed","tag":"legacy.custom","listen_port":1089,
     "users":[{"username":"legacy-user\n","password":"legacy-password\n"}]}
  ],
  "route":{"rules":[{"inbound":"legacy.custom","action":"route","outbound":"direct"}]}
}
EOF

mixed_config_store_candidate > "$TMP_DIR/legacy-candidate.json"
jq -e --arg name "$legacy_name" '
  .revision == 1 and .default_instance_id == "main" and
  ([.instances[]] | length) == 1 and .instances[0].id == "main" and
  .instances[0].name == $name and .instances[0].tag == "legacy.custom" and
  .instances[0].listen.address == "127.0.0.1" and .instances[0].listen.port == 1089 and
  .instances[0].authentication.username == "legacy-user\n" and
  .instances[0].authentication.password == "legacy-password\n" and
  .instances[0].outbound_policy == "direct"
' "$TMP_DIR/legacy-candidate.json" >/dev/null
rebuild_protocol_state_from_config
store_file=$(mixed_structured_store_file)
jq -e --arg name "$legacy_name" '
  .instances[0].id == "main" and .instances[0].name == $name and
  .instances[0].authentication.username == "legacy-user\n" and
  .instances[0].authentication.password == "legacy-password\n" and
  .instances[0].outbound_policy == "direct"
' "$store_file" >/dev/null
mixed_structured_state_active

# The verified sing-box default for omitted Mixed listen is loopback, never
# the current public stack bind.  An omitted port is ephemeral and must fail
# closed without touching the already committed state.
jq -e '.instances[0].listen.address == "127.0.0.1"' "$store_file" >/dev/null
state_hash=$(sha256sum "$SB_PROTOCOL_STATE_DIR/mixed.env")
store_hash=$(sha256sum "$store_file")
jq 'del(.inbounds[0].listen_port)' "$SINGBOX_CONFIG_FILE" > "$TMP_DIR/missing-port.json"
mv "$TMP_DIR/missing-port.json" "$SINGBOX_CONFIG_FILE"
if rebuild_protocol_state_from_config > "$TMP_DIR/missing-port.stdout" 2> "$TMP_DIR/missing-port.stderr"; then
  printf 'expected omitted Mixed listen_port takeover to fail\n' >&2
  exit 1
fi
[[ "$(sha256sum "$SB_PROTOCOL_STATE_DIR/mixed.env")" == "$state_hash" ]]
[[ "$(sha256sum "$store_file")" == "$store_hash" ]]
jq '.inbounds[0].listen_port = 1089' "$SINGBOX_CONFIG_FILE" > "$TMP_DIR/restored-port.json"
mv "$TMP_DIR/restored-port.json" "$SINGBOX_CONFIG_FILE"

# A representable legacy singleton stays schema 1, but its live credentials
# must still survive exact byte-for-byte extraction.
rm -f -- "$store_file"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=1\nNODE_NAME=%q\nPORT=1080\nAUTH_ENABLED=y\nUSERNAME=legacy-user\nPASSWORD=legacy-password\n' \
  "$legacy_name" > "$SB_PROTOCOL_STATE_DIR/mixed.env"
cat > "$SINGBOX_CONFIG_FILE" <<'EOF'
{
  "inbounds": [
    {"type":"mixed","tag":"mixed-in","listen":"0.0.0.0","listen_port":1080,
     "users":[{"username":"legacy-user\n","password":"legacy-password\n"}]}
  ]
}
EOF
SB_INBOUND_STACK_MODE=ipv4_only
rebuild_protocol_state_from_config
grep -Fqx 'CONFIG_SCHEMA_VERSION=1' "$SB_PROTOCOL_STATE_DIR/mixed.env"
unset NODE_NAME USERNAME PASSWORD
source "$SB_PROTOCOL_STATE_DIR/mixed.env"
[[ "${NODE_NAME}" == "$legacy_name" ]]
[[ "${USERNAME}" == $'legacy-user\n' && "${PASSWORD}" == $'legacy-password\n' ]]

# Continue with a clean legacy fixture for the multi-instance takeover path.
rm -f -- "$store_file"
cat > "$SB_PROTOCOL_STATE_DIR/mixed.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=legacy-singleton-name
PORT=1080
AUTH_ENABLED=y
USERNAME=legacy-user
PASSWORD=legacy-password
EOF
cat > "$SINGBOX_CONFIG_FILE" <<'EOF'
{
  "inbounds": [
    {"type":"mixed","tag":"alpha","listen":"127.0.0.1","listen_port":1080,
     "users":[{"username":"alpha-user","password":"alpha-password"}]},
    {"type":"mixed","tag":"edge.tag","listen":"::1","listen_port":1081,
     "set_system_proxy":false}
  ],
  "route":{"rules":[{"inbound":"alpha","action":"route","outbound":"direct"}]}
}
EOF

mixed_config_store_candidate > "$TMP_DIR/candidate.json"
validate_structured_instance_store mixed "$TMP_DIR/candidate.json"
jq -e '
  .revision == 1 and .default_instance_id == "alpha" and
  ([.instances[].tag] | sort) == ["alpha","edge.tag"] and
  ([.instances[] | select(.tag == "alpha")][0] |
    .id == "alpha" and .name == "alpha" and .listen.address == "127.0.0.1" and
    .listen.port == 1080 and .authentication.enabled and
    .authentication.username == "alpha-user" and
    .authentication.password == "alpha-password" and .outbound_policy == "direct") and
  ([.instances[] | select(.tag == "edge.tag")][0] |
    .authentication.enabled == false and .authentication.username == "" and
    .authentication.password == "" and .outbound_policy == "default")
' "$TMP_DIR/candidate.json" >/dev/null

rebuild_protocol_state_from_config
mixed_structured_state_active
store_file=$(mixed_structured_store_file)
jq -e '
  .schema_version == 1 and .revision == 1 and .default_instance_id == "alpha" and
  ([.instances[].tag] | sort) == ["alpha","edge.tag"] and
  ([.instances[] | select(.tag == "alpha")][0].authentication.password == "alpha-password") and
  ([.instances[] | select(.tag == "edge.tag")][0].authentication.enabled == false) and
  ([.instances[] | select(.tag == "alpha")][0].outbound_policy == "direct")
' "$store_file" >/dev/null
grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "$SB_PROTOCOL_STATE_DIR/mixed.env"
grep -Fqx 'INSTALLED_PROTOCOLS=mixed' "$SB_PROTOCOL_INDEX_FILE"
mixed_structured_state_matches_config
mixed_validate_state_inventory
protocol_state_matches_config mixed
agent_validate_indexed_protocol_states mixed

# Reordering inbounds must not alter identity, name, default, or revision.
jq '.inbounds |= reverse' "$SINGBOX_CONFIG_FILE" > "$TMP_DIR/reordered.json"
mv "$TMP_DIR/reordered.json" "$SINGBOX_CONFIG_FILE"
mixed_config_store_candidate > "$TMP_DIR/reordered-candidate.json"
jq -e '.revision == 1 and .default_instance_id == "alpha" and
  ([.instances[] | select(.tag == "alpha")][0].id == "alpha") and
  ([.instances[] | select(.tag == "edge.tag")][0].id | startswith("mixed-"))' \
  "$TMP_DIR/reordered-candidate.json" >/dev/null
jq '.inbounds |= reverse' "$SINGBOX_CONFIG_FILE" > "$TMP_DIR/order-restored.json"
mv "$TMP_DIR/order-restored.json" "$SINGBOX_CONFIG_FILE"

# Matching must cover every owned inbound.
jq '(.inbounds[1].listen_port) = 1091' "$SINGBOX_CONFIG_FILE" > "$TMP_DIR/drifted.json"
mv "$TMP_DIR/drifted.json" "$SINGBOX_CONFIG_FILE"
if mixed_structured_state_matches_config; then
  printf 'expected second Mixed listener drift to fail health check\n' >&2
  exit 1
fi
jq '.inbounds[1].listen_port = 1081' "$SINGBOX_CONFIG_FILE" > "$TMP_DIR/restored.json"
mv "$TMP_DIR/restored.json" "$SINGBOX_CONFIG_FILE"

# Lossy fields fail closed and restore all pre-existing state.
state_hash=$(sha256sum "$SB_PROTOCOL_STATE_DIR/mixed.env")
store_hash=$(sha256sum "$store_file")
jq '.inbounds[0].tls = {"enabled":true}' "$SINGBOX_CONFIG_FILE" > "$TMP_DIR/lossy.json"
mv "$TMP_DIR/lossy.json" "$SINGBOX_CONFIG_FILE"
if rebuild_protocol_state_from_config > "$TMP_DIR/lossy.stdout" 2> "$TMP_DIR/lossy.stderr"; then
  printf 'expected lossy Mixed takeover to fail\n' >&2
  exit 1
fi
[[ "$(sha256sum "$SB_PROTOCOL_STATE_DIR/mixed.env")" == "$state_hash" ]]
[[ "$(sha256sum "$store_file")" == "$store_hash" ]]
if grep -Eq 'alpha-password|legacy-password' "$TMP_DIR/lossy.stderr"; then
  printf 'takeover diagnostic leaked a credential\n' >&2
  exit 1
fi

# A pending public instance transaction owns the recovery snapshot; takeover
# must not clear or replace its state while that lock is present.
rm -f -- "$SINGBOX_CONFIG_FILE"
cat > "$SINGBOX_CONFIG_FILE" <<'EOF'
{"inbounds":[]}
EOF
printf '%s\n' pending > "$SB_PROJECT_DIR.instance-write.lock"
if rebuild_protocol_state_from_config > "$TMP_DIR/pending.stdout" 2> "$TMP_DIR/pending.stderr"; then
  printf 'expected pending instance transaction to block takeover\n' >&2
  exit 1
fi
rm -f -- "$SB_PROJECT_DIR.instance-write.lock"
grep -Fq 'instance_transaction_pending' "$TMP_DIR/pending.stderr"

printf 'mixed structured takeover checks passed\n'
