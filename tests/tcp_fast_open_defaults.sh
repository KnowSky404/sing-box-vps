#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"
source "${REPO_ROOT}/dev/verification/remote/scenarios/protocol_cases.sh"
trap 'printf "TFO defaults failed at line %s, protocol=%s\n" "${LINENO}" "${protocol:-unset}" >&2' ERR
core=${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}
ln -s "${core}" "${SINGBOX_BIN_PATH}"
cert_path="${TMP_DIR}/tls.pem"; key_path="${TMP_DIR}/tls.key"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=sing-box-vps-verification.invalid   -addext subjectAltName=DNS:sing-box-vps-verification.invalid   -keyout "${key_path}" -out "${cert_path}" > "${TMP_DIR}/openssl.log" 2>&1
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
set_protocol_defaults vless-reality
[[ "${SB_VLESS_TCP_FAST_OPEN}" == y ]]
SB_SNI=www.example.com
build_vless_inbound_json_from_current_state | jq -s '{inbounds:.}' > "${TMP_DIR}/reality.json"
jq -e '.inbounds[0].tcp_fast_open==true' "${TMP_DIR}/reality.json" >/dev/null
"${core}" check -c "${TMP_DIR}/reality.json"

for protocol in mixed socks http shadowsocks trojan vmess vless-plain anytls snell naive shadowtls hy2 tuic; do
  record="${TMP_DIR}/record.json"; store="${SB_PROTOCOL_STATE_DIR}/instances/${protocol}.json"
  if [[ "${protocol}" == vless-plain ]]; then
    verification_protocol_record vmess | jq '.tag="plain-vless-in" | .transport={type:"none"} |
      .authentication.users |= map(del(.alter_id,.security) + {flow:""})' > "${record}"
  elif [[ "${protocol}" == trojan || "${protocol}" == vmess ]]; then
    verification_protocol_record "${protocol}" | jq '.transport={type:"none"}' > "${record}"
  else verification_protocol_record "${protocol}" > "${record}"; fi
  structured_instance_store_candidate "${protocol}" '' create "${record}" 0 > "${store}"
  chmod 600 "${store}"
  expected=true; [[ "${protocol}" != hy2 && "${protocol}" != tuic ]] || expected=false
  jq -e --argjson expected "${expected}" '(.instances[0].listen.tcp_fast_open==true)==$expected' "${store}" >/dev/null
  render_structured_instance_inbounds "${protocol}" "${store}" | jq -s     '{inbounds:.,outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' > "${TMP_DIR}/server.json"
  "${core}" check -c "${TMP_DIR}/server.json"
  save_plain_proxy_structured_marker "${protocol}"
  plain_proxy_config_store_candidate "${protocol}" "${TMP_DIR}/server.json" "${store}" > "${TMP_DIR}/import.json"
  jq -e -s '.[0].instances==.[1].instances' "${store}" "${TMP_DIR}/import.json" >/dev/null
  SB_PROTOCOL=''
  build_client_outbound_json_for_protocol "${protocol}" 127.0.0.1 | jq -s '{outbounds:.}' > "${TMP_DIR}/client.json"
  "${core}" check -c "${TMP_DIR}/client.json"
  client_expected=${expected}; [[ "${protocol}" != anytls ]] || client_expected=false
  jq -e --argjson expected "${client_expected}" 'all(.outbounds[]; (.tcp_fast_open==true)==$expected)' "${TMP_DIR}/client.json" >/dev/null

  case "${protocol}" in
    snell|naive|shadowtls|vmess|vless-plain)
      builder="build_client_${protocol//-/_}_outbounds"
      "${builder}" 127.0.0.1 | jq -s '{outbounds:.}' > "${TMP_DIR}/direct-client.json"
      jq -e 'all(.outbounds[]; .tcp_fast_open==true)' "${TMP_DIR}/direct-client.json" >/dev/null
      "${core}" check -c "${TMP_DIR}/direct-client.json"
      if [[ "${protocol}" == shadowtls ]]; then
        build_client_shadowtls_bundle_json 127.0.0.1 | jq -e 'all(.outbounds[]; .tcp_fast_open==true)' >/dev/null
      fi
      ;;
  esac

  # Explicit false survives create, replacement from a menu record, render and takeover.
  if [[ "${expected}" == true ]]; then
    jq '.listen.tcp_fast_open=false | if has("detour") then .detour.listen.tcp_fast_open=false else . end' "${record}" > "${TMP_DIR}/off.json"
    structured_instance_store_candidate "${protocol}" '' create "${TMP_DIR}/off.json" 0 > "${TMP_DIR}/off-store.json"
    structured_instance_store_candidate "${protocol}" "${TMP_DIR}/off-store.json" replace "${record}" 1 > "${TMP_DIR}/replaced.json"
    jq -e '.revision==1 and .instances[0].listen.tcp_fast_open==false' "${TMP_DIR}/replaced.json" >/dev/null
    render_structured_instance_inbounds "${protocol}" "${TMP_DIR}/replaced.json" | jq -s '{inbounds:.}' > "${TMP_DIR}/off-config.json"
    "${core}" check -c "${TMP_DIR}/off-config.json"
    jq -e 'all(.inbounds[]; .tcp_fast_open==false)' "${TMP_DIR}/off-config.json" >/dev/null
    plain_proxy_config_store_candidate "${protocol}" "${TMP_DIR}/off-config.json" "${TMP_DIR}/replaced.json" > "${TMP_DIR}/off-import.json"
    jq -e '.instances[0].listen.tcp_fast_open==false' "${TMP_DIR}/off-import.json" >/dev/null
  fi
  printf 'TFO create/replace/import/server/client: %s passed\n' "${protocol}"
done
# No default on QUIC transports or UDP-only network variants.
for protocol in trojan vmess shadowsocks naive; do
  verification_protocol_record "${protocol}" > "${record}"
  if [[ "${protocol}" == shadowsocks || "${protocol}" == naive ]]; then
    jq '.listen.network=["udp"]' "${record}" > "${TMP_DIR}/udp.json"; cp "${TMP_DIR}/udp.json" "${record}"
  fi
  structured_instance_store_candidate "${protocol}" '' create "${record}" 0 > "${TMP_DIR}/excluded.json"
  jq -e '.instances[0].listen | has("tcp_fast_open")|not' "${TMP_DIR}/excluded.json" >/dev/null
done
# Legacy absence remains absent on replace; invalid boolean input is rejected.
verification_protocol_record socks > "${record}"
jq -n --slurpfile record "${record}" '{schema_version:1,protocol:"socks",revision:1,default_instance_id:"main",instances:$record}' > "${TMP_DIR}/legacy.json"
structured_instance_store_candidate socks "${TMP_DIR}/legacy.json" replace "${record}" 1 > "${TMP_DIR}/legacy-next.json"
jq -e '.revision==1 and (.instances[0].listen|has("tcp_fast_open")|not)' "${TMP_DIR}/legacy-next.json" >/dev/null
jq '.listen.tcp_fast_open="true"' "${record}" > "${TMP_DIR}/invalid.json"
if structured_instance_store_candidate socks '' create "${TMP_DIR}/invalid.json" 0 > /dev/null 2>&1; then exit 1; fi
printf 'TFO defaults, explicit false, legacy absence and UDP/QUIC exclusions passed\n'
