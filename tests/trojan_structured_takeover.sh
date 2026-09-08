#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 122
# Source at file scope for Bash 4.2 registry compatibility.
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
trap 'printf "Trojan structured takeover failed at line %s\n" "${LINENO}" >&2' ERR

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
printf 'INSTALLED_PROTOCOLS=trojan\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=trojan-takeover.example' \
  -keyout "${TMP_DIR}/trojan.key" -out "${TMP_DIR}/trojan.crt" >/dev/null 2>&1

jq -n --arg cert "${TMP_DIR}/trojan.crt" --arg key "${TMP_DIR}/trojan.key" '
  {
    log:{level:"warn",timestamp:true},
    custom_metadata:{preserve_me:true},
    experimental:{clash_api:{external_controller:"127.0.0.1:9090"}},
    dns:{servers:[{tag:"local",type:"local"}],final:"local"},
    inbounds:[
      {type:"trojan",tag:"trojan-none",listen:"127.0.0.1",listen_port:33501,
       users:[{name:"native",password:"native-password"}],tls:{enabled:false}},
      {type:"trojan",tag:"trojan-ws",listen:"0.0.0.0",listen_port:33502,
       users:[{name:"ws",password:"ws-password"}],
       tls:{enabled:true,server_name:"trojan-takeover.example",certificate_path:$cert,key_path:$key},
       transport:{type:"ws",path:"/trojan",headers:{Host:"trojan-takeover.example"}}},
      {type:"trojan",tag:"trojan-grpc",listen:"127.0.0.1",listen_port:33503,
       users:[{name:"grpc",password:"grpc-password"}],
       tls:{enabled:true,server_name:"trojan-takeover.example",certificate_path:$cert,key_path:$key},
       transport:{type:"grpc",service_name:"trojan"}},
      {type:"trojan",tag:"trojan-quic",listen:"127.0.0.1",listen_port:33501,
       users:[{name:"quic",password:"quic-password"}],
       tls:{enabled:true,server_name:"trojan-takeover.example",certificate_path:$cert,key_path:$key},
       transport:{type:"quic"}}
    ],
    outbounds:[{type:"direct",tag:"direct"}],
    route:{rules:[
      {inbound:"trojan-none",action:"sniff"},
      {inbound:"trojan-none",action:"route",outbound:"direct"},
      {inbound:"trojan-ws",action:"sniff"},
      {inbound:"trojan-ws",action:"route",outbound:"direct"},
      {inbound:"trojan-grpc",action:"route",outbound:"direct"},
      {inbound:"trojan-quic",action:"route",outbound:"direct"},
      {inbound:"trojan-ws",action:"reject",ip_is_private:true}
    ],final:"direct"}
  }
' > "${SINGBOX_CONFIG_FILE}"

before_config_hash=$(sha256sum "${SINGBOX_CONFIG_FILE}")
candidate=$(plain_proxy_config_store_candidate trojan)
jq -e --arg cert "${TMP_DIR}/trojan.crt" --arg key "${TMP_DIR}/trojan.key" '
  .protocol=="trojan" and .revision==1 and .default_instance_id=="trojan-grpc" and (.instances|length)==4 and
  any(.instances[]; .tag=="trojan-none" and .tls=={enabled:false} and .client_trust=="system" and .transport.type=="none") and
  any(.instances[]; .tag=="trojan-ws" and .tls.enabled and .tls.certificate_path==$cert and
    .client_trust=="certificate" and .transport.type=="ws" and .transport.path=="/trojan") and
  any(.instances[]; .tag=="trojan-grpc" and .transport.type=="grpc") and
  any(.instances[]; .tag=="trojan-quic" and .transport.type=="quic")
' <<< "${candidate}" >/dev/null
[[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${before_config_hash}" ]]

rebuild_protocol_state_from_config
store_file="${SB_PROTOCOL_STATE_DIR}/instances/trojan.json"
plain_proxy_structured_state_active trojan
plain_proxy_validate_state_inventory trojan
plain_proxy_structured_state_matches_config trojan
[[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${before_config_hash}" ]]
jq -e 'any(.instances[]; .tag=="trojan-none" and .client_trust=="system") and
  any(.instances[]; .tag=="trojan-ws" and .client_trust=="certificate")' "${store_file}" >/dev/null

# Metadata choices are authoritative on a subsequent read-only takeover even
# when config order changes.  Unknown root fields and custom routing remain.
jq '(.instances[] | select(.tag=="trojan-none") | .name)="Native display" |
    (.instances[] | select(.tag=="trojan-ws") | .client_trust)="certificate"' "${store_file}" > "${TMP_DIR}/named-store.json"
mv "${TMP_DIR}/named-store.json" "${store_file}"
jq '.inbounds |= reverse' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/reordered.json"
cp -- "${TMP_DIR}/reordered.json" "${SINGBOX_CONFIG_FILE}"
candidate=$(plain_proxy_config_store_candidate trojan)
jq -e 'any(.instances[]; .tag=="trojan-none" and .name=="Native display" and .client_trust=="system") and
  any(.instances[]; .tag=="trojan-ws" and .client_trust=="certificate")' <<< "${candidate}" >/dev/null
rebuild_protocol_state_from_config
jq -e '.experimental.clash_api.external_controller=="127.0.0.1:9090" and
  .log.timestamp==true and .custom_metadata.preserve_me==true and
  any(.route.rules[]; .action=="reject" and .ip_is_private==true)' \
  "${SINGBOX_CONFIG_FILE}" >/dev/null

# Profile inspection is the canonical ALPN contract for the typed transport.
ws_profile=$(inspect_v2ray_transport_profile_json trojan \
  '{"type":"ws","path":"/trojan","headers":{"Host":"trojan-takeover.example"}}' tls '' 1.14.0)
grpc_profile=$(inspect_v2ray_transport_profile_json trojan '{"type":"grpc","service_name":"trojan"}' tls '' 1.14.0)
quic_profile=$(inspect_v2ray_transport_profile_json trojan '{"type":"quic"}' tls '' 1.14.0)
jq -e '.listen_networks==["tcp"] and .tls_alpn==["http/1.1"]' <<< "${ws_profile}" >/dev/null
jq -e '.listen_networks==["tcp"] and .tls_alpn==["h2"]' <<< "${grpc_profile}" >/dev/null
jq -e '.listen_networks==["udp"] and .tls_alpn==["h3"]' <<< "${quic_profile}" >/dev/null

# A renderer round-trip must be accepted with the transport-derived ALPN, and
# an operator-supplied mismatch must remain rejected rather than being
# silently discarded during takeover.
rendered_inbounds=$(render_structured_instance_inbounds trojan "${store_file}" | jq -s .)
jq --argjson inbounds "${rendered_inbounds}" '.inbounds=$inbounds' \
  "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/self-rendered.json"
self_rendered_candidate=$(plain_proxy_config_store_candidate trojan \
  "${TMP_DIR}/self-rendered.json" "${store_file}")
jq -e 'any(.[]; .tag=="trojan-ws" and .tls.alpn == ["http/1.1"]) and
  any(.[]; .tag=="trojan-grpc" and .tls.alpn == ["h2"]) and
  any(.[]; .tag=="trojan-quic" and .tls.alpn == ["h3"])' \
  <<< "${rendered_inbounds}" >/dev/null
jq -e '.protocol=="trojan" and .revision==1 and (.instances|length)==4' \
  <<< "${self_rendered_candidate}" >/dev/null
jq '.inbounds |= map(if .tag=="trojan-ws" then .tls.alpn=["h2"] else . end)' \
  "${TMP_DIR}/self-rendered.json" > "${TMP_DIR}/bad-alpn.json"
if plain_proxy_config_store_candidate trojan "${TMP_DIR}/bad-alpn.json" "${store_file}" \
  >/dev/null 2>"${TMP_DIR}/bad-alpn.stderr"; then
  printf 'accepted mismatched Trojan TLS ALPN during takeover\n' >&2
  exit 1
fi

# Trojan has no typed representation for these inbound-level controls.  A
# takeover must reject each one, including the false-valued Mixed-only proxy
# switch, instead of dropping it from the managed record.
jq '.inbounds[0].set_system_proxy=false' "${SINGBOX_CONFIG_FILE}" \
  > "${TMP_DIR}/bad-system-proxy.json"
if plain_proxy_config_store_candidate trojan "${TMP_DIR}/bad-system-proxy.json" "${store_file}" \
  >/dev/null 2>"${TMP_DIR}/bad-system-proxy.stderr"; then
  printf 'accepted Trojan set_system_proxy=false during takeover\n' >&2
  exit 1
fi
jq '.inbounds[0].fallback={server:"127.0.0.1",server_port:33599}' \
  "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/bad-fallback.json"
if plain_proxy_config_store_candidate trojan "${TMP_DIR}/bad-fallback.json" "${store_file}" \
  >/dev/null 2>"${TMP_DIR}/bad-fallback.stderr"; then
  printf 'accepted unsupported Trojan fallback during takeover\n' >&2
  exit 1
fi
jq '.inbounds[0].multiplex={enabled:true}' "${SINGBOX_CONFIG_FILE}" \
  > "${TMP_DIR}/bad-multiplex.json"
if plain_proxy_config_store_candidate trojan "${TMP_DIR}/bad-multiplex.json" "${store_file}" \
  >/dev/null 2>"${TMP_DIR}/bad-multiplex.stderr"; then
  printf 'accepted unsupported Trojan multiplex during takeover\n' >&2
  exit 1
fi

# HTTPUpgrade and WebSocket early data remain diagnostic-only and cannot be
# silently imported into the deployable Trojan store.
jq '.inbounds[0].transport={type:"httpupgrade",path:"/upgrade"}' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/httpupgrade.json"
mv "${TMP_DIR}/httpupgrade.json" "${SINGBOX_CONFIG_FILE}"
if plain_proxy_config_store_candidate trojan >/dev/null 2>&1; then
  printf 'accepted blocked HTTPUpgrade during Trojan takeover\n' >&2
  exit 1
fi
jq --argjson original "$(jq '.inbounds[0]' "${SINGBOX_CONFIG_FILE}")" \
  '.inbounds[0].transport={type:"ws",path:"/trojan",max_early_data:1,early_data_header_name:"X-Early-Data"}' \
  "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/ws-early.json"
mv "${TMP_DIR}/ws-early.json" "${SINGBOX_CONFIG_FILE}"
if plain_proxy_config_store_candidate trojan >/dev/null 2>&1; then
  printf 'accepted blocked WebSocket early data during Trojan takeover\n' >&2
  exit 1
fi

core_checks=0
core_config="${TMP_DIR}/core-valid.json"
jq 'del(.custom_metadata)' "${TMP_DIR}/reordered.json" > "${core_config}"
for core_binary in "${SINGBOX_BINARY_113:-}" "${SINGBOX_BINARY_114:-}"; do
  if [[ -n "${core_binary}" && -x "${core_binary}" ]]; then
    # Check the original valid fixture; the blocked variants above are
    # intentionally not sent to the core because they are rejected at import.
    "${core_binary}" check -c "${core_config}"
    core_checks=$((core_checks + 1))
  fi
done

printf 'Trojan structured takeover checks passed; real core checks=%s\n' "${core_checks}"
