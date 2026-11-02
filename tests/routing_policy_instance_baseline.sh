#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120

cat > "${TMP_DIR}/bin/sing-box" <<'CORE'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  version) printf 'sing-box version 1.14.2\n' ;;
  check)
    jq -e 'type == "object"' "$3" >/dev/null
    if [[ -n "${ROUTING_POLICY_TEST_REAL_CORE:-}" ]]; then
      "${ROUTING_POLICY_TEST_REAL_CORE}" "$@"
    fi
    ;;
  *) exit 1 ;;
esac
CORE
cat > "${TMP_DIR}/bin/systemctl" <<'SERVICE'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  show) cat "${ROUTING_INSTANCE_SERVICE_STATE}" ;;
  is-active) [[ "$(cat "${ROUTING_INSTANCE_SERVICE_STATE}")" == active ]] ;;
  restart)
    if [[ -e "${ROUTING_INSTANCE_SERVICE_STATE}.fail-once" ]]; then
      rm -- "${ROUTING_INSTANCE_SERVICE_STATE}.fail-once"; exit 1
    fi
    printf 'active\n' > "${ROUTING_INSTANCE_SERVICE_STATE}" ;;
  stop) printf 'inactive\n' > "${ROUTING_INSTANCE_SERVICE_STATE}" ;;
esac
SERVICE
chmod +x "${TMP_DIR}/bin/sing-box" "${TMP_DIR}/bin/systemctl"
export ROUTING_INSTANCE_SERVICE_STATE="${TMP_DIR}/service.state"
printf 'active\n' > "${ROUTING_INSTANCE_SERVICE_STATE}"
source "${TESTABLE_INSTALL}"
source "${REPO_ROOT}/src/install/40-routing-policy.sh"
source "${REPO_ROOT}/src/install/20-config-ownership-and-apply.sh"
source "${REPO_ROOT}/src/install/22-config-generator-and-uninstall.sh"
source "${REPO_ROOT}/src/install/32-instance-transactions.sh"
trap 'printf "routing policy instance baseline failed at line %s\n" "${LINENO}" >&2' ERR

instance_firewall_prepare() {
  printf '%s\n' '{"schema_version":1,"status":"prepared","backend_statuses":[],"diagnostics":[]}' > "$3"
}
instance_firewall_apply() { :; }
instance_firewall_rollback() { :; }
mkdir -p "${SB_PROTOCOL_STATE_DIR}"
printf '[Unit]\nDescription=fixture\n' > "${SINGBOX_SERVICE_FILE}"
printf 'INSTALLED_PROTOCOLS=mixed\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
cat > "${SB_PROTOCOL_STATE_DIR}/mixed.env" <<'STATE'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME='Legacy Mixed'
PORT=13090
AUTH_ENABLED=n
USERNAME=
PASSWORD=
STATE
policy_file=$(routing_policy_file_path)
policy=$(routing_policy_read_json | jq -c '.server.private_network_block=false |
  .server.adblock=true | .adblock.url="" | .adblock.domains=["ads.example"]')
printf '%s\n' "${policy}" > "${policy_file}"
chmod 600 "${policy_file}"
SB_ENABLE_WARP=n
SB_ADVANCED_ROUTE=n
SB_WARP_ROUTE_MODE=selective
SB_OUTBOUND_STACK_MODE=prefer_ipv4
generate_config >/dev/null
baseline_file="${SB_PROJECT_DIR}/managed-config.generated.json"
# A real operator listener and scoped rule remain outside the generated record.
jq '.inbounds += [{type:"mixed",tag:"operator-mixed",listen:"127.0.0.1",listen_port:13092}] |
  .route.rules = [{inbound:"operator-mixed",action:"route",outbound:"direct"}] + .route.rules' \
  "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/manual.json"
mv "${TMP_DIR}/manual.json" "${SINGBOX_CONFIG_FILE}"
jq -n '{id:"added",name:"Added Mixed",tag:"mixed-added",listen:{address:"127.0.0.1",port:13091},
  authentication:{enabled:false,username:"",password:""},outbound_policy:"direct",dependencies:[]}' \
  > "${TMP_DIR}/record.json"

cp -p "${baseline_file}" "${TMP_DIR}/baseline.before"
printf 'previous-backup\n' > "${baseline_file}.bak"
touch "${ROUTING_INSTANCE_SERVICE_STATE}.fail-once"
if apply_plain_proxy_instance_change mixed create 0 "${TMP_DIR}/record.json" n \
  > "${TMP_DIR}/rollback.json" 2> "${TMP_DIR}/rollback.err"; then
  printf 'restart failure was accepted\n' >&2; exit 1
fi
jq -e '.transaction.status == "rolled_back"' "${TMP_DIR}/rollback.json" >/dev/null
cmp "${baseline_file}" "${TMP_DIR}/baseline.before"
[[ "$(cat "${baseline_file}.bak")" == previous-backup ]]
result=$(apply_plain_proxy_instance_change mixed create 0 "${TMP_DIR}/record.json" n)
jq -e '.ok and .revision == 1' <<< "${result}" >/dev/null
jq -e '.route.rules[0].inbound == "operator-mixed"' "${SINGBOX_CONFIG_FILE}" >/dev/null
cmp "${baseline_file}.bak" "${TMP_DIR}/baseline.before"
jq -e 'any(.inbounds[]; .tag == "mixed-added") and
  all(.inbounds[]; .tag != "operator-mixed") and
  all(.route.rules[]; .inbound != "operator-mixed") and
  any(.route.rules[]; .rule_set == ["sbv-adblock-inline"] and .inbound == ["mixed-added","mixed-in"])' \
  "${baseline_file}" >/dev/null

# The next real global generation must insert private protection ahead of the
# fixed direct override, preserving the independently scoped manual rule.
jq '.server.private_network_block=true' "${policy_file}" > "${TMP_DIR}/next-policy.json"
mv "${TMP_DIR}/next-policy.json" "${policy_file}"
cp -p "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/safe-live.json"
for manual in \
  '{domain_suffix:["manual.example"],action:"route",outbound:"direct"}' \
  '{inbound:"mixed-in",domain_suffix:["manual.example"],action:"route",outbound:"direct"}'; do
  jq ".route.rules += [${manual}]" "${TMP_DIR}/safe-live.json" > "${SINGBOX_CONFIG_FILE}"
  before=$(sha256sum "${SINGBOX_CONFIG_FILE}")
  if generate_config > "${TMP_DIR}/conflict.out" 2> "${TMP_DIR}/conflict.err"; then
    printf 'manual terminal rule was moved behind new protection\n' >&2; exit 1
  fi
  [[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${before}" ]]
  grep -Fq routing_policy_order_conflict "${TMP_DIR}/conflict.err"
done
cp -p "${TMP_DIR}/safe-live.json" "${SINGBOX_CONFIG_FILE}"
generate_config >/dev/null
jq -e '.route.rules[0].inbound == "operator-mixed" and
  any(.inbounds[]; .tag == "operator-mixed") and
  ([.route.rules | to_entries[] | select(.value.ip_is_private == true) | .key][0]) <
  ([.route.rules | to_entries[] | select(.value.inbound == "mixed-added" and .value.outbound == "direct") | .key][0])' \
  "${SINGBOX_CONFIG_FILE}" >/dev/null || {
    jq '.route.rules' "${SINGBOX_CONFIG_FILE}" >&2
    exit 1
  }
"${SINGBOX_BIN_PATH}" check -c "${SINGBOX_CONFIG_FILE}"
printf 'Typed baseline commit, service rollback and subsequent global policy generation passed\n'
