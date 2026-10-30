#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install
curl() { printf 'unexpected network access in generic naming fixture\n' >&2; return 99; }
systemctl() { printf 'unexpected service operation in generic naming fixture\n' >&2; return 99; }
SB_VERSION=1.14.2
CONFIG_SCHEMA_VERSION=2
SUBMAN_NODE_PREFIX=fixture-host
SB_NODE_NAME=stale-global-name
SB_MIXED_LISTEN_ADDRESS=192.0.2.99
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
for protocol in trojan vmess vless-plain hy2; do
  store=$(plain_proxy_structured_store_file "${protocol}")
  jq -n --arg protocol "${protocol}" '{schema_version:1,protocol:$protocol,revision:1,default_instance_id:"main",instances:[
    {id:"main",name:" 统一自定义名称 ",tag:($protocol+"-in"),listen:{address:"0.0.0.0",port:443},
     authentication:{users:[{name:"alice",password:"dummy-alice",uuid:"11111111-1111-4111-8111-111111111111",alter_id:0,security:"auto",flow:""},{name:"bob",password:"dummy-bob",uuid:"22222222-2222-4222-8222-222222222222",alter_id:0,security:"auto",flow:""}]},
     tls:{enabled:true,server_name:"fixture.example",certificate_path:"/etc/ssl/public.crt",key_path:"/etc/ssl/private.key"},client_trust:"system",transport:{type:"none"},outbound_policy:"default",dependencies:[],
     bandwidth:{up_mbps:20,down_mbps:80},obfs:{enabled:false,type:"",password:""},masquerade:""}
  ]} | .instances[0] |= (
    if $protocol=="trojan" then del(.bandwidth,.obfs,.masquerade) | .authentication.users |= map({name,password})
    elif $protocol=="vmess" then del(.bandwidth,.obfs,.masquerade) | .authentication.users |= map({name,uuid,alter_id,security})
    elif $protocol=="vless-plain" then del(.bandwidth,.obfs,.masquerade) | .authentication.users |= map({name,uuid,flow})
    else del(.transport) | .authentication.users |= map({name,password}) end)' > "${store}"
  printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "${SB_PROTOCOL_STATE_DIR}/${protocol}.env"
  chmod 600 "${store}" "${SB_PROTOCOL_STATE_DIR}/${protocol}.env"
  validate_structured_instance_store "${protocol}" "${store}"
  for binding in wildcard concrete; do
    if [[ "${binding}" == concrete ]]; then
      jq '.instances[0].listen.address="127.0.0.1"' "${store}" > "${store}.new"
      mv "${store}.new" "${store}"
    fi
    payload=$(build_subman_node_payload "${protocol}" 203.0.113.10 IPv4 main)
    python3 -c 'import sys,json,base64,urllib.parse;p=json.load(sys.stdin);r=p["raw"];n=json.loads(base64.urlsafe_b64decode(r[8:]+"="*(-len(r[8:])%4)))["ps"] if r.startswith("vmess://") else urllib.parse.unquote(r.rsplit("#",1)[1]);assert p["name"]==n,(p["name"],n);assert "stale-global-name" not in n;assert n.startswith("统一自定义名称-u-");assert (n.endswith("-v4")) == (sys.argv[1]=="wildcard")' "${binding}" <<< "${payload}"
  done
  printf '%s generic payload names match URI\n' "${protocol}"
done
printf 'Generic structured SubMan payload naming passed: URI remarks/VMess ps, trimmed custom names and captured listener metadata\n'
