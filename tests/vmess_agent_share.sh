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
trap 'printf "VMess Agent/share failed at line %s\n" "${LINENO}" >&2' ERR
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances" "${SB_PROJECT_DIR}"
printf 'INSTALLED_PROTOCOLS=vmess\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
printf '%s\n' INSTALLED=1 CONFIG_SCHEMA_VERSION=2 > "${SB_PROTOCOL_STATE_DIR}/vmess.env"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=vmess-agent.example' \
  -keyout "${TMP_DIR}/vmess.key" -out "${TMP_DIR}/vmess.crt" >/dev/null 2>&1

jq -n --arg cert "${TMP_DIR}/vmess.crt" --arg key "${TMP_DIR}/vmess.key" '
  {schema_version:1,protocol:"vmess",revision:3,default_instance_id:"public",instances:[
    {id:"local",name:"Local VMess",tag:"vmess-local",listen:{address:"127.0.0.1",port:33431},
     authentication:{users:[{name:"local-user",uuid:"11111111-1111-4111-8111-111111111111",alter_id:0,security:"auto"}]},
     tls:{enabled:false},client_trust:"system",transport:{type:"none"},outbound_policy:"default",dependencies:[]},
    {id:"public",name:"Public VMess",tag:"vmess-public",listen:{address:"0.0.0.0",port:33432},
     authentication:{users:[{name:"alice",uuid:"22222222-2222-4222-8222-222222222222",alter_id:0,security:"aes-128-gcm"},
       {name:"bob",uuid:"33333333-3333-4333-8333-333333333333",alter_id:7,security:"chacha20-poly1305"}]},
     tls:{enabled:true,server_name:"vmess-agent.example",certificate_path:$cert,key_path:$key},client_trust:"certificate",
     transport:{type:"ws",path:"/vmess",headers:{Host:"vmess-agent.example"}},outbound_policy:"direct",dependencies:[]}
  ]}
' > "${SB_PROTOCOL_STATE_DIR}/instances/vmess.json"
chmod 600 "${SB_PROTOCOL_STATE_DIR}/vmess.env" "${SB_PROTOCOL_STATE_DIR}/instances/vmess.json"

rendered=$(render_structured_instance_inbounds vmess "${SB_PROTOCOL_STATE_DIR}/instances/vmess.json" | jq -s .)
jq --argjson inbounds "${rendered}" '{log:{disabled:true},inbounds:$inbounds,outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' \
  > "${SINGBOX_CONFIG_FILE}"

load_plain_proxy_structured_instance vmess public
summary=$(agent_vmess_node_json 203.0.113.44)
jq -e '.protocol=="vmess" and .instance_id=="public" and .user_count==2 and .tls_enabled==true and .client_trust=="certificate" and .transport_type=="ws" and .client_exportable==true' \
  <<< "${summary}" >/dev/null
links=$(agent_vmess_link_json 203.0.113.44)
jq -e '.protocol=="vmess" and (.links|length)==2 and (.outbounds|length)==2 and all(.links[]; startswith("vmess://")) and all(.outbounds[]; .type=="vmess" and .server=="203.0.113.44" and (.tls.certificate|contains("BEGIN CERTIFICATE")))' \
  <<< "${links}" >/dev/null
! grep -Fq "${TMP_DIR}/vmess.key" <<< "${links}"
! grep -Fq 'private key fixture' <<< "${links}"

# Decode one generated link to check the standard VMess payload and the
# client-only security/alterId fields without treating URI text as a secret log.
one_link=$(jq -r '.links | to_entries[0].value' <<< "${links}")
payload=${one_link#vmess://}
payload=$(printf '%s' "${payload}" | tr '_-' '/+')
remainder=$(( ${#payload} % 4 ))
if (( remainder > 0 )); then
  payload=$(printf '%s%*s' "${payload}" $((4 - remainder)) '' | tr ' ' '=')
fi
decoded=$(printf '%s' "${payload}" | base64 -d)
jq -e '.v=="2" and .add=="203.0.113.44" and .net=="ws" and .tls=="tls" and .host=="vmess-agent.example" and .path=="/vmess" and (.id|type)=="string"' <<< "${decoded}" >/dev/null

exported=$(agent_cli export-client --json)
jq -e '.ok==true and .command=="export-client" and ([.data.config.outbounds[]|select(.type=="vmess")]|length)==3 and
  all(.data.config.outbounds[]|select(.type=="vmess"); (.server|type)=="string" and length>0) and
  (tostring|contains("private key fixture")|not)' <<< "${exported}" >/dev/null

# A concurrent revision between the snapshot and link render must fail closed.
original_snapshot=$(declare -f structured_instance_store_snapshot_json)
eval "${original_snapshot/structured_instance_store_snapshot_json/original_vmess_snapshot}"
structured_instance_store_snapshot_json() {
  local captured
  captured=$(original_vmess_snapshot "$@") || return 1
  jq '.revision += 1' "${SB_PROTOCOL_STATE_DIR}/instances/vmess.json" > "${TMP_DIR}/drifted.json"
  mv "${TMP_DIR}/drifted.json" "${SB_PROTOCOL_STATE_DIR}/instances/vmess.json"
  printf '%s\n' "${captured}"
}
if agent_vmess_link_json 203.0.113.44 > "${TMP_DIR}/drift.out" 2> "${TMP_DIR}/drift.err"; then
  printf 'VMess link renderer accepted a mixed-revision snapshot\n' >&2
  exit 1
fi
[[ ! -s "${TMP_DIR}/drift.out" ]]
eval "$(declare -f original_vmess_snapshot | sed '1s/^original_vmess_snapshot /structured_instance_store_snapshot_json /')"

printf 'VMess Agent/share checks passed: links=2 export-outbounds=3\n'
