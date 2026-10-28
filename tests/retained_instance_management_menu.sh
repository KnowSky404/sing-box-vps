#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
printf '%s\n' '{"inbounds":[],"outbounds":[{"type":"direct","tag":"direct"}],"route":{"final":"direct"}}' > "${SINGBOX_CONFIG_FILE}"
for protocol in mixed socks http shadowsocks trojan vmess vless-plain anytls hy2 snell tuic hysteria naive shadowtls; do
  structured_instance_store_empty_json "${protocol}" | jq '.revision=9' \
    > "${SB_PROTOCOL_STATE_DIR}/instances/${protocol}.json"
done
before=$(sha256sum "${SB_PROTOCOL_STATE_DIR}"/instances/*.json "${SINGBOX_CONFIG_FILE}")

# With no remaining inbound, loading/migrating active state is invalid. The
# chooser must discover retained stores without requiring an installed index.
migrate_legacy_single_protocol_state_if_needed() { printf 'unexpected migration\n' >&2; return 1; }
load_current_config_state() { printf 'unexpected active-state load\n' >&2; return 1; }
list_installed_protocols() { printf 'unexpected installed-only inventory read\n' >&2; return 1; }
mapfile -t retained < <(list_retained_instance_protocols)
[[ ${#retained[@]} -eq 14 ]]
for index in "${!retained[@]}"; do
  output=$(update_config_only <<EOF
$((index + 1))
0
EOF
)
  grep -Fq '暂无实例，可重新创建' <<< "${output}"
  grep -Fq -- "--- $(plain_proxy_management_label "${retained[$index]}") 实例管理 ---" <<< "${output}"
done

# An empty index left by a prior version is equally valid, and selecting
# Return must not fall through to the legacy editor with an empty protocol.
printf '%s\n' INSTALLED_PROTOCOLS= PROTOCOL_STATE_VERSION=1 > "${SB_PROTOCOL_INDEX_FILE}"
update_config_only >/dev/null <<'EOF'
0
EOF
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}"/instances/*.json "${SINGBOX_CONFIG_FILE}")" == "${before}" ]]

# Existing protocols remain selectable together with retained stores.
list_installed_protocols() { printf 'vless-reality\n'; }
retained_csv=$(IFS=,; printf '%s' "${retained[*]}")
prompt_installed_protocol_selection "${retained_csv}" >"${TMP_DIR}/choices" <<'EOF'
1
EOF
[[ "${SELECTED_PROTOCOL}" == vless-reality ]]
grep -Fq '1. VLESS + REALITY' "${TMP_DIR}/choices"
grep -Fq '暂无实例，可重新创建' "${TMP_DIR}/choices"

# Corrupt stores and an index with active entries cannot be treated as the
# known empty baseline. Preserve all files instead of inventing revision 0.
printf '%s\n' '{"malformed":true}' > "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json"
! list_retained_instance_protocols | grep -Fxq mixed
printf '%s\n' INSTALLED_PROTOCOLS=vless-reality PROTOCOL_STATE_VERSION=1 > "${SB_PROTOCOL_INDEX_FILE}"
if instance_management_empty_config_baseline; then
  printf 'nonempty protocol index accepted as an empty baseline\n' >&2
  exit 1
fi

printf 'retained instance menu checks passed: protocols=14 missing/empty-index=2 cancel=1\n'
