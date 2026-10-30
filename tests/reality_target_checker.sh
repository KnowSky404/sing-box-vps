#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf -- "${TMP_DIR}"' EXIT
mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/download"

# Use an independent fixture digest so successful staging can be tested without
# downloading or executing the external checker in the host regression suite.
cat > "${TMP_DIR}/payload.sh" <<'SCRIPT'
#!/usr/bin/env bash
VERSION=0.3.0
printf 'unexpected execution\n' > "${RTC_EXECUTION_MARKER}"
SCRIPT
FIXTURE_SHA256=$(sha256sum "${TMP_DIR}/payload.sh")
FIXTURE_SHA256=${FIXTURE_SHA256%% *}
sed -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  -e "s|^readonly SB_REALITY_CHECKER_SHA256=.*|readonly SB_REALITY_CHECKER_SHA256=\"${FIXTURE_SHA256}\"|" \
  "${REPO_ROOT}/install.sh" > "${TMP_DIR}/install.sh"
# shellcheck disable=SC1090
source "${TMP_DIR}/install.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

jq -n '
  {schema_version:"1.0",tool_version:"0.3.0",target:"good.example.com",sni:"good.example.com",port:443,
   selection:{scope:"dns",complete:true,limit:16},
   endpoints:[{ip:"192.0.2.1",family:4,checks:
     (["tcp443","tls13","cert_chain","cert_san","cert_validity","alpn_h2","x25519"] |
      map({id:.,status:"PASS",reason:"fixture"}))}],
   risks:[],unknowns:[],summary:{basic_tls:"PASS",compatibility:"PASS",ancillary:"PASS",status:"PASS",exit_code:0}}
' > "${TMP_DIR}/valid.json"
validate_reality_target_report "${TMP_DIR}/valid.json" good.example.com 0 || fail 'valid PASS report rejected'

jq '.summary.status="WARN" | .summary.exit_code=3 | .summary.ancillary="WARN" |
    .unknowns=[{id:"cdn",scope:"192.0.2.1",reason:"not established"}]' \
  "${TMP_DIR}/valid.json" > "${TMP_DIR}/warn.json"
validate_reality_target_report "${TMP_DIR}/warn.json" good.example.com 3 || fail 'valid reviewable WARN report rejected'

for mutation in \
  '.schema_version="2.0"' \
  '.tool_version="99.0.0"' \
  '.target="different.example.com"' \
  '.sni="different.example.com"' \
  '.port=8443' \
  '.summary.exit_code=3' \
  '.summary.status="WARN"' \
  '.summary.basic_tls="FAIL"' \
  '.summary.compatibility="UNKNOWN"' \
  '.selection.complete=false' \
  '.selection.complete="true"' \
  '.endpoints=[]' \
  '.endpoints={}' \
  '.endpoints[0].checks=[]' \
  '.endpoints[0].checks[0].status="UNKNOWN"' \
  '.endpoints[0].checks |= map(select(.id!="cert_san"))' \
  '.endpoints += [{ip:"192.0.2.2",family:4,checks:[{id:"tls13",status:"FAIL"}]}]' \
  '.risks={}' \
  '.unknowns=null'; do
  jq "${mutation}" "${TMP_DIR}/valid.json" > "${TMP_DIR}/mutated.json"
  if validate_reality_target_report "${TMP_DIR}/mutated.json" good.example.com 0; then
    fail "unsafe report mutation accepted: ${mutation}"
  fi
done
for rc in 1 2 124 130 137 143; do
  if validate_reality_target_report "${TMP_DIR}/valid.json" good.example.com "${rc}"; then
    fail "unexpected process status accepted: ${rc}"
  fi
done
cat "${TMP_DIR}/valid.json" "${TMP_DIR}/valid.json" > "${TMP_DIR}/multiple.json"
if validate_reality_target_report "${TMP_DIR}/multiple.json" good.example.com 0; then
  fail 'multiple JSON reports must not be accepted as a single probe result'
fi
for payload in '' 'not JSON' '{}' '[]' 'null'; do
  printf '%s' "${payload}" > "${TMP_DIR}/invalid.json"
  if validate_reality_target_report "${TMP_DIR}/invalid.json" good.example.com 0; then
    fail "invalid JSON report accepted: ${payload}"
  fi
done

# Curl simulates a complete/partial network download. Staging must never expose
# the destination before the pinned hash and shell syntax have been checked.
export RTC_EXECUTION_MARKER="${TMP_DIR}/executed"
DOWNLOAD_PAYLOAD="${TMP_DIR}/payload.sh"
DOWNLOAD_STATUS=0
# Preparation checks availability; DNS is never exercised by a download mock.
dig() { :; }
curl() {
  local output='' arg
  while (($#)); do
    arg=$1
    shift
    case "${arg}" in
      --output|-o) output=$1; shift ;;
    esac
  done
  [[ -n "${output}" ]] || return 90
  [[ "${output}" != "${TMP_DIR}/download/checker.sh" ]] || return 91
  cp -- "${DOWNLOAD_PAYLOAD}" "${output}" || return 92
  return "${DOWNLOAD_STATUS}"
}
prepare_reality_target_checker "${TMP_DIR}/download/checker.sh" || fail 'valid pinned download was not prepared'
cmp "${TMP_DIR}/payload.sh" "${TMP_DIR}/download/checker.sh" || fail 'published checker differs from validated download'
[[ ! -e "${RTC_EXECUTION_MARKER}" ]] || fail 'preparation executed downloaded code'
[[ ! -e "${TMP_DIR}/download/checker.sh.part" ]] || fail 'successful preparation leaked staging file'

printf '\n# tampered\n' >> "${TMP_DIR}/payload.sh"
if prepare_reality_target_checker "${TMP_DIR}/download/tampered.sh"; then
  fail 'hash mismatch accepted'
fi
[[ ! -e "${TMP_DIR}/download/tampered.sh" ]] || fail 'hash mismatch published an executable'
[[ ! -e "${RTC_EXECUTION_MARKER}" ]] || fail 'hash mismatch executed downloaded code'
DOWNLOAD_STATUS=22
if prepare_reality_target_checker "${TMP_DIR}/download/partial.sh"; then
  fail 'partial download accepted'
fi
[[ ! -e "${TMP_DIR}/download/partial.sh" ]] || fail 'partial download published an executable'

# Execution is separate from preparation: preserve the checker exit status and
# stdout report, including WARN=3, rather than allowing JSON parsing to mask it.
cat > "${TMP_DIR}/runner.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${RTC_ARGS_FILE}"
cat "${RTC_REPORT_FILE}"
exit 3
SCRIPT
export RTC_ARGS_FILE="${TMP_DIR}/args"
export RTC_REPORT_FILE="${TMP_DIR}/warn.json"
rc=0
run_reality_target_check "${TMP_DIR}/runner.sh" good.example.com "${TMP_DIR}/run.json" || rc=$?
[[ "${rc}" -eq 3 ]] || fail "checker WARN exit status was lost: ${rc}"
cmp "${TMP_DIR}/warn.json" "${TMP_DIR}/run.json" || fail 'checker report was altered'
[[ "$(cat "${RTC_ARGS_FILE}")" == $'check\ngood.example.com\n--json\n--timeout\n3' ]] || fail 'wrong checker invocation'
printf 'REALITY checker report, download and execution tests passed.\n'
