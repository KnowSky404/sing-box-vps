#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# Source at file scope so Bash 4.2 retains the real registry arrays.
source "${TESTABLE_INSTALL}"
trap 'printf "HTTP structured takeover failed at line %s\n" "${LINENO}" >&2' ERR

mkdir -p "${SB_PROTOCOL_STATE_DIR}"
printf 'INSTALLED_PROTOCOLS=http\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"

openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -subj '/CN=http-structured.example' \
  -keyout "${TMP_DIR}/http.key" -out "${TMP_DIR}/http.crt" >/dev/null 2>&1

jq -n \
  --arg cert "${TMP_DIR}/http.crt" --arg key "${TMP_DIR}/http.key" \
  '{
    log: {level:"warn"},
    inbounds: [
      {type:"http", tag:"http-edge", listen:"0.0.0.0", listen_port:33201,
       users:[{username:"edge-user",password:"edge-password"}],
       tls:{enabled:false}},
      {type:"http", tag:"http-tls", listen_port:33202,
       users:[{username:"tls-user",password:"tls-password"}],
       tls:{enabled:true,server_name:"http-structured.example",
            certificate_path:$cert,key_path:$key}}
    ],
    outbounds:[{type:"direct",tag:"direct"}],
    route:{rules:[
      {inbound:"http-edge",action:"route",outbound:"direct"},
      {inbound:"http-tls",action:"route",outbound:"direct"}
    ],final:"direct"}
  }' > "${SINGBOX_CONFIG_FILE}"

candidate=$(plain_proxy_config_store_candidate http)
jq -e --arg cert "${TMP_DIR}/http.crt" --arg key "${TMP_DIR}/http.key" '
  .protocol == "http" and .revision == 1 and .default_instance_id == "http-edge" and
  ([.instances[].tag] | sort) == ["http-edge", "http-tls"] and
  ([.instances[] | select(.tag == "http-edge")][0] |
    .id == "http-edge" and .name == "http-edge" and
    .listen.address == "0.0.0.0" and .listen.port == 33201 and
    .authentication.enabled and .authentication.username == "edge-user" and
    .authentication.password == "edge-password" and
    .outbound_policy == "direct" and .tls == {enabled:false}) and
  ([.instances[] | select(.tag == "http-tls")][0] |
    .listen.address == "127.0.0.1" and .listen.port == 33202 and
    .authentication.username == "tls-user" and .authentication.password == "tls-password" and
    .tls == {enabled:true,server_name:"http-structured.example",
             certificate_path:$cert,key_path:$key})
' <<< "${candidate}" >/dev/null

rebuild_protocol_state_from_config
store_file=$(plain_proxy_structured_store_file http)
plain_proxy_structured_state_active http
plain_proxy_validate_state_inventory http
plain_proxy_structured_state_matches_config http
protocol_state_matches_config http
agent_validate_indexed_protocol_states http
grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "${SB_PROTOCOL_STATE_DIR}/http.env"

jq -e --arg cert "${TMP_DIR}/http.crt" --arg key "${TMP_DIR}/http.key" '
  .revision == 1 and .default_instance_id == "http-edge" and
  ([.instances[] | select(.tag == "http-tls")][0].tls ==
    {enabled:true,server_name:"http-structured.example",
     certificate_path:$cert,key_path:$key})
' "${store_file}" >/dev/null

# Names are managed metadata, not a live-config label. Reordering inbounds
# and rebuilding must preserve names, IDs, TLS, credentials, and default.
jq '(.instances[] | select(.tag == "http-edge") | .name) = "Edge display name" |
    (.instances[] | select(.tag == "http-tls") | .name) = "TLS display name"' \
  "${store_file}" > "${TMP_DIR}/named-store.json"
mv "${TMP_DIR}/named-store.json" "${store_file}"
jq '.inbounds |= reverse' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/reordered.json"
mv "${TMP_DIR}/reordered.json" "${SINGBOX_CONFIG_FILE}"
cp -p "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/core-base.json"
candidate=$(plain_proxy_config_store_candidate http)
jq -e '
  .revision == 1 and .default_instance_id == "http-edge" and
  ([.instances[] | select(.tag == "http-edge")][0] |
    .id == "http-edge" and .name == "Edge display name" and
    .authentication.password == "edge-password" and .tls == {enabled:false}) and
  ([.instances[] | select(.tag == "http-tls")][0] |
    .id == "http-tls" and .name == "TLS display name" and
    .authentication.password == "tls-password" and .tls.enabled == true)
' <<< "${candidate}" >/dev/null
rebuild_protocol_state_from_config
protocol_state_matches_config http

# Unsupported TLS/provider fields and HTTP's unsupported system-proxy flag
# must fail before state clearing, with no secret-bearing diagnostics.
before_tree=$(find "${SB_PROTOCOL_STATE_DIR}" -type f -print0 | sort -z | xargs -0 sha256sum)
jq '.inbounds[0].tls = {enabled:false,provider:"acme"}' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/bad-tls.json"
mv "${TMP_DIR}/bad-tls.json" "${SINGBOX_CONFIG_FILE}"
if plain_proxy_config_store_candidate http >/dev/null 2>"${TMP_DIR}/bad-tls.stderr"; then
  printf 'expected unsupported HTTP TLS field to be rejected\n' >&2
  exit 1
fi
grep -Fq '[ERROR] http_store_candidate:' "${TMP_DIR}/bad-tls.stderr"
if grep -Eq 'edge-password|tls-password' "${TMP_DIR}/bad-tls.stderr"; then
  printf 'HTTP candidate diagnostics leaked a credential\n' >&2
  exit 1
fi
if rebuild_protocol_state_from_config >"${TMP_DIR}/bad-tls.stdout" 2>"${TMP_DIR}/bad-tls-rebuild.stderr"; then
  printf 'expected unsupported HTTP TLS rebuild to fail\n' >&2
  exit 1
fi
after_tree=$(find "${SB_PROTOCOL_STATE_DIR}" -type f -print0 | sort -z | xargs -0 sha256sum)
[[ "${before_tree}" == "${after_tree}" ]]

jq '.inbounds[0].tls = {enabled:false} | .inbounds[0].set_system_proxy = true' \
  "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/bad-proxy.json"
mv "${TMP_DIR}/bad-proxy.json" "${SINGBOX_CONFIG_FILE}"
if plain_proxy_config_store_candidate http >/dev/null 2>"${TMP_DIR}/bad-proxy.stderr"; then
  printf 'expected HTTP set_system_proxy=true to be rejected\n' >&2
  exit 1
fi
grep -Fq '[ERROR] http_store_candidate:' "${TMP_DIR}/bad-proxy.stderr"
if grep -Fq 'Mixed' "${TMP_DIR}/bad-proxy.stderr"; then
  printf 'HTTP candidate diagnostic incorrectly used Mixed label\n' >&2
  exit 1
fi

# The generated/default false form is explicitly representable.
jq '.inbounds[0].set_system_proxy = false' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/accepted-proxy.json"
mv "${TMP_DIR}/accepted-proxy.json" "${SINGBOX_CONFIG_FILE}"
plain_proxy_config_store_candidate http >/dev/null

# HTTP Basic userinfo cannot contain a colon or control character. The typed
# candidate validator must reject both rather than render a lossy state.
jq '.inbounds[0].set_system_proxy = false | .inbounds[0].users[0].username = "bad:user"' \
  "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/bad-user.json"
mv "${TMP_DIR}/bad-user.json" "${SINGBOX_CONFIG_FILE}"
if plain_proxy_config_store_candidate http >/dev/null 2>"${TMP_DIR}/bad-user.stderr"; then
  printf 'expected HTTP colon username to be rejected\n' >&2
  exit 1
fi

# Rendered typed HTTP inbounds must retain disabled/enabled TLS semantics and
# be accepted by every real core supplied by the verification environment.
jq --argjson inbounds "$(build_inbound_for_protocol http | jq -s .)" \
  '.inbounds = $inbounds' "${TMP_DIR}/core-base.json" > "${TMP_DIR}/rendered.json"
core_checks=0
for core_binary in "${SINGBOX_BINARY_113:-}" "${SINGBOX_BINARY_114:-}"; do
  if [[ -n "${core_binary}" && -x "${core_binary}" ]]; then
    "${core_binary}" check -c "${TMP_DIR}/rendered.json"
    core_checks=$((core_checks + 1))
  else
    printf 'SKIP HTTP real-core check: binary unavailable\n'
  fi
done

printf 'HTTP structured takeover checks passed; real core checks=%s\n' "${core_checks}"
