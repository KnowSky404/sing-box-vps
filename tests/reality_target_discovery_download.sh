#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf -- "${TMP_DIR}"' EXIT
mkdir -p "${TMP_DIR}/payload" "${TMP_DIR}/project"
export RTC_DISCOVERY_FIXTURE="${TMP_DIR}"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

cat > "${TMP_DIR}/payload/reality-target-checker.sh" <<'SH'
#!/usr/bin/env bash
printf 'unexpected execution\n' > "${RTC_DISCOVERY_FIXTURE}/executed"
SH
for module in discover sources; do
  cat > "${TMP_DIR}/payload/reality-target-${module}.py" <<'PY'
import os
from pathlib import Path
Path(os.environ['RTC_DISCOVERY_FIXTURE'], 'executed').write_text('unexpected execution')
PY
done
CHECKER_SHA=$(sha256sum "${TMP_DIR}/payload/reality-target-checker.sh")
DISCOVER_SHA=$(sha256sum "${TMP_DIR}/payload/reality-target-discover.py")
SOURCES_SHA=$(sha256sum "${TMP_DIR}/payload/reality-target-sources.py")
sed -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  -e "s|^readonly SB_REALITY_CHECKER_SHA256=.*|readonly SB_REALITY_CHECKER_SHA256=\"${CHECKER_SHA%% *}\"|" \
  -e "s|^readonly SB_REALITY_DISCOVER_SHA256=.*|readonly SB_REALITY_DISCOVER_SHA256=\"${DISCOVER_SHA%% *}\"|" \
  -e "s|^readonly SB_REALITY_SOURCES_SHA256=.*|readonly SB_REALITY_SOURCES_SHA256=\"${SOURCES_SHA%% *}\"|" \
  "${REPO_ROOT}/install.sh" > "${TMP_DIR}/install.sh"

# A complete preparation must validate all three artifacts without executing
# either shell or Python top-level code. Each file is downloaded to staging.
dig() { :; }
curl() {
  local output='' arg url=''
  while (($#)); do
    arg=$1
    shift
    case "${arg}" in
      --output|-o) output=$1; shift ;;
      https://*) url=${arg} ;;
    esac
  done
  [[ "${output}" == *.part && -n "${url}" ]] || return 91
  printf '%s\n' "${url##*/}" >> "${RTC_DISCOVERY_FIXTURE}/downloads"
  cp -- "${RTC_DISCOVERY_FIXTURE}/payload/${url##*/}" "${output}" || return 92
  [[ "${url##*/}" != "${RTC_FAILED_ARTIFACT:-}" ]] || return 22
}
export -f dig curl
run_preparation() {
  bash -c 'source "$1"; prepare_reality_target_discovery "$2"' _ "$1" "$2"
}
mkdir "${TMP_DIR}/valid"
run_preparation "${TMP_DIR}/install.sh" "${TMP_DIR}/valid" || fail 'valid discovery bundle rejected'
for filename in reality-target-checker.sh reality-target-discover.py reality-target-sources.py; do
  cmp "${TMP_DIR}/payload/${filename}" "${TMP_DIR}/valid/${filename}" || fail 'validated artifact bytes changed'
  [[ ! -e "${TMP_DIR}/valid/${filename}.part" ]] || fail 'successful download left staging'
done
[[ ! -e "${TMP_DIR}/executed" ]] || fail 'preparation executed downloaded code'

printf '\n# tampered\n' >> "${TMP_DIR}/payload/reality-target-discover.py"
mkdir "${TMP_DIR}/tampered"
if run_preparation "${TMP_DIR}/install.sh" "${TMP_DIR}/tampered"; then
  fail 'untrusted discovery module accepted'
fi
[[ ! -e "${TMP_DIR}/tampered/reality-target-discover.py" ]] || fail 'tampered module published'
[[ ! -e "${TMP_DIR}/tampered/reality-target-discover.py.part" ]] || fail 'tampered module leaked staging'
cp "${TMP_DIR}/valid/reality-target-discover.py" "${TMP_DIR}/payload/reality-target-discover.py"

mkdir "${TMP_DIR}/partial"
if RTC_FAILED_ARTIFACT=reality-target-sources.py run_preparation "${TMP_DIR}/install.sh" "${TMP_DIR}/partial"; then
  fail 'partial discovery module download accepted'
fi
[[ ! -e "${TMP_DIR}/partial/reality-target-sources.py" ]] || fail 'partial module published'
[[ ! -e "${TMP_DIR}/partial/reality-target-sources.py.part" ]] || fail 'partial module leaked staging'

# Matching digest is insufficient when Python syntax is invalid.
printf 'def invalid(\n' > "${TMP_DIR}/payload/reality-target-sources.py"
INVALID_SHA=$(sha256sum "${TMP_DIR}/payload/reality-target-sources.py")
sed "s|^readonly SB_REALITY_SOURCES_SHA256=.*|readonly SB_REALITY_SOURCES_SHA256=\"${INVALID_SHA%% *}\"|" \
  "${TMP_DIR}/install.sh" > "${TMP_DIR}/invalid-install.sh"
mkdir "${TMP_DIR}/invalid"
if run_preparation "${TMP_DIR}/invalid-install.sh" "${TMP_DIR}/invalid"; then
  fail 'Python syntax error accepted despite matching hash'
fi
[[ ! -e "${TMP_DIR}/invalid/reality-target-sources.py" ]] || fail 'invalid Python module published'
[[ ! -e "${TMP_DIR}/executed" ]] || fail 'failed preparation executed downloaded code'

downloads_before=$(wc -l < "${TMP_DIR}/downloads")
mkdir "${TMP_DIR}/missing-python"
if bash -c 'source "$1"; python3() { return 1; }; prepare_reality_target_discovery "$2"' \
  _ "${TMP_DIR}/install.sh" "${TMP_DIR}/missing-python"; then
  fail 'unavailable Python was accepted'
fi
[[ "$(wc -l < "${TMP_DIR}/downloads")" == "${downloads_before}" ]] || fail 'download started before checking Python'

# The external discovery command remains separated from preparation and keeps
# its original status/JSON. Every scope value is an argument, never shell code.
source "${TMP_DIR}/install.sh"
cat > "${TMP_DIR}/runner.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${RTC_DISCOVERY_FIXTURE}/arguments"
printf 'untrusted-checker-stderr\n' >&2
printf '{"report_type":"discovery","summary":{"exit_code":3}}\n'
exit 3
SH
started=${SECONDS}
rc=0
run_reality_target_discovery "${TMP_DIR}/runner.sh" "${TMP_DIR}/scan.json" scan 192.0.2.0/24 64500 \
  2>"${TMP_DIR}/runner.stderr" || rc=$?
[[ "${rc}" == 3 ]] || fail "discovery status was lost: ${rc}"
(( SECONDS - started < 3 )) || fail 'fast completion waited for a heartbeat'
[[ "$(cat "${TMP_DIR}/arguments")" == $'discover\n192.0.2.0/24\n--asn\n64500\n--json\n--timeout\n3\n--max-hosts\n256\n--concurrency\n8\n--rate\n10\n--max-candidates\n256\n--samples\n1\n--deadline\n300' ]] || fail 'discovery invocation lacks fixed budgets/scope'
jq -e '.summary.exit_code==3' "${TMP_DIR}/scan.json" >/dev/null || fail 'discovery stdout changed'
grep -Fqx untrusted-checker-stderr "${TMP_DIR}/scan.json.stderr" || fail 'checker diagnostic was not captured privately'
if grep -Fq untrusted-checker-stderr "${TMP_DIR}/runner.stderr"; then
  fail 'untrusted checker stderr escaped into progress output'
fi
rc=0
run_reality_target_discovery "${TMP_DIR}/runner.sh" "${TMP_DIR}/plan.json" plan 64500 || rc=$?
[[ "${rc}" == 3 ]] || fail 'planning status was lost'
[[ "$(head -5 "${TMP_DIR}/arguments")" == $'discover\n--asn\n64500\n--plan-only\n--json' ]] || fail 'ASN mode did not request a plan'
for invalid in --json '192.0.2.0/24;touch marker' ''; do
  if run_reality_target_discovery "${TMP_DIR}/runner.sh" "${TMP_DIR}/rejected.json" scan "${invalid}"; then
    fail 'unsafe discovery scope reached execution'
  fi
done
[[ ! -e "${TMP_DIR}/rejected.json" ]] || fail 'unsafe scope started discovery'

# Speed up only the timer's shell sleep; the mock Bash checker retains a real
# short delay. Progress must remain visible while child diagnostics stay private.
sed '/^exit 3$/i sleep 0.25' "${TMP_DIR}/runner.sh" > "${TMP_DIR}/heartbeat-checker.sh"
sleep() { command sleep 0.01; }
rc=0
run_reality_target_discovery "${TMP_DIR}/heartbeat-checker.sh" "${TMP_DIR}/heartbeat.json" plan 64500 \
  2>"${TMP_DIR}/heartbeat.stderr" || rc=$?
unset -f sleep
[[ "${rc}" == 3 ]] || fail 'planning heartbeat changed process status'
grep -Fq '候选发现仍在执行' "${TMP_DIR}/heartbeat.stderr" || fail 'planning heartbeat was hidden'
if grep -Fq untrusted-checker-stderr "${TMP_DIR}/heartbeat.stderr"; then
  fail 'child stderr leaked through planning heartbeat'
fi

# Send TERM only to the runner and verify that it cleans nested timeout groups.
cat > "${TMP_DIR}/cancel-checker.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${PPID}" > "${RTC_DISCOVERY_FIXTURE}/timeout.pid"
printf '%s\n' "$$" > "${RTC_DISCOVERY_FIXTURE}/checker.pid"
timeout --signal=TERM --kill-after=1 30 bash -c 'printf "%s\n" "$$" > "${RTC_DISCOVERY_FIXTURE}/sleeper.pid"; exec sleep 30'
SH
cat > "${TMP_DIR}/cancel-runner.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
source "$1"
rc=0
run_reality_target_discovery "$2" "$3" scan 192.0.2.1/32 || rc=$?
exit "${rc}"
SH
python3 - "${TMP_DIR}" <<'PY'
from pathlib import Path
import os
import signal
import subprocess
import sys
import time

root = Path(sys.argv[1])
process = subprocess.Popen(['bash', str(root / 'cancel-runner.sh'),
    str(root / 'install.sh'), str(root / 'cancel-checker.sh'), str(root / 'cancel.json')],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
tracked = []
try:
    deadline = time.monotonic() + 5
    while not (root / 'sleeper.pid').exists():
        if process.poll() is not None or time.monotonic() > deadline:
            raise AssertionError('discovery cancellation fixture did not start')
        time.sleep(0.02)
    timeout_pid = int((root / 'timeout.pid').read_text())
    tracked = [timeout_pid, int((root / 'checker.pid').read_text()), int((root / 'sleeper.pid').read_text())]
    status = Path(f'/proc/{timeout_pid}/status').read_text().splitlines()
    runner_pid = int(next(line.split()[1] for line in status if line.startswith('PPid:')))
    started = time.monotonic()
    os.kill(runner_pid, signal.SIGTERM)
    output, errors = process.communicate(timeout=3)
    assert process.returncode == 143, (process.returncode, output, errors)
    assert time.monotonic() - started < 3, 'cancellation waited for heartbeat'
    for pid in tracked:
        assert not Path(f'/proc/{pid}').exists(), f'discovery cancellation left process {pid}'
finally:
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
    for pid in tracked:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
PY

# Terminating only the outer selector must also cancel its active phase. Cover
# preparation, real nested discovery runner, and the final DNS checker separately.
cat > "${TMP_DIR}/cancel-selector.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
source "$1"
export RTC_DISCOVERY_FIXTURE=$2 RTC_CANCEL_PHASE=$3
SB_SNI=unchanged.example.test
prepare_reality_target_discovery() {
  awk '/^PPid:/ {print $2}' "/proc/${BASHPID}/status" > "${RTC_DISCOVERY_FIXTURE}/selector.pid"
  printf '%s\n' "$1" > "${RTC_DISCOVERY_FIXTURE}/selector-workdir"
  if [[ "${RTC_CANCEL_PHASE}" == prepare ]]; then
    printf '%s\n' "${BASHPID}" > "${RTC_DISCOVERY_FIXTURE}/phase.pid"
    sleep 30
  fi
  cat > "$1/reality-target-checker.sh" <<'CHECKER'
#!/usr/bin/env bash
printf '%s\n' "$$" > "${RTC_DISCOVERY_FIXTURE}/phase.pid"
timeout --signal=TERM --kill-after=1 30 sleep 30
CHECKER
}
if [[ "${RTC_CANCEL_PHASE}" != scan ]]; then
  run_reality_target_discovery() {
    printf '{"candidates":[{"sni":"final.example.test","eligible":true}]}\n' > "$2"
  }
  validate_reality_discovery_report() { return 0; }
fi
select_reality_sni_candidate() {
  if [[ "${RTC_CANCEL_PHASE}" == consent ]]; then
    local answer
    read -r answer || return 1
    [[ "${answer}" == y ]] || return 1
    printf '%s' "$1"
    return 0
  fi
  printf '%s\n' "${BASHPID}" > "${RTC_DISCOVERY_FIXTURE}/phase.pid"
  timeout --signal=TERM --kill-after=1 30 sleep 30
}
rc=0
selected=$(select_reality_sni_discovery cidr 192.0.2.1/32) || rc=$?
printf '%s\n' "${selected}" > "${RTC_DISCOVERY_FIXTURE}/selected"
printf '%s\n' "${SB_SNI}" > "${RTC_DISCOVERY_FIXTURE}/saved-sni"
exit "${rc}"
SH
python3 - "${TMP_DIR}" <<'PY'
from pathlib import Path
import os
import signal
import subprocess
import sys
import time

root = Path(sys.argv[1])

def children(pid):
    result = {pid}
    pending = [pid]
    while pending:
        parent = pending.pop()
        try:
            direct = Path(f'/proc/{parent}/task/{parent}/children').read_text().split()
        except FileNotFoundError:
            continue
        for value in map(int, direct):
            if value not in result:
                result.add(value)
                pending.append(value)
    return result

for phase in ('prepare', 'scan', 'dns'):
    fixture = root / ('selector-' + phase)
    fixture.mkdir()
    process = subprocess.Popen(['bash', str(root / 'cancel-selector.sh'),
        str(root / 'install.sh'), str(fixture), phase],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    tracked = set()
    try:
        deadline = time.monotonic() + 5
        while not (fixture / 'phase.pid').exists():
            if process.poll() is not None or time.monotonic() > deadline:
                raise AssertionError(f'{phase}: selector cancellation fixture did not start')
            time.sleep(0.02)
        selector = int((fixture / 'selector.pid').read_text())
        tracked = children(selector)
        started = time.monotonic()
        os.kill(selector, signal.SIGTERM)
        output, errors = process.communicate(timeout=3)
        assert process.returncode == 143, (phase, process.returncode, output, errors)
        assert time.monotonic() - started < 3, f'{phase}: selector cancellation was delayed'
        assert (fixture / 'selected').read_text().strip() == '', f'{phase}: cancellation selected a domain'
        assert (fixture / 'saved-sni').read_text().strip() == 'unchanged.example.test'
        assert not Path((fixture / 'selector-workdir').read_text().strip()).exists(), f'{phase}: private workdir leaked'
        for pid in tracked:
            assert not Path(f'/proc/{pid}').exists(), f'{phase}: cancellation left process {pid}'
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
        for pid in tracked:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        process.communicate()

fixture = root / 'selector-consent'
fixture.mkdir()
completed = subprocess.run(['bash', str(root / 'cancel-selector.sh'),
    str(root / 'install.sh'), str(fixture), 'consent'], input='y\n', text=True,
    capture_output=True, timeout=3)
assert completed.returncode == 0, (completed.returncode, completed.stderr)
assert (fixture / 'selected').read_text().strip() == 'final.example.test', 'owned DNS phase lost interactive stdin'
PY

# A new-instance fallback with no existing SNI must preserve interruption codes.
prompt_reality_sni_install() { return 130; }
SB_SNI=unchanged.example.test
rc=0
prompt_reality_sni_for_new_instance '' || rc=$?
[[ "${rc}" == 130 && "${SB_SNI}" == unchanged.example.test ]] || fail 'empty-default new instance lost cancellation status'
printf 'REALITY discovery verified-download, bounded-runner and cancellation tests passed.\n'
