#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bash "${REPO_ROOT}/tests/protocol_registry_legacy_bash.sh"
TEST_DIR=$(mktemp -d /tmp/sing-box-vps-registry-test.XXXXXX)
trap 'rm -rf "${TEST_DIR}"' EXIT

sed -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TEST_DIR}/project\"|" \
  -e "s|readonly SINGBOX_BIN_PATH=\"/usr/local/bin/sing-box\"|readonly SINGBOX_BIN_PATH=\"${TEST_DIR}/sing-box\"|" \
  "${REPO_ROOT}/install.sh" > "${TEST_DIR}/install.sh"
source "${TEST_DIR}/install.sh"

registry=$(protocol_registry_json)
jq -e '
  length == 15 and
  ([.[].state_id] | unique | length == 15) and
  ([.[].agent_id] | unique | length == 15) and
  ([.[].menu_order] | sort == [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]) and
  all(.[]; .implemented == true and .available == null and .validated.status == "not_assessed") and
  any(.[]; .state_id == "shadowsocks" and
    .features.listen_network_selection == true and
    .legacy_capabilities.listen_network_selection == true)
  and any(.[]; .state_id == "trojan" and
    .subman_type == "trojan" and
    .legacy_capabilities.subman_sync == true)
  and any(.[]; .state_id == "vmess" and
    .subman_type == "vmess" and
    .features.multi_instance == true and
    .features.listen_transport_projection == true and
    .features.client_export == true)
  and any(.[]; .state_id == "vless-plain" and
    .runtime_id == "vless" and .agent_id == "vless-plain" and
    .subman_type == "vless" and .features.multi_user == true and
    .features.listen_transport_projection == true and
    .features.client_export == true and .features.subman_sync == true)
  and any(.[]; .state_id == "anytls" and
    .runtime_id == "anytls" and .agent_id == "anytls" and
    .features.multi_instance == true and .features.multi_user == true and
    .features.authentication == true and .features.tls == true and
    .features.standard_share_uri == false and .features.client_export == true)
  and any(.[]; .state_id == "snell" and
    .runtime_id == "snell" and .agent_id == "snell" and
    .features.multi_instance == true and .features.multi_user == true and
    .features.authentication == true and .features.versions == [5,6] and
    .features.v5_obfs_modes == ["none", "http"] and
    .features.v6_modes == ["", "default", "unshaped", "unsafe-raw"] and
    .features.udp_via_tcp_packet_api == true and
    .features.standard_share_uri == false and .features.qr == false and .features.client_export == true and
    .features.subman_sync == false)
  and any(.[]; .state_id == "tuic" and
    .runtime_id == "tuic" and .agent_id == "tuic" and
    .features.multi_instance == true and .features.multi_user == true and
    .features.authentication == true and .features.tls == true and
    .features.tls_modes == ["manual_certificate"] and .features.quic == true and
    .features.congestion_control == ["cubic", "new_reno", "bbr"] and
    .features.udp_relay_modes == ["native", "quic"] and .features.udp_over_stream == true and
    .features.standard_share_uri == false and .features.qr == false and .features.client_export == true and
    .features.subman_sync == false)
  and any(.[]; .state_id == "hysteria" and
    .runtime_id == "hysteria" and .agent_id == "hysteria" and
    .features.multi_instance == true and .features.multi_user == true and
    .features.authentication == true and .features.tls == true and
    .features.tls_modes == ["manual_certificate"] and .features.bandwidth == true and
    .features.obfs == true and .features.quic == true and
    .features.standard_share_uri == false and .features.qr == false and .features.client_export == true and
    .features.subman_sync == false)
  and any(.[]; .state_id == "naive" and
    .runtime_id == "naive" and .agent_id == "naive" and
    .features.multi_instance == true and .features.multi_user == true and
    .features.authentication == true and .features.tls == true and
    .features.network == ["tcp", "udp"] and .features.listen_network_selection == true and
    .features.quic_congestion_control == ["bbr", "cubic", "reno"] and
    .features.standard_share_uri == false and .features.qr == false and .features.client_export == true and
    .features.subman_sync == false and
    .features.outbound_runtime == "with_naive_outbound+libcronet")
  and any(.[]; .state_id == "shadowtls" and
    .runtime_id == "shadowtls" and .agent_id == "shadowtls" and
    .features.multi_instance == true and .features.multi_user == true and
    .features.authentication == true and .features.versions == [1,2,3] and
    .features.handshake == true and .features.detour == true and
    .features.wildcard_sni == ["off", "authed", "all"] and
    .features.standard_share_uri == false and .features.qr == false and
    .features.client_export == true and .features.subman_sync == false and
    .features.composite == true)
' >/dev/null <<< "${registry}"
capabilities=$(agent_capabilities_json)
jq -e '
  .features.plain_proxy_instances as $plain |
  ($plain.operations | index("migrate") == null) and
  ($plain.operations_by_protocol.mixed | index("migrate") != null) and
  ($plain.operations_by_protocol.socks == ["create", "replace", "delete", "default", "recover"]) and
  ($plain.protocols | index("http") != null) and
  ($plain.operations_by_protocol.http == ["create", "replace", "delete", "default", "recover"]) and
  ($plain.protocols | index("trojan") != null) and
  ($plain.operations_by_protocol.trojan == ["create", "replace", "delete", "default", "recover"]) and
  ($plain.protocols | index("vmess") != null) and
  ($plain.operations_by_protocol.vmess == ["create", "replace", "delete", "default", "recover"]) and
  ($plain.protocols | index("vless-plain") != null) and
  ($plain.operations_by_protocol["vless-plain"] == ["create", "replace", "delete", "default", "recover"]) and
  ($plain.protocols | index("anytls") != null) and
  ($plain.operations_by_protocol.anytls == ["create", "replace", "delete", "default", "recover"]) and
  ($plain.protocols | index("snell") != null) and
  ($plain.operations_by_protocol.snell == ["create", "replace", "delete", "default", "recover"]) and
  ($plain.protocols | index("tuic") != null) and
  ($plain.operations_by_protocol.tuic == ["create", "replace", "delete", "default", "recover"]) and
  ($plain.protocols | index("hysteria") != null) and
  ($plain.operations_by_protocol.hysteria == ["create", "replace", "delete", "default", "recover"]) and
  ($plain.protocols | index("naive") != null) and
  ($plain.operations_by_protocol.naive == ["create", "replace", "delete", "default", "recover"]) and
  ($plain.protocols | index("shadowtls") != null) and
  ($plain.operations_by_protocol.shadowtls == ["create", "replace", "delete", "default", "recover"]) and
  .features.mixed_instances.operations == $plain.operations_by_protocol.mixed
' >/dev/null <<< "${capabilities}"
jq -e --argjson registry "${registry}" '
  .protocols == ($registry | map({key: .agent_id, value: .legacy_capabilities}) | from_entries) and
  ([.protocol_registry[].capabilities] == [$registry[].legacy_capabilities]) and
  any(.protocol_registry[]; .state_id == "shadowsocks" and
    .features.listen_network_selection == true and
    .capabilities.listen_network_selection == true) and
  any(.protocol_registry[]; .state_id == "trojan" and
    .features.listen_transport_projection == true and
    .capabilities.listen_transport_projection == true) and
  any(.protocol_registry[]; .state_id == "vmess" and
    .features.listen_transport_projection == true and
    .capabilities.listen_transport_projection == true) and
  any(.protocol_registry[]; .state_id == "vless-plain" and
    .capabilities.multi_user == true and .capabilities.subman_sync == true) and
  any(.protocol_registry[]; .state_id == "snell" and
    .features.multi_instance == true and .features.multi_user == true and
    .features.standard_share_uri == false and .features.qr == false and .features.client_export == true and
    .capabilities.subman_sync == false) and
  any(.protocol_registry[]; .state_id == "tuic" and
    .features.multi_instance == true and .features.multi_user == true and
    .features.standard_share_uri == false and .features.qr == false and .features.client_export == true and
    .capabilities.subman_sync == false) and
  any(.protocol_registry[]; .state_id == "hysteria" and
    .features.multi_instance == true and .features.multi_user == true and
    .features.bandwidth == true and .features.obfs == true and
    .features.standard_share_uri == false and .features.qr == false and .features.client_export == true and
    .capabilities.subman_sync == false) and
  any(.protocol_registry[]; .state_id == "naive" and
    .features.multi_instance == true and .features.multi_user == true and
    .features.network == ["tcp", "udp"] and .features.listen_network_selection == true and
    .features.standard_share_uri == false and .features.qr == false and .features.client_export == true and
    .capabilities.subman_sync == false and
    .features.outbound_runtime == "with_naive_outbound+libcronet") and
  any(.protocol_registry[]; .state_id == "shadowtls" and
    .features.multi_instance == true and .features.multi_user == true and
    .features.handshake == true and .features.detour == true and
    .features.standard_share_uri == false and .features.qr == false and
    .features.client_export == true and .capabilities.subman_sync == false and
    .features.composite == true) and
  (.features.subman.supported_protocols | index("trojan") != null) and
  .features.subman.supported_protocols == ($registry | map(select(.subman_type != "") | .agent_id))
' >/dev/null <<< "${capabilities}"

[[ "$(normalize_protocol_id vless)" == vless-reality ]]
[[ "$(normalize_protocol_id vless+reality)" == vless-reality ]]
[[ "$(normalize_protocol_id hysteria2)" == hy2 ]]
[[ "$(state_protocol_to_runtime vless-reality)" == vless+reality ]]
[[ "$(agent_protocol_id hy2)" == hysteria2 ]]
[[ "$(protocol_inbound_tag hysteria2)" == hy2-in ]]
for unknown in unknown '' '../mixed' 'mixed;touch /tmp/unsafe' '$(false)'; do
  for handler in normalize_protocol_id state_protocol_to_runtime protocol_inbound_tag protocol_state_file \
    build_inbound_for_protocol build_certificate_provider_for_protocol build_protocol_route_rules save_protocol_state; do
    if "${handler}" "${unknown}" > "${TEST_DIR}/unknown.stdout" 2> "${TEST_DIR}/unknown.stderr"; then
      printf 'unknown protocol accepted by %s\n' "${handler}" >&2
      exit 1
    fi
    [[ ! -s "${TEST_DIR}/unknown.stdout" ]]
  done
done

mkdir -p "${SB_PROTOCOL_STATE_DIR}"
for protocol in $(list_registered_protocols); do
  protocol_registry_require_handlers "${protocol}"
  [[ "$(protocol_option_to_id "$(protocol_registry_field "${protocol}" menu_order)")" == "${protocol}" ]]
  if [[ "${protocol}" == "socks" || "${protocol}" == "http" || "${protocol}" == "shadowsocks" || "${protocol}" == "trojan" || "${protocol}" == "vmess" || "${protocol}" == "vless-plain" || "${protocol}" == "anytls" || "${protocol}" == "snell" || "${protocol}" == "tuic" || "${protocol}" == "hysteria" || "${protocol}" == "naive" || "${protocol}" == "shadowtls" ]]; then
    printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "$(protocol_state_file "${protocol}")"
    mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
    if [[ "${protocol}" == "socks" ]]; then
      cat > "${SB_PROTOCOL_STATE_DIR}/instances/socks.json" <<'SOCKS_STORE_EOF'
{
  "schema_version": 1,
  "protocol": "socks",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [
    {
      "id": "main",
      "name": "SOCKS contract",
      "tag": "socks-in",
      "listen": {"address": "127.0.0.1", "port": 1081},
      "authentication": {"enabled": false, "username": "", "password": ""},
      "outbound_policy": "default",
      "dependencies": []
    }
  ]
}
SOCKS_STORE_EOF
    elif [[ "${protocol}" == "http" ]]; then
      cat > "${SB_PROTOCOL_STATE_DIR}/instances/http.json" <<'HTTP_STORE_EOF'
{
  "schema_version": 1,
  "protocol": "http",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [
    {
      "id": "main",
      "name": "HTTP contract",
      "tag": "http-in",
      "listen": {"address": "127.0.0.1", "port": 1082},
      "authentication": {"enabled": true, "username": "http-user", "password": "HTTP-CONTRACT-PASSWORD"},
      "outbound_policy": "default",
      "dependencies": [],
      "tls": {"enabled": true, "server_name": "http.example.com", "certificate_path": "/tmp/http-contract.crt", "key_path": "/tmp/http-contract.key"}
    }
  ]
}
HTTP_STORE_EOF
    elif [[ "${protocol}" == "shadowsocks" ]]; then
      cat > "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json" <<'SHADOWSOCKS_STORE_EOF'
{
  "schema_version": 1,
  "protocol": "shadowsocks",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [
    {
      "id": "main",
      "name": "Shadowsocks contract",
      "tag": "ss-in",
      "listen": {"address": "127.0.0.1", "port": 1083, "network": ["tcp", "udp"]},
      "authentication": {"method": "aes-256-gcm", "password": "ss-password", "users": []},
      "outbound_policy": "default",
      "dependencies": []
    }
  ]
}
SHADOWSOCKS_STORE_EOF
    elif [[ "${protocol}" == "trojan" ]]; then
      cat > "${SB_PROTOCOL_STATE_DIR}/instances/trojan.json" <<'TROJAN_STORE_EOF'
{
  "schema_version": 1,
  "protocol": "trojan",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [
    {
      "id": "main",
      "name": "Trojan contract",
      "tag": "trojan-in",
      "listen": {"address": "127.0.0.1", "port": 1084},
      "authentication": {"users": [{"name": "trojan-user", "password": "TROJAN-CONTRACT-PASSWORD"}]},
      "tls": {"enabled": false},
      "client_trust": "system",
      "transport": {"type": "none"},
      "outbound_policy": "default",
      "dependencies": []
    }
  ]
}
TROJAN_STORE_EOF
    elif [[ "${protocol}" == "vless-plain" ]]; then
      cat > "${SB_PROTOCOL_STATE_DIR}/instances/vless-plain.json" <<'VLESS_PLAIN_STORE_EOF'
{
  "schema_version": 1,
  "protocol": "vless-plain",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [
    {
      "id": "main",
      "name": "VLESS contract",
      "tag": "vless-plain-in",
      "listen": {"address": "127.0.0.1", "port": 1086},
      "authentication": {"users": [{"name": "vless-user", "uuid": "11111111-1111-4111-8111-111111111111", "flow": ""}]},
      "tls": {"enabled": false},
      "client_trust": "system",
      "transport": {"type": "none"},
      "outbound_policy": "default",
      "dependencies": []
    }
  ]
}
VLESS_PLAIN_STORE_EOF
    elif [[ "${protocol}" == "anytls" ]]; then
      cat > "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json" <<'ANYTLS_STORE_EOF'
{
  "schema_version": 1,
  "protocol": "anytls",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [
    {
      "id": "main",
      "name": "AnyTLS contract",
      "tag": "anytls-in",
      "listen": {"address": "127.0.0.1", "port": 1087},
      "authentication": {"users": [{"name": "anytls-user", "password": "ANYTLS-CONTRACT-PASSWORD"}]},
      "tls": {"enabled": true, "server_name": "anytls.example.com", "certificate_path": "/tmp/anytls-contract.crt", "key_path": "/tmp/anytls-contract.key"},
      "client_trust": "system",
      "outbound_policy": "default",
      "dependencies": []
    }
  ]
}
ANYTLS_STORE_EOF
    elif [[ "${protocol}" == "snell" ]]; then
      cat > "${SB_PROTOCOL_STATE_DIR}/instances/snell.json" <<'SNELL_STORE_EOF'
{
  "schema_version": 1,
  "protocol": "snell",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [
    {
      "id": "main",
      "name": "Snell contract",
      "tag": "snell-in",
      "listen": {"address": "127.0.0.1", "port": 1088},
      "version": 6,
      "authentication": {"psk": "snell-contract-psk-123", "users": [{"name": "snell-user", "userkey": "snell-user-key"}]},
      "mode": "default",
      "outbound_policy": "default",
      "dependencies": []
    }
  ]
}
SNELL_STORE_EOF
    elif [[ "${protocol}" == "tuic" ]]; then
      cat > "${SB_PROTOCOL_STATE_DIR}/instances/tuic.json" <<'TUIC_STORE_EOF'
{
  "schema_version": 1,
  "protocol": "tuic",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [
    {
      "id": "main",
      "name": "TUIC contract",
      "tag": "tuic-in",
      "listen": {"address": "127.0.0.1", "port": 1089},
      "authentication": {"users": [{"name": "tuic-user", "uuid": "11111111-1111-4111-8111-111111111111", "password": "TUIC-CONTRACT-PASSWORD"}]},
      "tls": {"enabled": true, "server_name": "tuic.example.com", "certificate_path": "/tmp/tuic-contract.crt", "key_path": "/tmp/tuic-contract.key"},
      "client_trust": "system",
      "tuic": {"auth_timeout_seconds": 3, "congestion_control": "bbr", "heartbeat_seconds": 10, "udp_over_stream": false, "udp_relay_mode": "native", "zero_rtt_handshake": false},
      "outbound_policy": "default",
      "dependencies": []
    }
  ]
}
TUIC_STORE_EOF
    elif [[ "${protocol}" == "hysteria" ]]; then
      cat > "${SB_PROTOCOL_STATE_DIR}/instances/hysteria.json" <<'HYSTERIA_STORE_EOF'
{
  "schema_version": 1,
  "protocol": "hysteria",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [
    {
      "id": "main",
      "name": "Hysteria contract",
      "tag": "hysteria-in",
      "listen": {"address": "127.0.0.1", "port": 1090},
      "authentication": {"users": [{"name": "hysteria-user", "auth_str": "HYSTERIA-CONTRACT-AUTH"}]},
      "tls": {"enabled": true, "server_name": "hysteria.example.com", "certificate_path": "/tmp/hysteria-contract.crt", "key_path": "/tmp/hysteria-contract.key"},
      "client_trust": "system",
      "bandwidth": {"up_mbps": 100, "down_mbps": 200},
      "obfs": {"enabled": true, "password": "HYSTERIA-OBFS"},
      "hysteria": {"connection_receive_window": "", "disable_path_mtu_discovery": false, "initial_packet_size": 0, "max_concurrent_streams": 0, "stream_receive_window": ""},
      "outbound_policy": "default",
      "dependencies": []
    }
  ]
}
HYSTERIA_STORE_EOF
    elif [[ "${protocol}" == "naive" ]]; then
      cat > "${SB_PROTOCOL_STATE_DIR}/instances/naive.json" <<'NAIVE_STORE_EOF'
{
  "schema_version": 1,
  "protocol": "naive",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [
    {
      "id": "main",
      "name": "Naive contract",
      "tag": "naive-in",
      "listen": {"address": "127.0.0.1", "port": 1091, "network": ["tcp", "udp"]},
      "authentication": {"users": [{"name": "naive-user", "username": "naive-user", "password": "NAIVE-CONTRACT-PASSWORD"}]},
      "tls": {"enabled": true, "server_name": "naive.example.com", "certificate_path": "/tmp/naive-contract.crt", "key_path": "/tmp/naive-contract.key"},
      "client_trust": "system",
      "naive": {"extra_headers": {}, "insecure_concurrency": 0, "quic": false, "quic_congestion_control": "bbr", "quic_session_receive_window": "", "stream_receive_window": ""},
      "outbound_policy": "default",
      "dependencies": []
    }
  ]
}
NAIVE_STORE_EOF
    elif [[ "${protocol}" == "shadowtls" ]]; then
      cat > "${SB_PROTOCOL_STATE_DIR}/instances/shadowtls.json" <<'SHADOWTLS_STORE_EOF'
{
  "schema_version": 1,
  "protocol": "shadowtls",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [
    {
      "id": "main",
      "name": "ShadowTLS contract",
      "tag": "shadowtls-in",
      "listen": {"address": "127.0.0.1", "port": 1092},
      "version": 3,
      "authentication": {"password": "", "users": [{"name": "shadowtls-user", "password": "SHADOWTLS-CONTRACT-PASSWORD"}]},
      "handshake": {"server": "shadowtls.example.com", "server_port": 443},
      "handshake_for_server_name": {},
      "strict_mode": false,
      "wildcard_sni": "off",
      "detour": {"tag": "shadowtls-inner-main", "listen": {"address": "127.0.0.1", "port": 1093}},
      "dependencies": ["shadowtls-inner-main"],
      "client_trust": "system",
      "client_tls": {"server_name": "shadowtls.example.com", "certificate_path": ""},
      "outbound_policy": "default"
    }
  ]
}
SHADOWTLS_STORE_EOF
    else
      cat > "${SB_PROTOCOL_STATE_DIR}/instances/vmess.json" <<'VMESS_STORE_EOF'
{
  "schema_version": 1,
  "protocol": "vmess",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [
    {
      "id": "main",
      "name": "VMess contract",
      "tag": "vmess-in",
      "listen": {"address": "127.0.0.1", "port": 1085},
      "authentication": {"users": [{"name": "vmess-user", "uuid": "11111111-1111-4111-8111-111111111111", "alter_id": 0, "security": "auto"}]},
      "tls": {"enabled": false},
      "client_trust": "system",
      "transport": {"type": "none"},
      "outbound_policy": "default",
      "dependencies": []
    }
  ]
}
VMESS_STORE_EOF
    fi
  else
    printf 'CONFIG_SCHEMA_VERSION=1\n' > "$(protocol_state_file "${protocol}")"
  fi
done
printf 'INSTALLED_PROTOCOLS=vless-reality,mixed,hy2,anytls,snell,tuic,hysteria,naive,shadowtls,socks,http,shadowsocks,trojan,vmess,vless-plain\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
[[ "$(list_exportable_client_protocols)" == $'vless-reality\nmixed\nhy2\nanytls\nsnell\ntuic\nhysteria\nnaive\nshadowtls\nsocks\nhttp\nshadowsocks\ntrojan\nvmess\nvless-plain' ]]
[[ "$(protocol_registry_field mixed client_export)" == true ]]
[[ "$(protocol_registry_field mixed multi_instance)" == true ]]
[[ -z "$(protocol_registry_field mixed subman_type)" ]]
[[ "$(protocol_registry_field socks client_export)" == true ]]
[[ "$(protocol_registry_field socks multi_instance)" == true ]]
[[ "$(protocol_registry_field socks menu_order)" == 5 ]]
[[ "$(protocol_registry_field socks default_tag)" == socks-in ]]
[[ "$(protocol_registry_field socks handlers)" == *load_plain_proxy_structured_instance* ]]
[[ "$(protocol_registry_field socks handlers)" == *apply_plain_proxy_instance_change* ]]
[[ "$(protocol_registry_field http menu_order)" == 6 ]]
[[ "$(protocol_registry_field http default_tag)" == http-in ]]
[[ "$(protocol_registry_field http state_id)" == http ]]
[[ "$(protocol_registry_field http listen_networks)" == tcp ]]
[[ "$(protocol_registry_field http handlers)" == *load_plain_proxy_structured_instance* ]]
[[ "$(protocol_registry_field http handlers)" == *apply_plain_proxy_instance_change* ]]
[[ "$(protocol_registry_field snell menu_order)" == 11 ]]
[[ "$(protocol_registry_field snell default_tag)" == snell-in ]]
[[ "$(protocol_registry_field snell state_id)" == snell ]]
[[ "$(protocol_registry_field snell agent_id)" == snell ]]
[[ "$(protocol_registry_field snell runtime_id)" == snell ]]
[[ "$(protocol_registry_field snell listen_networks)" == tcp ]]
[[ "$(protocol_registry_field snell client_export)" == true ]]
[[ -z "$(protocol_registry_field snell subman_type)" ]]
[[ "$(protocol_registry_field snell handlers)" == *build_snell_inbound_json* ]]
[[ "$(protocol_registry_field snell handlers)" == *build_client_snell_outbounds* ]]
[[ "$(protocol_registry_field snell handlers)" == *load_plain_proxy_structured_instance* ]]
[[ "$(protocol_registry_field snell handlers)" == *apply_plain_proxy_instance_change* ]]
[[ "$(protocol_registry_field tuic menu_order)" == 12 ]]
[[ "$(protocol_registry_field tuic default_tag)" == tuic-in ]]
[[ "$(protocol_registry_field tuic state_id)" == tuic ]]
[[ "$(protocol_registry_field tuic agent_id)" == tuic ]]
[[ "$(protocol_registry_field tuic runtime_id)" == tuic ]]
[[ "$(protocol_registry_field tuic listen_networks)" == udp ]]
[[ "$(protocol_registry_field tuic traffic_networks)" == tcp,udp ]]
[[ "$(protocol_registry_field tuic client_export)" == true ]]
[[ -z "$(protocol_registry_field tuic subman_type)" ]]
[[ "$(protocol_registry_field tuic handlers)" == *build_tuic_inbound_json* ]]
[[ "$(protocol_registry_field tuic handlers)" == *build_client_tuic_outbounds* ]]
[[ "$(protocol_registry_field tuic handlers)" == *load_plain_proxy_structured_instance* ]]
[[ "$(protocol_registry_field tuic handlers)" == *apply_plain_proxy_instance_change* ]]
[[ "$(protocol_registry_field hysteria menu_order)" == 13 ]]
[[ "$(protocol_registry_field hysteria default_tag)" == hysteria-in ]]
[[ "$(protocol_registry_field hysteria state_id)" == hysteria ]]
[[ "$(protocol_registry_field hysteria agent_id)" == hysteria ]]
[[ "$(protocol_registry_field hysteria runtime_id)" == hysteria ]]
[[ "$(protocol_registry_field hysteria listen_networks)" == udp ]]
[[ "$(protocol_registry_field hysteria traffic_networks)" == tcp,udp ]]
[[ "$(protocol_registry_field hysteria client_export)" == true ]]
[[ -z "$(protocol_registry_field hysteria subman_type)" ]]
[[ "$(protocol_registry_field hysteria handlers)" == *build_hysteria_inbound_json* ]]
[[ "$(protocol_registry_field hysteria handlers)" == *build_client_hysteria_outbounds* ]]
[[ "$(protocol_registry_field hysteria handlers)" == *load_plain_proxy_structured_instance* ]]
[[ "$(protocol_registry_field hysteria handlers)" == *apply_plain_proxy_instance_change* ]]
[[ "$(protocol_registry_field naive menu_order)" == 14 ]]
[[ "$(protocol_registry_field naive default_tag)" == naive-in ]]
[[ "$(protocol_registry_field naive state_id)" == naive ]]
[[ "$(protocol_registry_field naive agent_id)" == naive ]]
[[ "$(protocol_registry_field naive runtime_id)" == naive ]]
[[ "$(protocol_registry_field naive listen_networks)" == tcp,udp ]]
[[ "$(protocol_registry_field naive traffic_networks)" == tcp,udp ]]
[[ "$(protocol_registry_field naive client_export)" == true ]]
[[ -z "$(protocol_registry_field naive subman_type)" ]]
[[ "$(protocol_registry_field naive handlers)" == *build_naive_inbound_json* ]]
[[ "$(protocol_registry_field naive handlers)" == *build_client_naive_outbounds* ]]
[[ "$(protocol_registry_field naive handlers)" == *load_plain_proxy_structured_instance* ]]
[[ "$(protocol_registry_field naive handlers)" == *apply_plain_proxy_instance_change* ]]
[[ "$(protocol_registry_field shadowtls menu_order)" == 15 ]]
[[ "$(protocol_registry_field shadowtls default_tag)" == shadowtls-in ]]
[[ "$(protocol_registry_field shadowtls state_id)" == shadowtls ]]
[[ "$(protocol_registry_field shadowtls agent_id)" == shadowtls ]]
[[ "$(protocol_registry_field shadowtls listen_networks)" == tcp ]]
[[ "$(protocol_registry_field shadowtls client_export)" == true ]]
[[ -z "$(protocol_registry_field shadowtls subman_type)" ]]
[[ "$(protocol_registry_field shadowtls handlers)" == *build_shadowtls_inbound_json* ]]
[[ "$(protocol_registry_field shadowtls handlers)" == *build_client_shadowtls_outbounds* ]]
[[ "$(protocol_registry_field shadowtls handlers)" == *load_plain_proxy_structured_instance* ]]
[[ "$(protocol_registry_field shadowtls handlers)" == *apply_plain_proxy_instance_change* ]]
[[ "$(protocol_registry_field shadowsocks menu_order)" == 7 ]]
[[ "$(protocol_registry_field shadowsocks default_tag)" == ss-in ]]
[[ "$(protocol_registry_field shadowsocks state_id)" == shadowsocks ]]
[[ "$(protocol_registry_field shadowsocks agent_id)" == shadowsocks ]]
[[ "$(protocol_registry_field shadowsocks runtime_id)" == shadowsocks ]]
[[ "$(protocol_registry_field shadowsocks listen_networks)" == tcp,udp ]]
[[ "$(protocol_registry_field shadowsocks multi_instance)" == true ]]
[[ "$(protocol_registry_field shadowsocks handlers)" == *load_plain_proxy_structured_instance* ]]
[[ "$(protocol_registry_field trojan menu_order)" == 8 ]]
[[ "$(protocol_registry_field trojan default_tag)" == trojan-in ]]
[[ "$(protocol_registry_field trojan state_id)" == trojan ]]
[[ "$(protocol_registry_field trojan agent_id)" == trojan ]]
[[ "$(protocol_registry_field trojan runtime_id)" == trojan ]]
[[ "$(protocol_registry_field trojan listen_networks)" == tcp,udp ]]
[[ "$(protocol_registry_field trojan subman_type)" == trojan ]]
[[ "$(protocol_registry_field trojan share_formats)" == trojan ]]
[[ "$(protocol_registry_field trojan handlers)" == *build_trojan_inbound_json* ]]
[[ "$(protocol_registry_field trojan handlers)" == *build_client_trojan_outbounds* ]]
[[ "$(protocol_registry_field trojan handlers)" == *load_plain_proxy_structured_instance* ]]
[[ "$(protocol_registry_field trojan handlers)" == *apply_plain_proxy_instance_change* ]]
[[ "$(protocol_registry_field vmess menu_order)" == 9 ]]
[[ "$(protocol_registry_field vmess default_tag)" == vmess-in ]]
[[ "$(protocol_registry_field vmess state_id)" == vmess ]]
[[ "$(protocol_registry_field vmess agent_id)" == vmess ]]
[[ "$(protocol_registry_field vmess runtime_id)" == vmess ]]
[[ "$(protocol_registry_field vmess listen_networks)" == tcp,udp ]]
[[ "$(protocol_registry_field vmess subman_type)" == vmess ]]
[[ "$(protocol_registry_field vmess share_formats)" == vmess ]]
[[ "$(protocol_registry_field vmess handlers)" == *build_vmess_inbound_json* ]]
[[ "$(protocol_registry_field vmess handlers)" == *build_client_vmess_outbounds* ]]
[[ "$(protocol_registry_field vmess handlers)" == *load_plain_proxy_structured_instance* ]]
[[ "$(protocol_registry_field vmess handlers)" == *apply_plain_proxy_instance_change* ]]
[[ "$(protocol_registry_field vless-plain menu_order)" == 10 ]]
[[ "$(protocol_registry_field vless-plain default_tag)" == vless-plain-in ]]
[[ "$(protocol_registry_field vless-plain state_id)" == vless-plain ]]
[[ "$(protocol_registry_field vless-plain agent_id)" == vless-plain ]]
[[ "$(protocol_registry_field vless-plain runtime_id)" == vless ]]
[[ "$(protocol_registry_field vless-plain listen_networks)" == tcp,udp ]]
[[ "$(protocol_registry_field vless-plain subman_type)" == vless ]]
[[ "$(protocol_registry_field vless-plain share_formats)" == vless ]]
[[ "$(protocol_registry_field vless-plain handlers)" == *build_vless_plain_inbound_json* ]]
[[ "$(protocol_registry_field vless-plain handlers)" == *build_client_vless_plain_outbounds* ]]
[[ "$(protocol_registry_field vless-plain handlers)" == *load_plain_proxy_structured_instance* ]]
[[ "$(protocol_registry_field vless-plain handlers)" == *apply_plain_proxy_instance_change* ]]

trojan_store_file=$(plain_proxy_structured_store_file trojan)
trojan_inbounds=$(render_structured_instance_inbounds trojan "${trojan_store_file}" | jq -s .)
jq -e '
  length == 1 and
  .[0].type == "trojan" and .[0].tag == "trojan-in" and
  .[0].listen == "127.0.0.1" and .[0].listen_port == 1084 and
  (.[0].tls.enabled // false) == false and .[0].users[0].name == "trojan-user" and
  (.[0] | has("transport") | not)
' >/dev/null <<< "${trojan_inbounds}"
trojan_export=$(build_client_trojan_outbounds 127.0.0.1 | jq -s .)
jq -e '
  length == 1 and .[0].type == "trojan" and .[0].tag == "trojan-main-user-dHJvamFuLXVzZXI=" and
  .[0].server == "127.0.0.1" and .[0].server_port == 1084 and
  .[0].password == "TROJAN-CONTRACT-PASSWORD" and (.[0] | has("tls") | not) and
  (.[0] | has("transport") | not)
' >/dev/null <<< "${trojan_export}"

vmess_store_file=$(plain_proxy_structured_store_file vmess)
vmess_inbounds=$(render_structured_instance_inbounds vmess "${vmess_store_file}" | jq -s .)
jq -e '
  length == 1 and
  .[0].type == "vmess" and .[0].tag == "vmess-in" and
  .[0].listen == "127.0.0.1" and .[0].listen_port == 1085 and
  .[0].users[0].name == "vmess-user" and
  .[0].users[0].uuid == "11111111-1111-4111-8111-111111111111" and
  .[0].users[0].alterId == 0 and (.[0] | has("tls") | not) and
  (.[0] | has("transport") | not)
' >/dev/null <<< "${vmess_inbounds}"
vmess_export=$(build_client_vmess_outbounds 127.0.0.1 | jq -s .)
jq -e '
  length == 1 and .[0].type == "vmess" and
  .[0].tag == "vmess-main-user-dm1lc3MtdXNlcg==" and
  .[0].server == "127.0.0.1" and .[0].server_port == 1085 and
  .[0].uuid == "11111111-1111-4111-8111-111111111111" and
  .[0].alter_id == 0 and .[0].security == "auto" and
  .[0].network == ["tcp", "udp"] and
  (.[0] | has("tls") | not) and (.[0] | has("transport") | not)
' >/dev/null <<< "${vmess_export}"

vless_plain_store_file=$(plain_proxy_structured_store_file vless-plain)
vless_plain_inbounds=$(render_structured_instance_inbounds vless-plain "${vless_plain_store_file}" | jq -s .)
jq -e '
  length == 1 and
  .[0].type == "vless" and .[0].tag == "vless-plain-in" and
  .[0].listen == "127.0.0.1" and .[0].listen_port == 1086 and
  .[0].users[0].name == "vless-user" and
  .[0].users[0].uuid == "11111111-1111-4111-8111-111111111111" and
  (.[0].users[0] | has("flow") | not) and (.[0] | has("tls") | not) and
  (.[0] | has("transport") | not)
' >/dev/null <<< "${vless_plain_inbounds}"
vless_plain_export=$(build_client_vless_plain_outbounds 127.0.0.1 | jq -s .)
jq -e '
  length == 1 and .[0].type == "vless" and
  .[0].tag == "vless-plain-main-user-dmxlc3MtdXNlcg==" and
  .[0].server == "127.0.0.1" and .[0].server_port == 1086 and
  .[0].uuid == "11111111-1111-4111-8111-111111111111" and
  .[0].network == ["tcp", "udp"] and
  (.[0] | has("tls") | not) and (.[0] | has("transport") | not)
' >/dev/null <<< "${vless_plain_export}"

anytls_store_file=$(plain_proxy_structured_store_file anytls)
anytls_inbounds=$(render_structured_instance_inbounds anytls "${anytls_store_file}" | jq -s .)
jq -e '
  length == 1 and .[0].type == "anytls" and .[0].tag == "anytls-in" and
  .[0].listen == "127.0.0.1" and .[0].listen_port == 1087 and
  .[0].users[0].name == "anytls-user" and .[0].users[0].password == "ANYTLS-CONTRACT-PASSWORD" and
  .[0].tls.enabled == true and .[0].tls.server_name == "anytls.example.com" and
  (.[0] | has("transport") | not)
' >/dev/null <<< "${anytls_inbounds}"
anytls_export=$(build_client_anytls_outbounds 127.0.0.1 | jq -s .)
jq -e '
  length == 1 and .[0].type == "anytls" and
  .[0].tag == "anytls-main-user-YW55dGxzLXVzZXI=" and
  .[0].server == "127.0.0.1" and .[0].server_port == 1087 and
  .[0].password == "ANYTLS-CONTRACT-PASSWORD" and .[0].client_metadata == "" and
  .[0].tls.enabled == true and .[0].tls.server_name == "anytls.example.com" and
  (.[0].tls | has("certificate") | not) and (.[0] | has("transport") | not)
' >/dev/null <<< "${anytls_export}"

tuic_store_file=$(plain_proxy_structured_store_file tuic)
tuic_inbounds=$(render_structured_instance_inbounds tuic "${tuic_store_file}" | jq -s .)
jq -e '
  length == 1 and .[0].type == "tuic" and .[0].tag == "tuic-in" and
  .[0].listen == "127.0.0.1" and .[0].listen_port == 1089 and
  .[0].users[0].name == "tuic-user" and .[0].users[0].uuid == "11111111-1111-4111-8111-111111111111" and
  .[0].users[0].password == "TUIC-CONTRACT-PASSWORD" and
  .[0].tls.enabled == true and .[0].tls.server_name == "tuic.example.com" and
  .[0].tls.alpn == ["h3"] and .[0].congestion_control == "bbr" and
  .[0].auth_timeout == "3s" and .[0].heartbeat == "10s" and
  (.[0].zero_rtt_handshake // false) == false and
  (.[0] | has("udp_relay_mode") | not) and (.[0] | has("udp_over_stream") | not)
' >/dev/null <<< "${tuic_inbounds}"
tuic_export=$(build_client_tuic_outbounds 127.0.0.1 | jq -s .)
jq -e '
  length == 1 and .[0].type == "tuic" and
  .[0].tag == "tuic-main-user-dHVpYy11c2Vy" and
  .[0].server == "127.0.0.1" and .[0].server_port == 1089 and
  .[0].uuid == "11111111-1111-4111-8111-111111111111" and
  .[0].password == "TUIC-CONTRACT-PASSWORD" and .[0].network == ["tcp", "udp"] and
  .[0].congestion_control == "bbr" and .[0].udp_relay_mode == "native" and
  (.[0].udp_over_stream // false) == false and .[0].heartbeat == "10s" and
  (.[0].zero_rtt_handshake // false) == false and .[0].tls.enabled == true and
  .[0].tls.server_name == "tuic.example.com" and
  (.[0].tls | has("certificate") | not)
' >/dev/null <<< "${tuic_export}"

hysteria_store_file=$(plain_proxy_structured_store_file hysteria)
hysteria_inbounds=$(render_structured_instance_inbounds hysteria "${hysteria_store_file}" | jq -s .)
jq -e '
  length == 1 and .[0].type == "hysteria" and .[0].tag == "hysteria-in" and
  .[0].listen == "127.0.0.1" and .[0].listen_port == 1090 and
  .[0].users[0].name == "hysteria-user" and .[0].users[0].auth_str == "HYSTERIA-CONTRACT-AUTH" and
  .[0].tls.enabled == true and .[0].tls.server_name == "hysteria.example.com" and
  .[0].tls.alpn == ["h3"] and .[0].up_mbps == 100 and .[0].down_mbps == 200 and
  .[0].obfs == "HYSTERIA-OBFS" and
  (.[0] | has("initial_packet_size") | not)
' >/dev/null <<< "${hysteria_inbounds}"
hysteria_export=$(build_client_hysteria_outbounds 127.0.0.1 | jq -s .)
jq -e '
  length == 1 and .[0].type == "hysteria" and
  .[0].tag == "hysteria-main-user-aHlzdGVyaWEtdXNlcg==" and
  .[0].server == "127.0.0.1" and .[0].server_port == 1090 and
  .[0].auth_str == "HYSTERIA-CONTRACT-AUTH" and .[0].up_mbps == 100 and .[0].down_mbps == 200 and
  .[0].obfs == "HYSTERIA-OBFS" and .[0].tls.server_name == "hysteria.example.com" and
  (.[0].tls | has("certificate") | not)
' >/dev/null <<< "${hysteria_export}"

shadowtls_store_file=$(plain_proxy_structured_store_file shadowtls)
shadowtls_inbounds=$(render_structured_instance_inbounds shadowtls "${shadowtls_store_file}" | jq -s .)
jq -e '
  length == 2 and
  .[0].type == "shadowtls" and .[0].tag == "shadowtls-in" and
  .[0].listen == "127.0.0.1" and .[0].listen_port == 1092 and
  .[0].detour == "shadowtls-inner-main" and .[0].version == 3 and
  .[0].handshake.server == "shadowtls.example.com" and
  .[0].users[0].password == "SHADOWTLS-CONTRACT-PASSWORD" and
  .[0].strict_mode == false and .[0].wildcard_sni == "off" and
  .[1].type == "mixed" and .[1].tag == "shadowtls-inner-main" and
  .[1].listen == "127.0.0.1" and .[1].listen_port == 1093
' >/dev/null <<< "${shadowtls_inbounds}"
shadowtls_export=$(build_client_shadowtls_outbounds 127.0.0.1 | jq -s .)
jq -e '
  length == 1 and .[0].type == "shadowtls" and
  (.[0].tag | startswith("shadowtls-main-")) and
  .[0].server == "127.0.0.1" and .[0].server_port == 1092 and
  .[0].version == 3 and .[0].password == "SHADOWTLS-CONTRACT-PASSWORD" and
  .[0].tls.enabled == true and .[0].tls.server_name == "shadowtls.example.com" and
  (.[0].tls | has("certificate") | not)
' >/dev/null <<< "${shadowtls_export}"

# Unknown protocol and future schema must not disappear during reconciliation.
for invalid in $'INSTALLED_PROTOCOLS=mixed,future-protocol\nPROTOCOL_STATE_VERSION=1' \
  $'INSTALLED_PROTOCOLS=mixed\nPROTOCOL_STATE_VERSION=9'; do
  printf '%s\n' "${invalid}" > "${SB_PROTOCOL_INDEX_FILE}"
  cp "${SB_PROTOCOL_INDEX_FILE}" "${TEST_DIR}/index.before"
  for handler in reconcile_protocol_index_if_needed list_installed_protocols list_effective_protocols list_exportable_client_protocols rebuild_protocol_state_from_config; do
    if "${handler}" > "${TEST_DIR}/unknown.stdout" 2> "${TEST_DIR}/unknown.stderr"; then
      printf 'unknown state accepted by %s\n' "${handler}" >&2
      exit 1
    fi
    cmp "${SB_PROTOCOL_INDEX_FILE}" "${TEST_DIR}/index.before"
    [[ ! -s "${TEST_DIR}/unknown.stdout" ]]
  done
done
printf 'INSTALLED_PROTOCOLS=mixed\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
printf 'CONFIG_SCHEMA_VERSION=1\n' > "${SB_PROTOCOL_STATE_DIR}/future.env"
cp "${SB_PROTOCOL_INDEX_FILE}" "${TEST_DIR}/index.before"
if rebuild_protocol_state_from_config > /dev/null 2>&1; then
  printf 'unindexed unknown state was accepted for destructive rebuild\n' >&2
  exit 1
fi
cmp "${SB_PROTOCOL_INDEX_FILE}" "${TEST_DIR}/index.before"
[[ -f "${SB_PROTOCOL_STATE_DIR}/future.env" ]]
rm "${SB_PROTOCOL_STATE_DIR}/future.env"

printf '{"inbounds":[]}\n' > "${SINGBOX_CONFIG_FILE}"
mv "${SB_PROTOCOL_STATE_DIR}/mixed.env" "${TEST_DIR}/mixed.saved"
for handler in reconcile_protocol_index_if_needed list_installed_protocols; do
  if "${handler}" > "${TEST_DIR}/unknown.stdout" 2> "${TEST_DIR}/unknown.stderr"; then
    printf 'failed stale-index recovery was reported as success\n' >&2
    exit 1
  fi
  cmp "${SB_PROTOCOL_INDEX_FILE}" "${TEST_DIR}/index.before"
  [[ ! -s "${TEST_DIR}/unknown.stdout" ]]
done
for handler in reconcile_protocol_index_if_needed list_installed_protocols; do
  status=0
  (
    rebuild_protocol_state_from_config() { return 47; }
    "${handler}"
  ) > "${TEST_DIR}/unknown.stdout" 2> "${TEST_DIR}/unknown.stderr" || status=$?
  [[ "${status}" -eq 47 ]]
  cmp "${SB_PROTOCOL_INDEX_FILE}" "${TEST_DIR}/index.before"
done
mv "${TEST_DIR}/mixed.saved" "${SB_PROTOCOL_STATE_DIR}/mixed.env"

printf '{"inbounds":[{"type":"mixed","tag":"keep-mixed"}]}\n' > "${SINGBOX_CONFIG_FILE}"
mv "${SB_PROTOCOL_STATE_DIR}/mixed.env" "${TEST_DIR}/mixed.saved"
if reconcile_protocol_index_if_needed > /dev/null 2>&1; then
  printf 'a live inbound without state was dropped from the index\n' >&2
  exit 1
fi
cmp "${SB_PROTOCOL_INDEX_FILE}" "${TEST_DIR}/index.before"
mv "${TEST_DIR}/mixed.saved" "${SB_PROTOCOL_STATE_DIR}/mixed.env"
printf 'INSTALLED_PROTOCOLS=mixed\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
printf 'CONFIG_SCHEMA_VERSION=99\n' > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
if load_protocol_state mixed read-only > /dev/null 2>&1 || reconcile_protocol_index_if_needed > /dev/null 2>&1; then
  printf 'future per-protocol schema was accepted\n' >&2
  exit 1
fi

# A present handler with empty/wrong output must fail as firmly as a missing one.
build_mixed_inbound_json() { :; }
if append_protocol_fragment mixed inbound "${TEST_DIR}/fragments" 2>/dev/null; then
  printf 'empty inbound was accepted\n' >&2
  exit 1
fi
build_mixed_inbound_json() { printf '{"type":"vless","tag":"mixed-in"}\n'; }
if append_protocol_fragment mixed inbound "${TEST_DIR}/fragments" 2>/dev/null; then
  printf 'wrong inbound type was accepted\n' >&2
  exit 1
fi
build_mixed_inbound_json() { printf '{"type":"mixed","tag":"mixed-in"}\n'; }
append_protocol_fragment mixed inbound "${TEST_DIR}/fragments"
append_protocol_fragment mixed certificate "${TEST_DIR}/certificates"
[[ ! -s "${TEST_DIR}/certificates" || -z "$(tr -d '[:space:]' < "${TEST_DIR}/certificates")" ]]
build_protocol_route_rules() { :; }
if append_protocol_fragment mixed route "${TEST_DIR}/routes" 2>/dev/null; then
  printf 'missing route array was accepted\n' >&2
  exit 1
fi
unset -f build_mixed_inbound_json
if append_protocol_fragment mixed inbound "${TEST_DIR}/fragments" 2>/dev/null; then
  printf 'missing handler was accepted\n' >&2
  exit 1
fi

# Partial discovery output followed by failure must never become a live config.
printf '#!/usr/bin/env bash\nexit 91\n' > "${SINGBOX_BIN_PATH}"
chmod 700 "${SINGBOX_BIN_PATH}"
printf '{"preserve":"unknown-state"}\n' > "${SINGBOX_CONFIG_FILE}"
cp "${SINGBOX_CONFIG_FILE}" "${TEST_DIR}/config.before"
list_effective_protocols() { printf 'mixed\n'; return 23; }
ensure_warp_routing_assets() { touch "${SB_PROJECT_DIR}/unexpected-prepare"; }
if generate_config > "${TEST_DIR}/generate.stdout" 2> "${TEST_DIR}/generate.stderr"; then
  printf 'discovery failure published a partial configuration\n' >&2
  exit 1
fi
cmp "${SINGBOX_CONFIG_FILE}" "${TEST_DIR}/config.before"
[[ ! -e "${SB_PROJECT_DIR}/unexpected-prepare" && ! -e "${SINGBOX_CONFIG_FILE}.bak" ]]

printf 'protocol registry and fail-closed contracts passed\n'
