#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
core=${ROUTING_POLICY_TEST_REAL_CORE:-${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}}
[[ -x "${core}" ]] || { printf 'real sing-box 1.14.2 core required\n' >&2; exit 1; }
[[ "$("${core}" version | head -n 1)" == 'sing-box version 1.14.2' ]]
ln -s "${core}" "${TMP_DIR}/bin/sing-box"
cat > "${TMP_DIR}/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
printf 'unexpected systemctl call: %s\n' "$*" >&2
exit 98
SYSTEMCTL
chmod +x "${TMP_DIR}/bin/systemctl"
source_testable_install
trap 'printf "neutral rebuild defaults failed at line %s\n" "${LINENO}" >&2' ERR
[[ "${SB_ADVANCED_ROUTE}" == n ]]

# Retained node state represents a neutral installation with no policy file.
# Prepare it through the real state writer and validated generator, then lose
# only the live config. The Agent command below starts a separate shell.
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
# A loopback node avoids firewall mutations in this host-only recovery test.
store_file=$(mixed_structured_store_file)
jq -n '{schema_version:1,protocol:"mixed",revision:7,default_instance_id:"main",instances:[
  {id:"main",name:"Retained Mixed",tag:"mixed-in",listen:{address:"127.0.0.1",port:18080},
   authentication:{enabled:false,username:"",password:""},outbound_policy:"default",dependencies:[]}]}' \
  > "${store_file}"
chmod 600 "${store_file}"
save_mixed_structured_marker
SB_INBOUND_STACK_MODE=ipv4_only SB_OUTBOUND_STACK_MODE=prefer_ipv4
save_stack_mode_state
write_protocol_index mixed
generate_config > "${TMP_DIR}/initial.log" 2>&1
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
jq -e 'all(.route.rules[]; (.ip_is_private // false) == false)' "${SINGBOX_CONFIG_FILE}" >/dev/null
sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env" "${SB_PROTOCOL_INDEX_FILE}" "${store_file}" > "${TMP_DIR}/nodes.before"
rm -- "${SINGBOX_CONFIG_FILE}"
cp -a -- "${SB_PROJECT_DIR}" "${TMP_DIR}/retained-neutral"

# Negative control: the former initial flag reproduces the unintended rule
# through the same public Agent operation, without touching the real script.
sed 's/^SB_ADVANCED_ROUTE="n"$/SB_ADVANCED_ROUTE="y"/' "${TESTABLE_INSTALL}" > "${TMP_DIR}/old-default.sh"
if ! bash "${TMP_DIR}/old-default.sh" agent component rebuild --json --yes --expected-revision 0 \
  > "${TMP_DIR}/old-result.json" 2> "${TMP_DIR}/old-result.stderr"; then
  cat "${TMP_DIR}/old-result.json" "${TMP_DIR}/old-result.stderr" >&2
  exit 1
fi
jq -e '.action == "component-apply" and .operation == "rebuild" and .revision == 0 and (.service_restarted | not)' \
  "${TMP_DIR}/old-result.json" >/dev/null
jq -e 'any(.route.rules[]; .ip_is_private == true and .action == "reject")' \
  "${SINGBOX_CONFIG_FILE}" >/dev/null

rm -rf -- "${SB_PROJECT_DIR}"
cp -a -- "${TMP_DIR}/retained-neutral" "${SB_PROJECT_DIR}"
if ! bash "${TESTABLE_INSTALL}" agent component rebuild --json --yes --expected-revision 0 \
  > "${TMP_DIR}/result.json" 2> "${TMP_DIR}/result.stderr"; then
  cat "${TMP_DIR}/result.json" "${TMP_DIR}/result.stderr" >&2
  exit 1
fi
jq -e '.action == "component-apply" and .operation == "rebuild" and .revision == 0 and (.service_restarted | not)' \
  "${TMP_DIR}/result.json" >/dev/null
jq -e '.route.final == "direct" and (.endpoints | length) == 0 and
  any(.inbounds[]; .type == "mixed" and .listen_port == 18080) and
  all(.route.rules[]; (.ip_is_private // false) == false and .action != "reject")' \
  "${SINGBOX_CONFIG_FILE}" >/dev/null
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env" "${SB_PROTOCOL_INDEX_FILE}" "${store_file}" > "${TMP_DIR}/nodes.after"
cmp "${TMP_DIR}/nodes.before" "${TMP_DIR}/nodes.after"
for path in "${SB_ROUTING_POLICY_FILE}" "${SB_WARP_KEY_FILE}" "${SB_WARP_ROUTE_SETTINGS_FILE}" \
  "${SB_WARP_DOMAINS_FILE}" "${SB_WARP_REMOTE_RULESETS_FILE}" "${SB_WARP_LOCAL_RULESET_DIR}"; do
  [[ ! -e "${path}" && ! -L "${path}" ]]
done

# A neutral initial value must not prevent reading explicitly retained legacy
# private protection. Full legacy rendering/runtime coverage is separate.
jq '.route.rules += [{ip_is_private:true,action:"reject"}]' "${SINGBOX_CONFIG_FILE}" \
  > "${TMP_DIR}/legacy-private.json"
"${core}" check -c "${TMP_DIR}/legacy-private.json"
load_config_generation_settings "${TMP_DIR}/legacy-private.json"
[[ "${SB_ADVANCED_ROUTE}" == y ]]
printf 'Fresh Agent neutral rebuild passed sing-box 1.14.2 check; old-default regression reproduced; explicit legacy setting retained\n'
