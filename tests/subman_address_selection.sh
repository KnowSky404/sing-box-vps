#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

CHECK_COUNT=0
FAILURE_COUNT=0
PUBLIC_IPV4=203.0.113.10
PUBLIC_IPV6=2001:db8::10
PUSHES_FILE="${TMP_DIR}/pushes.jsonl"
DELETES_FILE="${TMP_DIR}/deletes"

get_public_ipv4() {
  [[ -n "${PUBLIC_IPV4}" ]] || return 1
  printf '%s\n' "${PUBLIC_IPV4}"
}

get_public_ipv6() {
  [[ -n "${PUBLIC_IPV6}" ]] || return 1
  printf '%s\n' "${PUBLIC_IPV6}"
}

detect_host_ip_stack() { printf dual; }
curl() { printf 'unexpected network request in address-selection test\n' >&2; return 99; }

check() {
  local label=$1
  shift
  CHECK_COUNT=$((CHECK_COUNT + 1))
  if ! "$@" >/dev/null; then
    printf 'FAIL %s\n' "${label}" >&2
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
  fi
}

expect_selection() {
  local label=$1 expected=$2 expected_status=${3:-success} actual status=0
  actual=$(list_subman_addresses_for_current_protocol) || status=$?
  CHECK_COUNT=$((CHECK_COUNT + 1))
  if [[ "${actual}" != "${expected}" ]] ||
    [[ "${expected_status}" == success && "${status}" -ne 0 ]] ||
    [[ "${expected_status}" == failure && "${status}" -eq 0 ]]; then
    printf 'FAIL %s: addresses=%q status=%s\n' "${label}" "${actual}" "${status}" >&2
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
  fi
}

# Keep the real selector and public-IP orchestration while isolating only the
# structured-state presence check for this address-family truth table.
declare -f plain_proxy_structured_state_active > "${TMP_DIR}/real-structured-check.sh"
plain_proxy_structured_state_active() { [[ "${FIXTURE_STRUCTURED}" == yes ]]; }
FIXTURE_STRUCTURED=yes
SB_OUTBOUND_STACK_MODE=prefer_ipv4
for protocol in vmess trojan shadowsocks vless-plain hy2; do
  SB_PROTOCOL=${protocol}
  for mode in ipv4_only ipv6_only dual_stack; do
    SB_INBOUND_STACK_MODE=${mode}
    SB_MIXED_LISTEN_ADDRESS=0.0.0.0
    expect_selection "${protocol} IPv4 wildcard with ${mode}" 'IPv4|203.0.113.10'
    SB_MIXED_LISTEN_ADDRESS=::
    expect_selection "${protocol} IPv6 wildcard with ${mode}" $'IPv4|203.0.113.10\nIPv6|2001:db8::10'
  done
  SB_MIXED_LISTEN_ADDRESS=0:0:0:0:0:0:0:0
  expect_selection "${protocol} expanded IPv6 wildcard" $'IPv4|203.0.113.10\nIPv6|2001:db8::10'
  SB_MIXED_LISTEN_ADDRESS=2001:db8::20
  expect_selection "${protocol} concrete IPv6 listener" '监听地址|2001:db8::20'
  SB_MIXED_LISTEN_ADDRESS=198.51.100.20
  expect_selection "${protocol} concrete IPv4 listener" '监听地址|198.51.100.20'
  PUBLIC_IPV4=''
  SB_MIXED_LISTEN_ADDRESS=0.0.0.0
  expect_selection "${protocol} IPv4 wildcard cannot use available IPv6" '' failure
  PUBLIC_IPV4=203.0.113.10
done

FIXTURE_STRUCTURED=no
for protocol in vless+reality hy2; do
  SB_PROTOCOL=${protocol}
  SB_INBOUND_STACK_MODE=ipv4_only
  expect_selection "legacy ${protocol} IPv4-only selection" 'IPv4|203.0.113.10'
  SB_INBOUND_STACK_MODE=ipv6_only
  expect_selection "legacy ${protocol} IPv6-only selection" 'IPv6|2001:db8::10'
  SB_INBOUND_STACK_MODE=dual_stack
  expect_selection "legacy ${protocol} dual-stack selection" $'IPv4|203.0.113.10\nIPv6|2001:db8::10'
  PUBLIC_IPV6=''
  SB_INBOUND_STACK_MODE=ipv6_only
  expect_selection "legacy ${protocol} IPv6-only cannot fall back to IPv4" '' failure
  PUBLIC_IPV6=2001:db8::10
  PUBLIC_IPV4=''
  SB_INBOUND_STACK_MODE=ipv4_only
  expect_selection "legacy ${protocol} IPv4-only cannot fall back to IPv6" '' failure
  SB_INBOUND_STACK_MODE=dual_stack
  expect_selection "legacy ${protocol} dual-stack retains available IPv6" 'IPv6|2001:db8::10'
  PUBLIC_IPV4=203.0.113.10
done
# shellcheck disable=SC1090
source "${TMP_DIR}/real-structured-check.sh"

# Exercise the real typed stores, loader, selector, URI producer, per-user keys
# and protocol workers together. Only the final API write is mocked.
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "${TMP_DIR}/hy2.key" \
  -out "${TMP_DIR}/hy2.crt" -subj /CN=hy2.example -days 1 >/dev/null 2>&1
for protocol in vmess hy2; do
  state_file="${SB_PROTOCOL_STATE_DIR}/${protocol}.env"
  store_file="${SB_PROTOCOL_STATE_DIR}/instances/${protocol}.json"
  printf '%s\n' INSTALLED=1 CONFIG_SCHEMA_VERSION=2 > "${state_file}"
  jq -n --arg protocol "${protocol}" --arg certificate "${TMP_DIR}/hy2.crt" \
    --arg key "${TMP_DIR}/hy2.key" '
    {schema_version:1,protocol:$protocol,revision:1,default_instance_id:"v4",instances:[
      {id:"v4",address:"0.0.0.0",port:33601},
      {id:"dual",address:"::",port:33602},
      {id:"expanded",address:"0:0:0:0:0:0:0:0",port:33603},
      {id:"bound",address:"2001:db8::20",port:33604}
    ] | map(. as $entry |
      {id:$entry.id,name:($protocol + " " + $entry.id),tag:($protocol + "-" + $entry.id),
       listen:{address:$entry.address,port:$entry.port},
       authentication:{users:[
         if $protocol=="vmess" then
           {name:"alice",uuid:"11111111-1111-4111-8111-111111111111",alter_id:0,security:"auto"}
         else {name:"alice",password:"test-password"} end]},
       tls:{enabled:true,server_name:($protocol + ".example"),certificate_path:$certificate,key_path:$key},
       client_trust:"system",outbound_policy:"default",dependencies:[]}
       + (if $protocol=="vmess" then {transport:{type:"none"}}
          else {bandwidth:{up_mbps:null,down_mbps:null},obfs:{enabled:false,type:"",password:""},masquerade:""} end))}
  ' > "${store_file}"
  chmod 600 "${state_file}" "${store_file}"
  validate_structured_instance_store "${protocol}" "${store_file}"
  save_plain_proxy_structured_marker "${protocol}"
done
SUBMAN_NODE_PREFIX=address-test
push_subman_node() {
  jq -cn --arg key "$1" --argjson payload "$2" '{key:$key,payload:$payload}' >> "${PUSHES_FILE}"
}
delete_subman_node_by_external_key() { printf '%s\n' "$1" >> "${DELETES_FILE}"; }

# Capture the actual outbound bytes that feed each raw URI. This preserves the
# real producer and lets the optional pinned core validate the selected v4/v6
# configurations without invoking the expensive typed-store render twice.
declare -f build_vmess_client_outbounds_from_store | \
  sed '1s/^build_vmess_client_outbounds_from_store /original_build_vmess_client_outbounds_from_store /' \
  > "${TMP_DIR}/real-outbound-builders.sh"
declare -f build_client_hy2_outbounds | \
  sed '1s/^build_client_hy2_outbounds /original_build_client_hy2_outbounds /' \
  >> "${TMP_DIR}/real-outbound-builders.sh"
# shellcheck disable=SC1090
source "${TMP_DIR}/real-outbound-builders.sh"
build_vmess_client_outbounds_from_store() {
  local output
  output=$(original_build_vmess_client_outbounds_from_store "$@") || return $?
  printf '%s\n' "${output}" >> "${TMP_DIR}/vmess-generated.jsonl" || return 1
  printf '%s\n' "${output}"
}
build_client_hy2_outbounds() {
  local output
  output=$(original_build_client_hy2_outbounds "$@") || return $?
  printf '%s\n' "${output}" >> "${TMP_DIR}/hy2-generated.jsonl" || return 1
  printf '%s\n' "${output}"
}

if [[ -n "${SINGBOX_BINARY_114:-}" ]]; then
  core_version=$("${SINGBOX_BINARY_114}" version)
  printf 'Generated client checks: %s\n' "${core_version%%$'\n'*}"
fi

for protocol in vmess hy2; do
  : > "${PUSHES_FILE}"
  : > "${TMP_DIR}/${protocol}-generated.jsonl"
  SB_INBOUND_STACK_MODE=ipv6_only
  check "${protocol} typed protocol worker succeeds" "push_subman_${protocol}_protocol" y
  check "${protocol} typed stores produce six eligible nodes" \
    jq -es 'length==6' "${PUSHES_FILE}"
  check "${protocol} wildcard names and keys distinguish address families" \
    jq -es '
      (map(select(.key|contains(":v4:user-"))) | length)==1 and
      (map(select(.key|contains(":dual:user-"))) | length)==2 and
      (map(select(.key|contains(":expanded:user-"))) | length)==2 and
      all(.[] | select(.key|test(":(v4|dual|expanded):user-"));
        if (.key|endswith(":v4")) then (.payload.name|endswith("-v4"))
        elif (.key|endswith(":v6")) then (.payload.name|endswith("-v6")) else false end) and
      all(.[] | select(.key|contains(":bound:user-"));
        (.key|test(":v[46]$")|not) and (.payload.name|test("-v[46]$")|not))
    ' "${PUSHES_FILE}"
  if [[ "${protocol}" == hy2 ]]; then
    check 'HY2 raw URI keeps SNI while selecting eligible IPs' jq -es '
      all(.[]; (.payload.raw|contains("sni=hy2.example"))) and
      (map(select(.key|contains(":v4:user-"))) | all(.[]; .payload.raw|contains("@203.0.113.10:"))) and
      (map(select(.key|contains(":dual:user-") or contains(":expanded:user-"))) |
        any(.[]; .payload.raw|contains("@[2001:db8::10]:"))) and
      (map(select(.key|contains(":bound:user-"))) | all(.[]; .payload.raw|contains("@[2001:db8::20]:")))
    ' "${PUSHES_FILE}"
  else
    decoded_file="${TMP_DIR}/vmess-decoded.jsonl"
    : > "${decoded_file}"
    while IFS= read -r raw; do
      encoded=${raw#vmess://}
      encoded=${encoded//-/+}
      encoded=${encoded//_/\/}
      while (( ${#encoded} % 4 != 0 )); do encoded="${encoded}="; done
      printf '%s' "${encoded}" | base64 --decode >> "${decoded_file}"
      printf '\n' >> "${decoded_file}"
    done < <(jq -r '.payload.raw' "${PUSHES_FILE}")
    check 'VMess IP selection keeps SNI' jq -es '
      length==6 and all(.[]; .sni=="vmess.example") and
      any(.[]; .add=="203.0.113.10") and any(.[]; .add=="2001:db8::10") and
      any(.[]; .add=="2001:db8::20")
    ' "${decoded_file}"
  fi
  check "${protocol} captures actual selected-IP outbounds with unchanged SNI" \
    jq -es --arg sni "${protocol}.example" '
      length==6 and all(.[]; .tls.server_name==$sni) and
      any(.[]; .server=="203.0.113.10") and any(.[]; .server=="2001:db8::10") and
      any(.[]; .server=="2001:db8::20")
    ' "${TMP_DIR}/${protocol}-generated.jsonl"
  if [[ -n "${SINGBOX_BINARY_114:-}" ]]; then
    candidate_number=0
    while IFS= read -r outbound; do
      candidate_number=$((candidate_number + 1))
      candidate_file="${TMP_DIR}/${protocol}-client-${candidate_number}.json"
      printf '{"outbounds":[%s]}\n' "${outbound}" > "${candidate_file}"
      check "${protocol} selected-IP client candidate ${candidate_number} passes sing-box check" \
        "${SINGBOX_BINARY_114}" check -c "${candidate_file}"
    done < "${TMP_DIR}/${protocol}-generated.jsonl"
  fi
done

# A missing eligible REALITY address must survive aggregation when another
# protocol succeeds, and must never authorize deleting the legacy REALITY key.
cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME='address-reality'
PORT=443
UUID='11111111-1111-4111-8111-111111111111'
SNI='reality.example'
REALITY_PRIVATE_KEY='private-key'
REALITY_PUBLIC_KEY='public-key'
SHORT_ID_1='abcd1234'
SHORT_ID_2='dcba4321'
EOF
chmod 600 "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
vmess_store="${SB_PROTOCOL_STATE_DIR}/instances/vmess.json"
jq '.default_instance_id="bound" | .instances |= map(select(.id=="bound"))' \
  "${vmess_store}" > "${TMP_DIR}/vmess-bound.json"
cat "${TMP_DIR}/vmess-bound.json" > "${vmess_store}"
save_plain_proxy_structured_marker vmess
write_protocol_index 'vless-reality,vmess'
prompt_subman_config_if_needed() { SUBMAN_NODE_PREFIX=address-test; }
PUBLIC_IPV6=''
SB_INBOUND_STACK_MODE=ipv6_only
load_protocol_state vmess
for interface in menu agent; do
  : > "${PUSHES_FILE}"
  : > "${DELETES_FILE}"
  status=0
  if [[ "${interface}" == menu ]]; then
    result=$(push_nodes_to_subman 2>&1) || status=$?
    check 'menu reports failed REALITY selection alongside a successful VMess push' \
      test "${status}" -ne 0
    check 'menu keeps explicit partial-success counts' \
      test "${result#*已同步: 1，已跳过: 0，失败: 1}" != "${result}"
  else
    result=$(agent_push_nodes_to_subman_json) || status=$?
    check 'Agent reports failed REALITY selection alongside successful VMess push' \
      test "${status}" -ne 0
    check 'Agent keeps explicit partial-success counts' jq -e \
      '.ok==false and .synced==1 and .skipped==0 and .failed==1' <<< "${result}"
  fi
  check "${interface} never pushes an ineligible REALITY address" jq -es \
    'length==1 and all(.[]; .payload.type=="vmess")' "${PUSHES_FILE}"
  check "${interface} never deletes REALITY keys after selection failure" test ! -s "${DELETES_FILE}"
done

if [[ "${FAILURE_COUNT}" -gt 0 ]]; then
  printf 'SubMan address selection checks: %s/%s failed\n' "${FAILURE_COUNT}" "${CHECK_COUNT}" >&2
  exit 1
fi
if [[ -z "${SINGBOX_BINARY_114:-}" ]]; then
  printf 'sing-box check not run: set SINGBOX_BINARY_114 to the supported core\n'
fi
printf 'SubMan address selection checks passed (%s cases)\n' "${CHECK_COUNT}"
