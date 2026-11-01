#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"

# A retained revision does not mean a protocol is installed. Rendering and
# choosing from an empty inventory must not mutate these recreation records.
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
for protocol in mixed socks http shadowsocks trojan vmess vless-plain anytls hy2 snell tuic hysteria naive shadowtls; do
  structured_instance_store_empty_json "${protocol}" | jq '.revision=9' \
    > "${SB_PROTOCOL_STATE_DIR}/instances/${protocol}.json"
done
before=$(sha256sum "${SB_PROTOCOL_STATE_DIR}"/instances/*.json)
list_installed_protocols() { printf 'unexpected reconciliation\n' >&2; return 99; }

if prompt_protocol_install_selection additional '' > "${TMP_DIR}/empty.output" <<<'0'; then
  printf 'expected main-menu cancellation\n' >&2
  exit 1
fi
grep -Fxq '当前已安装协议: 无' "${TMP_DIR}/empty.output"
grep -Fxq '1. VLESS' "${TMP_DIR}/empty.output"
grep -Fxq '3. Hysteria2' "${TMP_DIR}/empty.output"
grep -Fxq '11. TUIC' "${TMP_DIR}/empty.output"
! grep -Eq '新增|新建|^- ' "${TMP_DIR}/empty.output"
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}"/instances/*.json)" == "${before}" ]]

# Both VLESS variants are chosen under one family, including default, invalid
# input retry, repeated family selection and mixed family/protocol choices.
prompt_protocol_install_selection fresh > "${TMP_DIR}/reality.output" <<'INPUT'
1

INPUT
[[ "${SELECTED_PROTOCOLS_CSV}" == vless-reality ]]
grep -Fxq '1. VLESS + REALITY' "${TMP_DIR}/reality.output"
grep -Fxq '2. 普通 VLESS' "${TMP_DIR}/reality.output"
prompt_protocol_install_selection fresh > "${TMP_DIR}/plain.output" <<'INPUT'
1,2,1
9
2
INPUT
[[ "${SELECTED_PROTOCOLS_CSV}" == vless-plain,mixed ]]
[[ "$(grep -c -- '--- VLESS ---' "${TMP_DIR}/plain.output")" == 1 ]]

# Canceling a VLESS sub-selection never publishes earlier choices. EOF at
# either level is cancellation, rather than implicit all/default selection.
for input in '2,1' '1'; do
  if prompt_protocol_install_selection fresh > /dev/null <<INPUT
${input}
0
INPUT
  then
    printf 'expected VLESS sub-menu cancellation\n' >&2
    exit 1
  fi
  [[ -z "${SELECTED_PROTOCOLS_CSV}" ]]
done
if prompt_protocol_install_selection fresh > /dev/null </dev/null; then exit 1; fi
[[ -z "${SELECTED_PROTOCOLS_CSV}" ]]
if prompt_protocol_install_selection fresh > /dev/null <<<'1'; then exit 1; fi
[[ -z "${SELECTED_PROTOCOLS_CSV}" ]]

# Historical registry menu_order and Agent IDs stay intact, while the new
# contiguous UI options after VMess select the correct protocols.
prompt_protocol_install_selection fresh > /dev/null <<<'10,11,12,13,14'
[[ "${SELECTED_PROTOCOLS_CSV}" == snell,tuic,hysteria,naive,shadowtls ]]
[[ "$(protocol_option_to_id 10)" == vless-plain ]]
[[ "$(protocol_option_to_id 12)" == tuic ]]

# Real active inventory still appears, and an installed plain VLESS remains
# hidden as before. REALITY can still create an additional instance.
prompt_protocol_install_selection additional $'vless-reality\nvless-plain' > "${TMP_DIR}/active.output" <<'INPUT'
1
2
1
INPUT
[[ "${SELECTED_PROTOCOLS_CSV}" == vless-reality ]]
grep -Fxq -- '- VLESS + REALITY' "${TMP_DIR}/active.output"
grep -Fxq -- '- VLESS' "${TMP_DIR}/active.output"
! grep -Fxq '2. 普通 VLESS' "${TMP_DIR}/active.output"
! grep -Eq '新增|新建' "${TMP_DIR}/active.output"

# An empty retained HY2 inventory remains selectable with the common name.
prompt_protocol_install_selection additional '' > "${TMP_DIR}/hy2.output" <<<'3'
[[ "${SELECTED_PROTOCOLS_CSV}" == hy2 ]]
grep -Fxq '当前已安装协议: 无' "${TMP_DIR}/hy2.output"
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}"/instances/*.json)" == "${before}" ]]

printf 'protocol menu checks passed: VLESS grouping, numbering, cancel/EOF, retained/active inventory\n'
