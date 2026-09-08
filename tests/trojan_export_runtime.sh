#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TESTS_DIR=$REPO_ROOT/tests

if [[ ${1:-} != --run ]]; then
  if [[ $# -ne 0 ]]; then
    printf 'usage: %s [--run CORE_BINARY CORE_LABEL]\n' "${BASH_SOURCE[0]}" >&2
    exit 2
  fi
  if [[ -z "${SINGBOX_BINARY_113:-}" && -z "${SINGBOX_BINARY_114:-}" ]]; then
    printf 'Trojan export runtime skipped: no configured real cores\n'
    exit 0
  fi
  dispatch_status=0
  if [[ -n "${SINGBOX_BINARY_113:-}" ]]; then
    [[ -x "${SINGBOX_BINARY_113}" ]] || { printf 'configured 1.13.18 core unavailable\n' >&2; exit 1; }
    bash "${BASH_SOURCE[0]}" --run "${SINGBOX_BINARY_113}" 1.13.18 || dispatch_status=$?
  fi
  if [[ -n "${SINGBOX_BINARY_114:-}" ]]; then
    [[ -x "${SINGBOX_BINARY_114}" ]] || { printf 'configured 1.14.0 core unavailable\n' >&2; exit 1; }
    bash "${BASH_SOURCE[0]}" --run "${SINGBOX_BINARY_114}" 1.14.0 || dispatch_status=$?
  fi
  exit "${dispatch_status}"
fi

if [[ $# -ne 3 || ! -x ${2:-} ]]; then
  printf 'usage: %s --run CORE_BINARY CORE_LABEL\n' "$0" >&2
  exit 2
fi

core_binary=$2
core_label=$3
actual_core_version=$("$core_binary" version | awk 'NR == 1 {print $3}')
[[ $actual_core_version == ${core_label#v} ]] || {
  printf 'Trojan export runtime core version does not match its label\n' >&2
  exit 1
}
printf 'Trojan export runtime shell: Bash %s; core=%s\n' "$BASH_VERSION" "$actual_core_version"
source "$TESTS_DIR/menu_test_helper.sh"
setup_menu_test_env 120
cp -p "$core_binary" "$TMP_DIR/bin/sing-box"
# Source at top level so all registry, managed-store, render and export paths
# execute under the selected shell (including the Bash 4.2 compatibility run).
# shellcheck disable=SC1090
source "$TESTABLE_INSTALL"
export SINGBOX_CONFIG_FILE
mkdir -p "$SB_PROTOCOL_STATE_DIR/instances" "$SB_PROJECT_DIR"

server_pid=
client_pid=
marker_pid=
cleanup() {
  local rc=$? pid wait_rc failure_dir cleanup_status=0
  if (( rc != 0 )); then
    failure_dir=$(mktemp -d /tmp/sbv-trojan-export-failure.XXXXXX)
    chmod 700 "$failure_dir"
    for file in server.json client.json server.log client.log server-check.log client-check.log \
      marker.stderr openssl.stderr trojan-bad-tls-trust.json trojan-bad-trust.json; do
      if [[ -f $TMP_DIR/$file ]]; then
        cp -p "$TMP_DIR/$file" "$failure_dir/$file"
        chmod 600 "$failure_dir/$file"
      fi
    done
    printf 'Trojan export runtime diagnostics preserved at %s (private mode)\n' "$failure_dir" >&2
  fi
  for pid in "$client_pid" "$server_pid" "$marker_pid"; do
    [[ -n $pid ]] || continue
    if kill -0 "$pid" 2>/dev/null; then
      if kill "$pid" 2>/dev/null; then :; else
        printf 'Trojan cleanup could not signal owned pid %s\n' "$pid" >&2
        cleanup_status=1
      fi
    fi
    if wait "$pid" 2>/dev/null; then :; else
      wait_rc=$?
      case "$wait_rc" in
        129|130|143) ;;
        *)
          printf 'Trojan cleanup observed unexpected pid %s status %s\n' "$pid" "$wait_rc" >&2
          cleanup_status=1
          ;;
      esac
    fi
  done
  if rm -rf -- "$TMP_DIR"; then :; else
    printf 'Trojan cleanup could not remove private temp directory %s\n' "$TMP_DIR" >&2
    cleanup_status=1
  fi
  if (( rc == 0 && cleanup_status != 0 )); then rc=$cleanup_status; fi
  return "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

cat > "$TMP_DIR/marker.py" <<'PY_MARKER'
import select
import socket
import threading

tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
tcp.bind(("127.0.0.1", 0))
tcp.listen(32)
udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
udp.bind(("127.0.0.1", 0))
print("%d %d" % (tcp.getsockname()[1], udp.getsockname()[1]), flush=True)

def handle(connection):
    try:
        connection.settimeout(4)
        connection.recv(65536)
        body = b"trojan-export-runtime-tcp-ok\n"
        connection.sendall(
            b"HTTP/1.1 200 OK\r\nContent-Length: " + str(len(body)).encode()
            + b"\r\nConnection: close\r\n\r\n" + body
        )
    finally:
        connection.close()

while True:
    ready, _, _ = select.select([tcp, udp], [], [], 1)
    for sock in ready:
        if sock is tcp:
            connection, _ = tcp.accept()
            threading.Thread(target=handle, args=(connection,), daemon=True).start()
        else:
            payload, address = udp.recvfrom(65536)
            udp.sendto(payload, address)
PY_MARKER

cat > "$TMP_DIR/udp_probe.py" <<'PY_UDP'
import socket
import sys

proxy_port = int(sys.argv[1])
marker_port = int(sys.argv[2])
want = b"trojan-export-runtime-udp-ok"

def read_exact(sock, amount):
    value = b""
    while len(value) < amount:
        part = sock.recv(amount - len(value))
        if not part:
            raise SystemExit("SOCKS control connection closed")
        value += part
    return value

control = socket.create_connection(("127.0.0.1", proxy_port), 5)
control.sendall(b"\x05\x01\x00")
greeting = read_exact(control, 2)
if greeting != b"\x05\x00":
    raise SystemExit("SOCKS no-auth greeting failed")
control.sendall(b"\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00")
reply = read_exact(control, 4)
if reply[:2] != b"\x05\x00":
    raise SystemExit("SOCKS UDP associate failed")
if reply[3] == 1:
    read_exact(control, 4)
elif reply[3] == 3:
    read_exact(control, read_exact(control, 1)[0])
elif reply[3] == 4:
    read_exact(control, 16)
else:
    raise SystemExit("SOCKS UDP associate address type failed")
relay_port = int.from_bytes(read_exact(control, 2), "big")
datagram = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
datagram.settimeout(8)
datagram.sendto(
    b"\x00\x00\x00\x01\x7f\x00\x00\x01" + marker_port.to_bytes(2, "big") + want,
    ("127.0.0.1", relay_port),
)
response, _ = datagram.recvfrom(65536)
if response[:4] != b"\x00\x00\x00\x01" or response[10:] != want:
    raise SystemExit("UDP marker payload mismatch")
print(want.decode(), end="")
control.close()
datagram.close()
PY_UDP

python3 -u "$TMP_DIR/marker.py" > "$TMP_DIR/marker.ports" 2> "$TMP_DIR/marker.stderr" &
marker_pid=$!
for _ in {1..200}; do
  if [[ -s $TMP_DIR/marker.ports ]]; then break; fi
  if ! kill -0 "$marker_pid" 2>/dev/null; then
    printf 'Trojan marker exited before publishing ports\n' >&2
    exit 1
  fi
  sleep 0.02
done
read -r marker_tcp marker_udp < "$TMP_DIR/marker.ports"
[[ $marker_tcp =~ ^[0-9]+$ && $marker_tcp -gt 0 ]]
[[ $marker_udp =~ ^[0-9]+$ && $marker_udp -gt 0 ]]

read -r none_port http_port ws_port grpc_port quic_port plain_none_port plain_http_port plain_ws_port plain_grpc_port client_port < <(
  python3 - <<'PY_PORTS'
import socket
values = []
reserved = []
for index in range(10):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM if index == 4 else socket.SOCK_STREAM)
    sock.bind(("127.0.0.1", 0))
    values.append(sock.getsockname()[1])
    reserved.append(sock)
print(*values)
for sock in reserved:
    sock.close()
PY_PORTS
)

openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -subj '/CN=proxy.local' -addext 'subjectAltName=DNS:proxy.local' \
  -keyout "$TMP_DIR/server.key" -out "$TMP_DIR/server.crt" \
  >/dev/null 2> "$TMP_DIR/openssl.stderr"
chmod 600 "$TMP_DIR/server.key" "$TMP_DIR/server.crt"

printf '%s\n' 'INSTALLED_PROTOCOLS=trojan' 'PROTOCOL_STATE_VERSION=1' > "$SB_PROTOCOL_INDEX_FILE"
cat > "$SB_PROTOCOL_STATE_DIR/trojan.env" <<'EOF_TROJAN_STATE'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
EOF_TROJAN_STATE

alice_password=$'trojan-päss-密码\nline\n'
bob_password='trojan-bob-密码'
single_password='trojan-single-password'
http_password='trojan-http-password'
ws_password='trojan-ws-password'
grpc_password='trojan-grpc-password'
quic_password='trojan-quic-password'
plain_none_password='trojan-plain-none-password'
plain_http_password='trojan-plain-http-password'
plain_ws_password='trojan-plain-ws-password'
plain_grpc_password='trojan-plain-grpc-password'
cert_path=$TMP_DIR/server.crt
key_path=$TMP_DIR/server.key

jq -n \
  --arg alice_password "$alice_password" --arg bob_password "$bob_password" \
  --arg single_password "$single_password" --arg http_password "$http_password" \
  --arg ws_password "$ws_password" --arg grpc_password "$grpc_password" \
  --arg quic_password "$quic_password" --arg plain_none_password "$plain_none_password" \
  --arg plain_http_password "$plain_http_password" --arg plain_ws_password "$plain_ws_password" \
  --arg plain_grpc_password "$plain_grpc_password" --arg cert "$cert_path" --arg key "$key_path" \
  --argjson none_port "$none_port" --argjson http_port "$http_port" \
  --argjson ws_port "$ws_port" --argjson grpc_port "$grpc_port" \
  --argjson quic_port "$quic_port" --argjson plain_none_port "$plain_none_port" \
  --argjson plain_http_port "$plain_http_port" --argjson plain_ws_port "$plain_ws_port" \
  --argjson plain_grpc_port "$plain_grpc_port" '
  def tls: {enabled:true,server_name:"proxy.local",certificate_path:$cert,key_path:$key};
  def rec($id;$name;$tag;$port;$users;$tls;$trust;$transport):
    {id:$id,name:$name,tag:$tag,listen:{address:"127.0.0.1",port:$port},
     authentication:{users:$users},tls:$tls,client_trust:$trust,
     transport:$transport,outbound_policy:"default",dependencies:[]};
  {schema_version:1,protocol:"trojan",revision:1,default_instance_id:"trojan-none",
   instances:[
    rec("trojan-none";"Trojan 用户";"trojan-none";$none_port;
      [{name:"alice 用户",password:$alice_password},{name:"用户-bob",password:$bob_password}];
      tls;"certificate";{type:"none"}),
    rec("trojan-http";"Trojan HTTP";"trojan-http";$http_port;
      [{name:"http 用户",password:$http_password}];
      tls;"certificate";{type:"http",host:["proxy.local"],path:"/trojan"}),
    rec("trojan-ws";"Trojan WebSocket";"trojan-ws";$ws_port;
      [{name:"ws 用户",password:$ws_password}];
      tls;"certificate";{type:"ws",path:"/trojan-ws"}),
    rec("trojan-grpc";"Trojan gRPC";"trojan-grpc";$grpc_port;
      [{name:"grpc 用户",password:$grpc_password}];
      tls;"certificate";{type:"grpc",service_name:"trojan_runtime"}),
    rec("trojan-quic";"Trojan QUIC";"trojan-quic";$quic_port;
      [{name:"quic 用户",password:$quic_password}];
      tls;"certificate";{type:"quic"}),
    rec("trojan-plain-none";"Trojan Plain";"trojan-plain-none";$plain_none_port;
      [{name:"plain-none 用户",password:$plain_none_password}];
      {enabled:false};"system";{type:"none"}),
    rec("trojan-plain-http";"Trojan Plain HTTP";"trojan-plain-http";$plain_http_port;
      [{name:"plain-http 用户",password:$plain_http_password}];
      {enabled:false};"system";{type:"http",path:"/plain-trojan"}),
    rec("trojan-plain-ws";"Trojan Plain WebSocket";"trojan-plain-ws";$plain_ws_port;
      [{name:"plain-ws 用户",password:$plain_ws_password}];
      {enabled:false};"system";{type:"ws",path:"/plain-trojan-ws"}),
    rec("trojan-plain-grpc";"Trojan Plain gRPC";"trojan-plain-grpc";$plain_grpc_port;
      [{name:"plain-grpc 用户",password:$plain_grpc_password}];
      {enabled:false};"system";{type:"grpc",service_name:"plain_trojan_runtime"})
   ]}' > "$SB_PROTOCOL_STATE_DIR/instances/trojan.json"
chmod 600 "$SB_PROTOCOL_STATE_DIR/trojan.env" "$SB_PROTOCOL_STATE_DIR/instances/trojan.json"
store_file=$SB_PROTOCOL_STATE_DIR/instances/trojan.json

# This is the real managed store path, not a hand-built inbound fixture.
validate_structured_instance_store trojan "$store_file"
plain_proxy_structured_state_active trojan

rendered_inbounds=$(render_structured_instance_inbounds trojan "$store_file" | jq -s .)
jq -e '
  length == 9 and
  all(.[]; .type == "trojan") and
  all(.[] | select(.tag | startswith("trojan-plain-") | not);
    .tls.enabled == true and .tls.server_name == "proxy.local" and
    (.tls | has("certificate_path") and has("key_path"))) and
  any(.[]; .tag == "trojan-none" and (has("transport") | not)) and
  any(.[]; .tag == "trojan-http" and .transport.type == "http" and .transport.path == "/trojan") and
  any(.[]; .tag == "trojan-ws" and .transport.type == "ws" and
    .transport.path == "/trojan-ws" and (.transport | has("max_early_data") | not)) and
  any(.[]; .tag == "trojan-grpc" and .transport.type == "grpc" and
    .transport.service_name == "trojan_runtime") and
  any(.[]; .tag == "trojan-quic" and .transport.type == "quic") and
  all(.[] | select(.tag | startswith("trojan-plain-")); (.tls // {}) | has("enabled") | not)
' <<< "$rendered_inbounds" >/dev/null
jq -n --argjson inbounds "$rendered_inbounds" \
  '{log:{level:"info"},inbounds:$inbounds,
    outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' \
  > "$TMP_DIR/server.json"
"$SINGBOX_BIN_PATH" check -c "$TMP_DIR/server.json" > "$TMP_DIR/server-check.log" 2>&1

# Both public API layers must consume the same managed snapshot and preserve
# per-user identity, transport, strict trust and Unicode/newline passwords.
public_export=$(build_trojan_client_outbounds_from_store "$store_file" 198.51.100.10)
public_outbounds=$(jq -s . <<< "$public_export")
jq -e --arg alice_password "$alice_password" '
  length == 10 and
  all(.[]; .type == "trojan" and .server == "198.51.100.10" and
    ((.tls == null) or (.tls.enabled == true and .tls.server_name == "proxy.local" and
      (.tls.certificate | contains("BEGIN CERTIFICATE")))) and
    (.tls | has("insecure") | not)) and
  (map(.tag) | unique | length) == 10 and
  any(.[]; .password == $alice_password) and
  any(.[]; .transport.type == "http" and .transport.path == "/trojan") and
  any(.[]; .transport.type == "ws" and .transport.path == "/trojan-ws" and
    (.transport | has("max_early_data") | not)) and
  any(.[]; .transport.type == "grpc" and .transport.service_name == "trojan_runtime") and
  any(.[]; .transport.type == "quic") and
  all(.[] | select(.tag | contains("-plain-")); has("tls") | not)
' <<< "$public_outbounds" >/dev/null

local_export=$(build_trojan_client_outbounds_from_store "$store_file" 127.0.0.1 | jq -s .)
wrapper_export=$(build_client_trojan_outbounds 127.0.0.1 | jq -s .)
jq -e --argjson expected "$local_export" '
  (map(.tag) | sort) == ($expected | map(.tag) | sort)
' <<< "$wrapper_export" >/dev/null

# Tags must remain stable when managed instance and user arrays are reordered.
reordered_store="$TMP_DIR/trojan-reordered.json"
jq '.instances |= (map(.authentication.users |= reverse) | reverse)' \
  "$store_file" > "$reordered_store"
chmod 600 "$reordered_store"
reordered_export=$(build_trojan_client_outbounds_from_store "$reordered_store" 127.0.0.1 | jq -s .)
jq -e --argjson before "$local_export" '
  (map(.tag) | sort) == ($before | map(.tag) | sort)
' <<< "$reordered_export" >/dev/null

# client_trust is an explicit managed contract: certificate embeds the public
# certificate, system trust does not; invalid combinations fail closed.
system_store="$TMP_DIR/trojan-system.json"
jq '(.instances[0].client_trust = "system")' "$store_file" > "$system_store"
chmod 600 "$system_store"
validate_structured_instance_store trojan "$system_store"
system_export=$(build_trojan_client_outbounds_from_store "$system_store" 127.0.0.1 | jq -s .)
jq -e '
  any(.[]; .tag | contains("trojan-none")) and
  all(.[] | select(.tag | contains("trojan-none")); .tls.enabled == true and
    (.tls | has("certificate") | not))
' <<< "$system_export" >/dev/null

bad_trust="$TMP_DIR/trojan-bad-trust.json"
jq '(.instances[0].client_trust = "bogus")' "$store_file" > "$bad_trust"
if validate_structured_instance_store trojan "$bad_trust" >/dev/null 2>&1; then
  printf 'Trojan validator accepted an unknown client_trust value\n' >&2
  exit 1
fi
bad_tls_trust="$TMP_DIR/trojan-bad-tls-trust.json"
jq '(.instances[0].tls = {enabled:false} | .instances[0].client_trust = "certificate")' \
  "$store_file" > "$bad_tls_trust"
if validate_structured_instance_store trojan "$bad_tls_trust" >/dev/null 2>&1; then
  printf 'Trojan validator accepted certificate trust with TLS disabled\n' >&2
  exit 1
fi

# WS early data is intentionally unsupported by the real core pair. It must
# be rejected by the render/export adapter rather than silently published.
bad_ws="$TMP_DIR/trojan-ws-early-data.json"
jq '(.instances[2].transport.max_early_data = 1024 |
     .instances[2].transport.early_data_header_name = "Sec-WebSocket-Protocol")' \
  "$store_file" > "$bad_ws"
if render_structured_instance_inbounds trojan "$bad_ws" > "$TMP_DIR/bad-ws.out" 2> "$TMP_DIR/bad-ws.stderr"; then
  printf 'Trojan renderer accepted WebSocket early data\n' >&2
  exit 1
fi
[[ ! -s "$TMP_DIR/bad-ws.out" ]]

stop_owned_process() {
  local pid=$1 wait_status
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" || return 1
  fi
  if wait "$pid"; then :; else
    wait_status=$?
    case "$wait_status" in
      129|130|143) ;;
      *) printf 'Trojan process %s exited unexpectedly: %s\n' "$pid" "$wait_status" >&2; return 1 ;;
    esac
  fi
}
stop_server() {
  if [[ -n $server_pid ]]; then
    stop_owned_process "$server_pid" || return 1
    server_pid=
  fi
}
start_server() {
  "$SINGBOX_BIN_PATH" run -c "$TMP_DIR/server.json" > "$TMP_DIR/server.log" 2>&1 &
  server_pid=$!
  for _ in {1..300}; do
    if ! kill -0 "$server_pid" 2>/dev/null; then
      tail -100 "$TMP_DIR/server.log" >&2
      return 1
    fi
    if grep -Fq 'sing-box started' "$TMP_DIR/server.log"; then return 0; fi
    sleep 0.02
  done
  tail -100 "$TMP_DIR/server.log" >&2
  return 1
}
stop_client() {
  if [[ -n $client_pid ]]; then
    stop_owned_process "$client_pid" || return 1
    client_pid=
  fi
}
start_client() {
  local outbound=$1 tag
  tag=$(jq -er '.tag | select(type == "string" and length > 0)' <<< "$outbound")
  jq -n --argjson outbound "$outbound" --arg tag "$tag" --argjson port "$client_port" \
    '{log:{level:"info"},
      inbounds:[{type:"mixed",tag:"local",listen:"127.0.0.1",listen_port:$port}],
      outbounds:[$outbound,{type:"direct",tag:"direct"}],route:{final:$tag}}' \
    > "$TMP_DIR/client.json"
  "$SINGBOX_BIN_PATH" check -c "$TMP_DIR/client.json" > "$TMP_DIR/client-check.log" 2>&1
  "$SINGBOX_BIN_PATH" run -c "$TMP_DIR/client.json" > "$TMP_DIR/client.log" 2>&1 &
  client_pid=$!
  for _ in {1..300}; do
    if ! kill -0 "$client_pid" 2>/dev/null; then
      tail -100 "$TMP_DIR/client.log" >&2
      return 1
    fi
    if grep -Fq 'sing-box started' "$TMP_DIR/client.log"; then return 0; fi
    sleep 0.02
  done
  tail -100 "$TMP_DIR/client.log" >&2
  return 1
}
probe_tcp() {
  local label=$1
  curl --silent --show-error --fail --max-time 8 --noproxy '' \
    --proxy "socks5h://127.0.0.1:$client_port" \
    "http://127.0.0.1:$marker_tcp/" > "$TMP_DIR/$label.tcp"
  grep -Fqx 'trojan-export-runtime-tcp-ok' "$TMP_DIR/$label.tcp"
}
probe_udp() {
  local label=$1
  python3 "$TMP_DIR/udp_probe.py" "$client_port" "$marker_udp" > "$TMP_DIR/$label.udp"
  grep -Fqx 'trojan-export-runtime-udp-ok' "$TMP_DIR/$label.udp"
}

start_server
runtime_export=$(build_client_trojan_outbounds 127.0.0.1 | jq -s .)
runtime_count=$(jq -r 'length' <<< "$runtime_export")
[[ $runtime_count -eq 10 ]]
while IFS= read -r outbound; do
  [[ -n $outbound ]] || continue
  tag=$(jq -r '.tag' <<< "$outbound")
  safe_tag=$(printf '%s' "$tag" | tr -c 'A-Za-z0-9_.-' '_')
  start_client "$outbound"
  probe_tcp "$safe_tag"
  probe_udp "$safe_tag"
  stop_client
done < <(jq -c '.[]' <<< "$runtime_export")

first_outbound=$(jq -c '.[0]' <<< "$runtime_export")
wrong_auth=$(jq '.password = "wrong-trojan-password"' <<< "$first_outbound")
start_client "$wrong_auth"
if probe_tcp wrong-auth; then
  printf 'Trojan wrong credentials unexpectedly reached the marker\n' >&2
  exit 1
fi
stop_client
wrong_sni=$(jq '.tls.server_name = "wrong.proxy.local"' <<< "$first_outbound")
start_client "$wrong_sni"
if probe_tcp wrong-sni; then
  printf 'Trojan wrong SNI unexpectedly reached the marker\n' >&2
  exit 1
fi
stop_client
stop_server

for secret in "$alice_password" "$bob_password" "$single_password" "$http_password" "$ws_password" "$grpc_password" "$quic_password" \
  "$plain_none_password" "$plain_http_password" "$plain_ws_password" "$plain_grpc_password"; do
  if jq -en --arg secret "$secret" --rawfile server "$TMP_DIR/server.log" \
      --rawfile client "$TMP_DIR/client.log" \
      '($server | contains($secret)) or ($client | contains($secret))' >/dev/null; then
    printf 'Trojan runtime logs leaked a credential\n' >&2
    exit 1
  fi
done

printf 'Trojan export runtime passed: core=%s shell=%s instances=9 users=10 tcp=10 udp=10 wrong-auth=1 wrong-sni=1 strict-ca=1 transports=none,http,ws-no-ed,grpc,quic-tls,plain-none,plain-http,plain-ws,plain-grpc\n' \
  "$core_label" "$BASH_VERSION"
