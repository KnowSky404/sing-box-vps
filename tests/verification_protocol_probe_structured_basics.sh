#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# shellcheck disable=SC1091
source "${REPO_ROOT}/dev/verification/remote/scenarios/protocol_cases.sh"

PROTOCOLS_DIR="${TMP_DIR}/project/protocols"
mkdir -p "${PROTOCOLS_DIR}/instances"
cert_path="${TMP_DIR}/cert.pem"
key_path="${TMP_DIR}/key.pem"
openssl req -x509 -newkey ed25519 -nodes -keyout "${key_path}" \
  -out "${cert_path}" -subj /CN=sing-box-vps-verification.invalid \
  -days 1 >/dev/null 2>&1
awk '/^if ! mkdir "\$\{LOCK_DIR\}" 2>\/dev\/null; then$/ {exit} {print}' \
  "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" \
  | perl -0pe 's|/root/.sing-box-vps/runtime/protocols/|'"${PROTOCOLS_DIR}"'/|g' \
  > "${TMP_DIR}/entrypoint.sh"
cat > "${TMP_DIR}/generate.sh" <<'GENERATOR'
#!/usr/bin/env bash
set -euo pipefail
source "$1"
rm -rf -- "${VERIFY_ARTIFACT_DIR}"
VERIFY_ARTIFACT_DIR=$2
VERIFY_REMOTE_INSTALL_SCRIPT=$3
VERIFY_CURRENT_SCENARIO_DIR=scenarios/structured
verification_generate_protocol_probe_client_config "$4" "$5" >/dev/null
GENERATOR

render_config() {
  bash -s -- "${TESTABLE_INSTALL}" "$1" "${PROTOCOLS_DIR}/instances/$1.json" <<'RENDER'
set -euo pipefail
source "$1"
render_structured_instance_inbounds "$2" "$3" | jq -s '{inbounds:.}'
RENDER
}
generate_client() {
  bash "${TMP_DIR}/generate.sh" "${TMP_DIR}/entrypoint.sh" "${TMP_DIR}/artifacts" \
    "${TESTABLE_INSTALL}" "$1" "${TMP_DIR}/$1-config.json"
}

# Exercise real schema-2 fixture -> renderer -> verification generator ->
# production client exporter. Marker files intentionally have no credentials.
for protocol in mixed hy2 anytls; do
  verification_protocol_record "${protocol}" > "${TMP_DIR}/${protocol}-record.json"
  jq -n --arg protocol "${protocol}" --slurpfile records "${TMP_DIR}/${protocol}-record.json" \
    '{schema_version:1,protocol:$protocol,revision:1,default_instance_id:"main",instances:$records}' \
    > "${PROTOCOLS_DIR}/instances/${protocol}.json"
  printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "${PROTOCOLS_DIR}/${protocol}.env"
  chmod 600 "${PROTOCOLS_DIR}/instances/${protocol}.json" "${PROTOCOLS_DIR}/${protocol}.env"
  render_config "${protocol}" > "${TMP_DIR}/${protocol}-config.json"
  generate_client "${protocol}"
  client="${TMP_DIR}/artifacts/scenarios/structured/protocol-probes/${protocol}/client.json"
  jq -e --arg protocol "${protocol}" --slurpfile records "${TMP_DIR}/${protocol}-record.json" '
    (.outbounds|length)==1 and .outbounds[0].server=="127.0.0.1" and
    .outbounds[0].server_port==$records[0].listen.port and
    (if $protocol=="mixed" then
      .outbounds[0].type=="socks" and .outbounds[0].version=="5" and
      .outbounds[0].username==$records[0].authentication.username and
      .outbounds[0].password==$records[0].authentication.password
    else
      .outbounds[0].type==(if $protocol=="hy2" then "hysteria2" else "anytls" end) and
      .outbounds[0].password==$records[0].authentication.users[0].password and
      .outbounds[0].tls.server_name==$records[0].tls.server_name and
      (.outbounds[0].tls.certificate|contains("BEGIN CERTIFICATE")) and
      (.outbounds[0].tls|has("insecure")|not) and
      (.outbounds[0].tls|has("key")|not)
    end)' "${client}" >/dev/null
  [[ "$(stat -c %a "${client}")" == 600 ]]
done

# Disabled authentication is explicit; it must not inherit credentials from
# an earlier enabled fixture or turn a malformed typed record into anonymous.
jq '.instances[0].authentication={enabled:false,username:"",password:""}' \
  "${PROTOCOLS_DIR}/instances/mixed.json" > "${TMP_DIR}/mixed-disabled.json"
cp "${TMP_DIR}/mixed-disabled.json" "${PROTOCOLS_DIR}/instances/mixed.json"
render_config mixed > "${TMP_DIR}/mixed-config.json"
generate_client mixed
MIXED_CLIENT="${TMP_DIR}/artifacts/scenarios/structured/protocol-probes/mixed/client.json"
jq -e '.outbounds[0]|has("username")==false and has("password")==false' "${MIXED_CLIENT}" >/dev/null
jq '.instances[0].authentication={enabled:true,username:"mixed-user",password:""}' \
  "${PROTOCOLS_DIR}/instances/mixed.json" > "${TMP_DIR}/mixed-invalid.json"
cp "${TMP_DIR}/mixed-invalid.json" "${PROTOCOLS_DIR}/instances/mixed.json"
cp "${MIXED_CLIENT}" "${TMP_DIR}/client-before-invalid.json"
if generate_client mixed > "${TMP_DIR}/invalid.stdout" 2> "${TMP_DIR}/invalid.stderr"; then
  printf 'invalid authenticated typed Mixed record unexpectedly exported\n' >&2
  exit 1
fi
cmp "${MIXED_CLIENT}" "${TMP_DIR}/client-before-invalid.json"

# Legacy markers still use the original isolated env decoder, even if a
# stale typed store exists. Enabled auth remains mandatory in the export.
printf 'AUTH_ENABLED=y\nUSERNAME=legacy-user\nPASSWORD=legacy-password\n' > "${PROTOCOLS_DIR}/mixed.env"
generate_client mixed
jq -e '.outbounds[0].username=="legacy-user" and .outbounds[0].password=="legacy-password"' \
  "${MIXED_CLIENT}" >/dev/null
printf 'Structured Mixed, HY2 and AnyTLS probe exports and legacy fallback passed\n'
