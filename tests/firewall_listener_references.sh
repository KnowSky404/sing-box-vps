#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"
trap 'printf "firewall reference test failed at line %s\n" "${LINENO}" >&2' ERR

# These are backend call-contract tests. Never invoke a host firewall backend.
BACKEND_LOG="${TMP_DIR}/backends.log"
mkdir -p "${SB_PROTOCOL_STATE_DIR}"
: > "${BACKEND_LOG}"
ufw() {
  if [[ "$1" == status ]]; then printf 'Status: active\n'; return 0; fi
  printf 'ufw %s\n' "$*" >> "${BACKEND_LOG}"
  return "${UFW_FAILURE:-0}"
}
firewall-cmd() {
  [[ "$1" != --state ]] || return 0
  printf 'firewalld %s\n' "$*" >> "${BACKEND_LOG}"
  return "${FIREWALLD_FAILURE:-0}"
}
iptables() {
  printf 'iptables %s\n' "$*" >> "${BACKEND_LOG}"
  if [[ "$1" == -C ]]; then return "${IPTABLES_CHECK_STATUS:-0}"; fi
  return "${IPTABLES_DELETE_STATUS:-0}"
}
systemctl() {
  [[ "$1" == show ]] || return 97
  [[ "${SERVICE_SHOW_STATUS:-0}" == 0 ]] || return "${SERVICE_SHOW_STATUS}"
  printf '%s\n' "${SERVICE_STATE:-inactive}"
}
config() {
  jq -cn --argjson items "$1" '{inbounds:$items}' > "$2"
}
reject_cleanup() {
  local status
  : > "${BACKEND_LOG}"
  if close_firewall_port "$@" > "${TMP_DIR}/out" 2> "${TMP_DIR}/err"; then
    printf 'expected cleanup rejection\n' >&2; return 1
  else status=$?; fi
  [[ ! -s "${BACKEND_LOG}" && -s "${TMP_DIR}/err" ]]
  ! grep -Fq 'private-tag' "${TMP_DIR}/err"
  return 0
}

tcp='{"type":"mixed","tag":"private-tag-a","listen":"127.0.0.1","listen_port":32100}'
udp='{"type":"hysteria2","tag":"private-tag-b","listen":"127.0.0.1","listen_port":32100}'
other_tcp='{"type":"vless","tag":"private-tag-c","listen":"127.0.0.2","listen_port":32100}'
config "[${tcp},${udp}]" "${SINGBOX_CONFIG_FILE}.bak"
config "[${udp}]" "${SINGBOX_CONFIG_FILE}"
close_firewall_port 32100 >/dev/null
grep -Fqx 'ufw delete allow 32100/tcp' "${BACKEND_LOG}"
grep -Fqx 'firewalld --permanent --remove-port=32100/tcp' "${BACKEND_LOG}"
grep -Fqx 'iptables -D INPUT -p tcp --dport 32100 -j ACCEPT' "${BACKEND_LOG}"
! grep -q udp "${BACKEND_LOG}"

# Broad rules remain referenced even if only a different address still uses it.
: > "${BACKEND_LOG}"
config "[${tcp},${other_tcp}]" "${SINGBOX_CONFIG_FILE}.bak"
config "[${other_tcp}]" "${SINGBOX_CONFIG_FILE}"
close_firewall_port 32100 >/dev/null
[[ ! -s "${BACKEND_LOG}" ]]

# Removing TCP does not clean a UDP rule that never belonged to that listener.
: > "${BACKEND_LOG}"
config "[${tcp}]" "${SINGBOX_CONFIG_FILE}.bak"
config '[]' "${SINGBOX_CONFIG_FILE}"
close_firewall_port 32100 >/dev/null
grep -q 'iptables -D.*tcp' "${BACKEND_LOG}"
! grep -q udp "${BACKEND_LOG}"
: > "${BACKEND_LOG}"
close_firewall_port 32101 >/dev/null
[[ ! -s "${BACKEND_LOG}" ]]

: > "${BACKEND_LOG}"
config "[${tcp},${udp}]" "${SINGBOX_CONFIG_FILE}.bak"
config "[${tcp}]" "${SINGBOX_CONFIG_FILE}"
close_firewall_port 32100 >/dev/null
grep -q 'iptables -D.*udp' "${BACKEND_LOG}"
! grep -q tcp "${BACKEND_LOG}"

config '[{"type":"unknown","tag":"private-tag","listen_port":32100}]' "${SINGBOX_CONFIG_FILE}"
reject_cleanup 32100
printf 'not json private-tag\n' > "${SINGBOX_CONFIG_FILE}"
reject_cleanup 32100
rm -f "${SINGBOX_CONFIG_FILE}"
reject_cleanup 32100
printf 'INSTALLED_PROTOCOLS=mixed\n' > "${SB_PROTOCOL_INDEX_FILE}"
reject_cleanup 32100 all_removed
rm -f "${SB_PROTOCOL_INDEX_FILE}"
SERVICE_STATE=active
reject_cleanup 32100 all_removed
unset SERVICE_STATE
SERVICE_SHOW_STATUS=47
reject_cleanup 32100 all_removed
unset SERVICE_SHOW_STATUS
: > "${BACKEND_LOG}"
close_firewall_port 32100 all_removed >/dev/null
grep -q 'iptables -D.*udp' "${BACKEND_LOG}"
grep -q 'iptables -D.*tcp' "${BACKEND_LOG}"
rm -f "${SINGBOX_CONFIG_FILE}.bak"
reject_cleanup 32100 all_removed

# Open and cleanup use the same registered fixed-transport set. No new broad
# opposite-transport rules are created and left behind by TCP-only/UDP-only
# listener removal. Pre-existing unowned legacy extras cannot be inferred.
for protocol in mixed vless-reality anytls hy2; do
  : > "${BACKEND_LOG}"
  IPTABLES_CHECK_STATUS=1
  open_firewall_port 32100 "${protocol}" >/dev/null
  unset IPTABLES_CHECK_STATUS
  if [[ "${protocol}" == hy2 ]]; then
    type=hysteria2; network=udp; opposite=tcp
  else
    network=tcp; opposite=udp
    if [[ "${protocol}" == vless-reality ]]; then type=vless; else type=${protocol}; fi
  fi
  config "[{\"type\":\"${type}\",\"tag\":\"removed\",\"listen_port\":32100}]" "${SINGBOX_CONFIG_FILE}.bak"
  config '[]' "${SINGBOX_CONFIG_FILE}"
  close_firewall_port 32100 >/dev/null
  grep -Fqx "ufw allow 32100/${network}" "${BACKEND_LOG}"
  grep -Fqx "ufw delete allow 32100/${network}" "${BACKEND_LOG}"
  grep -Fqx "iptables -I INPUT -p ${network} --dport 32100 -j ACCEPT" "${BACKEND_LOG}"
  grep -Fqx "iptables -D INPUT -p ${network} --dport 32100 -j ACCEPT" "${BACKEND_LOG}"
  ! grep -q "${opposite}" "${BACKEND_LOG}"
done

# Raw backend statuses propagate; diagnostics never pretend a partial external
# mutation has rolled back just because files could be restored.
config "[${tcp}]" "${SINGBOX_CONFIG_FILE}.bak"
config '[]' "${SINGBOX_CONFIG_FILE}"
for fault in UFW_FAILURE FIREWALLD_FAILURE IPTABLES_CHECK_STATUS IPTABLES_DELETE_STATUS; do
  printf -v "${fault}" 47
  if close_firewall_port 32100 > "${TMP_DIR}/out" 2> "${TMP_DIR}/err"; then
    printf 'expected backend failure\n' >&2; exit 1
  else status=$?; fi
  [[ ${status} == 47 ]]
  grep -Fq 'external_state_may_be_partial' "${TMP_DIR}/err"
  unset "${fault}"
done
IPTABLES_CHECK_STATUS=1
: > "${BACKEND_LOG}"
close_firewall_port 32100 >/dev/null
! grep -q 'iptables -D' "${BACKEND_LOG}"
unset IPTABLES_CHECK_STATUS

# The real collector reads the complete committed config, not a lossy first
# state/instance. It does not change the active protocol or regenerate state.
config "[${tcp},${udp},${other_tcp}]" "${SINGBOX_CONFIG_FILE}"
: > "${BACKEND_LOG}"
original_protocol=${SB_PROTOCOL}
open_all_protocol_ports >/dev/null
[[ "${SB_PROTOCOL}" == "${original_protocol}" ]]
grep -Fqx 'ufw allow 32100/tcp' "${BACKEND_LOG}"
grep -Fqx 'ufw allow 32100/udp' "${BACKEND_LOG}"
UFW_FAILURE=47
if open_committed_protocol_ports > "${TMP_DIR}/out" 2> "${TMP_DIR}/err"; then
  printf 'expected committed apply failure\n' >&2; exit 1
else status=$?; fi
[[ ${status} == 47 ]]
grep -Fq 'config_committed; firewall_may_be_partial; service_restart_not_attempted' "${TMP_DIR}/err"
unset UFW_FAILURE

# Test-only dual-network metadata isolates malformed/resource contracts from
# the real Shadowsocks adapter. Backends remain mocked throughout.
base_registry=$(protocol_registry_json | jq 'map(select(.state_id!="shadowsocks"))')
fixture_registry=$(jq '. + [{state_id:"shadowsocks",type:"shadowsocks",
  listen_networks:["tcp","udp"],features:{listen_network_selection:true}}]' <<< "${base_registry}")
protocol_registry_json() { printf '%s\n' "${fixture_registry}"; }
protocol_registry_field() {
  [[ "$2" == listen_networks ]] || return 98
  jq -er --arg protocol "$1" '.[] | select(.state_id==$protocol) | .listen_networks | join(",")' <<< "${fixture_registry}"
}
ss='{"type":"shadowsocks","tag":"private-tag-ss","listen":"127.0.0.1","listen_port":32100}'
for network in tcp udp; do
  config "[${ss}]" "${SINGBOX_CONFIG_FILE}.base"
  jq --arg network "${network}" '.inbounds[0].network=$network' "${SINGBOX_CONFIG_FILE}.base" > "${SINGBOX_CONFIG_FILE}"
  : > "${BACKEND_LOG}"
  IPTABLES_CHECK_STATUS=1
  open_all_protocol_ports >/dev/null
  unset IPTABLES_CHECK_STATUS
  grep -Fqx "ufw allow 32100/${network}" "${BACKEND_LOG}"
  grep -Fqx "firewalld --permanent --add-port=32100/${network}" "${BACKEND_LOG}"
  grep -Fqx "iptables -I INPUT -p ${network} --dport 32100 -j ACCEPT" "${BACKEND_LOG}"
  if [[ "${network}" == tcp ]]; then opposite=udp; else opposite=tcp; fi
  ! grep -q "${opposite}" "${BACKEND_LOG}"
  cp "${SINGBOX_CONFIG_FILE}" "${SINGBOX_CONFIG_FILE}.bak"
  config '[]' "${SINGBOX_CONFIG_FILE}"
  close_firewall_port 32100 >/dev/null
  grep -Fqx "ufw delete allow 32100/${network}" "${BACKEND_LOG}"
  ! grep -q "${opposite}" "${BACKEND_LOG}"
done

# Preserve both selected transports on one port; deduplicate same-network
# owners across addresses, but do not collapse the UDP owner into TCP.
jq -n --argjson ss "${ss}" '{inbounds:[
  ($ss + {network:"tcp"}),
  ($ss + {tag:"second-tcp",listen:"127.0.0.2",network:"tcp"}),
  ($ss + {tag:"udp",network:"udp"})]}' > "${SINGBOX_CONFIG_FILE}"
: > "${BACKEND_LOG}"
open_all_protocol_ports >/dev/null
[[ $(grep -Fxc 'ufw allow 32100/tcp' "${BACKEND_LOG}") == 1 ]]
[[ $(grep -Fxc 'ufw allow 32100/udp' "${BACKEND_LOG}") == 1 ]]

# Legacy calls still open registered defaults. An explicit selection must be
# one valid member, never an empty value, a list, or expanded capability.
: > "${BACKEND_LOG}"
open_firewall_port 32100 shadowsocks >/dev/null
grep -Fqx 'ufw allow 32100/tcp' "${BACKEND_LOG}"
grep -Fqx 'ufw allow 32100/udp' "${BACKEND_LOG}"
for selection in '' icmp 'tcp,udp' 'tcp private-tag'; do
  : > "${BACKEND_LOG}"
  if open_firewall_port 32100 shadowsocks "${selection}" > "${TMP_DIR}/out" 2> "${TMP_DIR}/err"; then
    printf 'invalid firewall selection accepted\n' >&2; exit 1
  fi
  [[ ! -s "${BACKEND_LOG}" && ! -s "${TMP_DIR}/out" ]]
  ! grep -Fq 'private-tag' "${TMP_DIR}/err"
done
: > "${BACKEND_LOG}"
if open_firewall_port 32100 mixed udp >/dev/null 2>&1; then
  printf 'firewall selection expanded protocol capability\n' >&2; exit 1
fi
[[ ! -s "${BACKEND_LOG}" ]]

# Reject the entire malformed plan before any backend calls, even when an
# earlier inbound would be valid. Preserve raw backend failure status too.
jq '.inbounds[2].network="invalid"' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if open_all_protocol_ports > "${TMP_DIR}/out" 2> "${TMP_DIR}/err"; then
  printf 'malformed firewall listener plan accepted\n' >&2; exit 1
fi
[[ ! -s "${BACKEND_LOG}" ]]
config "[${ss}]" "${SINGBOX_CONFIG_FILE}"
UFW_FAILURE=47
if open_all_protocol_ports > "${TMP_DIR}/out" 2> "${TMP_DIR}/err"; then
  printf 'expected selected backend failure\n' >&2; exit 1
else status=$?; fi
[[ ${status} == 47 ]]
grep -Fq 'external_state_may_be_partial' "${TMP_DIR}/err"
unset UFW_FAILURE
printf 'firewall listener reference checks passed (mock backends only)\n'
