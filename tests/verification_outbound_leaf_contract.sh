#!/usr/bin/env bash

# Host-safe CAS/dispatch contract only. Real outbound data-plane acceptance runs
# in the corresponding disposable Docker leaves, never this mock fixture.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf -- "${TMP_DIR}"' EXIT

python3 - "${REPO_ROOT}" "${TMP_DIR}" <<'PY'
from pathlib import Path
import json
import os
import re
import subprocess
import sys

root, temp = map(Path, sys.argv[1:])
source = root / 'dev/verification/remote/scenarios/outbound_cases.sh'
text = source.read_text()
names = ['ssh', 'socks', 'selector', 'urltest', 'shadowsocks', 'direct',
         'block', 'vless', 'shadowtls', 'shadowsocks_udp', 'socks_udp']
subprocess.run(['bash', '-n', str(source)], check=True)
functions = {}
for index, name in enumerate(names):
    start = text.index('verification_case_' + name + '_outbound() {')
    end = text.find('\nverification_case_', start + 1)
    if end < 0:
        end = len(text)
    body = text[start:end]
    functions[name] = body
    mutations = 4 if name == 'shadowtls' else 2
    offsets = list(map(int, re.findall(r'--expected-revision "\$\(\(base_revision \+ (\d+)\)\)"', body)))
    assert offsets == list(range(mutations)), (name, offsets)
    assert not re.search(r'\.revision\s*==\s*\d+', body), name
    assert not re.search(r'--expected-revision \d+', body), name
    assert 'verification_wait_for_service_active sing-box' in body, name
    assert 'sing-box check -c /root/.sing-box-vps/runtime/config.json' in body, name
    assert body.index("'RESULT=success'") > body.rindex('agent component delete'), name
    assert not re.search(r'kill .*\|\| true|wait .*\|\| true', body), name
    wrapper = root / ('dev/verification/remote/scenarios/component_' + name + '_outbound.sh')
    subprocess.run(['bash', '-n', str(wrapper)], check=True)
    entry = wrapper.read_text()
    assert 'verification_case_context_start' in entry, name
    assert 'verification_case_' + name + '_outbound 0' in entry, name
    assert 'verification_case_assert_clean ' + str(mutations) in entry, name
    assert 'verification_scenario_multi_protocol_coexistence' not in entry, name

# Unlike an NXDOMAIN-only request, the Block leaf proves a working path before
# and after its expected rejection. The Docker acceptance executes these calls.
assert 'block-control-before.txt' in functions['block']
assert 'block-control-after.txt' in functions['block']
assert "local block_outbound_target_domain='localhost'" in functions['block']

# Execute one shared body against an isolated typed-component model. Testing
# bases 0, 13 and 103 proves the new leaf and retained aggregate use exact CAS
# increments rather than silently reading/retrying whatever revision is current.
def fixture_paths(body):
    return body.replace('/root/.sing-box-vps/runtime/config.json',
                        '"${SCOPED_FIXTURE_ROOT}/config.json"').replace(
                        '/root/.sing-box-vps/runtime/components.json',
                        '"${SCOPED_FIXTURE_ROOT}/components.json"')

selector = fixture_paths(functions['selector'])
mock = temp / 'component-cli.sh'
mock.write_text('''#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == agent && "$2" == component ]]
action=$3; shift 3
expected=''; record=''; component_id=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json|--yes) shift ;;
    --expected-revision) expected=$2; shift 2 ;;
    --file) record=$2; shift 2 ;;
    --id) component_id=$2; shift 2 ;;
    *) exit 64 ;;
  esac
done
state="${SCOPED_FIXTURE_ROOT}/components.json"
config="${SCOPED_FIXTURE_ROOT}/config.json"
actual=$(jq -r .revision "$state")
printf '%s:%s\\n' "$action" "$expected" >> "${SCOPED_FIXTURE_ROOT}/calls.txt"
if [[ "$expected" != "$actual" ]]; then
  printf '{"ok":false,"error":"revision_conflict"}\\n'; exit 65
fi
next=$((actual + 1))
expected_type=${SCOPED_FIXTURE_COMPONENT_TYPE:-selector}
expected_id=${SCOPED_FIXTURE_COMPONENT_ID:-selector-outbound-verification}
case "$action" in
  create)
    jq -e --arg type "$expected_type" --arg id "$expected_id" \\
      '.type==$type and .id==$id' "$record" >/dev/null
    jq --slurpfile record "$record" --argjson revision "$next" \\
      '.revision=$revision | .components += $record' "$state" > "$state.stage"
    jq -n --slurpfile record "$record" \\
      '{inbounds:[],outbounds:[{type:"direct",tag:"direct"},($record[0].config+{type:$record[0].type,tag:$record[0].tag})],route:{rules:$record[0].route_rules}}' > "$config"
    printf '{"ok":true,"operation":"create","type":"%s","revision":%s}\\n' "$expected_type" "$next"
    ;;
  delete)
    [[ "$component_id" == "$expected_id" ]]
    jq --arg id "$component_id" --argjson revision "$next" \\
      '.revision=$revision | .components |= map(select(.id!=$id))' "$state" > "$state.stage"
    printf '{"inbounds":[],"outbounds":[{"type":"direct","tag":"direct"}],"route":{"rules":[]}}\\n' > "$config"
    printf '{"ok":true,"operation":"delete","id":"%s","revision":%s}\\n' "$component_id" "$next"
    ;;
  *) exit 64 ;;
esac
mv "$state.stage" "$state"
''')
mock.chmod(0o700)
stubs = '''set -euo pipefail
VERIFY_REMOTE_LOCAL_TREE_DIR="${SCOPED_FIXTURE_ROOT}/tree"
VERIFY_REMOTE_INSTALL_SCRIPT="${SCOPED_FIXTURE_MOCK}"
VERIFY_CURRENT_SCENARIO_DIR=case
mkdir -p "${VERIFY_REMOTE_LOCAL_TREE_DIR}" "${SCOPED_FIXTURE_ROOT}/artifacts/case"
direct_marker=selector-marker
direct_marker_port=12345
direct_marker_requests="${SCOPED_FIXTURE_ROOT}/marker.requests"
verification_artifact_path() { printf '%s/%s\\n' "${SCOPED_FIXTURE_ROOT}/artifacts" "$1"; }
verification_capture_file_if_present() { cp "$1" "$(verification_artifact_path "$2")"; }
verification_wait_for_service_active() { :; }
verification_capture_command() { local path=$1; shift; "$@" > "$(verification_artifact_path "$path")"; }
verification_mark_step() { :; }
verification_write_artifact() { local path=$1; shift; printf '%s\\n' "$@" > "$(verification_artifact_path "$path")"; }
sing-box() { [[ "$1" == check ]]; }
curl() {
  if [[ "${SCOPED_FIXTURE_COMPONENT_TYPE:-selector}" == urltest ]]; then
    printf 'GET /urltest-business\\n' >> "${direct_marker_requests}"
    if [[ "${SCOPED_FIXTURE_HEALTH_REQUEST:-missing}" != missing ]]; then
      printf '%s /urltest-health\\n' "${SCOPED_FIXTURE_HEALTH_REQUEST}" >> "${direct_marker_requests}"
    fi
  fi
  printf '%s\\n' "${direct_marker}"
}
sleep() { :; }
'''
script = temp / 'selector-case.sh'
script.write_text(stubs + selector + '\nverification_case_selector_outbound "$1"\n')

def execute(base, suffix, script_path=script, extra_env=None):
    target = temp / suffix
    target.mkdir()
    (target / 'components.json').write_text(json.dumps({'revision': base,
        'components': [{'id': 'retained-aggregate-fixture'}]}))
    (target / 'config.json').write_text(json.dumps({'inbounds': [],
        'outbounds': [{'type': 'direct', 'tag': 'direct'}], 'route': {'rules': []}}))
    env = dict(os.environ, SCOPED_FIXTURE_ROOT=str(target), SCOPED_FIXTURE_MOCK=str(mock))
    env.update(extra_env or {})
    result = subprocess.run(['bash', str(script_path), str(base)], env=env,
                            text=True, capture_output=True)
    return target, result

for base in (0, 13, 103):
    target, result = execute(base, 'base-' + str(base))
    assert result.returncode == 0, (base, result.stdout, result.stderr)
    state = json.loads((target / 'components.json').read_text())
    assert state == {'revision': base + 2, 'components': [{'id': 'retained-aggregate-fixture'}]}, state
    assert (target / 'calls.txt').read_text().splitlines() == [f'create:{base}', f'delete:{base+1}']
    assert 'RESULT=success' in (target / 'artifacts/case/selector-outbound.result.env').read_text()

# A mutation must fail before deletion or success evidence; an assertion that
# merely executes the source without checking CAS would incorrectly accept it.
mutant = temp / 'selector-mutant.sh'
mutant.write_text(script.read_text().replace('--expected-revision "$((base_revision + 0))"',
                                            '--expected-revision "$((base_revision + 99))"', 1))
target, result = execute(0, 'mutated', mutant)
assert result.returncode != 0, (result.stdout, result.stderr)
assert not (target / 'artifacts/case/selector-outbound.result.env').exists()
assert json.loads((target / 'components.json').read_text())['revision'] == 0

# Run the actual URLTest body with the typed CLI model. A business marker is
# insufficient: both GET and HEAD active-probe evidence are accepted, while a
# missing health request must fail before delete or a successful result file.
urltest = temp / 'urltest-case.sh'
urltest.write_text(stubs + fixture_paths(functions['urltest']) +
                   '\nverification_case_urltest_outbound "$1"\n')
for method in ('GET', 'HEAD', 'missing'):
    target, result = execute(15, 'health-' + method, urltest, {
        'SCOPED_FIXTURE_COMPONENT_TYPE': 'urltest',
        'SCOPED_FIXTURE_COMPONENT_ID': 'urltest-outbound-verification',
        'SCOPED_FIXTURE_HEALTH_REQUEST': method})
    evidence = target / 'artifacts/case/urltest-outbound.result.env'
    if method == 'missing':
        assert result.returncode != 0, (result.stdout, result.stderr)
        assert not evidence.exists()
        assert (target / 'calls.txt').read_text().splitlines() == ['create:15']
        assert json.loads((target / 'components.json').read_text())['revision'] == 16
    else:
        assert result.returncode == 0, (method, result.stdout, result.stderr)
        assert 'HEALTH_PROBE=observed' in evidence.read_text()
        assert (target / 'calls.txt').read_text().splitlines() == ['create:15', 'delete:16']
        observed = (target / 'artifacts/case/urltest-marker.requests.txt').read_text()
        assert observed.splitlines() == ['GET /urltest-business', method + ' /urltest-health']
print('Outbound leaf contracts, exact CAS, mutation rejection and URLTest health gating passed')
PY
