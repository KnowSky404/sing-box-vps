#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"

snapshot="${TMP_DIR}/snapshot.json"
record="${TMP_DIR}/record.json"
guidance="${TMP_DIR}/guidance.txt"
printf '%s\n' '{"schema_version":1,"protocol":"hy2","revision":0,"default_instance_id":"","instances":[]}' > "${snapshot}"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -subj /CN=hy2.example.com -addext subjectAltName=DNS:hy2.example.com \
  -keyout "${TMP_DIR}/hy2.key" -out "${TMP_DIR}/hy2.pem" >"${TMP_DIR}/openssl.log" 2>&1

# Non-terminal outbound policy keeps its default without consuming a line.
# Leave display/identity/listen/auth defaults blank, retry blank SNI, then use
# a self-signed certificate with explicit certificate trust.
printf '%s\n' '' '' '' '' 48443 '' '' '' '' hy2.example.com \
  "${TMP_DIR}/hy2.pem" "${TMP_DIR}/hy2.key" 1 '' '' '' '' > "${TMP_DIR}/input"
hy2_management_build_record "${snapshot}" create '' "${record}" \
  < "${TMP_DIR}/input" >"${TMP_DIR}/stdout" 2>"${guidance}"
[[ ! -s "${TMP_DIR}/stdout" ]]
for description in 'ID 用于区分实例' '仅本机可连' '密码用于客户端连接认证' \
  '已有的手动证书' 'server_name / SNI' '必填且需与证书匹配' '自签名证书' \
  '系统证书库' '带宽为可选项' '留空不限制' '新建默认关闭' '新建留空则不启用'; do
  grep -Fq "${description}" "${guidance}"
done
jq -e '.listen.address=="127.0.0.1" and .listen.port==48443 and
  .tls.server_name=="hy2.example.com" and .client_trust=="certificate" and
  (.authentication.users|length)==1 and (.authentication.users[0].password|length)>0 and
  .bandwidth=={up_mbps:null,down_mbps:null} and .obfs.enabled==false and .masquerade==""' "${record}" >/dev/null

# Render and validate actual server/client configs from the entered record.
jq -n --slurpfile record "${record}" \
  '{schema_version:1,protocol:"hy2",revision:1,default_instance_id:$record[0].id,instances:$record}' > "${snapshot}"
render_structured_instance_inbounds hy2 "${snapshot}" | jq -s \
  '{inbounds:.,outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' > "${TMP_DIR}/server.json"
build_client_hy2_outbounds 127.0.0.1 "${snapshot}" | jq -s '{outbounds:.}' > "${TMP_DIR}/client.json"
core=${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}
"${core}" check -c "${TMP_DIR}/server.json"
"${core}" check -c "${TMP_DIR}/client.json"

printf 'Hysteria2 guidance checks passed: defaults preserved, server/client sing-box check passed\n'
