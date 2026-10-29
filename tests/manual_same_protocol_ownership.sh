#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
core=${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}
ln -s "${core}" "${TMP_DIR}/bin/sing-box"
source_testable_install
ensure_warp_routing_assets() { :; }
load_warp_route_settings() { :; }
refresh_warp_route_assets() {
  SB_WARP_CUSTOM_DOMAINS_JSON='[]' SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON='[]'
  SB_WARP_LOCAL_RULE_SETS_JSON='[]' SB_WARP_REMOTE_RULE_SETS_JSON='[]' SB_WARP_RULE_SET_TAGS_JSON='[]'
}
runtime=${SBV_MANUAL_OWNER_RUNTIME:-0}
server_pid="" http_pid=""
cleanup() {
  local pid
  for pid in "${server_pid}" "${http_pid}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}"
      wait "${pid}" || [[ $? == 143 ]]
    fi
  done
  rm -rf -- "${TMP_DIR}"
}
trap cleanup EXIT
trap 'printf "same-protocol test failure at line %s (%s)\n" "${LINENO}" "${protocol:-setup}" >&2' ERR
if [[ "${runtime}" == 1 ]]; then
  [[ -f /.dockerenv ]] || exit 64
  # The menu helper's hostname fixture is for node names, not networking.
  container_ip=$(/bin/hostname -I | awk '{print $1}')
  [[ -n "${container_ip}" && "${container_ip}" != 127.* ]]
  printf 'manual-ownership-transfer-ok\n' > "${TMP_DIR}/marker.txt"
  python3 -m http.server 19081 --bind 127.0.0.1 --directory "${TMP_DIR}" >"${TMP_DIR}/http.log" 2>&1 &
  http_pid=$!
fi
assert_manual_blocked() {
  if python3 - "${container_ip}" "${manual_port}" <<'PY'
import socket,sys
try:
    connection=socket.create_connection((sys.argv[1],int(sys.argv[2])),timeout=1)
    connection.close()
except TimeoutError:
    sys.exit(10)
PY
  then return 1; else [[ $? == 10 ]]; fi
}
offset=0
for protocol in mixed socks http; do
  rm -rf -- "${SB_PROJECT_DIR}"
  mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
  managed_port=$((18080 + offset)) manual_port=$((19090 + offset))
  offset=$((offset + 1))
  printf 'INSTALLED_PROTOCOLS=%s\nPROTOCOL_STATE_VERSION=1\n' "${protocol}" > "${SB_PROTOCOL_INDEX_FILE}"
  printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "$(protocol_state_file "${protocol}")"
  store=$(plain_proxy_structured_store_file "${protocol}")
  jq -n --arg protocol "${protocol}" --argjson port "${managed_port}" '
    {schema_version:1,protocol:$protocol,revision:1,default_instance_id:"main",instances:[
      ({id:"main",name:"Managed",tag:("owned-"+$protocol),listen:{address:"0.0.0.0",port:$port},
        authentication:{enabled:true,username:"fixture-user",password:"fixture-password"},
        outbound_policy:"direct",dependencies:[]} +
       if $protocol=="http" then {tls:{enabled:false}} else {} end)]}' > "${store}"
  chmod 600 "${store}"
  validate_structured_instance_store "${protocol}" "${store}"
  jq -n --arg protocol "${protocol}" --argjson managed "${managed_port}" --argjson manual "${manual_port}" '
    {inbounds:[{type:$protocol,tag:("owned-"+$protocol),listen:"0.0.0.0",listen_port:$managed,
      users:[{username:"fixture-user",password:"fixture-password"}]},
      {type:$protocol,tag:("manual-"+$protocol),listen:"0.0.0.0",listen_port:$manual}],
      outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct",rules:[
        {inbound:("owned-"+$protocol),action:"sniff"},
        {inbound:("owned-"+$protocol),action:"route",outbound:"direct"}]}}' > "${SINGBOX_CONFIG_FILE}"
  "${core}" check -c "${SINGBOX_CONFIG_FILE}"
  manual=$(jq -c '.inbounds[1]' "${SINGBOX_CONFIG_FILE}")
  manual_client_inbound_is_unmanaged "${manual}"
  [[ "$(config_protocol_inbound_count "${protocol}")" == 1 ]]
  plain_proxy_validate_state_inventory "${protocol}" || { printf 'initial inventory failed: %s\n' "${protocol}" >&2; exit 1; }
  if [[ "${runtime}" == 1 ]]; then
    "${core}" run -c "${SINGBOX_CONFIG_FILE}" >"${TMP_DIR}/${protocol}.log" 2>&1 &
    server_pid=$!
    for ((attempt=0; attempt<50; attempt++)); do
      if ss -ltn | grep -Fq "0.0.0.0:${manual_port}"; then break; fi
      sleep 0.1
    done
    ss -ltn | grep -Fq "0.0.0.0:${manual_port}"
    iptables -I INPUT -d "${container_ip}/32" -p tcp --dport "${manual_port}" -j DROP
    assert_manual_blocked
  fi
  cp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/before-${protocol}.json"
  rebuild_protocol_state_from_config
  cmp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/before-${protocol}.json"
  jq -e --arg tag "owned-${protocol}" '.instances|length==1 and .[0].tag==$tag' "${store}" >/dev/null
  plain_proxy_validate_state_inventory "${protocol}" || { printf 'rebuilt inventory failed: %s\n' "${protocol}" >&2; exit 1; }
  generate_config >"${TMP_DIR}/generate-${protocol}.log"
  "${core}" check -c "${SINGBOX_CONFIG_FILE}"
  [[ "$(jq -c --arg tag "manual-${protocol}" '.inbounds[]|select(.tag==$tag)' "${SINGBOX_CONFIG_FILE}")" == "${manual}" ]]
  plan=$(instance_firewall_plan_file "${SINGBOX_CONFIG_FILE}")
  jq -e --arg tag "manual-${protocol}" 'all(.[]; .owner!=$tag)' <<< "${plan}" >/dev/null
  if [[ "${runtime}" == 1 ]]; then
    journal="${TMP_DIR}/firewall-${protocol}.json"
    instance_firewall_prepare "${TMP_DIR}/before-${protocol}.json" "${SINGBOX_CONFIG_FILE}" "${journal}"
    instance_firewall_apply "${journal}"
    instance_firewall_commit "${journal}"
    assert_manual_blocked
    iptables -C INPUT -d "${container_ip}/32" -p tcp --dport "${manual_port}" -j DROP
    jq -e --arg tag "manual-${protocol}" 'all(.rules[].refs[]?; .owner!=$tag)' "${INSTANCE_FIREWALL_LEDGER_FILE}" >/dev/null
    scheme=http
    [[ "${protocol}" != socks ]] || scheme=socks5h
    curl --silent --show-error --fail --max-time 5 --noproxy '' \
      --proxy "${scheme}://${container_ip}:${managed_port}" --proxy-user fixture-user:fixture-password \
      http://127.0.0.1:19081/marker.txt > "${TMP_DIR}/transfer-${protocol}"
    cmp "${TMP_DIR}/marker.txt" "${TMP_DIR}/transfer-${protocol}"
    kill "${server_pid}"
    wait "${server_pid}" || [[ $? == 143 ]]
    server_pid=""
  fi
  printf 'protocol=%s owned=1 manual-excluded=yes runtime=%s\n' "${protocol}" "${runtime}"
done
# A singleton legacy Mixed state owns its reserved tag, not every Mixed
# listener. Capturing this before state clearing must also retain the manual tag.
rm -rf -- "${SB_PROJECT_DIR}"
mkdir -p "${SB_PROTOCOL_STATE_DIR}"
printf 'INSTALLED_PROTOCOLS=mixed\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=1\nNODE_NAME=legacy\nPORT=18083\nAUTH_ENABLED=y\nUSERNAME=fixture-user\nPASSWORD=fixture-password\n' > "$(protocol_state_file mixed)"
jq -n '{inbounds:[{type:"mixed",tag:"mixed-in",listen:"0.0.0.0",listen_port:18083,
  users:[{username:"fixture-user",password:"fixture-password"}]},
  {type:"mixed",tag:"manual-legacy",listen:"0.0.0.0",listen_port:19093}],
  outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct",rules:[]}}' > "${SINGBOX_CONFIG_FILE}"
manual_client_inbound_is_unmanaged "$(jq -c '.inbounds[1]' "${SINGBOX_CONFIG_FILE}")"
[[ "$(config_protocol_inbound_count mixed)" == 1 ]]
cp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/legacy.before.json"
rebuild_protocol_state_from_config
cmp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/legacy.before.json"
[[ "$(config_protocol_inbound_count mixed)" == 1 ]]
if [[ -f "$(mixed_structured_store_file)" ]]; then
  jq -e 'all(.instances[]; .tag!="manual-legacy")' "$(mixed_structured_store_file)" >/dev/null
fi
instance_firewall_plan_file "${SINGBOX_CONFIG_FILE}" | jq -e 'all(.[]; .owner!="manual-legacy")' >/dev/null
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
printf 'Same-protocol manual ownership: typed Mixed/SOCKS/HTTP and legacy Mixed rebuild/inventory/firewall exclusions passed; runtime=%s\n' "${runtime}"
