#!/usr/bin/env python3
"""Real WireGuard/core probes in a container with no external network or keys."""
import hashlib
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time

os.umask(0o077)
root = Path(tempfile.mkdtemp(prefix='sbv-media-'))
processes = []
requests = []

def run(*args, **kw):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kw).stdout.strip()

def start(config, path, executable='/core'):
    path.write_text(json.dumps(config))
    run(executable, 'check', '-c', str(path))
    p = subprocess.Popen([executable, 'run', '-c', str(path)],
                         stdout=subprocess.DEVNULL, stderr=open(root / "core.log", "ab"))
    processes.append(p)
    time.sleep(.3)
    assert p.poll() is None
    return p

def stop(p):
    p.terminate()
    p.wait(timeout=3)
    processes.remove(p)

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        requests.append((self.path, self.client_address[0]))
        self.send_response(200)
        self.end_headers()
        try:
            if self.path == '/cdn-cgi/trace':
                self.wfile.write(b'warp=on\n' if self.client_address[0] == '10.77.0.2' else b'warp=off\n')
            else:
                for _ in range(60 if self.path == '/stream' else 1):
                    self.wfile.write(b'x' * 1000)
                    self.wfile.flush()
                    time.sleep(.1)
        except (BrokenPipeError, ConnectionResetError):
            pass

def curl(port, path, timeout=8):
    return ['curl', '-q', '--noproxy', '', '--socks5-hostname', f'127.0.0.1:{port}',
            '-fsS', '--max-time', str(timeout), f'http://10.77.0.1:8080/{path}']

def core_pids():
    found = set()
    for path in Path('/proc').glob('[0-9]*/cmdline'):
        try:
            args = path.read_bytes().split(b'\0')
            if args[0].endswith((b'/core', b'/sing-box')) and args[1:2] == [b'run']:
                found.add(int(path.parent.name))
        except FileNotFoundError:
            pass
    return found

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

try:
    server_key, client_key = run('wg', 'genkey'), run('wg', 'genkey')
    server_pub = run('wg', 'pubkey', input=server_key)
    client_pub = run('wg', 'pubkey', input=client_key)
    (root / 'server.key').write_text(server_key)
    run('ip', 'link', 'set', 'lo', 'up')
    run('ip', 'link', 'add', 'wg-lab', 'type', 'wireguard')
    run('ip', 'addr', 'add', '10.77.0.1/24', 'dev', 'wg-lab')
    run('wg', 'set', 'wg-lab', 'private-key', str(root / 'server.key'), 'listen-port', '51820',
        'peer', client_pub, 'allowed-ips', '10.77.0.2/32')
    run('ip', 'link', 'set', 'wg-lab', 'up')
    # Newer cores pause endpoints when the netns has no default interface.
    # A dummy link supplies that metadata without granting external access.
    run('ip', 'link', 'add', 'uplink', 'type', 'dummy')
    run('ip', 'addr', 'add', '192.0.2.1/24', 'dev', 'uplink')
    run('ip', 'link', 'set', 'uplink', 'up')
    run('ip', 'route', 'add', 'default', 'dev', 'uplink')
    http = http.server.ThreadingHTTPServer(('10.77.0.1', 8080), Handler)
    threading.Thread(target=http.serve_forever, daemon=True).start()
    endpoint = dict(type='wireguard', tag='warp-ep', address=['10.77.0.2/32'], private_key=client_key,
                    peers=[dict(address='127.0.0.1', port=51820, public_key=server_pub, allowed_ips=['0.0.0.0/0'])])

    def config(port, protocol='socks', auth=False):
        inbound = dict(type=protocol, tag='probe', listen='127.0.0.1', listen_port=port)
        if auth:
            inbound['users'] = [dict(username='fixture', password='secret')]
        return dict(log=dict(disabled=True), inbounds=[inbound], endpoints=[endpoint], route=dict(final='warp-ep'))

    # Demonstrate endpoint/session interference with two independent instances.
    a = start(config(20080), root / 'a.json')
    baseline = subprocess.run(curl(20080, 'stream'), capture_output=True)
    assert baseline.returncode == 0 and len(baseline.stdout) == 60000, (baseline.returncode, len(baseline.stdout), baseline.stderr.decode(), (root / "core.log").read_text())
    first_endpoint = run('wg', 'show', 'wg-lab', 'endpoints').split()[-1]
    with open(root / 'stream.bin', 'wb') as output:
        stream = subprocess.Popen(curl(20080, 'stream'), stdout=output, stderr=subprocess.DEVNULL)
        time.sleep(1)
        b = start(config(20081), root / 'b.json')
        second = subprocess.run(curl(20081, '', 2), capture_output=True)
        second_endpoint = run('wg', 'show', 'wg-lab', 'endpoints').split()[-1]
        stream.wait(timeout=10)
    received = (root / 'stream.bin').stat().st_size
    assert second.returncode == 0 and first_endpoint != second_endpoint
    assert stream.returncode != 0 and received < 60000
    print(json.dumps(dict(probe='identity-concurrency', baseline_bytes=60000, received_bytes=received,
                          endpoint_changed=True, stream_exit=stream.returncode)), flush=True)
    stop(b)
    stop(a)

    fixture = root / 'fixture'
    fixture.mkdir()
    install = fixture / 'install.sh'
    install.write_text(run('bash', '/repo/tests/install_fixture_source_helper.sh', '--source'))
    run('bash', '/repo/tests/install_fixture_source_helper.sh', '--isolate', str(install))
    (fixture / 'bin').mkdir()
    (fixture / 'bin/sing-box').symlink_to('/core')
    runtime = fixture / 'runtime'
    runtime.mkdir()
    backend = runtime / 'media-check/region_restriction_check.sh'
    backend.parent.mkdir()
    backend.write_text('''#!/usr/bin/env bash
set -euo pipefail
while getopts 'P:C:' opt; do if [[ $opt == C ]]; then curl_command=$OPTARG; fi; done
printf '%s\\n' "$HOME" > "$CASE_HOME"
"$curl_command" -fsS https://media.fixture.invalid/ >/dev/null
printf 'backend-called\\n' >> "$CASE_BACKEND"
''')
    backend.chmod(0o700)
    (fixture / 'bin/systemctl').write_text('''#!/usr/bin/env bash
set -euo pipefail
[[ "$*" != *--timestamp* && "$*" != *--value* ]] || exit 98
case "$*" in
 *is-active*) kill -0 "$(cat "$FIXTURE/pid")" ;;
 *MainPID*) printf 'MainPID=%s\\n' "$(cat "$FIXTURE/pid")" ;;
 *) exit 1 ;;
esac
''')
    # Substitute only test URLs/timeouts. All proxy, auth and routing are real.
    # Model the systemd 219 D-Bus property (no --value/--timestamp flags).
    (fixture / 'bin/busctl').write_text('''#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == 'get-property org.freedesktop.systemd1 /org/freedesktop/systemd1/unit/sing_2dbox_2eservice org.freedesktop.systemd1.Service ExecMainStartTimestamp' ]]
printf 't %s\\n' "$(cat "$FIXTURE/started")"
''')
    (fixture / 'bin/curl').write_text('''#!/usr/bin/env bash
set -euo pipefail
args=()
for value; do
 case "$value" in
  https://www.cloudflare.com/cdn-cgi/trace) value=http://10.77.0.1:8080/cdn-cgi/trace ;;
  https://media.fixture.invalid/) value=http://10.77.0.1:8080/media ;;
  15) value=2 ;;
 esac
 args+=("$value")
done
exec /usr/bin/curl "${args[@]}"
''')
    for name in ['systemctl', 'busctl', 'curl']:
        (fixture / 'bin' / name).chmod(0o700)
    # Diagnostics must not read or repair the saved account sidecar.
    (runtime / 'warp.key').write_text('deliberately-invalid-saved-credentials\n')
    before_key = sha(runtime / 'warp.key')
    env = dict(os.environ, FIXTURE=str(fixture), PATH=f'{fixture}/bin:' + os.environ['PATH'],
               CASE_HOME=str(root / 'home'), CASE_BACKEND=str(root / 'called'), NO_PROXY='*')
    command = f'source "{install}"; ensure_media_check_backend() {{ :; }}; run_media_check_via_warp'
    for protocol in ['socks', 'mixed', 'http']:
        service_config = runtime / 'config.json'
        cfg = config(20080, protocol, True)
        cfg['log'] = dict(level='warn')
        p = start(cfg, service_config, str(fixture / 'bin/sing-box'))
        (fixture / 'pid').write_text(str(p.pid))
        (fixture / 'started').write_text(str(time.time_ns() // 1000))
        before = sha(service_config)
        started = (fixture / 'started').read_text()
        (fixture / 'started').write_text('invalid')
        bad_time = subprocess.run(['bash', '-c', command], env=env, capture_output=True, timeout=5)
        assert bad_time.returncode != 0
        (fixture / 'started').write_text(started)
        listeners = run('ss', '-Hltn')
        count = len(requests)
        completed = subprocess.run(['bash', '-c', command], env=env, capture_output=True, text=True, timeout=10)
        assert completed.returncode == 0, completed.stderr + completed.stdout + (root / "core.log").read_text()
        assert core_pids() == {p.pid}, 'diagnostics started a second core'
        assert sha(service_config) == before and sha(runtime / 'warp.key') == before_key
        assert run('ss', '-Hltn') == listeners, 'new listener remained'
        assert not Path((root / 'home').read_text().strip()).exists()
        observed = requests[count:]
        assert [x[0] for x in observed] == ['/cdn-cgi/trace', '/media']
        assert all(x[1] == '10.77.0.2' for x in observed), 'DIRECT path observed'
        # On-disk routing written after service start is not trusted as loaded.
        original_stat = service_config.stat()
        time.sleep(.02)
        os.utime(service_config, None)
        stale = subprocess.run(['bash', '-c', command], env=env, capture_output=True, timeout=5)
        assert stale.returncode != 0
        os.utime(service_config, ns=(original_stat.st_atime_ns, original_stat.st_mtime_ns))
        if protocol == 'socks':
            calls = (root / 'called').read_bytes()
            run('ip', 'link', 'set', 'wg-lab', 'down')
            outage = subprocess.run(['bash', '-c', command], env=env, capture_output=True, timeout=8)
            assert outage.returncode != 0 and (root / 'called').read_bytes() == calls
            run('ip', 'link', 'set', 'wg-lab', 'up')
        print(f'{protocol}: real authenticated ingress -> existing WireGuard, no second core/listener, '
              'config/key unchanged; stale config rejected', flush=True)
        stop(p)
    print('isolated runtime checks passed; local trace fixture is not Cloudflare acceptance', flush=True)
finally:
    for p in processes:
        p.terminate()
    for p in processes:
        p.wait(timeout=3)
    subprocess.run(['ip', 'link', 'del', 'wg-lab'], capture_output=True)
