#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"
source "${REPO_ROOT}/src/install/01-common-and-stack.sh"
source "${REPO_ROOT}/src/install/41-routing-transactions.sh"
trap 'printf "routing WARP receipt test failed at line %s\n" "${LINENO}" >&2' ERR

# Exercise the real provider receipt, credential writer and outer transaction;
# provider POST, config generation and systemd are isolated local doubles.
[[ "${SB_PROJECT_DIR}" == "${TMP_DIR}/project" ]]
SERVICE_STATE="${TMP_DIR}/service.state"
RESPONSE='{"id":"fixture-id","token":"fixture-token","config":{"client_id":"hCaJ","interface":{"addresses":{"v4":"172.16.0.2","v6":"2606:4700:110:8cde::1"}}}}'
run_singbox_generate_command() {
  printf '%s\n' 'PrivateKey: 8DcUSmPINFuK1xkA1TncAJh46Ra8Mq8o42XL3b+rT2s=' \
    'PublicKey: j/gT24P0qv0p5RFqYVehc7Y88S5fDhcJ8E3HGqpCPVg='
}
curl() {
  local output=''
  printf 'POST\n' >> "${TMP_DIR}/requests"
  while [[ $# -gt 0 ]]; do
    case "$1" in -o) output=$2; shift 2 ;; *) shift ;; esac
  done
  printf '%s\n' "${RESPONSE}" > "${output}"
  printf 200
}
systemctl() {
  case "${1:-}" in
    is-active)
      if [[ "$(cat "${SERVICE_STATE}")" == active ]]; then
        [[ "${2:-}" == --quiet ]] || printf 'active\n'
      else
        [[ "${2:-}" == --quiet ]] || printf 'inactive\n'
        return 3
      fi
      ;;
    restart)
      if [[ -e "${TMP_DIR}/restart-fail-once" ]]; then
        rm -- "${TMP_DIR}/restart-fail-once"
        printf 'inactive\n' > "${SERVICE_STATE}"
        return 72
      fi
      printf 'active\n' > "${SERVICE_STATE}" ;;
    stop) printf 'inactive\n' > "${SERVICE_STATE}" ;;
    show) cat "${SERVICE_STATE}" ;;
    *) return 1 ;;
  esac
}
run_with_progress() { shift; "$@"; }
load_current_config_state() { :; }
ensure_existing_generated_config_baseline() { :; }
generate_config() { :; }

cat > "${SINGBOX_BIN_PATH}" <<'CORE'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == check ]]
jq -e 'type == "object"' "$3" >/dev/null
CORE
chmod +x "${SINGBOX_BIN_PATH}"
printf '[Service]\nExecStart=fixture\n' > "${SINGBOX_SERVICE_FILE}"
printf 'active\n' > "${SERVICE_STATE}"
printf '{"outbounds":[{"type":"direct","tag":"direct"}],"route":{"final":"direct","rules":[]}}\n' > "${SINGBOX_CONFIG_FILE}"
printf 'WARP_ROUTE_MODE=selective\nWARP_ENABLED=n\n' > "${SB_WARP_ROUTE_SETTINGS_FILE}"
initial_policy=$(routing_policy_read_json)
printf '%s\n' "${initial_policy}" > "${SB_ROUTING_POLICY_FILE}"
chmod 600 "${SB_ROUTING_POLICY_FILE}"
write_warp_credentials_atomic old-id old-token AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= \
  AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= 172.16.0.3 2606:4700:110::3 AAAA
cp -p "${SB_WARP_KEY_FILE}" "${TMP_DIR}/original-key"
routing_draft_create "${TMP_DIR}/draft.json"
routing_draft_edit "${TMP_DIR}/draft.json" '.warp.enabled=true | .warp.reregister=true'

# A completed provider response must survive a later service failure. The
# local key rolls back, and retry consumes the same received response.
touch "${TMP_DIR}/restart-fail-once"
if routing_policy_apply "${TMP_DIR}/draft.json" > "${TMP_DIR}/failed.log" 2>&1; then
  printf 'restart failure was accepted\n' >&2; exit 1
fi
cmp "${SB_WARP_KEY_FILE}" "${TMP_DIR}/original-key"
jq -e '.schema==1 and .phase=="received"' "${SB_WARP_REGISTRATION_PENDING_FILE}" >/dev/null
[[ "$(wc -l < "${TMP_DIR}/requests")" == 1 && ! -e "${SB_ROUTING_TRANSACTION_DIR}" ]]
routing_policy_apply "${TMP_DIR}/draft.json" > "${TMP_DIR}/retry.log" 2>&1
[[ "$(wc -l < "${TMP_DIR}/requests")" == 1 && ! -e "${SB_WARP_REGISTRATION_PENDING_FILE}" ]]
grep -Fq 'WARP_ID=fixture-id' "${SB_WARP_KEY_FILE}"
jq -e '.phase=="committed" and (.warp_registration_deferred.receipt_sha256|length)==64' \
  "${SB_ROUTING_PREVIOUS_DIR}/transaction.json" >/dev/null

# An unchanged network transaction has no custody over an unrelated unknown receipt.
printf '{"schema":1,"phase":"sent","private_key":"unrelated"}\n' > "${SB_WARP_REGISTRATION_PENDING_FILE}"
chmod 600 "${SB_WARP_REGISTRATION_PENDING_FILE}"
cp -p "${SB_WARP_REGISTRATION_PENDING_FILE}" "${TMP_DIR}/unknown-receipt"
routing_draft_create "${TMP_DIR}/client.json"
routing_policy_apply "${TMP_DIR}/client.json" > "${TMP_DIR}/client.log" 2>&1
cmp "${SB_WARP_REGISTRATION_PENDING_FILE}" "${TMP_DIR}/unknown-receipt"
jq -e '.warp_registration_deferred==null and (.service_changed|not)' \
  "${SB_ROUTING_PREVIOUS_DIR}/transaction.json" >/dev/null
rm -- "${SB_WARP_REGISTRATION_PENDING_FILE}"

# Stop once at committed receipt cleanup. Recovery must verify the receipt and
# installed credential bytes before deleting it, then finish without a new POST.
rm() {
  if [[ "${*: -1}" == "${SB_WARP_REGISTRATION_PENDING_FILE}" && -e "${TMP_DIR}/cleanup-fail-once" ]]; then
    command rm -- "${TMP_DIR}/cleanup-fail-once"
    return 73
  fi
  command rm "$@"
}
routing_draft_create "${TMP_DIR}/cleanup.json"
routing_draft_edit "${TMP_DIR}/cleanup.json" '.warp.reregister=true'
touch "${TMP_DIR}/cleanup-fail-once"
if routing_policy_apply "${TMP_DIR}/cleanup.json" > "${TMP_DIR}/cleanup.log" 2>&1; then
  printf 'cleanup failure was hidden\n' >&2; exit 1
fi
[[ "$(wc -l < "${TMP_DIR}/requests")" == 2 && -f "${SB_WARP_REGISTRATION_PENDING_FILE}" ]]
jq -e '.phase=="committed"' "${SB_ROUTING_TRANSACTION_DIR}/transaction.json" >/dev/null
cp -p "${SB_WARP_KEY_FILE}" "${TMP_DIR}/committed-key"
printf 'unexpected credential bytes\n' > "${SB_WARP_KEY_FILE}"
if routing_transaction_finalize_warp_registration; then
  printf 'mismatched credentials allowed receipt deletion\n' >&2; exit 1
fi
[[ -f "${SB_WARP_REGISTRATION_PENDING_FILE}" ]]
cp -p "${TMP_DIR}/committed-key" "${SB_WARP_KEY_FILE}"
routing_policy_recover > "${TMP_DIR}/recover.log" 2>&1
[[ ! -e "${SB_ROUTING_TRANSACTION_DIR}" && ! -e "${SB_WARP_REGISTRATION_PENDING_FILE}" &&
   "$(wc -l < "${TMP_DIR}/requests")" == 2 ]]
printf 'Rules WARP receipt rollback, retry, custody and committed recovery passed\n'
