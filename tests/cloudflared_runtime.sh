#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ ${SBV_COMPONENT_RUNTIME:-} == 1 && -f /.dockerenv && -f /tmp/sbv-component-disposable ]] || {
  printf 'requires explicit disposable Docker guard\n' >&2; exit 64;
}
[[ ! -e /root/sing-box-vps && ! -e /etc/systemd/system/sing-box.service ]] || {
  printf 'refusing existing installation\n' >&2; exit 64;
}
[[ ${SBV_CF_PRODUCTION_ACCEPT:-} == 1 && -n ${SBV_CF_TEST_HOSTNAME:-} && -f ${SBV_CF_TUNNEL_TOKEN_FILE:-/nonexistent} ]] || {
  printf 'requires authorized test hostname and private tunnel credential file\n' >&2; exit 64;
}
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "${REPO_ROOT}/install.sh"
ARTIFACT_DIR=${CF_RUNTIME_ARTIFACT_DIR:-/tmp/cloudflared-acceptance}
mkdir -p "${ARTIFACT_DIR}" "${SB_PROTOCOL_STATE_DIR}/instances"
chmod 700 "${ARTIFACT_DIR}"
[[ $("${SINGBOX_BIN_PATH}" version | sed -n 's/^sing-box version //p') == 1.14.2 ]]
sha256sum "${REPO_ROOT}/install.sh" "${SINGBOX_BIN_PATH}" > "${ARTIFACT_DIR}/hashes.txt"
printf 'INSTALLED_PROTOCOLS=mixed\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
cat > "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json" <<'JSON'
{"schema_version":1,"protocol":"mixed","revision":1,"default_instance_id":"main","instances":[{"id":"main","name":"Cloudflared fixture","tag":"mixed-in","listen":{"address":"127.0.0.1","port":2080},"authentication":{"enabled":false,"username":"","password":""},"outbound_policy":"default","dependencies":[]}]}
JSON
SB_VERSION=1.14.2
SB_ADVANCED_ROUTE=y
generate_config > "${ARTIFACT_DIR}/baseline.log" 2>&1
jq -e 'any(.route.rules[]; .ip_is_private==true and .action=="reject")' "${SINGBOX_CONFIG_FILE}" >/dev/null
cat > "${SINGBOX_SERVICE_FILE}" <<UNIT
[Unit]
Description=Disposable Cloudflared acceptance
[Service]
ExecStart=${SINGBOX_BIN_PATH} run -c ${SINGBOX_CONFIG_FILE}
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl start sing-box
marker="sbv-cloudflare-$(cat /proc/sys/kernel/random/uuid)"
printf '%s' "${marker}" > "${ARTIFACT_DIR}/marker"
python3 - "${ARTIFACT_DIR}/marker" > "${ARTIFACT_DIR}/origin.log" 2>&1 <<'PY' &
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
import sys
marker=Path(sys.argv[1]).read_bytes()
class Handler(BaseHTTPRequestHandler):
 protocol_version='HTTP/1.1'
 def do_GET(self):
  self.send_response(200);self.send_header('Content-Length',str(len(marker)));self.end_headers();self.wfile.write(marker)
 def log_message(self,*args):pass
ThreadingHTTPServer(('127.0.0.1',18181),Handler).serve_forever()
PY
origin_pid=$!
trap 'kill "${origin_pid}"; wait "${origin_pid}" || true' EXIT
for ((attempt=0;attempt<30;attempt++)); do
  if curl -fsS --connect-timeout 1 --max-time 1 http://127.0.0.1:18181/spec-marker > "${ARTIFACT_DIR}/origin-response" 2> "${ARTIFACT_DIR}/origin.stderr" &&
     cmp -s "${ARTIFACT_DIR}/marker" "${ARTIFACT_DIR}/origin-response"; then break; fi
  kill -0 "${origin_pid}" || exit 1
  sleep 0.1
done
cmp -s "${ARTIFACT_DIR}/marker" "${ARTIFACT_DIR}/origin-response"
# Keep the default private-destination rejection. Only this managed tunnel's
# explicitly authorized local origin may bypass it; unrelated proxy users may not.
if curl -fsS --connect-timeout 2 --max-time 5 --noproxy '' --proxy http://127.0.0.1:2080 \
  http://127.0.0.1:18181/spec-marker > "${ARTIFACT_DIR}/private-rejection.response" 2> "${ARTIFACT_DIR}/private-rejection.stderr"; then
  printf 'unrelated Mixed inbound bypassed the private-destination guard\n' >&2
  exit 1
fi
jq -cn --rawfile token "${SBV_CF_TUNNEL_TOKEN_FILE}" \
  '{id:"cloudflare-spec",role:"inbound",type:"cloudflared",tag:"cloudflare-spec",enabled:true,
    route_rules:[{inbound:"cloudflare-spec",ip_cidr:"127.0.0.1/32",port:18181,action:"route",outbound:"direct"}],
    config:{token:($token|gsub("[\\r\\n]+$";"")),ha_connections:1,protocol:"http2",edge_ip_version:4}}' \
  > "${ARTIFACT_DIR}/record.json"
bash "${REPO_ROOT}/install.sh" agent component create --json --yes --allow-public --expected-revision 0 --file "${ARTIFACT_DIR}/record.json" > "${ARTIFACT_DIR}/create.json" 2> "${ARTIFACT_DIR}/create.log"
jq -e '.ok==true and .revision==1 and .config_check=="passed"' "${ARTIFACT_DIR}/create.json" >/dev/null
jq '(.inbounds[] | select(.type=="cloudflared")) |= del(.token)' "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/config.redacted.json"
passed=n
for ((attempt=0;attempt<60;attempt++)); do
  if curl -fsS --http1.1 --connect-timeout 5 --max-time 10 "https://${SBV_CF_TEST_HOSTNAME}/spec-marker" > "${ARTIFACT_DIR}/response" 2> "${ARTIFACT_DIR}/probe.stderr" && [[ $(cat "${ARTIFACT_DIR}/response") == "${marker}" ]]; then
    passed=y; break
  fi
  sleep 2
done
[[ ${passed} == y ]]
systemctl is-active --quiet sing-box
"${SINGBOX_BIN_PATH}" check -c "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/core.check" 2>&1
bash "${REPO_ROOT}/install.sh" agent component delete --json --yes --expected-revision 1 --id cloudflare-spec > "${ARTIFACT_DIR}/delete.json" 2> "${ARTIFACT_DIR}/delete.log"
jq -e '.ok==true and .revision==2' "${ARTIFACT_DIR}/delete.json" >/dev/null
jq -e '.components==[] and .revision==2' "${SB_COMPONENT_STATE_FILE}" >/dev/null
jq -e 'all(.inbounds[]; .type!="cloudflared") and
  all(.route.rules[]; .inbound!="cloudflare-spec") and
  any(.route.rules[]; .ip_is_private==true and .action=="reject")' "${SINGBOX_CONFIG_FILE}" >/dev/null
systemctl is-active --quiet sing-box
printf 'FP-06=passed\nTRANSPORT=http2\nORIGIN=HTTP1.1\nDATA_PLANE=https_cloudflare_edge_http_marker\nPRIVATE_ROUTE_SCOPE=cloudflare-spec+127.0.0.1/32+18181\nUNRELATED_PRIVATE_REJECTION=passed\nCOMPONENT_CLEANUP=passed\n' > "${ARTIFACT_DIR}/results.env"
printf 'Cloudflared real control-plane and HTTPS edge marker passed; component deleted\n'
