#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
core=${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}
cat > "${TMP_DIR}/bin/sing-box" <<'CORE'
#!/usr/bin/env bash
if [[ "${1:-}" == version ]]; then printf 'sing-box version 1.14.2\n'; else exec "${HY2_TEST_CORE}" "$@"; fi
CORE
cat > "${TMP_DIR}/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
case "${1:-}" in
  show) cat "${HY2_TEST_SERVICE_STATE}" ;;
  is-active) [[ "$(cat "${HY2_TEST_SERVICE_STATE}")" == active ]] ;;
  restart)
    if [[ -f "${HY2_TEST_SERVICE_STATE}.fail-once" ]]; then
      rm -- "${HY2_TEST_SERVICE_STATE}.fail-once"; exit 1
    fi
    printf 'active\n' > "${HY2_TEST_SERVICE_STATE}" ;;
  stop) printf 'inactive\n' > "${HY2_TEST_SERVICE_STATE}" ;;
esac
SYSTEMCTL
chmod +x "${TMP_DIR}/bin/sing-box" "${TMP_DIR}/bin/systemctl"
export HY2_TEST_CORE="${core}" HY2_TEST_SERVICE_STATE="${TMP_DIR}/service.state"
printf 'active\n' > "${HY2_TEST_SERVICE_STATE}"
source "${TESTABLE_INSTALL}"
trap 'printf "HY2 ACME lifecycle failed at line %s\n" "${LINENO}" >&2' ERR

instance_firewall_prepare() {
  jq -n '{schema_version:1,status:"prepared",before_ledger_exists:false,
    before_ledger:{schema_version:1,rules:[]},after_ledger:{schema_version:1,rules:[]},
    operations:[],backend_statuses:[],diagnostics:[]}' > "$3"
}
instance_firewall_apply() { :; }
instance_firewall_rollback() { :; }
mkdir -p "${SB_PROTOCOL_STATE_DIR}"
printf '[Unit]\nDescription=fixture\n' > "${SINGBOX_SERVICE_FILE}"
# Begin with a real legacy ACME record, then add an independent HTTP-01
# instance. The transaction must adopt the old node instead of dropping it.
set_protocol_defaults hy2
SB_HY2_DOMAIN=legacy.example.com
SB_HY2_ACME_DOMAIN=legacy.example.com
SB_HY2_PASSWORD=legacy-password
SB_HY2_OBFS_ENABLED=n
SB_HY2_MASQUERADE=""
SB_PORT=48443
save_hy2_state
printf 'INSTALLED_PROTOCOLS=hy2\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
legacy=$(build_hy2_inbound_json)
provider=$(build_hy2_certificate_provider_json)
jq -n --argjson legacy "${legacy}" --argjson provider "${provider}" \
  '{inbounds:[$legacy,{type:"socks",tag:"existing-socks",listen:"127.0.0.1",listen_port:49080}],
    certificate_providers:[$provider],outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' > "${SINGBOX_CONFIG_FILE}"

make_record() {
  jq -n --arg directory "${TMP_DIR}/acme" '{id:"new",name:"New HY2",tag:"hy2-new",listen:{address:"127.0.0.1",port:48444},
    authentication:{users:[{name:"alice",password:"new-password"}]},
    tls:{enabled:true,server_name:"new.example.com",acme:{domain:["new.example.com"],data_directory:$directory,disable_tls_alpn_challenge:true}},
    client_trust:"system",bandwidth:{up_mbps:null,down_mbps:null},obfs:{enabled:false,type:"",password:""},
    masquerade:"",outbound_policy:"default",dependencies:[]}' > "$1"
}
make_record "${TMP_DIR}/new.json"
plain_proxy_management_capture_snapshot hy2 "${TMP_DIR}/before.json"
jq -e '.revision==0 and (.instances|length)==1 and .instances[0].tls.acme.domain==["legacy.example.com"]' "${TMP_DIR}/before.json" >/dev/null
result=$(apply_plain_proxy_instance_change hy2 create 0 "${TMP_DIR}/new.json" n)
jq -e '.ok and .revision==1' <<< "${result}" >/dev/null
store="${SB_PROTOCOL_STATE_DIR}/instances/hy2.json"
jq -e '.revision==1 and (.instances|length)==2 and any(.instances[]; .tag=="hy2-in" and .tls.acme.domain==["legacy.example.com"])' "${store}" >/dev/null
jq -e '([.inbounds[] | select(.type=="hysteria2")]|length)==2 and any(.inbounds[]; .tag=="existing-socks")' "${SINGBOX_CONFIG_FILE}" >/dev/null
jq -e '(.certificate_providers|length)==0' "${SINGBOX_CONFIG_FILE}" >/dev/null
plain_proxy_structured_state_matches_config hy2
plain_proxy_validate_state_inventory hy2
"${core}" check -c "${SINGBOX_CONFIG_FILE}"

cp "${store}" "${TMP_DIR}/store.before"
cp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/config.before"
if apply_plain_proxy_instance_change hy2 replace 0 "${TMP_DIR}/new.json" n >"${TMP_DIR}/stale.json" 2>"${TMP_DIR}/stale.stderr"; then
  printf 'stale revision accepted\n' >&2; exit 1
fi
cmp "${store}" "${TMP_DIR}/store.before"
cmp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/config.before"

# Real core validation failure and a service restart failure both retain the
# complete ACME state and configuration through the existing rollback path.
jq '.masquerade="not a valid URL"' "${TMP_DIR}/new.json" > "${TMP_DIR}/invalid.json"
if apply_plain_proxy_instance_change hy2 replace 1 "${TMP_DIR}/invalid.json" n >"${TMP_DIR}/invalid.result" 2>"${TMP_DIR}/invalid.stderr"; then
  printf 'invalid core configuration accepted\n' >&2; exit 1
fi
cmp "${store}" "${TMP_DIR}/store.before"
cmp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/config.before"
jq '.tls.acme.email="admin@example.com"' "${TMP_DIR}/new.json" > "${TMP_DIR}/replace.json"
touch "${HY2_TEST_SERVICE_STATE}.fail-once"
if apply_plain_proxy_instance_change hy2 replace 1 "${TMP_DIR}/replace.json" n >"${TMP_DIR}/rollback.json" 2>"${TMP_DIR}/rollback.stderr"; then
  printf 'restart failure accepted\n' >&2; exit 1
fi
jq -e '.transaction.status=="rolled_back" and .transaction.manual_intervention_required==false' "${TMP_DIR}/rollback.json" >/dev/null
cmp "${store}" "${TMP_DIR}/store.before"
cmp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/config.before"
result=$(apply_plain_proxy_instance_change hy2 replace 1 "${TMP_DIR}/replace.json" n)
jq -e '.ok and .revision==2' <<< "${result}" >/dev/null
result=$(apply_plain_proxy_instance_change hy2 delete 2 new n)
jq -e '.ok and .revision==3' <<< "${result}" >/dev/null
jq -e '(.instances|length)==1 and .instances[0].tls.acme.domain==["legacy.example.com"]' "${store}" >/dev/null
jq -e '([.inbounds[] | select(.type=="hysteria2")]|length)==1 and any(.inbounds[]; .tag=="existing-socks")' "${SINGBOX_CONFIG_FILE}" >/dev/null
plain_proxy_structured_state_matches_config hy2
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
printf 'HY2 ACME create, legacy adoption, CAS, replace, delete and rollback passed\n'
