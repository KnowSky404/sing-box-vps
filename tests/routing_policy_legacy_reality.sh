#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
core=${ROUTING_POLICY_TEST_REAL_CORE:-${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}}
[[ "$("${core}" version | head -n1)" == 'sing-box version 1.14.2' ]] || {
  printf 'Set ROUTING_POLICY_TEST_REAL_CORE to the real sing-box 1.14.2 executable\n' >&2; exit 1;
}
ln -s "${core}" "${TMP_DIR}/bin/sing-box"
source "${TESTABLE_INSTALL}"
# Independently exercise the source fix before the shared artifact is rebuilt.
source "${REPO_ROOT}/src/install/03-reality-and-protocol-state.sh"
source "${REPO_ROOT}/src/install/13-protocol-render.sh"
source "${REPO_ROOT}/src/install/23-ui-and-network-menus.sh"
source "${REPO_ROOT}/src/install/41-routing-transactions.sh"
trap 'printf "legacy REALITY routing test failed at line %s\n" "${LINENO}" >&2' ERR

SERVICE_STATE="${TMP_DIR}/service.state"
SERVICE_CALLS="${TMP_DIR}/service.calls"
systemctl() {
  printf '%s\n' "$*" >> "${SERVICE_CALLS}"
  case "${1:-}" in
    is-active)
      if [[ "$(cat "${SERVICE_STATE}")" == active ]]; then
        [[ "${2:-}" == --quiet ]] || printf 'active\n'
      else
        [[ "${2:-}" == --quiet ]] || cat "${SERVICE_STATE}"
        return 3
      fi
      ;;
    show) cat "${SERVICE_STATE}" ;;
    restart)
      if [[ -e "${TMP_DIR}/restart-fail-once" ]]; then
        rm -- "${TMP_DIR}/restart-fail-once"
        printf 'inactive\n' > "${SERVICE_STATE}"
        return 72
      fi
      printf 'active\n' > "${SERVICE_STATE}" ;;
    stop) printf 'inactive\n' > "${SERVICE_STATE}" ;;
    *) return 1 ;;
  esac
}
run_with_progress() { shift; "$@"; }

mkdir -p "${SB_PROTOCOL_STATE_DIR}"
printf '[Service]\nExecStart=fixture\n' > "${SINGBOX_SERVICE_FILE}"
printf 'active\n' > "${SERVICE_STATE}"
: > "${SERVICE_CALLS}"
pair=$("${core}" generate reality-keypair)
private=$(awk '/PrivateKey/ {print $2}' <<< "${pair}")
public=$(awk '/PublicKey/ {print $2}' <<< "${pair}")
# A legacy installation's key-material sidecar is independent of its missing
# protocol index/env cache and lets the existing loader retain its public key.
printf 'PRIVATE_KEY=%s\nPUBLIC_KEY=%s\n' "${private}" "${public}" > "${SB_KEY_FILE}"
chmod 600 "${SB_KEY_FILE}"
{
  printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=1\nNODE_NAME=private-legacy-name\nPORT=34443\n'
  printf 'UUID=11111111-1111-1111-1111-111111111111\nSNI=example.com\n'
  write_env_assignment REALITY_PRIVATE_KEY "${private}"
  write_env_assignment REALITY_PUBLIC_KEY "${public}"
  printf 'SHORT_ID_1=aaaaaaaaaaaaaaaa\nSHORT_ID_2=bbbbbbbbbbbbbbbb\n'
} > "${TMP_DIR}/legacy.env"
chmod 600 "${TMP_DIR}/legacy.env"
cp -p "${TMP_DIR}/legacy.env" "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
write_protocol_index vless-reality
SB_ENABLE_WARP=n SB_ADVANCED_ROUTE=n SB_WARP_ROUTE_MODE=selective
SB_INBOUND_STACK_MODE=ipv4_only SB_OUTBOUND_STACK_MODE=prefer_ipv4
save_stack_mode_state
save_warp_route_settings

# Ordinary migration retains its historical timestamped backup behavior.
load_protocol_state vless-reality
mapfile -t ordinary_backups < <(find "${SB_PROTOCOL_STATE_DIR}" -maxdepth 1 -name 'vless-reality.env.bak.*' -type f)
[[ ${#ordinary_backups[@]} == 1 ]]
cmp "${ordinary_backups[0]}" "${TMP_DIR}/legacy.env"
generate_config > "${TMP_DIR}/initial.log" 2>&1 || { cat "${TMP_DIR}/initial.log" >&2; exit 1; }
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
mkdir "${TMP_DIR}/template"
cp -a "${SB_PROJECT_DIR}/." "${TMP_DIR}/template/"

reset_legacy() {
  local representation=$1
  rm -rf -- "${SB_PROJECT_DIR}" "${SB_ROUTING_TRANSACTION_DIR}" "${SB_ROUTING_PREVIOUS_DIR}"
  mkdir -p "${SB_PROJECT_DIR}"
  cp -a "${TMP_DIR}/template/." "${SB_PROJECT_DIR}/"
  rm -rf -- "${SB_PROTOCOL_STATE_DIR}"
  rm -f -- "${SB_PROJECT_DIR}/managed-config.generated.json" "${SB_PROJECT_DIR}/managed-config.generated.json.bak"
  if [[ "${representation}" == schema1 ]]; then
    mkdir -p "${SB_PROTOCOL_STATE_DIR}"
    cp -p "${TMP_DIR}/legacy.env" "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
    write_protocol_index vless-reality
    printf 'manual archive\n' > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env.bak.19990101000000"
  fi
  printf 'active\n' > "${SERVICE_STATE}"
  : > "${SERVICE_CALLS}"
  "${core}" check -c "${SINGBOX_CONFIG_FILE}"
}

for representation in schema1 config-with-key-sidecar; do
  reset_legacy "${representation}"
  before=$(routing_state_fingerprint)
  nodes=$(routing_nodes_json)
  if [[ "${representation}" == schema1 ]]; then
    jq -e 'length==1 and .[0]=={protocol:"vless-reality",id:"main",name:"VLESS + REALITY (legacy)",tag:"vless-in",policy:"default",revision:0,editable:false}' \
      <<< "${nodes}" >/dev/null
  else
    [[ "${nodes}" == '[]' ]]
  fi
  routing_draft_create "${TMP_DIR}/draft.json"
  routing_policy_preview "${TMP_DIR}/draft.json" > "${TMP_DIR}/preview.log" 2>&1
  [[ "$(routing_state_fingerprint)" == "${before}" && ! -e "${SB_ROUTING_POLICY_FILE}" &&
     ! -e "${SB_PROTOCOL_STATE_DIR}/vless-reality.d" ]]
  # An internal flag alone cannot authorize a backup without a valid journal.
  if (SB_ROUTING_JOURNAL_LEGACY_BACKUP=y; routing_transaction_backup_legacy_reality_state "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"); then
    printf 'legacy backup accepted an untrusted journal\n' >&2; exit 1
  fi
  routing_draft_edit "${TMP_DIR}/draft.json" '.policy.server.private_network_block=true'
  routing_policy_apply "${TMP_DIR}/draft.json" > "${TMP_DIR}/${representation}-apply.log" 2>&1 || {
    cat "${TMP_DIR}/${representation}-apply.log" >&2; exit 1;
  }
  [[ ! -e "${SB_ROUTING_TRANSACTION_DIR}" && "$(grep -c '^restart sing-box$' "${SERVICE_CALLS}")" == 1 ]]
  jq -e 'any(.route.rules[]; .action=="resolve") and any(.route.rules[]; .ip_is_private==true)' "${SINGBOX_CONFIG_FILE}" >/dev/null
  jq -e --arg private "${private}" 'any(.inbounds[]; .tls.reality.private_key? == $private)' "${SINGBOX_CONFIG_FILE}" >/dev/null
  "${core}" check -c "${SINGBOX_CONFIG_FILE}"
  if [[ "${representation}" == schema1 ]]; then
    backup="${SB_ROUTING_PREVIOUS_DIR}/legacy-vless-reality.env.bak"
    [[ "$(stat -c %a "${backup}")" == 600 ]]
    cmp "${backup}" "${TMP_DIR}/legacy.env"
    [[ "$(find "${SB_PROTOCOL_STATE_DIR}" -maxdepth 1 -name 'vless-reality.env.bak.*' -type f | wc -l)" == 1 ]]
    # A timestamp-like operator archive remains external and hash-protected.
    archive="${SB_PROTOCOL_STATE_DIR}/vless-reality.env.bak.19990101000000"
    if routing_path_is_managed "${archive}"; then printf 'manual backup was exempted\n' >&2; exit 1; fi
    external_before=$(routing_state_fingerprint external)
    printf 'operator update\n' >> "${archive}"
    [[ "$(routing_state_fingerprint external)" != "${external_before}" ]]
  fi

  reset_legacy "${representation}"
  before=$(routing_state_fingerprint)
  routing_draft_create "${TMP_DIR}/draft.json"
  routing_draft_edit "${TMP_DIR}/draft.json" '.policy.server.private_network_block=true'
  touch "${TMP_DIR}/restart-fail-once"
  if routing_policy_apply "${TMP_DIR}/draft.json" > "${TMP_DIR}/${representation}-rollback.log" 2>&1; then
    printf 'restart failure was accepted\n' >&2; exit 1
  fi
  [[ "$(routing_state_fingerprint)" == "${before}" && ! -e "${SB_ROUTING_TRANSACTION_DIR}" &&
     ! -e "${SB_ROUTING_PREVIOUS_DIR}" && "$(cat "${SERVICE_STATE}")" == active ]]
  grep -Fq '已回滚配置及原服务状态' "${TMP_DIR}/${representation}-rollback.log"
  "${core}" check -c "${SINGBOX_CONFIG_FILE}"
done

# Missing public-key material remains a protected refusal. Do not turn this
# routing fix into an implicit key replacement or a public-key derivation path.
reset_legacy config-with-key-sidecar
rm -- "${SB_KEY_FILE}"
before=$(routing_state_fingerprint)
routing_draft_create "${TMP_DIR}/draft.json"
routing_draft_edit "${TMP_DIR}/draft.json" '.policy.server.private_network_block=true'
if routing_policy_apply "${TMP_DIR}/draft.json" > "${TMP_DIR}/missing-material.log" 2>&1; then
  printf 'missing key material silently replaced the existing REALITY key\n' >&2; exit 1
fi
[[ "$(routing_state_fingerprint)" == "${before}" && ! -e "${SB_ROUTING_TRANSACTION_DIR}" &&
   ! -e "${SB_ROUTING_PREVIOUS_DIR}" && "$(cat "${SERVICE_STATE}")" == active ]]
grep -Fq managed_config_conflict "${TMP_DIR}/missing-material.log"
"${core}" check -c "${SINGBOX_CONFIG_FILE}"

# A failed journal backup must propagate through ordinary statements even
# when the outer apply is invoked in an if/|| context that suppresses errexit.
cp() {
  local destination=${*: -1}
  if [[ -e "${TMP_DIR}/backup-fail" &&
        "${destination}" == "${SB_ROUTING_TRANSACTION_DIR}/.legacy-vless-reality.env.bak.candidate."* ]]; then
    return 73
  fi
  command cp "$@"
}
reset_legacy schema1
before=$(routing_state_fingerprint)
routing_draft_create "${TMP_DIR}/draft.json"
routing_draft_edit "${TMP_DIR}/draft.json" '.policy.server.private_network_block=true'
touch "${TMP_DIR}/backup-fail"
if routing_policy_apply "${TMP_DIR}/draft.json" > "${TMP_DIR}/backup-failure.log" 2>&1; then
  printf 'journal backup failure was masked by a later successful statement\n' >&2; exit 1
fi
[[ "$(routing_state_fingerprint)" == "${before}" && ! -e "${SB_ROUTING_TRANSACTION_DIR}" &&
   ! -e "${SB_ROUTING_PREVIOUS_DIR}" && "$(cat "${SERVICE_STATE}")" == active ]]
grep -Fq '已回滚配置及原服务状态' "${TMP_DIR}/backup-failure.log"
"${core}" check -c "${SINGBOX_CONFIG_FILE}"

printf 'Legacy REALITY schema1 and config-protocol-state with existing key sidecar: read-only, journal backup, apply and rollback passed with real sing-box 1.14.2\n'
