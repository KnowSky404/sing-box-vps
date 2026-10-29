#!/usr/bin/env bash

set -euo pipefail

# Run only in a fresh disposable verification container, with a separately
# supplied Pebble binary. Never use a public CA, DNS token, or production trust.
[[ "${SBV_HY2_ACME_RUNTIME:-}" == 1 && -f /.dockerenv ]] || {
  printf 'requires SBV_HY2_ACME_RUNTIME=1 in a disposable Docker container\n' >&2; exit 64;
}
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "${REPO_ROOT}/install.sh"
[[ ! -e "${SB_PROJECT_DIR}" && ! -e "${SINGBOX_SERVICE_FILE}" ]] || {
  printf 'refusing to overwrite an existing installation\n' >&2; exit 64;
}
ARTIFACT_DIR=${HY2_ACME_ARTIFACT_DIR:-/tmp/hy2-acme-runtime}
PEBBLE_BINARY=${PEBBLE_BINARY:?supply a Pebble test-server binary}
mkdir -p "${ARTIFACT_DIR}" "${SB_PROTOCOL_STATE_DIR}" "${SB_ACME_DATA_DIR}"
chmod 700 "${ARTIFACT_DIR}"
pebble_pid="" client_pid="" http_pid=""
cleanup() {
  local pid
  for pid in "${client_pid}" "${http_pid}" "${pebble_pid}"; do
    [[ -z "${pid}" ]] || { kill "${pid}"; wait "${pid}" || [[ $? == 143 ]]; }
  done
}
trap cleanup EXIT
trap 'printf "HY2 ACME runtime failure at line %s\n" "${LINENO}" >&2' ERR
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=localhost \
  -addext subjectAltName=DNS:localhost,IP:127.0.0.1 -addext basicConstraints=critical,CA:TRUE \
  -keyout "${ARTIFACT_DIR}/https.key" -out "${ARTIFACT_DIR}/https.crt" >"${ARTIFACT_DIR}/openssl.log" 2>&1
jq -n --arg cert "${ARTIFACT_DIR}/https.crt" --arg key "${ARTIFACT_DIR}/https.key" \
  '{pebble:{listenAddress:"127.0.0.1:14000",managementListenAddress:"127.0.0.1:15000",
    certificate:$cert,privateKey:$key,httpPort:80,tlsPort:443,ocspResponderURL:"",
    externalAccountBindingRequired:false,retryAfter:{authz:1,order:1}}}' > "${ARTIFACT_DIR}/pebble.json"
printf '127.0.0.1 one.hy2.example.com two.hy2.example.com\n' >> /etc/hosts
PEBBLE_VA_NOSLEEP=1 PEBBLE_WFE_NONCEREJECT=0 "${PEBBLE_BINARY}" -config "${ARTIFACT_DIR}/pebble.json" >"${ARTIFACT_DIR}/pebble.log" 2>&1 &
pebble_pid=$!
for ((attempt=0; attempt<60; attempt++)); do
  if curl --silent --show-error --fail --cacert "${ARTIFACT_DIR}/https.crt" https://localhost:15000/roots/0 \
    > "${ARTIFACT_DIR}/root.crt" 2>"${ARTIFACT_DIR}/root-fetch.stderr"; then break; fi
  sleep 0.2
done
openssl x509 -in "${ARTIFACT_DIR}/root.crt" -noout -subject > "${ARTIFACT_DIR}/root-subject.txt"
printf 'INSTALLED_PROTOCOLS=\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
jq -n '{log:{level:"info"},
  inbounds:[{type:"mixed",tag:"manual-client",listen:"127.0.0.1",listen_port:18090}],
  dns:{servers:[{type:"local",tag:"manual-dns"}]},
  outbounds:[{type:"direct",tag:"direct"},{type:"direct",tag:"manual-direct"},
    {type:"socks",tag:"manual-proxy",server:"127.0.0.1",server_port:19999}],
  route:{final:"direct",rules:[{inbound:"manual-client",action:"route",outbound:"manual-direct"}],
    default_domain_resolver:"manual-dns"},experimental:{cache_file:{enabled:false}}}' > "${SINGBOX_CONFIG_FILE}"
manual_projection() {
  jq -cS '{inbound:[.inbounds[]|select(.tag=="manual-client")],
    outbounds:[.outbounds[]|select(.tag=="manual-direct" or .tag=="manual-proxy")],
    rules:[.route.rules[]|select(.inbound=="manual-client")],
    dns:{servers:[.dns.servers[]|select(.tag=="manual-dns")]},experimental,
    resolver:.route.default_domain_resolver}' "${SINGBOX_CONFIG_FILE}"
}
manual_projection > "${ARTIFACT_DIR}/manual.before.json"

setup_service > "${ARTIFACT_DIR}/setup.log" 2>&1
mkdir -p /etc/systemd/system/sing-box.service.d
printf '[Service]\nEnvironment="SSL_CERT_FILE=%s/https.crt"\n' "${ARTIFACT_DIR}" > /etc/systemd/system/sing-box.service.d/acme-test.conf
# A slow pre-start proves that progress remains visible during systemd waits.
printf '[Service]\nExecStartPre=/bin/sleep 2\n' > /etc/systemd/system/sing-box.service.d/progress-test.conf
export SB_PROGRESS_INTERVAL_SECONDS=1
systemctl daemon-reload
systemctl start sing-box

make_record() {
  local id=$1 domain=$2 port=$3
  jq -n --arg id "${id}" --arg domain "${domain}" --argjson port "${port}" --arg directory "${SB_ACME_DATA_DIR}" \
    '{id:$id,name:$id,tag:("hy2-"+$id),listen:{address:"0.0.0.0",port:$port},
      authentication:{users:[{name:"test",password:("test-password-"+$id)}]},
      tls:{enabled:true,server_name:$domain,acme:{domain:[$domain],data_directory:$directory,
        provider:"https://localhost:14000/dir",disable_http_challenge:false,disable_tls_alpn_challenge:true}},
      client_trust:"system",bandwidth:{up_mbps:null,down_mbps:null},obfs:{enabled:false,type:"",password:""},
      masquerade:"",outbound_policy:"default",dependencies:[]}' > "${ARTIFACT_DIR}/${id}.json"
}
make_record one one.hy2.example.com 48443
make_record two two.hy2.example.com 48444
if [[ "${HY2_ACME_LEGACY_BASELINE:-0}" == 1 ]]; then
  # A prepared legacy baseline exercises adoption and removal of the old
  # generator-owned shared provider without deleting its certificate cache.
  set_protocol_defaults hy2
  SB_NODE_NAME=one SB_PORT=48443 SB_HY2_DOMAIN=one.hy2.example.com
  SB_HY2_ACME_DOMAIN=one.hy2.example.com SB_HY2_USER_NAME=test
  SB_HY2_PASSWORD=test-password-one SB_HY2_OBFS_ENABLED=n SB_HY2_MASQUERADE=""
  SB_HY2_ACME_EXTRA_JSON='{"provider":"https://localhost:14000/dir","disable_http_challenge":false,"disable_tls_alpn_challenge":true}'
  save_hy2_state
  write_protocol_index hy2
  jq --slurpfile record "${ARTIFACT_DIR}/one.json" '
    $record[0] as $one |
    .certificate_providers=[$one.tls.acme+{type:"acme",tag:"hy2-cert-provider"}] |
    .inbounds += [{type:"hysteria2",tag:$one.tag,listen:$one.listen.address,listen_port:$one.listen.port,
      users:$one.authentication.users,tls:{enabled:true,server_name:$one.tls.server_name,
        alpn:["h3"],certificate_provider:"hy2-cert-provider"}}]
  ' "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/legacy-config.json"
  sing-box check -c "${ARTIFACT_DIR}/legacy-config.json"
  cp "${ARTIFACT_DIR}/legacy-config.json" "${SINGBOX_CONFIG_FILE}"
  systemctl restart sing-box
  current_revision=0
else
  apply_plain_proxy_instance_change hy2 create 0 "${ARTIFACT_DIR}/one.json" y > "${ARTIFACT_DIR}/create-one.json"
  current_revision=1
fi
apply_plain_proxy_instance_change hy2 create "${current_revision}" "${ARTIFACT_DIR}/two.json" y > "${ARTIFACT_DIR}/create-two.json" 2> "${ARTIFACT_DIR}/create-two.progress.log"
current_revision=$((current_revision + 1))
grep -Fq '已等待 1 秒' "${ARTIFACT_DIR}/create-two.progress.log"
manual_projection > "${ARTIFACT_DIR}/manual.after-instance.json"
cmp "${ARTIFACT_DIR}/manual.before.json" "${ARTIFACT_DIR}/manual.after-instance.json"
# The isolated marker is private; disable the optional private-IP reject
# policy explicitly so this local data-plane probe can reach its fixture.
SB_ADVANCED_ROUTE=n
# Global rebuild must preserve the same unowned client configuration too.
generate_config > "${ARTIFACT_DIR}/global-rebuild.log" 2>&1
systemctl restart sing-box
manual_projection > "${ARTIFACT_DIR}/manual.after-rebuild.json"
cmp "${ARTIFACT_DIR}/manual.before.json" "${ARTIFACT_DIR}/manual.after-rebuild.json"
jq -e '((.certificate_providers // [])|length)==0' "${SINGBOX_CONFIG_FILE}" >/dev/null
for ((attempt=0; attempt<120; attempt++)); do
  certificate_count=$(find "${SB_ACME_DATA_DIR}" -type f -name '*.crt' | wc -l)
  [[ "${certificate_count:-0}" == 2 ]] && break
  sleep 0.5
done
[[ "${certificate_count:-0}" == 2 ]]
plain_proxy_structured_state_matches_config hy2
plain_proxy_validate_state_inventory hy2
sing-box check -c "${SINGBOX_CONFIG_FILE}"
systemctl is-active --quiet sing-box
find "${SB_ACME_DATA_DIR}" -type f -name '*.crt' | sort | xargs sha256sum > "${ARTIFACT_DIR}/certificates.before.sha256"
systemctl restart sing-box
sha256sum -c "${ARTIFACT_DIR}/certificates.before.sha256" > "${ARTIFACT_DIR}/cache-reuse.txt"
printf 'hy2-acme-runtime-transfer-ok\n' > "${ARTIFACT_DIR}/marker.txt"
python3 -m http.server 19081 --bind 127.0.0.1 --directory "${ARTIFACT_DIR}" > "${ARTIFACT_DIR}/http.log" 2>&1 &
http_pid=$!
container_ip=$(hostname -I | awk '{print $1}')
[[ -n "${container_ip}" && "${container_ip}" != 127.* ]]
jq -e 'all(.inbounds[]|select(.type=="hysteria2"); .listen=="0.0.0.0")' "${SINGBOX_CONFIG_FILE}" >/dev/null
outbounds=$(build_client_hy2_outbounds "${container_ip}" | jq -s .)
for index in 0 1; do
  jq -n --argjson outbounds "${outbounds}" --argjson index "${index}" --arg root "${ARTIFACT_DIR}/root.crt" \
    '{log:{level:"info"},inbounds:[{type:"socks",listen:"127.0.0.1",listen_port:19080}],
      outbounds:[($outbounds[$index] | .tls.certificate_path=$root)]}' > "${ARTIFACT_DIR}/client-${index}.json"
  sing-box check -c "${ARTIFACT_DIR}/client-${index}.json"
  sing-box run -c "${ARTIFACT_DIR}/client-${index}.json" >"${ARTIFACT_DIR}/client-${index}.log" 2>&1 &
  client_pid=$!
  for ((attempt=0; attempt<40; attempt++)); do
    if curl --silent --show-error --fail --max-time 3 --noproxy '' --proxy socks5h://127.0.0.1:19080 \
      http://127.0.0.1:19081/marker.txt > "${ARTIFACT_DIR}/transfer-${index}.txt" 2>"${ARTIFACT_DIR}/transfer-${index}.stderr"; then break; fi
    sleep 0.2
  done
  cmp "${ARTIFACT_DIR}/marker.txt" "${ARTIFACT_DIR}/transfer-${index}.txt"
  kill "${client_pid}"
  wait "${client_pid}" || [[ $? == 143 ]]
  client_pid=""
done
curl --silent --show-error --fail --max-time 5 --noproxy '' \
  --proxy socks5h://127.0.0.1:18090 http://127.0.0.1:19081/marker.txt > "${ARTIFACT_DIR}/manual-client-transfer.txt"
cmp "${ARTIFACT_DIR}/marker.txt" "${ARTIFACT_DIR}/manual-client-transfer.txt"
ss -lun > "${ARTIFACT_DIR}/listeners.txt"
grep -Fq '0.0.0.0:48443' "${ARTIFACT_DIR}/listeners.txt"
grep -Fq '0.0.0.0:48444' "${ARTIFACT_DIR}/listeners.txt"
apply_plain_proxy_instance_change hy2 delete "${current_revision}" two n > "${ARTIFACT_DIR}/delete-two.json"
manual_projection > "${ARTIFACT_DIR}/manual.after-delete.json"
cmp "${ARTIFACT_DIR}/manual.before.json" "${ARTIFACT_DIR}/manual.after-delete.json"
plain_proxy_structured_state_matches_config hy2
systemctl is-active --quiet sing-box
sing-box check -c "${SINGBOX_CONFIG_FILE}"
journalctl -u sing-box --no-pager > "${ARTIFACT_DIR}/service.log"
printf 'HY2 ACME Docker runtime passed: actual HTTP-01 issuance=2, verified TLS transfers via container IPv4=2, cache reuse, delete isolation, manual client coexistence, global rebuild and slow-service progress\n'
