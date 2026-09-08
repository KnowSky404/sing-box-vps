#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 126

cat > "${TMP_DIR}/bin/sing-box" <<'EOF_CORE'
#!/usr/bin/env bash
case "${1:-}" in
  version) printf 'sing-box version 1.14.0\n' ;;
  check) exit 0 ;;
  *) exit 64 ;;
esac
EOF_CORE
chmod +x "${TMP_DIR}/bin/sing-box"
cat > "${TMP_DIR}/bin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
case "${1:-}:${2:-}:${3:-}" in
  is-active:--quiet:sing-box) exit 0 ;;
  is-active:sing-box:) printf 'active\n' ;;
  show:*) printf 'active\n' ;;
  *) exit 0 ;;
esac
EOF_SYSTEMCTL
chmod +x "${TMP_DIR}/bin/systemctl"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
trap 'printf "VLESS Agent/share failed at line %s\n" "${LINENO}" >&2' ERR
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances" "${SB_PROJECT_DIR}"
printf 'INSTALLED_PROTOCOLS=vless-plain\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
printf '%s\n' INSTALLED=1 CONFIG_SCHEMA_VERSION=2 > "${SB_PROTOCOL_STATE_DIR}/vless-plain.env"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=vless-agent.example' \
  -keyout "${TMP_DIR}/vless.key" -out "${TMP_DIR}/vless.crt" >/dev/null 2>&1

jq -n --arg cert "${TMP_DIR}/vless.crt" --arg key "${TMP_DIR}/vless.key" '
  {schema_version:1,protocol:"vless-plain",revision:3,default_instance_id:"public",instances:[
    {id:"local",name:"Local VLESS",tag:"vless-local",listen:{address:"127.0.0.1",port:33441},
     authentication:{users:[{name:"local-user",uuid:"11111111-1111-4111-8111-111111111111",flow:""}]},
     tls:{enabled:false},client_trust:"system",transport:{type:"none"},outbound_policy:"default",dependencies:[]},
    {id:"public",name:"Public VLESS",tag:"vless-public",listen:{address:"0.0.0.0",port:33442},
     authentication:{users:[
       {name:"alice",uuid:"22222222-2222-4222-8222-222222222222",flow:""},
       {name:"bob",uuid:"33333333-3333-4333-8333-333333333333",flow:""}]},
     tls:{enabled:true,server_name:"vless-agent.example",certificate_path:$cert,key_path:$key},client_trust:"system",
     transport:{type:"ws",path:"/vless",headers:{Host:"vless-agent.example"}},outbound_policy:"direct",dependencies:[]}
  ]}
' > "${SB_PROTOCOL_STATE_DIR}/instances/vless-plain.json"
chmod 600 "${SB_PROTOCOL_STATE_DIR}/vless-plain.env" "${SB_PROTOCOL_STATE_DIR}/instances/vless-plain.json"

rendered=$(render_structured_instance_inbounds vless-plain "${SB_PROTOCOL_STATE_DIR}/instances/vless-plain.json" | jq -s .)
jq --argjson inbounds "${rendered}" '{log:{disabled:true},inbounds:$inbounds,outbounds:[{type:"direct",tag:"direct"},{type:"direct",tag:"warp-ep"}],route:{final:"direct"}}' \
  > "${SINGBOX_CONFIG_FILE}"

load_plain_proxy_structured_instance vless-plain public
summary=$(agent_vless_plain_node_json 203.0.113.44)
jq -e '.protocol=="vless-plain" and .instance_id=="public" and .user_count==2 and .tls_enabled==true and
  .client_trust=="system" and .transport_type=="ws" and .outbound_policy=="direct" and
  .client_exportable==true and .shareable==true' <<< "${summary}" >/dev/null
links=$(agent_vless_plain_link_json 203.0.113.44)
jq -e '.protocol=="vless-plain" and (.links|length)==2 and (.outbounds|length)==2 and
all(.links[]; startswith("vless://")) and
  all(.outbounds[]; .type=="vless" and .server=="203.0.113.44" and .tls.server_name=="vless-agent.example" and
    (.tls.certificate? == null) and (.transport.type=="ws"))' <<< "${links}" >/dev/null
! grep -Fq "${TMP_DIR}/vless.key" <<< "${links}"
! grep -Fq 'private key fixture' <<< "${links}"

one_link=$(jq -r '.links | to_entries[0].value' <<< "${links}")
[[ "${one_link}" == vless://*"encryption=none"*"type=ws"*"security=tls"*"sni=vless-agent.example"*"path=%2Fvless"*"host=vless-agent.example"* ]]

exported=$(agent_cli export-client --json)
jq -e '.ok==true and .command=="export-client" and
  ([.data.config.outbounds[]|select(.type=="vless")]|length)==3 and
  all(.data.config.outbounds[]|select(.type=="vless"); (.server|type)=="string" and length>0) and
  (tostring|contains("private key fixture")|not)' <<< "${exported}" >/dev/null

# A revision changing between the two snapshots must not produce mixed links.
original_snapshot=$(declare -f structured_instance_store_snapshot_json)
eval "${original_snapshot/structured_instance_store_snapshot_json/original_vless_snapshot}"
structured_instance_store_snapshot_json() {
  local captured
  captured=$(original_vless_snapshot "$@") || return 1
  jq '.revision += 1' "${SB_PROTOCOL_STATE_DIR}/instances/vless-plain.json" > "${TMP_DIR}/drifted.json"
  mv "${TMP_DIR}/drifted.json" "${SB_PROTOCOL_STATE_DIR}/instances/vless-plain.json"
  printf '%s\n' "${captured}"
}
if agent_vless_plain_link_json 203.0.113.44 > "${TMP_DIR}/drift.out" 2> "${TMP_DIR}/drift.err"; then
  printf 'VLESS link renderer accepted a mixed-revision snapshot\n' >&2
  exit 1
fi
[[ ! -s "${TMP_DIR}/drift.out" ]]
eval "$(declare -f original_vless_snapshot | sed '1s/^original_vless_snapshot /structured_instance_store_snapshot_json /')"

printf 'VLESS Agent/share checks passed: links=2 export-outbounds=3\n'
