#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 129

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
trap 'printf "AnyTLS Agent/share failed at line %s\n" "${LINENO}" >&2' ERR
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances" "${SB_PROJECT_DIR}"
printf 'INSTALLED_PROTOCOLS=anytls\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
printf '%s\n' INSTALLED=1 CONFIG_SCHEMA_VERSION=2 > "${SB_PROTOCOL_STATE_DIR}/anytls.env"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=anytls-agent.example' \
  -keyout "${TMP_DIR}/anytls.key" -out "${TMP_DIR}/anytls.crt" >/dev/null 2>&1
chmod 600 "${TMP_DIR}/anytls.key" "${TMP_DIR}/anytls.crt"

jq -n --arg cert "${TMP_DIR}/anytls.crt" --arg key "${TMP_DIR}/anytls.key" '
  {schema_version:1,protocol:"anytls",revision:3,default_instance_id:"public",instances:[
    {id:"local",name:"Local AnyTLS",tag:"anytls-local",listen:{address:"127.0.0.1",port:33451},
     authentication:{users:[{name:"local-user",password:"local-password"}]},
     tls:{enabled:true,server_name:"anytls-agent.example",certificate_path:$cert,key_path:$key},client_trust:"system",
     outbound_policy:"default",dependencies:[]},
    {id:"public",name:"Public AnyTLS",tag:"anytls-public",listen:{address:"0.0.0.0",port:33452},
     authentication:{users:[{name:"alice",password:"alice-password"},{name:"bob",password:"bob-password"}]},
     tls:{enabled:true,server_name:"anytls-agent.example",certificate_path:$cert,key_path:$key},client_trust:"certificate",
     outbound_policy:"direct",dependencies:[]}
  ]}
' > "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json"
chmod 600 "${SB_PROTOCOL_STATE_DIR}/anytls.env" "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json"

rendered=$(render_structured_instance_inbounds anytls "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json" | jq -s .)
jq -n --argjson inbounds "${rendered}" \
  '{log:{disabled:true},inbounds:$inbounds,outbounds:[{type:"direct",tag:"direct"}],route:{rules:[{inbound:"anytls-public",action:"route",outbound:"direct"}],final:"direct"}}' \
  > "${SINGBOX_CONFIG_FILE}"

load_plain_proxy_structured_instance anytls public
summary=$(agent_anytls_node_json 203.0.113.44)
jq -e '.protocol=="anytls" and .instance_id=="public" and .user_count==2 and .tls_enabled==true and
  .client_trust=="certificate" and .client_exportable==true and .shareable==false and
  (.password? == null) and (.users? == null)' <<< "${summary}" >/dev/null

links=$(agent_anytls_link_json 203.0.113.44)
jq -e '.protocol=="anytls" and (.links|length)==0 and (.outbounds|length)==2 and
  (.warnings|length)==1 and .warnings[0].code=="anytls_standard_uri_unavailable" and
  all(.outbounds[]; .type=="anytls" and .server=="203.0.113.44" and
    (.password|type)=="string" and (.tls.certificate | contains("BEGIN CERTIFICATE")))' \
  <<< "${links}" >/dev/null
! grep -Fq "${TMP_DIR}/anytls.key" <<< "${links}"
! grep -Fq 'private key fixture' <<< "${links}"

exported=$(agent_cli export-client --json)
jq -e '.ok==true and .command=="export-client" and
  ([.data.config.outbounds[]|select(.type=="anytls")]|length)==3 and
  all(.data.config.outbounds[]|select(.type=="anytls"); (.server|type)=="string" and length>0 and
    (.password|type)=="string") and (tostring|contains("private key fixture")|not)' \
  <<< "${exported}" >/dev/null

# System trust remains an explicit verified mode and still carries the warning
# that AnyTLS has no lossless standard URI representation.
jq '(.instances[] | select(.id=="public") | .client_trust) = "system"' \
  "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json" > "${TMP_DIR}/system.json"
mv "${TMP_DIR}/system.json" "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json"
load_plain_proxy_structured_instance anytls public
links=$(agent_anytls_link_json 203.0.113.44)
jq -e '.protocol=="anytls" and (.links|length)==0 and (.outbounds|length)==2 and
  all(.outbounds[]; .type=="anytls" and .server=="203.0.113.44" and
    (.password|type)=="string" and .tls.enabled==true and .tls.server_name=="anytls-agent.example" and
    (.tls.certificate? == null)) and (.warnings[0].code=="anytls_standard_uri_unavailable")' \
  <<< "${links}" >/dev/null

nodes=$(agent_cli nodes --json)
jq -e '.ok==true and ([.data.nodes[]|select(.protocol=="anytls")]|length)==2 and
  all(.data.nodes[]|select(.protocol=="anytls"); (.password? == null) and (.outbound? == null))' \
  <<< "${nodes}" >/dev/null

printf 'AnyTLS Agent/share checks passed: links=2 export=secret-safe\n'
