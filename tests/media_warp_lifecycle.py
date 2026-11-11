#!/usr/bin/env python3
"""Fixture helper: real process groups, dummy credentials, no external traffic."""
import os
from pathlib import Path
import signal
import subprocess
import time

root = Path(os.environ['MEDIA_FIXTURE_ROOT'])

def live(pid):
    try:
        return Path(f'/proc/{pid}/stat').read_text().split(') ', 1)[1][0] != 'Z'
    except FileNotFoundError:
        return False

def wait_for(predicate, seconds=5):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.03)
    raise AssertionError('fixture wait timed out')

def start(name, mode='ok', route='warp', trace_off=False, start_fail=False):
    case = root / name
    case.mkdir()
    if trace_off:
        (case / 'trace-off').touch()
    if start_fail:
        (case / 'start-fail').touch()
    env = dict(os.environ, CASE_DIR=str(case), MEDIA_FIXTURE_MODE=mode,
               MEDIA_FIXTURE_ROUTE=route, NO_PROXY='*', ALL_PROXY='http://127.0.0.1:1')
    log = open(case / 'output', 'wb')
    p = subprocess.Popen(['bash', str(root / 'driver.sh')], env=env,
                         stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    log.close()
    return p, case

def active(case):
    return list(case.glob('active.*'))

def assert_clean(p, case, expected=None):
    status = p.wait(timeout=6)
    if expected is not None:
        assert status == expected, (case.name, status, (case / 'output').read_text())
    records = [x.read_text().splitlines() for x in active(case)]
    for home, backend_pid, runner_pid in records:
        wait_for(lambda: not Path(home).exists() and not live(backend_pid) and not live(runner_pid))
    for child in case.glob('child.*'):
        wait_for(lambda: not live(child.read_text().strip()))
    assert 'secret' not in (case / 'output').read_text(), 'credential appeared in output'
    if (case / 'curl-args').exists():
        assert 'secret' not in (case / 'curl-args').read_text()
    print(f'{case.name}: exit={status}, no live descendants/private workspace')

for name, mode, status in [('success', 'ok', 0), ('backend-failure', 'fail', 37)]:
    p, case = start(name, mode)
    assert_clean(p, case, status)
    assert len((case / 'curl-args').read_text().splitlines()) == 3
p, case = start('service-pid-change', mode='pid-change')
assert_clean(p, case, 1)
(root / 'pid').write_text('13579\n')
p, case = start('start-failure', start_fail=True)
assert_clean(p, case, 76)
assert not active(case)
p, case = start('trace-off', trace_off=True)
assert_clean(p, case, 1)
assert not active(case)
(root / 'stopped').touch()
p, case = start('service-stopped')
assert_clean(p, case, 1)
assert not active(case)
(root / 'stopped').unlink()
p, case = start('native', route='native')
assert_clean(p, case, 0)
assert not (case / 'curl-args').exists()

for signum, expected in [(signal.SIGINT, 130), (signal.SIGTERM, 143), (signal.SIGHUP, 129)]:
    p, case = start(f'signal-{signum}', 'hang')
    wait_for(lambda: active(case) and list(case.glob('child.*')))
    runner_pid = active(case)[0].read_text().splitlines()[2]
    owner = Path(f'/proc/{runner_pid}/cmdline').read_bytes().split(b'\0')[2]
    os.kill(int(owner), signum)
    assert_clean(p, case, expected)
for name, victim in [('parent-exit', 'parent'), ('owner-kill', 'owner')]:
    p, case = start(name, 'hang')
    wait_for(lambda: active(case) and list(case.glob('child.*')))
    runner_pid = active(case)[0].read_text().splitlines()[2]
    owner = Path(f'/proc/{runner_pid}/cmdline').read_bytes().split(b'\0')[2]
    os.kill(p.pid if victim == 'parent' else int(owner), signal.SIGKILL)
    assert_clean(p, case)
p, case = start('timeout', 'hang')
assert_clean(p, case)
assert '15 分钟上限' in (case / 'output').read_text()

pairs = [start(f'concurrent-{i}', 'hang') for i in range(2)]
for p, case in pairs:
    wait_for(lambda: active(case) and list(case.glob('child.*')))
homes = [active(case)[0].read_text().splitlines()[0] for _, case in pairs]
assert homes[0] != homes[1]
p, case = pairs[0]
runner_pid = active(case)[0].read_text().splitlines()[2]
owner = Path(f'/proc/{runner_pid}/cmdline').read_bytes().split(b'\0')[2]
os.kill(int(owner), signal.SIGTERM)
assert_clean(p, case, 143)
assert Path(homes[1]).exists() and pairs[1][0].poll() is None
assert_clean(*pairs[1])
