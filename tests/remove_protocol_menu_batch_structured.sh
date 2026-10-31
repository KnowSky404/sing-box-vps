#!/usr/bin/env bash

set -euo pipefail
trap 'printf "[ERROR] batch removal regression failed at %s:%s (exit=%s)\n" "${BASH_SOURCE[0]}" "${LINENO}" "$?" >&2' ERR

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
core=${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}
export BATCH_REMOVE_TEST_CORE="${core}"
cat > "${TMP_DIR}/bin/sing-box" <<'CORE'
#!/usr/bin/env bash
exec "${BATCH_REMOVE_TEST_CORE}" "$@"
CORE
cat > "${TMP_DIR}/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${BATCH_REMOVE_TEST_SYSTEMCTL_LOG}"
case "${1:-}" in
  show) cat "${BATCH_REMOVE_TEST_SERVICE_STATE}" ;;
  is-active) [[ "$(cat "${BATCH_REMOVE_TEST_SERVICE_STATE}")" == active ]] ;;
  restart)
    if [[ -e "${BATCH_REMOVE_TEST_RESTART_FAILURE}" ]]; then
      rm -- "${BATCH_REMOVE_TEST_RESTART_FAILURE}"
      printf 'failed\n' > "${BATCH_REMOVE_TEST_SERVICE_STATE}"
      exit 47
    fi
    printf 'active\n' > "${BATCH_REMOVE_TEST_SERVICE_STATE}"
    ;;
  daemon-reload|enable)
    if [[ -f "${BATCH_REMOVE_TEST_SETUP_FAILURE}" ]] &&
       [[ "$(cat "${BATCH_REMOVE_TEST_SETUP_FAILURE}")" == "$1" ]]; then
      rm -- "${BATCH_REMOVE_TEST_SETUP_FAILURE}"
      exit 48
    fi
    ;;
  stop) printf 'inactive\n' > "${BATCH_REMOVE_TEST_SERVICE_STATE}" ;;
esac
SYSTEMCTL
chmod +x "${TMP_DIR}/bin/sing-box" "${TMP_DIR}/bin/systemctl"
export BATCH_REMOVE_TEST_SERVICE_STATE="${TMP_DIR}/service.state"
export BATCH_REMOVE_TEST_SYSTEMCTL_LOG="${TMP_DIR}/systemctl.log"
export BATCH_REMOVE_TEST_RESTART_FAILURE="${TMP_DIR}/restart-failure"
export BATCH_REMOVE_TEST_SETUP_FAILURE="${TMP_DIR}/setup-failure"
source "${TESTABLE_INSTALL}"
original_setup_service=$(declare -f setup_service)
eval "${original_setup_service/setup_service/batch_remove_actual_setup_service}"

# Host resources are mocked; the actual store/CAS/config transaction and core
# validation run below, against paths redirected into the private fixture.
setup_service() { :; }
open_committed_protocol_ports() { :; }
refresh_vless_reality_qos_rules() { :; }
clear_vless_reality_qos_rules() { :; }
close_firewall_port() { printf '%s\n' "$*" >> "${TMP_DIR}/closed-ports"; }
instance_firewall_prepare() {
  jq -n '{schema_version:1,status:"prepared",before_ledger_exists:false,
    before_ledger:{schema_version:1,rules:[]},after_ledger:{schema_version:1,rules:[]},
    operations:[],backend_statuses:[],diagnostics:[]}' > "$3"
}
instance_firewall_apply() { :; }
instance_firewall_rollback() { :; }

# Legacy generation is covered separately. Here it removes the selected legacy
# REALITY projection while keeping the config produced by instance transactions.
generate_config() {
  local candidate="${TMP_DIR}/generated.json"
  if [[ -f "$(protocol_state_file vless-reality)" ]]; then
    cp "${SINGBOX_CONFIG_FILE}" "${candidate}"
  else
    jq '.inbounds |= map(select((.tls.reality.enabled // false) | not))' "${SINGBOX_CONFIG_FILE}" > "${candidate}"
  fi
  "${core}" check -c "${candidate}"
  cp "${candidate}" "${SINGBOX_CONFIG_FILE}"
  cp "${candidate}" "${SB_PROJECT_DIR}/managed-config.generated.json"
}

openssl req -x509 -newkey ed25519 -nodes \
  -keyout "${TMP_DIR}/hy2.key" -out "${TMP_DIR}/hy2.crt" \
  -subj /CN=hy2.example -days 1 >/dev/null 2>&1

restore_fixture() {
  local include_http=${1:-n} reality hy2 http
  rm -rf -- "${SB_PROTOCOL_STATE_DIR}" "${SB_PROJECT_DIR}.instance-write.lock" "${SB_COMPONENT_TRANSACTION_DIR}"
  rm -f -- "${SB_PROJECT_DIR}/managed-config.generated.json" "${TMP_DIR}/closed-ports" \
    "${BATCH_REMOVE_TEST_RESTART_FAILURE}" "${BATCH_REMOVE_TEST_SETUP_FAILURE}" "${TMP_DIR}/instance-calls"
  mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances" "${SB_PROTOCOL_STATE_DIR}/vless-reality.d"
  printf 'active\n' > "${BATCH_REMOVE_TEST_SERVICE_STATE}"
  : > "${BATCH_REMOVE_TEST_SYSTEMCTL_LOG}"
  printf '[Unit]\nDescription=fixture\n' > "${SINGBOX_SERVICE_FILE}"
  cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'STATE'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main
REALITY_PRIVATE_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
REALITY_PUBLIC_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
STATE
  cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" <<'STATE'
INSTANCE_ID=main
INBOUND_TAG=vless-in
ENABLED=1
NODE_NAME=Reality
PORT=48443
UUID=11111111-1111-1111-1111-111111111111
SNI=example.com
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=
ALPN_MODE=off
TCP_FAST_OPEN=n
OUTBOUND_POLICY=default
STATE
  jq -n --arg certificate_path "${TMP_DIR}/hy2.crt" --arg key_path "${TMP_DIR}/hy2.key" '
    {schema_version:1,protocol:"hy2",revision:9,default_instance_id:"edge",instances:[
      {id:"edge",name:"Edge",tag:"hy2-edge",listen:{address:"127.0.0.1",port:48444},
       authentication:{users:[{name:"alice",password:"fixture-password"}]},
       tls:{enabled:true,server_name:"hy2.example",certificate_path:$certificate_path,key_path:$key_path},
       client_trust:"system",bandwidth:{up_mbps:null,down_mbps:null},
       obfs:{enabled:false,type:"",password:""},masquerade:"",
       outbound_policy:"default",dependencies:[]}
    ]} | .instances += [(.instances[0] | .id="backup" | .name="Backup" | .tag="hy2-backup" | .listen.port=48445)]
  ' > "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json"
  save_plain_proxy_structured_marker hy2
  reality=$(build_vless_inbound_json_for_instance main)
  hy2=$(render_structured_instance_inbounds hy2 "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json" | jq -s .)
  http='[]'
  if [[ "${include_http}" == y ]]; then
    jq -n '{schema_version:1,protocol:"http",revision:4,default_instance_id:"keep",instances:[
      {id:"keep",name:"Keep",tag:"http-keep",listen:{address:"127.0.0.1",port:49080},
       authentication:{enabled:true,username:"fixture-user",password:"fixture-password"},
       tls:{enabled:false},outbound_policy:"default",dependencies:[]}
    ]}' > "${SB_PROTOCOL_STATE_DIR}/instances/http.json"
    save_plain_proxy_structured_marker http
    http=$(render_structured_instance_inbounds http "${SB_PROTOCOL_STATE_DIR}/instances/http.json" | jq -s .)
  fi
  jq -n --argjson reality "${reality}" --argjson hy2 "${hy2}" --argjson http "${http}" \
    '{inbounds:([$reality]+$hy2+$http),outbounds:[{type:"direct",tag:"direct"}],route:{rules:[],final:"direct"}}' \
    > "${SINGBOX_CONFIG_FILE}"
  if [[ "${include_http}" == y ]]; then
    write_protocol_index vless-reality,hy2,http
  else
    write_protocol_index vless-reality,hy2
  fi
  cp "${SINGBOX_CONFIG_FILE}" "${SB_PROJECT_DIR}/managed-config.generated.json"
  chmod 600 "${SINGBOX_CONFIG_FILE}" "${SB_PROJECT_DIR}/managed-config.generated.json" \
    "${SB_PROTOCOL_STATE_DIR}"/*.env "${SB_PROTOCOL_STATE_DIR}"/instances/*.json
  "${core}" check -c "${SINGBOX_CONFIG_FILE}"
  plain_proxy_structured_state_matches_config hy2
}

assert_hy2_removed() {
  jq -e '.revision==11 and .instances==[] and .default_instance_id==""' \
    "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json" >/dev/null
  [[ ! -e "$(protocol_state_file hy2)" ]]
  [[ ! -d "${SB_PROJECT_DIR}.instance-write.lock" ]]
}

assert_reality_removed() {
  [[ ! -e "$(protocol_state_file vless-reality)" ]]
  [[ ! -e "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" ]]
}

capture_removal_state() {
  sha256sum "${SINGBOX_CONFIG_FILE}" "${SB_PROTOCOL_INDEX_FILE}" \
    "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json" "$(protocol_state_file hy2)" \
    "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" \
    "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" \
    "${SB_PROJECT_DIR}/managed-config.generated.json"
}

# Pending instance/component journals, including symlink paths, block the
# batch before mutation and remain available for explicit recovery.
restore_fixture
before=$(capture_removal_state)
for pending_dir in "${SB_PROJECT_DIR}.instance-write.lock" "${SB_COMPONENT_TRANSACTION_DIR}"; do
  for pending_shape in directory symlink; do
    if [[ "${pending_shape}" == directory ]]; then
      mkdir "${pending_dir}"
      printf 'preserve recovery material\n' > "${pending_dir}/fixture"
    else
      ln -s "${TMP_DIR}/missing-recovery-target" "${pending_dir}"
    fi
    failed_status=0
    output=$(remove_protocol_batch vless-reality hy2 <<< y 2>&1) || failed_status=$?
    [[ "${failed_status}" != 0 ]] || {
      printf 'expected pending %s journal to block batch removal:\n%s\n' "${pending_shape}" "${output}" >&2
      exit 1
    }
    [[ "$(capture_removal_state)" == "${before}" ]]
    ! grep -Eq "^(restart|stop|disable|enable|daemon-reload)( |$)" "${BATCH_REMOVE_TEST_SYSTEMCTL_LOG}"
    if [[ "${pending_shape}" == directory ]]; then
      [[ "$(cat "${pending_dir}/fixture")" == 'preserve recovery material' ]]
      rm -- "${pending_dir}/fixture"
      rmdir "${pending_dir}"
    else
      [[ -L "${pending_dir}" ]]
      rm -- "${pending_dir}"
    fi
  done
done

# A valid typed store with a divergent live projection is rejected before
# the legacy REALITY removal can commit any work.
restore_fixture
jq '(.inbounds[] | select(.tag=="hy2-edge") | .users[0].password)="changed-outside-store"' \
  "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/drift-config.json"
cp "${TMP_DIR}/drift-config.json" "${SINGBOX_CONFIG_FILE}"
before=$(capture_removal_state)
failed_status=0
output=$(remove_protocol_menu <<< $'1,2\ny' 2>&1) || failed_status=$?
[[ "${failed_status}" != 0 ]] || {
  printf 'expected typed config drift to block the complete batch:\n%s\n' "${output}" >&2
  exit 1
}
[[ "$(capture_removal_state)" == "${before}" ]]
! grep -Eq "^(restart|stop|disable|enable|daemon-reload)( |$)" "${BATCH_REMOVE_TEST_SYSTEMCTL_LOG}"
[[ ! -e "${TMP_DIR}/closed-ports" ]]

# A single confirmation cancels the complete batch before any store/config or
# service mutation. Both explicit and blank (all-protocol) selection are valid.
for choice in 1,2 ''; do
  restore_fixture
  before=$(sha256sum "${SINGBOX_CONFIG_FILE}" "${SB_PROTOCOL_INDEX_FILE}" \
    "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json" "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" \
    "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env")
  cancel_status=0
  output=$(remove_protocol_menu <<< "${choice}"$'\nn\n' 2>&1) || cancel_status=$?
  [[ "${cancel_status}" == 0 ]] || {
    printf 'expected cancelled structured batch to return successfully, status=%s:\n%s\n' "${cancel_status}" "${output}" >&2
    exit 1
  }
  [[ "$(sha256sum "${SINGBOX_CONFIG_FILE}" "${SB_PROTOCOL_INDEX_FILE}" \
    "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json" "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" \
    "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env")" == "${before}" ]]
  ! grep -Eq "^(restart|stop|disable|enable|daemon-reload)( |$)" "${BATCH_REMOVE_TEST_SYSTEMCTL_LOG}"
done

for choice in 1,2 2,1 ''; do
  restore_fixture
  output=$(remove_protocol_menu <<< "${choice}"$'\ny\n' 2>&1) || {
    printf 'expected REALITY + structured HY2 batch selection %s to succeed:\n%s\n' "${choice:-all}" "${output}" >&2
    exit 1
  }
  assert_hy2_removed
  assert_reality_removed
  [[ -f "${SINGBOX_CONFIG_FILE}" && -f "${SB_PROTOCOL_INDEX_FILE}" ]]
  [[ -z "$(extract_protocols_from_index)" ]]
  jq -e '(.inbounds|length)==0' "${SINGBOX_CONFIG_FILE}" >/dev/null
  "${core}" check -c "${SINGBOX_CONFIG_FILE}"
done

# Selecting REALITY together with another protocol removes all REALITY
# instances without unexpectedly asking for a second scope/target selection.
restore_fixture
sed -e 's/^INSTANCE_ID=main$/INSTANCE_ID=extra/' \
  -e 's/^INBOUND_TAG=vless-in$/INBOUND_TAG=vless-extra/' \
  -e 's/^PORT=48443$/PORT=48446/' \
  "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" \
  > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/extra.env"
sed -i 's/^INSTANCE_IDS=main$/INSTANCE_IDS=main,extra/' "$(protocol_state_file vless-reality)"
extra=$(build_vless_inbound_json_for_instance extra)
jq --argjson extra "${extra}" '.inbounds += [$extra]' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/multiple-reality.json"
cp "${TMP_DIR}/multiple-reality.json" "${SINGBOX_CONFIG_FILE}"
cp "${SINGBOX_CONFIG_FILE}" "${SB_PROJECT_DIR}/managed-config.generated.json"
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
output=$(remove_protocol_menu <<<'1,2
y' 2>&1) || {
  printf 'expected batch removal of every REALITY instance:\n%s\n' "${output}" >&2
  exit 1
}
assert_hy2_removed
assert_reality_removed
[[ ! -e "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/extra.env" ]]

restore_fixture y
cp "${SB_PROTOCOL_STATE_DIR}/instances/http.json" "${TMP_DIR}/http.before"
output=$(remove_protocol_menu <<<'1,2
y' 2>&1) || {
  printf 'expected removal to preserve unselected HTTP:\n%s\n' "${output}" >&2
  exit 1
}
assert_hy2_removed
assert_reality_removed
cmp -s "${TMP_DIR}/http.before" "${SB_PROTOCOL_STATE_DIR}/instances/http.json"
[[ -f "$(protocol_state_file http)" ]]
[[ "$(list_installed_protocols)" == http ]]
jq -e '.inbounds|length==1 and .[0].tag=="http-keep"' "${SINGBOX_CONFIG_FILE}" >/dev/null
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
# A batch containing only structured protocols retains each revisioned empty
# store and the empty runtime configuration, preserving later create/CAS flows.
restore_fixture y
rm -- "$(protocol_state_file vless-reality)" "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env"
jq '.inbounds |= map(select(.tag != "vless-in"))' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/structured-only.json"
cp "${TMP_DIR}/structured-only.json" "${SINGBOX_CONFIG_FILE}"
cp "${SINGBOX_CONFIG_FILE}" "${SB_PROJECT_DIR}/managed-config.generated.json"
write_protocol_index hy2,http
output=$(remove_protocol_menu <<<'
y' 2>&1) || {
  printf 'expected structured-only all selection to succeed:\n%s\n' "${output}" >&2
  exit 1
}
assert_hy2_removed
jq -e '.revision==5 and .instances==[] and .default_instance_id==""' \
  "${SB_PROTOCOL_STATE_DIR}/instances/http.json" >/dev/null
[[ ! -e "$(protocol_state_file http)" ]]
[[ -z "$(extract_protocols_from_index)" ]]
jq -e '(.inbounds|length)==0' "${SINGBOX_CONFIG_FILE}" >/dev/null
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
# The legacy continuation runs in an if-condition. Its service failure must
# be propagated explicitly instead of being hidden by Bash's errexit rules.
restore_fixture
cp "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json" "${TMP_DIR}/hy2.before-restart-failure"
: > "${BATCH_REMOVE_TEST_RESTART_FAILURE}"
failed_status=0
output=$(remove_protocol_menu <<< $'1,2\ny' 2>&1) || failed_status=$?
[[ "${failed_status}" == 47 ]] || {
  printf 'expected legacy restart failure status 47, got %s:\n%s\n' "${failed_status}" "${output}" >&2
  exit 1
}
assert_reality_removed
cmp -s "${TMP_DIR}/hy2.before-restart-failure" "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json"
jq -e '.revision==9 and (.instances|length)==2' "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json" >/dev/null
[[ -f "$(protocol_state_file hy2)" ]]
[[ "$(grep -c '^restart sing-box$' "${BATCH_REMOVE_TEST_SYSTEMCTL_LOG}")" == 1 ]]
[[ "$(cat "${BATCH_REMOVE_TEST_SERVICE_STATE}")" == failed ]]
[[ ! -e "${TMP_DIR}/closed-ports" && ! -e "${SB_PROJECT_DIR}.instance-write.lock" ]]
grep -Eq '停止|尚未处理' <<< "${output}"
plain_proxy_structured_state_matches_config hy2
"${core}" check -c "${SINGBOX_CONFIG_FILE}"

# Failures while installing the systemd unit must also stop the legacy
# continuation before any restart, firewall cleanup or typed deletion.
for setup_failure_action in daemon-reload enable; do
  restore_fixture
  cp "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json" "${TMP_DIR}/hy2.before-setup-failure"
  printf '%s\n' "${setup_failure_action}" > "${BATCH_REMOVE_TEST_SETUP_FAILURE}"
  failed_status=0
  output=$(
    setup_service() { batch_remove_actual_setup_service; }
    ensure_sbv_command_installed() { :; }
    remove_protocol_menu <<< $'1,2\ny' 2>&1
  ) || failed_status=$?
  [[ "${failed_status}" == 48 ]] || {
    printf 'expected legacy %s failure status 48, got %s:\n%s\n' "${setup_failure_action}" "${failed_status}" "${output}" >&2
    exit 1
  }
  assert_reality_removed
  cmp -s "${TMP_DIR}/hy2.before-setup-failure" "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json"
  jq -e '.revision==9 and (.instances|length)==2' "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json" >/dev/null
  [[ -f "$(protocol_state_file hy2)" ]]
  grep -Fxq "${setup_failure_action}$([[ "${setup_failure_action}" == enable ]] && printf ' sing-box')" "${BATCH_REMOVE_TEST_SYSTEMCTL_LOG}"
  ! grep -Eq '^(restart|stop)( |$)' "${BATCH_REMOVE_TEST_SYSTEMCTL_LOG}"
  if [[ "${setup_failure_action}" == daemon-reload ]]; then
    ! grep -Eq '^enable( |$)' "${BATCH_REMOVE_TEST_SYSTEMCTL_LOG}"
  fi
  [[ ! -e "${TMP_DIR}/closed-ports" && ! -e "${SB_PROJECT_DIR}.instance-write.lock" ]]
  grep -Eq '停止|尚未处理' <<< "${output}"
  plain_proxy_structured_state_matches_config hy2
  "${core}" check -c "${SINGBOX_CONFIG_FILE}"
done

# The batch consists of separate transactions. If a later instance fails,
# earlier commits remain visible and later targets are not attempted. The
# failed transaction must not be reported as complete or restore earlier work.
restore_fixture y
original_apply=$(declare -f apply_plain_proxy_instance_change)
eval "${original_apply/apply_plain_proxy_instance_change/batch_remove_actual_apply}"
apply_plain_proxy_instance_change() {
  printf '%s %s %s %s\n' "$1" "$2" "$3" "$4" >> "${TMP_DIR}/instance-calls"
  if [[ "$1" == hy2 && "$4" == backup ]]; then
    printf '{"ok":false,"error":"fixture_failure","transaction":{"status":"unchanged"}}\n'
    return 71
  fi
  batch_remove_actual_apply "$@"
}
failed_status=0
output=$(remove_protocol_menu <<<'1,2,3
y' 2>&1) || failed_status=$?
[[ "${failed_status}" != 0 ]] || {
  printf 'expected a failed instance transaction to stop the batch:\n%s\n' "${output}" >&2
  exit 1
}
assert_reality_removed
jq -e '.revision==10 and (.instances|length)==1 and .instances[0].id=="backup"' \
  "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json" >/dev/null
jq -e '.revision==4 and (.instances|length)==1' "${SB_PROTOCOL_STATE_DIR}/instances/http.json" >/dev/null
[[ -f "$(protocol_state_file hy2)" && -f "$(protocol_state_file http)" ]]
[[ "$(cat "${TMP_DIR}/instance-calls")" == $'hy2 delete 9 edge\nhy2 delete 10 backup' ]]
grep -Eq '部分|已提交|停止' <<< "${output}"
plain_proxy_structured_state_matches_config hy2
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
printf 'batch protocol removal passed: cancellation=2 selection-orders=3 HY2-instances=2 multiple-REALITY=1 preserved-protocol=HTTP structured-only=1 partial-failure=1 pending-journals=4 config-drift=1 legacy-restart-failure=1 legacy-setup-failure=2\n'

