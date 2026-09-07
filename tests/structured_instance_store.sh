#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"
trap 'printf "structured instance test failed at line %s\n" "${LINENO}" >&2' ERR
runtime_core_pid=''
runtime_marker_pid=''
cleanup_runtime() {
  local owned_pid
  for owned_pid in "${runtime_core_pid}" "${runtime_marker_pid}"; do
    [[ -n "${owned_pid}" ]] || continue
    if kill -0 "${owned_pid}" 2>/dev/null; then
      kill "${owned_pid}" || printf 'could not stop owned test process\n' >&2
    fi
    if wait "${owned_pid}" 2>/dev/null; then :; else :; fi
  done
  rm -rf "${TMP_DIR}"
}
trap cleanup_runtime EXIT

for api in validate_structured_instance_store structured_instance_store_candidate \
  publish_structured_instance_store render_structured_instance_inbounds render_structured_instance_route_rules; do
  declare -F "${api}" >/dev/null || { printf 'missing API: %s\n' "${api}" >&2; exit 1; }
done

reject() {
  if "$@" > "${TMP_DIR}/rejected.stdout" 2> "${TMP_DIR}/rejected.stderr"; then
    printf 'expected structured state rejection\n' >&2
    return 1
  fi
  [[ ! -s "${TMP_DIR}/rejected.stdout" ]]
}

make_record() {
  jq -n --arg id "$1" --argjson port "$2" \
    --arg name 'name with spaces; $(false) `false` and "quotes"' \
    --arg password 'password ; $() & ? "' '
    {id:$id,name:$name,tag:("mixed-"+$id),listen:{address:"127.0.0.1",port:$port},
     authentication:{enabled:true,username:"proxy user",password:$password},
     outbound_policy:"default",dependencies:[]}' > "$3"
}

mkdir -p "${SB_PROTOCOL_STATE_DIR}"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=1\nNODE_NAME=legacy\n' > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
legacy_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env")
store_file="${SB_PROTOCOL_STATE_DIR}/instances/mixed.json"
make_record main 32101 "${TMP_DIR}/main.json"
make_record edge 32102 "${TMP_DIR}/edge.json"
jq '.authentication.password += " edge"' "${TMP_DIR}/edge.json" > "${TMP_DIR}/edge-unique.json"
mv "${TMP_DIR}/edge-unique.json" "${TMP_DIR}/edge.json"

structured_instance_store_candidate mixed '' create "${TMP_DIR}/main.json" 0 > "${TMP_DIR}/one.json"
jq -e '.schema_version == 1 and .revision == 1 and .default_instance_id == "main" and (.instances|length)==1' "${TMP_DIR}/one.json" >/dev/null
validate_structured_instance_store mixed "${TMP_DIR}/one.json"
publish_structured_instance_store mixed "${TMP_DIR}/one.json" 0
[[ "$(stat -c %a "${store_file}")" == 600 ]]
[[ "$(stat -c %a "${SB_PROTOCOL_STATE_DIR}/instances")" == 700 ]]

structured_instance_store_candidate mixed "${store_file}" create "${TMP_DIR}/edge.json" 1 > "${TMP_DIR}/two.json"
publish_structured_instance_store mixed "${TMP_DIR}/two.json" 1
jq -e '.revision == 2 and [.instances[].id] == ["main","edge"]' "${store_file}" >/dev/null
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env")" == "${legacy_hash}" ]]
store_hash=$(sha256sum "${store_file}")
backup_hash=$(sha256sum "${store_file}.bak")
store_inode=$(stat -c %i "${store_file}")

# CAS and no-op writes cannot erase another writer's commit or rotate backups.
reject structured_instance_store_candidate mixed "${store_file}" delete edge 1
reject publish_structured_instance_store mixed "${TMP_DIR}/one.json" 1
jq '.revision=3 | .instances[0].tag="changed-stable-tag"' "${store_file}" > "${TMP_DIR}/changed-tag.json"
reject publish_structured_instance_store mixed "${TMP_DIR}/changed-tag.json" 2
structured_instance_store_candidate mixed "${store_file}" replace "${TMP_DIR}/edge.json" 2 > "${TMP_DIR}/noop.json"
jq -e '.revision == 2' "${TMP_DIR}/noop.json" >/dev/null
publish_structured_instance_store mixed "${TMP_DIR}/noop.json" 2
[[ "$(sha256sum "${store_file}")" == "${store_hash}" && "$(stat -c %i "${store_file}")" == "${store_inode}" ]]
[[ "$(sha256sum "${store_file}.bak")" == "${backup_hash}" ]]
cp -p "${store_file}" "${TMP_DIR}/before-edit.json"
cp -p "${store_file}.bak" "${TMP_DIR}/before-edit.bak"
jq '.name="edited node" | .authentication.password="edited password"' "${TMP_DIR}/edge.json" > "${TMP_DIR}/edited-record.json"
structured_instance_store_candidate mixed "${store_file}" replace "${TMP_DIR}/edited-record.json" 2 > "${TMP_DIR}/edited-store.json"
publish_structured_instance_store mixed "${TMP_DIR}/edited-store.json" 2
jq -e '.revision==3 and .instances[1].id=="edge" and .instances[1].tag=="mixed-edge" and .instances[1].name=="edited node" and .instances[1].authentication.password=="edited password"' "${store_file}" >/dev/null
cp -p "${TMP_DIR}/before-edit.json" "${store_file}"
cp -p "${TMP_DIR}/before-edit.bak" "${store_file}.bak"
reject structured_instance_store_candidate mixed "${store_file}" create "${TMP_DIR}/edge.json" 2
reject structured_instance_store_candidate mixed "${store_file}" delete unknown 2
reject structured_instance_store_candidate mixed "${store_file}" default unknown 2
reject structured_instance_store_candidate unknown "${store_file}" delete edge 2
reject structured_instance_store_candidate hy2 "${store_file}" delete edge 2

for mutation in '.unknown=true' '.listen.extra=true' '.listen.port=0' '.listen.port=1.5' \
  '.listen.address="example.com"' '.listen.address="999.1.2.3"' '.id="../escape"' \
  '.authentication.enabled="yes"' '.authentication.password=""' '.authentication.enabled=false' \
  '.dependencies=["unknown"]' '.outbound_policy="shell"' '.tag=""' '.name=""'; do
  jq "${mutation}" "${TMP_DIR}/edge.json" > "${TMP_DIR}/bad-record.json"
  reject structured_instance_store_candidate mixed "${store_file}" replace "${TMP_DIR}/bad-record.json" 2
done
jq '.tag="renamed-tag"' "${TMP_DIR}/edge.json" > "${TMP_DIR}/bad-record.json"
reject structured_instance_store_candidate mixed "${store_file}" replace "${TMP_DIR}/bad-record.json" 2
jq '.id="collision" | .tag="collision-tag" | .listen.port=32101' "${TMP_DIR}/edge.json" > "${TMP_DIR}/bad-record.json"
reject structured_instance_store_candidate mixed "${store_file}" create "${TMP_DIR}/bad-record.json" 2
for mutation in '.schema_version=999' '.schema_version=1.5' '.revision=-1' '.revision=9007199254740992' \
  '.extra={}' '.default_instance_id="missing"' '.default_instance_id=""' \
  '.instances += [.instances[0]]' '.instances[1].tag=.instances[0].tag' \
  '.instances[0].authentication.username=("é"*128)' \
  '.instances[0].authentication.password="bad\u0000password"' \
  '.instances[0].name="bad\u0000name"'; do
  jq "${mutation}" "${store_file}" > "${TMP_DIR}/bad-store.json"
  reject validate_structured_instance_store mixed "${TMP_DIR}/bad-store.json"
done
printf '{}\n{}\n' > "${TMP_DIR}/bad-store.json"
reject validate_structured_instance_store mixed "${TMP_DIR}/bad-store.json"
[[ "$(sha256sum "${store_file}")" == "${store_hash}" ]]
for address in '::::' '1::2::3' '::1:' ':1:2:3:4:5:6:7:8' '1:2:3:4:5:6:7:8:' \
  '1:2:3:4:5:6:7:8:9' '127.0.0.01' $'127.0.0.1\n127.0.0.2'; do
  jq --arg address "${address}" '.instances[0].listen.address=$address' "${store_file}" > "${TMP_DIR}/bad-store.json"
  reject validate_structured_instance_store mixed "${TMP_DIR}/bad-store.json"
done
for address in '::' '::1' '2001:db8::1' '1:2:3:4:5:6:7:8'; do
  jq --arg address "${address}" '.instances[0].listen.address=$address' "${store_file}" > "${TMP_DIR}/ipv6-store.json"
  validate_structured_instance_store mixed "${TMP_DIR}/ipv6-store.json"
done
jq '.revision=9007199254740991' "${store_file}" > "${TMP_DIR}/max-revision.json"
reject structured_instance_store_candidate mixed "${TMP_DIR}/max-revision.json" default edge 9007199254740991
structured_instance_store_candidate mixed "${TMP_DIR}/max-revision.json" default main 9007199254740991 > "${TMP_DIR}/max-noop.json"
jq -e '.revision==9007199254740991' "${TMP_DIR}/max-noop.json" >/dev/null

# Rendering consumes typed data without credential preparation or legacy writes.
ensure_mixed_auth_credentials() { printf 'unexpected credential preparation\n' >&2; return 49; }
render_structured_instance_inbounds mixed "${store_file}" > "${TMP_DIR}/inbounds.jsonl"
render_structured_instance_route_rules mixed "${store_file}" > "${TMP_DIR}/rules.json"
jq '.instances[0].outbound_policy="direct" | .instances[1].outbound_policy="warp"' "${store_file}" > "${TMP_DIR}/policies.json"
render_structured_instance_route_rules mixed "${TMP_DIR}/policies.json" > "${TMP_DIR}/policy-rules.json"
jq -e 'length==4 and [.[].action]==["sniff","route","sniff","route"] and .[1].outbound=="direct" and .[3].outbound=="warp-ep"' "${TMP_DIR}/policy-rules.json" >/dev/null
jq -s -e 'length==2 and ([.[].tag]|unique|length)==2 and all(.[]; .type=="mixed" and (.users|length)==1)' "${TMP_DIR}/inbounds.jsonl" >/dev/null
jq -n --slurpfile inbounds "${TMP_DIR}/inbounds.jsonl" --slurpfile rules "${TMP_DIR}/rules.json" \
  '{inbounds:$inbounds,outbounds:[{type:"direct",tag:"direct"}],route:{rules:$rules[0],final:"direct"}}' > "${TMP_DIR}/server.json"
validate_managed_component_graph "${TMP_DIR}/server.json"
core_checks=0
runtime_probes=0
if [[ -n "${SINGBOX_BINARY_113:-}${SINGBOX_BINARY_114:-}" ]]; then
  # Only a loopback marker server and temporary proxy listeners; no public
  # services, external credentials or system proxy/firewall modifications.
  python3 -u - > "${TMP_DIR}/runtime-ports.json" <<'PY' &
import http.server
import json
import socket

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"structured-instance-loopback-ok\n"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass

server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
reserved = [socket.socket(), socket.socket()]
for sock in reserved:
    sock.bind(("127.0.0.1", 0))
ports = [sock.getsockname()[1] for sock in reserved]
for sock in reserved:
    sock.close()
print(json.dumps({"marker": server.server_port, "proxies": ports}), flush=True)
server.serve_forever()
PY
  runtime_marker_pid=$!
  for attempt in {1..100}; do
    [[ ! -s "${TMP_DIR}/runtime-ports.json" ]] || break
    kill -0 "${runtime_marker_pid}"
    sleep 0.05
  done
  jq -e '.proxies | length==2' "${TMP_DIR}/runtime-ports.json" >/dev/null
fi
for core in "${SINGBOX_BINARY_113:-}" "${SINGBOX_BINARY_114:-}"; do
  [[ -n "${core}" ]] || continue
  "${core}" check -c "${TMP_DIR}/server.json"
  core_checks=$((core_checks+1))
  jq --slurpfile ports "${TMP_DIR}/runtime-ports.json" \
    '.inbounds[0].listen_port=$ports[0].proxies[0] | .inbounds[1].listen_port=$ports[0].proxies[1]' \
    "${TMP_DIR}/server.json" > "${TMP_DIR}/runtime-server.json"
  "${core}" check -c "${TMP_DIR}/runtime-server.json"
  "${core}" run -c "${TMP_DIR}/runtime-server.json" > "${TMP_DIR}/runtime-core.log" 2>&1 &
  runtime_core_pid=$!
  marker_port=$(jq -r '.marker' "${TMP_DIR}/runtime-ports.json")
  for instance_index in 0 1; do
    proxy_port=$(jq -r --argjson i "${instance_index}" '.proxies[$i]' "${TMP_DIR}/runtime-ports.json")
    proxy_auth=$(jq -r --argjson i "${instance_index}" '.instances[$i].authentication | .username+":"+.password' "${store_file}")
    for proxy_scheme in http socks5h; do
      connected=n
      for attempt in {1..50}; do
        if curl --silent --show-error --fail --max-time 2 --noproxy '' \
          --proxy "${proxy_scheme}://127.0.0.1:${proxy_port}" --proxy-user "${proxy_auth}" \
          "http://127.0.0.1:${marker_port}/marker" > "${TMP_DIR}/marker-body" 2> "${TMP_DIR}/curl.stderr"; then
          connected=y
          break
        fi
        kill -0 "${runtime_core_pid}"
        sleep 0.05
      done
      [[ "${connected}" == y ]]
      grep -Fqx 'structured-instance-loopback-ok' "${TMP_DIR}/marker-body"
      if curl --silent --show-error --fail --max-time 2 --noproxy '' \
        --proxy "${proxy_scheme}://127.0.0.1:${proxy_port}" --proxy-user 'wrong:wrong' \
        "http://127.0.0.1:${marker_port}/marker" > "${TMP_DIR}/wrong-auth-body" 2> "${TMP_DIR}/wrong-auth.stderr"; then
        printf 'structured instance accepted wrong proxy credentials\n' >&2
        exit 1
      fi
      runtime_probes=$((runtime_probes+1))
    done
  done
  kill "${runtime_core_pid}"
  if wait "${runtime_core_pid}"; then :; else :; fi
  runtime_core_pid=''
done
[[ "$(sha256sum "${store_file}")" == "${store_hash}" ]]

structured_instance_store_candidate mixed "${store_file}" default edge 2 > "${TMP_DIR}/default.json"
cp -p "${store_file}" "${TMP_DIR}/before-fault.json"
cp -p "${store_file}.bak" "${TMP_DIR}/before-fault.bak"
lock_dir="${SB_PROTOCOL_STATE_DIR}/instances/.mixed.write.lock"
mkdir "${lock_dir}"
printf 'other owner\n' > "${lock_dir}/owner"
reject publish_structured_instance_store mixed "${TMP_DIR}/default.json" 2
[[ -f "${lock_dir}/owner" ]]
rm "${lock_dir}/owner"
rmdir "${lock_dir}"

for fault in commit postcheck signal; do
  (
    mv() {
      local destination=${@: -1}
      if [[ "${destination}" == "${store_file}" && "$*" == *'.candidate.'* ]]; then
        [[ "${fault}" != commit ]] || return 41
        command mv "$@" || return $?
        if [[ "${fault}" == postcheck ]]; then
          printf '{}\n' > "${store_file}"
        else
          kill -TERM "${BASHPID}"
        fi
        return 0
      fi
      command mv "$@"
    }
    failure_status=0
    publish_structured_instance_store mixed "${TMP_DIR}/default.json" 2 \
      > "${TMP_DIR}/fault.stdout" 2> "${TMP_DIR}/fault.stderr" || failure_status=$?
    [[ "${failure_status}" != 0 && ! -s "${TMP_DIR}/fault.stdout" ]]
    [[ "${fault}" != commit || "${failure_status}" == 41 ]]
    [[ "${fault}" != signal || "${failure_status}" == 143 ]]
  )
  [[ "$(sha256sum "${store_file}")" == "${store_hash}" ]]
  [[ "$(sha256sum "${store_file}.bak")" == "${backup_hash}" ]]
  [[ ! -e "${lock_dir}" ]]
done

# A failed rollback retains the private old bytes and the lock, never deletes
# its own recovery copy. Restore only this test's known sandbox afterwards.
(
  mv() {
    local destination=${@: -1}
    if [[ "${destination}" == "${store_file}" ]]; then
      if [[ "$*" == *'.candidate.'* ]]; then
        command mv "$@" || return $?
        printf '{}\n' > "${store_file}"
        return 0
      fi
      [[ "$*" != *'.previous.'* ]] || return 57
    fi
    command mv "$@"
  }
  reject publish_structured_instance_store mixed "${TMP_DIR}/default.json" 2
  grep -Fq 'rollback_failed' "${TMP_DIR}/rejected.stderr"
)
[[ -f "${lock_dir}/recovery" ]]
recovery_source=$(sed -n 's/^previous=//p' "${lock_dir}/recovery")
[[ "${recovery_source}" == "${SB_PROTOCOL_STATE_DIR}/instances/.mixed.previous."* && -f "${recovery_source}" ]]
cmp "${recovery_source}" "${TMP_DIR}/before-fault.json"
cp -p "${TMP_DIR}/before-fault.json" "${store_file}"
cp -p "${TMP_DIR}/before-fault.bak" "${store_file}.bak"
for artifact in "${SB_PROTOCOL_STATE_DIR}/instances"/.mixed.*; do
  [[ -f "${artifact}" ]] || continue
  rm -f -- "${artifact}"
done
rm "${lock_dir}/recovery"
rmdir "${lock_dir}"

for link_target in "${store_file}" "${store_file}.bak"; do
  cp -p "${link_target}" "${TMP_DIR}/symlink-original"
  printf 'untouched outside data\n' > "${TMP_DIR}/outside-data"
  rm "${link_target}"
  ln -s "${TMP_DIR}/outside-data" "${link_target}"
  reject publish_structured_instance_store mixed "${TMP_DIR}/default.json" 2
  grep -Fqx 'untouched outside data' "${TMP_DIR}/outside-data"
  [[ -L "${link_target}" && ! -e "${lock_dir}" ]]
  rm "${link_target}"
  cp -p "${TMP_DIR}/symlink-original" "${link_target}"
done

publish_structured_instance_store mixed "${TMP_DIR}/default.json" 2 > "${TMP_DIR}/writer1.out" 2> "${TMP_DIR}/writer1.err" &
writer1=$!
publish_structured_instance_store mixed "${TMP_DIR}/default.json" 2 > "${TMP_DIR}/writer2.out" 2> "${TMP_DIR}/writer2.err" &
writer2=$!
status1=0 status2=0
wait "${writer1}" || status1=$?
wait "${writer2}" || status2=$?
[[ ( "${status1}" == 0 && "${status2}" != 0 ) || ( "${status1}" != 0 && "${status2}" == 0 ) ]]
jq -e '.revision==3 and .default_instance_id=="edge"' "${store_file}" >/dev/null
[[ ! -e "${lock_dir}" ]]
cp -p "${TMP_DIR}/before-fault.json" "${store_file}"
cp -p "${TMP_DIR}/before-fault.bak" "${store_file}.bak"

publish_structured_instance_store mixed "${TMP_DIR}/default.json" 2
structured_instance_store_candidate mixed "${store_file}" delete edge 3 > "${TMP_DIR}/delete.json"
jq -e '.revision==4 and .default_instance_id=="main" and [.instances[].id]==["main"]' "${TMP_DIR}/delete.json" >/dev/null
publish_structured_instance_store mixed "${TMP_DIR}/delete.json" 3
structured_instance_store_candidate mixed "${store_file}" delete main 4 > "${TMP_DIR}/empty.json"
jq -e '.revision==5 and .default_instance_id=="" and .instances==[]' "${TMP_DIR}/empty.json" >/dev/null
publish_structured_instance_store mixed "${TMP_DIR}/empty.json" 4
render_structured_instance_inbounds mixed "${store_file}" > "${TMP_DIR}/empty-inbounds"
[[ ! -s "${TMP_DIR}/empty-inbounds" ]]
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env")" == "${legacy_hash}" ]]
printf 'structured instance store checks passed; real core checks=%s; HTTP/SOCKS TCP probes=%s\n' "${core_checks}" "${runtime_probes}"
