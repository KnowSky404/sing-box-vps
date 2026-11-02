#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install
# shellcheck disable=SC1091
source "${TESTS_DIR}/uninstall_routing_previous_helper.sh"

[[ "${SB_PROJECT_DIR}" == "${TMP_DIR}/project" &&
   "${SINGBOX_BIN_PATH}" == "${TMP_DIR}/bin/sing-box" &&
   "${SBV_BIN_PATH}" == "${TMP_DIR}/bin/sbv" &&
   "${SINGBOX_SERVICE_FILE}" == "${TMP_DIR}/sing-box.service" ]]
SIDE_EFFECTS="${TMP_DIR}/side-effects"
UNRELATED_SIBLING="${SB_PROJECT_DIR}.rules-previous-other"
systemctl() { printf 'systemctl:%s\n' "$*" >> "${SIDE_EFFECTS}"; }
clear_vless_reality_qos_rules() { printf 'qos\n' >> "${SIDE_EFFECTS}"; }
managed_component_redirect_policy_uninstall() { printf 'redirect\n' >> "${SIDE_EFFECTS}"; }
managed_component_tproxy_policy_uninstall() { printf 'tproxy\n' >> "${SIDE_EFFECTS}"; }

reset_fixture() {
  rm -rf -- "${SB_PROJECT_DIR}" "${SB_ROUTING_PREVIOUS_DIR}" "${SB_ROUTING_TRANSACTION_DIR}" \
    "${SB_COMPONENT_TRANSACTION_DIR}" "${SB_PROJECT_DIR}.instance-write.lock" "${UNRELATED_SIBLING}"
  mkdir -p "${SB_PROJECT_DIR}" "${UNRELATED_SIBLING}"
  printf '{"inbounds":[],"outbounds":[],"route":{"rules":[]}}\n' > "${SINGBOX_CONFIG_FILE}"
  printf 'PRIVATE_KEY=fixture-private-material\n' > "${SB_PROJECT_DIR}/private.env"
  chmod 600 "${SB_PROJECT_DIR}/private.env"
  printf 'fixture\n' > "${SINGBOX_BIN_PATH}"
  printf 'fixture\n' > "${SBV_BIN_PATH}"
  printf '[Service]\nExecStart=fixture\n' > "${SINGBOX_SERVICE_FILE}"
  printf 'unrelated snapshot\n' > "${UNRELATED_SIBLING}/keep.txt"
  printf '{"phase":"received","id":"fixture-receipt"}\n' > "${SB_WARP_REGISTRATION_PENDING_FILE}"
  : > "${SIDE_EFFECTS}"
}

snapshot_fingerprint() (
  cd -- "${SB_ROUTING_PREVIOUS_DIR}"
  find . -printf '%y %m %p\n' | LC_ALL=C sort
  while IFS= read -r -d '' file; do sha256sum -- "${file}"; done \
    < <(find . -type f -print0 | LC_ALL=C sort -z)
)

assert_other_siblings_retained() {
  grep -Fxq 'unrelated snapshot' "${UNRELATED_SIBLING}/keep.txt"
  jq -e '.id=="fixture-receipt"' "${SB_WARP_REGISTRATION_PENDING_FILE}" >/dev/null
}

run_entry() {
  case "$1" in
    full) perform_full_uninstall ;;
    runtime) perform_singbox_runtime_uninstall ;;
    delete-script) uninstall_script <<<'y' ;;
    keep-config) uninstall_script <<<'n' ;;
    *) return 99 ;;
  esac
}

assert_rejected_without_mutation() {
  local entry=$1 config_hash private_hash
  config_hash=$(sha256sum "${SINGBOX_CONFIG_FILE}")
  private_hash=$(sha256sum "${SB_PROJECT_DIR}/private.env")
  if (run_entry "${entry}") > "${TMP_DIR}/rejected.stdout" 2> "${TMP_DIR}/rejected.stderr"; then
    printf 'uninstall unexpectedly accepted unsafe recovery state: %s\n' "${entry}" >&2
    return 1
  fi
  [[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${config_hash}" &&
     "$(sha256sum "${SB_PROJECT_DIR}/private.env")" == "${private_hash}" ]]
  [[ -f "${SINGBOX_BIN_PATH}" && -f "${SBV_BIN_PATH}" && -f "${SINGBOX_SERVICE_FILE}" ]]
  [[ ! -s "${SIDE_EFFECTS}" ]]
  assert_other_siblings_retained
}

# A real completed snapshot contains private data, and a full purge must remove
# it together with the runtime rather than leaving a credential-bearing sibling.
reset_fixture
create_uninstall_routing_previous_snapshot
grep -Fxq 'PRIVATE_KEY=fixture-private-material' "${SB_ROUTING_PREVIOUS_DIR}/snapshot/project/private.env"
(run_entry full) > "${TMP_DIR}/full.stdout" 2> "${TMP_DIR}/full.stderr"
[[ ! -e "${SB_PROJECT_DIR}" && ! -e "${SB_ROUTING_PREVIOUS_DIR}" &&
   ! -e "${SINGBOX_BIN_PATH}" && ! -e "${SBV_BIN_PATH}" && ! -e "${SINGBOX_SERVICE_FILE}" ]]
assert_other_siblings_retained

reset_fixture
create_uninstall_routing_previous_snapshot
(run_entry delete-script) > "${TMP_DIR}/delete-script.stdout" 2> "${TMP_DIR}/delete-script.stderr"
[[ ! -e "${SB_PROJECT_DIR}" && ! -e "${SB_ROUTING_PREVIOUS_DIR}" && ! -e "${SBV_BIN_PATH}" ]]
[[ -f "${SINGBOX_BIN_PATH}" && -f "${SINGBOX_SERVICE_FILE}" ]]
assert_other_siblings_retained

reset_fixture
create_uninstall_routing_previous_snapshot
previous_before=$(snapshot_fingerprint)
config_before=$(sha256sum "${SINGBOX_CONFIG_FILE}")
(run_entry keep-config) > "${TMP_DIR}/keep-config.stdout" 2> "${TMP_DIR}/keep-config.stderr"
[[ "$(snapshot_fingerprint)" == "${previous_before}" &&
   "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${config_before}" ]]
[[ ! -e "${SBV_BIN_PATH}" && -f "${SINGBOX_BIN_PATH}" && -f "${SINGBOX_SERVICE_FILE}" ]]
[[ ! -s "${SIDE_EFFECTS}" ]]
assert_other_siblings_retained

# Untrusted paths and incomplete transaction metadata fail before service,
# firewall, runtime or config changes, for every uninstall entrypoint.
for unsafe_kind in symlink invalid uncommitted pending; do
  reset_fixture
  case "${unsafe_kind}" in
    symlink) ln -s "${UNRELATED_SIBLING}" "${SB_ROUTING_PREVIOUS_DIR}" ;;
    invalid)
      mkdir -m 700 "${SB_ROUTING_PREVIOUS_DIR}"
      printf 'untrusted recovery material\n' > "${SB_ROUTING_PREVIOUS_DIR}/retain.txt"
      ;;
    uncommitted)
      create_uninstall_routing_previous_snapshot
      jq '.phase="publish"' "${SB_ROUTING_PREVIOUS_DIR}/transaction.json" > "${TMP_DIR}/uncommitted.json"
      chmod 600 "${TMP_DIR}/uncommitted.json"
      mv "${TMP_DIR}/uncommitted.json" "${SB_ROUTING_PREVIOUS_DIR}/transaction.json"
      routing_transaction_valid "${SB_ROUTING_PREVIOUS_DIR}"
      ;;
    pending)
      create_uninstall_routing_previous_snapshot
      mkdir -m 700 "${SB_ROUTING_TRANSACTION_DIR}"
      ;;
  esac
  for entry in full runtime delete-script keep-config; do
    assert_rejected_without_mutation "${entry}"
  done
  [[ -e "${SB_ROUTING_PREVIOUS_DIR}" || -L "${SB_ROUTING_PREVIOUS_DIR}" ]]
done

# A successful rm status is insufficient if recovery material still exists.
# Report partial cleanup and retain sbv so the operator can inspect the result.
reset_fixture
create_uninstall_routing_previous_snapshot
if (
  rm() {
    [[ "${*: -1}" != "${SB_ROUTING_PREVIOUS_DIR}" ]] || return 0
    command rm "$@"
  }
  run_entry full
) > "${TMP_DIR}/failed-cleanup.stdout" 2> "${TMP_DIR}/failed-cleanup.stderr"; then
  printf 'uninstall reported success while the private routing snapshot remained\n' >&2
  exit 1
fi
[[ -d "${SB_ROUTING_PREVIOUS_DIR}" && -f "${SBV_BIN_PATH}" ]]
grep -Fq '规则恢复快照清理失败' "${TMP_DIR}/failed-cleanup.stderr"
assert_other_siblings_retained

printf 'Uninstall routing recovery cleanup and preservation checks passed\n'
