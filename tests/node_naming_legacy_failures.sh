#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install

curl() { printf 'unexpected network access in legacy naming regression\n' >&2; return 99; }
systemctl() { printf 'unexpected service operation in legacy naming regression\n' >&2; return 99; }
get_public_ip() { printf 'unexpected public-IP discovery in legacy naming regression\n' >&2; return 99; }
migrate_vless_reality_state_to_instances_if_needed() { return 0; }
load_vless_reality_protocol_state() { return 0; }
list_vless_reality_instance_ids() { printf 'main\n'; }
load_vless_reality_instance_state() {
  [[ "${1:-}" == main ]] || return 1
  SB_VLESS_INSTANCE_ID=main
  return 0
}

CONFIG_SCHEMA_VERSION=1
SB_VERSION=1.14.2
SUBMAN_NODE_PREFIX=identity-host
SB_PORT=8443
SB_UUID=11111111-1111-4111-8111-111111111111
SB_SNI=fixture.example
SB_PUBLIC_KEY=synthetic-public-key
SB_SHORT_ID_1=abcd1234
SB_VLESS_INSTANCE_ID=main
SB_VLESS_RATE_LIMIT_UP_MBPS=40
SB_VLESS_RATE_LIMIT_DOWN_MBPS=100
SB_VLESS_ALPN_MODE=off
SB_VLESS_TCP_FAST_OPEN=n
SB_HY2_PASSWORD=synthetic-hy2-password
SB_HY2_DOMAIN=''
SB_HY2_USER_NAME=legacy-user
SB_HY2_TLS_MODE=manual
SB_HY2_CERT_PATH=''
SB_HY2_KEY_PATH=''
SB_HY2_UP_MBPS=20
SB_HY2_DOWN_MBPS=80
SB_HY2_OBFS_ENABLED=n
SB_HY2_OBFS_TYPE=''
SB_HY2_OBFS_PASSWORD=''

writes_file="${TMP_DIR}/mock-writes"
: > "${writes_file}"
qr_calls_file="${TMP_DIR}/mock-qr-calls"
: > "${qr_calls_file}"
qrencode() {
  printf '%s\n' "${3:-}" >> "${qr_calls_file}"
  printf 'QR-STUB\n'
  return 0
}
push_subman_node() {
  printf 'write\n' >> "${writes_file}"
  return 0
}

expect_rejected_without_output() {
  local label=$1
  shift
  # The conditional deliberately disables errexit inside the complete call
  # chain. Only explicit error propagation can keep an invalid candidate out.
  if "$@" >"${TMP_DIR}/rejected.out" 2>"${TMP_DIR}/rejected.err"; then
    printf 'FAIL: invalid legacy name unexpectedly succeeded: %s\n' "${label}" >&2
    exit 1
  fi
  if [[ -s "${TMP_DIR}/rejected.out" ]]; then
    printf 'FAIL: rejected legacy name emitted successful output: %s\n' "${label}" >&2
    exit 1
  fi
}

expect_tui_rejected_without_material() {
  local label=$1 calls_before
  shift
  calls_before=$(wc -l < "${qr_calls_file}")
  if "$@" >"${TMP_DIR}/tui-rejected.out" 2>"${TMP_DIR}/tui-rejected.err"; then
    printf 'FAIL: invalid legacy name unexpectedly succeeded in TUI: %s\n' "${label}" >&2
    exit 1
  fi
  # Human-readable headers may precede validation, but no connection material
  # or QR encoder invocation may escape a rejected formatter result.
  if grep -Eq 'vless://|hy2://|QR-STUB' "${TMP_DIR}/tui-rejected.out"; then
    printf 'FAIL: rejected TUI name emitted connection material: %s\n' "${label}" >&2
    exit 1
  else
    [[ "$?" == 1 ]]
  fi
  [[ "$(wc -l < "${qr_calls_file}")" == "${calls_before}" ]]
}

for protocol in vless-reality hy2; do
  if [[ "${protocol}" == vless-reality ]]; then
    SB_PROTOCOL=vless+reality
    SB_NODE_NAME=fra-01-vless
    builder=build_vless_link
    expected_base=fra-01-vless-U40M-D100M
    link_key=vless
  else
    SB_PROTOCOL=hy2
    SB_NODE_NAME=fra-01-hy2
    builder=build_hy2_link
    expected_base=fra-01-hy2-U20M-D80M
    link_key=hy2
  fi
  expected_name="${expected_base}-v4"
  # Valid invocations also run as conditional assignments, matching the public
  # callers which initially exposed swallowed formatter failures.
  if ! link=$("${builder}" 203.0.113.20 IPv4); then
    printf 'valid legacy link unexpectedly failed: %s\n' "${protocol}" >&2
    exit 1
  fi
  [[ "${link}" == *"#${expected_name}" ]]
  if ! payload=$(build_subman_node_payload "${protocol}" 203.0.113.20 IPv4); then
    printf 'valid legacy payload unexpectedly failed: %s\n' "${protocol}" >&2
    exit 1
  fi
  jq -e --arg name "${expected_name}" --arg raw "${link}" '.name==$name and .raw==$raw' <<< "${payload}" >/dev/null
  if ! agent_links=$(agent_link_json_for_current_protocol 203.0.113.20); then
    printf 'valid legacy Agent links unexpectedly failed: %s\n' "${protocol}" >&2
    exit 1
  fi
  jq -e --arg name "${expected_name}" --arg raw "${link}" --arg key "${link_key}" \
    '.name==$name and .links[$key]==$raw' <<< "${agent_links}" >/dev/null
  if ! summary=$(agent_node_summary_json_for_current_protocol 203.0.113.20); then
    printf 'valid legacy Agent summary unexpectedly failed: %s\n' "${protocol}" >&2
    exit 1
  fi
  jq -e --arg name "${expected_base}" '.name==$name and .shareable==true' <<< "${summary}" >/dev/null
  if ! push_subman_protocol_instance "${protocol}" 203.0.113.20 '' y IPv4; then
    printf 'valid legacy mock push unexpectedly failed: %s\n' "${protocol}" >&2
    exit 1
  fi
  writes_before=$(wc -l < "${writes_file}")
  for mode in link qr both; do
    if ! show_connection_details "${mode}" 203.0.113.20 IPv4 >"${TMP_DIR}/tui-valid.out" 2>"${TMP_DIR}/tui-valid.err"; then
      printf 'valid legacy TUI mode unexpectedly failed: %s/%s\n' "${protocol}" "${mode}" >&2
      exit 1
    fi
    if [[ "${mode}" == link || "${mode}" == both ]]; then
      grep -Fq "${link}" "${TMP_DIR}/tui-valid.out"
    fi
    if [[ "${mode}" == qr || "${mode}" == both ]]; then
      [[ "$(tail -n 1 "${qr_calls_file}")" == "${link}" ]]
    fi
  done

  for rejected_name in '' '   ' $'\t \t' $'invalid\tinterior' $'invalid\ninterior'; do
    SB_NODE_NAME=${rejected_name}
    expect_rejected_without_output "${protocol} formatter" display_node_name_for_protocol "${protocol}" "${SB_NODE_NAME}" IPv4
    expect_rejected_without_output "${protocol} direct link" "${builder}" 203.0.113.20 IPv4
    expect_rejected_without_output "${protocol} raw URI" build_subman_raw_for_protocol "${protocol}" 203.0.113.20 IPv4
    expect_rejected_without_output "${protocol} payload" build_subman_node_payload "${protocol}" 203.0.113.20 IPv4
    expect_rejected_without_output "${protocol} Agent links" agent_link_json_for_current_protocol 203.0.113.20
    expect_rejected_without_output "${protocol} Agent summary" agent_node_summary_json_for_current_protocol 203.0.113.20
    expect_rejected_without_output "${protocol} mock push" push_subman_protocol_instance "${protocol}" 203.0.113.20 '' y IPv4
    [[ "$(wc -l < "${writes_file}")" == "${writes_before}" ]]
    expect_tui_rejected_without_material "${protocol} direct link display" show_link_info 203.0.113.20 IPv4
    expect_tui_rejected_without_material "${protocol} direct QR display" show_qr_info 203.0.113.20 IPv4
    for mode in link qr both; do
      expect_tui_rejected_without_material "${protocol} dispatcher ${mode}" show_connection_details "${mode}" 203.0.113.20 IPv4
    done
  done
  printf 'legacy naming failure propagation: protocol=%s valid=ok rejected=5 no_partial_output=ok no_invalid_push=ok tui_link_qr_both=ok\n' "${protocol}"
done
[[ "$(wc -l < "${writes_file}")" -eq 2 ]]
[[ "$(wc -l < "${qr_calls_file}")" -eq 4 ]]
printf 'Legacy naming regression passed: valid URI/payload/Agent parity and explicit formatter failure propagation\n'
