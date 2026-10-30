#!/usr/bin/env bash

set -euo pipefail

# Run this same selector regression with Bash 4.3 and the current system Bash;
# first-candidate selection must remain valid with nounset and an empty array.
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf -- "${TMP_DIR}"' EXIT
mkdir -p "${TMP_DIR}/project"
sed -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  "${REPO_ROOT}/install.sh" > "${TMP_DIR}/install.sh"
# shellcheck disable=SC1090
source "${TMP_DIR}/install.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# All external calls below are fixtures. No DNS, remote API or target ports are
# contacted by these selection, scope and interaction regressions.
jq -n '{schema_version:"1.0",tool_version:"0.3.0",report_type:"discovery_plan",
  requires_selection:true,targets:[],seeds:[],
  asn:{asn:64500,status:"PASS",prefixes_v4:["192.0.2.0/24"],prefixes_v6:[],
    snapshot_time:"2026-10-30T00:00:00Z",retrieved_at:"2026-10-30T01:00:00Z"},
  scope:{cidr:null,prefixes:[],selection:"cidr_hosts",host_count:0,
    within_budget:true,requires_known_ipv6:false},
  summary:{status:"PASS",exit_code:0}}' > "${TMP_DIR}/plan.json"

for cidr in 192.0.2.0/24 192.0.2.128/25 192.0.2.0/31 192.0.2.10/32; do
  validate_reality_discovery_cidr "${cidr}" || fail "valid explicit scope rejected: ${cidr}"
  validate_reality_discovery_cidr "${cidr}" "${TMP_DIR}/plan.json" || fail "announced subnet rejected: ${cidr}"
done
for cidr in '' 192.0.2.0 192.0.2.1/24 192.0.2.0/024 192.0.02.0/24 \
  192.0.2.0/255.255.255.0 192.0.0.0/23 0.0.0.0/0 2001:db8::/128 \
  --help '192.0.2.0/24;false' '192.0.2.0/24 extra'; do
  if validate_reality_discovery_cidr "${cidr}"; then fail "invalid scan scope accepted: ${cidr}"; fi
done
if validate_reality_discovery_cidr 198.51.100.0/24 "${TMP_DIR}/plan.json"; then
  fail 'subnet outside ASN announcement accepted'
fi

validate_reality_discovery_plan "${TMP_DIR}/plan.json" 64500 0 || fail 'valid ASN plan rejected'
for mutation in \
  '.schema_version="2.0"' '.tool_version="0.1.0"' '.report_type="discovery"' \
  '.summary.status="UNKNOWN"' '.summary.exit_code=2' '.requires_selection=false' \
  '.asn.asn=64501' '.asn.status="UNKNOWN"' '.asn.prefixes_v4=[]' \
  '.asn.prefixes_v4=["192.0.2.1/24"]' '.asn.prefixes_v4=["192.0.2.0/24\u001b[2J"]' \
  '.scope.prefixes=["192.0.2.0/24"]' '.scope.host_count=2' \
  '.targets=["192.0.2.1"]' '.seeds=[{ip:"192.0.2.1",sni:"one.example.test"}]'; do
  jq "${mutation}" "${TMP_DIR}/plan.json" > "${TMP_DIR}/mutated.json"
  if validate_reality_discovery_plan "${TMP_DIR}/mutated.json" 64500 0; then
    fail "unsafe ASN plan accepted: ${mutation}"
  fi
done
for status in 1 2 3 124 130 143; do
  if validate_reality_discovery_plan "${TMP_DIR}/plan.json" 64500 "${status}"; then
    fail "failed ASN plan status accepted: ${status}"
  fi
done

# A complete finite scan has two explicit IPs. Its fixed-IP success is only a
# source of names; the installer must check the normal DNS target again.
jq -n '{schema_version:"1.0",tool_version:"0.3.0",report_type:"discovery",
  scope:{cidr:"192.0.2.0/31",prefixes:["192.0.2.0/31"],selection:"cidr_hosts",
    host_count:2,within_budget:true,requires_known_ipv6:false,origin_ip:null,
    excluded_input_ips:[],limits:{max_hosts:256,concurrency:8,rate:10,timeout:3,
      deadline:300,max_candidates:256,samples:1}},
  plan:{asn:null},
  scan:{complete:true,coverage:"best_effort",hosts_completed:2,
    candidates_discovered:1,candidates_checked:1,elapsed_ms:50,reasons:[]},
  hosts:[{ip:"192.0.2.0",completed:true},{ip:"192.0.2.1",completed:true}],
  candidates:[{ip:"192.0.2.0",sni:"first.example.test",eligible:true,dns_binding:"MATCH"}],
  summary:{status:"WARN",exit_code:3,eligible_count:1}}' > "${TMP_DIR}/discovery.json"
validate_reality_discovery_report "${TMP_DIR}/discovery.json" 192.0.2.0/31 3 || fail 'valid complete scan rejected'
jq '.summary.status="PASS" | .summary.exit_code=0' "${TMP_DIR}/discovery.json" > "${TMP_DIR}/pass.json"
validate_reality_discovery_report "${TMP_DIR}/pass.json" 192.0.2.0/31 0 || fail 'valid PASS scan rejected'
for mutation in \
  '.schema_version="2.0"' '.tool_version="0.1.0"' '.report_type="discovery_plan"' \
  '.summary.status="PASS"' '.summary.exit_code=0' '.scan.complete=false' \
  '.scan.complete="true"' '.scan.hosts_completed=1' '.scan.reasons=["DEADLINE"]' \
  '.scope.cidr="198.51.100.0/31"' '.scope.prefixes=["198.51.100.0/31"]' \
  '.scope.host_count=257' '.scope.host_count=1' '.scope.within_budget=false' \
  '.hosts[0].completed=false' '.hosts=[]' '.candidates={}' \
  '.candidates[0].ip="198.51.100.1"' '.candidates[0].eligible="true"'; do
  jq "${mutation}" "${TMP_DIR}/discovery.json" > "${TMP_DIR}/mutated.json"
  if validate_reality_discovery_report "${TMP_DIR}/mutated.json" 192.0.2.0/31 3; then
    fail "unsafe discovery report accepted: ${mutation}"
  fi
done
for status in 1 2 124 130 137 143; do
  if validate_reality_discovery_report "${TMP_DIR}/discovery.json" 192.0.2.0/31 "${status}"; then
    fail "incomplete discovery status accepted: ${status}"
  fi
done
jq '.plan.asn={asn:64500,status:"PASS"}' "${TMP_DIR}/discovery.json" > "${TMP_DIR}/asn-discovery.json"
validate_reality_discovery_report "${TMP_DIR}/asn-discovery.json" 192.0.2.0/31 3 64500 || fail 'matching ASN scan rejected'
if validate_reality_discovery_report "${TMP_DIR}/asn-discovery.json" 192.0.2.0/31 3 64501; then
  fail 'scan result from another ASN accepted'
fi
for payload in '' 'not JSON' '{}' '[]' 'null'; do
  printf '%s' "${payload}" > "${TMP_DIR}/invalid.json"
  if validate_reality_discovery_report "${TMP_DIR}/invalid.json" 192.0.2.0/31 3; then
    fail "invalid discovery JSON accepted: ${payload}"
  fi
done
cat "${TMP_DIR}/discovery.json" "${TMP_DIR}/discovery.json" > "${TMP_DIR}/multiple.json"
if validate_reality_discovery_report "${TMP_DIR}/multiple.json" 192.0.2.0/31 3; then
  fail 'multiple discovery reports accepted'
fi

PLAN_PAYLOAD="${TMP_DIR}/plan.json"
PLAN_STATUS=0
DISCOVERY_PAYLOAD="${TMP_DIR}/discovery.json"
DISCOVERY_STATUS=3
DNS_STATUS=0
prepare_reality_target_discovery() {
  printf '%s\n' "$1" >> "${TMP_DIR}/prepared"
  mkdir -p -- "$1"
  printf '#!/usr/bin/env bash\n' > "$1/reality-target-checker.sh"
}
run_reality_target_discovery() {
  local checker=$1 report=$2 mode=$3 scope=$4 asn=${5:-}
  [[ -f "${checker}" ]] || fail 'discovery started without prepared checker'
  printf '%s|%s|%s\n' "${mode}" "${scope}" "${asn}" >> "${TMP_DIR}/calls"
  case "${mode}" in
    plan) cp -- "${PLAN_PAYLOAD}" "${report}"; return "${PLAN_STATUS}" ;;
    scan) cp -- "${DISCOVERY_PAYLOAD}" "${report}"; return "${DISCOVERY_STATUS}" ;;
    *) fail 'unexpected discovery command' ;;
  esac
}
select_reality_sni_candidate() {
  printf '%s\n' "$@" > "${TMP_DIR}/dns-candidates"
  [[ "${DNS_STATUS}" == 0 ]] || return "${DNS_STATUS}"
  printf '%s' "$1"
}

for scope in '' 192.0.0.0/23 192.0.2.1/24 --help; do
  if selected=$(select_reality_sni_discovery cidr "${scope}" </dev/null); then
    fail 'invalid explicit scope selected SNI'
  fi
done
[[ ! -e "${TMP_DIR}/prepared" && ! -e "${TMP_DIR}/calls" ]] || fail 'invalid CIDR started download or scan'

selected=$(select_reality_sni_discovery cidr 192.0.2.0/31 </dev/null)
[[ "${selected}" == first.example.test ]] || fail 'valid discovered name not selected after DNS check'
[[ "$(cat "${TMP_DIR}/dns-candidates")" == first.example.test ]] || fail 'discovered name bypassed DNS selection'
[[ "$(cat "${TMP_DIR}/calls")" == 'scan|192.0.2.0/31|' ]] || fail 'scan did not retain explicit CIDR scope'

# Deduplicate names, skip ineligible or syntactically unsafe seeds, and bound
# subsequent DNS checks to five names in the discovery order.
UNSAFE_SEED="\$(touch ${TMP_DIR}/unexpected-execution)"
jq --arg unsafe "${UNSAFE_SEED}" '.candidates=[
  {ip:"192.0.2.0",sni:"first.example.test",eligible:true},
  {ip:"192.0.2.1",sni:"FIRST.EXAMPLE.TEST",eligible:true},
  {ip:"192.0.2.0",sni:"ignored.example.test",eligible:false},
  {ip:"192.0.2.0",sni:$unsafe,eligible:true},
  {ip:"192.0.2.0",sni:"second.example.test",eligible:true},
  {ip:"192.0.2.0",sni:"third.example.test",eligible:true},
  {ip:"192.0.2.0",sni:"fourth.example.test",eligible:true},
  {ip:"192.0.2.0",sni:"fifth.example.test",eligible:true},
  {ip:"192.0.2.0",sni:"sixth.example.test",eligible:true}]
  | .scan.candidates_discovered=9 | .scan.candidates_checked=9 | .summary.eligible_count=8' \
  "${TMP_DIR}/discovery.json" > "${TMP_DIR}/many.json"
DISCOVERY_PAYLOAD="${TMP_DIR}/many.json"
selected=$(select_reality_sni_discovery cidr 192.0.2.0/31 </dev/null)
[[ "${selected}" == first.example.test ]] || fail 'candidate deduplication changed first choice'
[[ "$(cat "${TMP_DIR}/dns-candidates")" == $'first.example.test\nsecond.example.test\nthird.example.test\nfourth.example.test\nfifth.example.test' ]] || fail 'unsafe, duplicate or excessive names reached DNS checker'
[[ ! -e "${TMP_DIR}/unexpected-execution" ]] || fail 'discovery seed was executed'

DISCOVERY_PAYLOAD="${TMP_DIR}/asn-discovery.json"
: > "${TMP_DIR}/calls"
selected=$(select_reality_sni_discovery asn 64500 192.0.2.0/31 </dev/null)
[[ "${selected}" == first.example.test ]] || fail 'ASN plan/explicit subnet discovery failed'
[[ "$(cat "${TMP_DIR}/calls")" == $'plan|64500|\nscan|192.0.2.0/31|64500' ]] || fail 'ASN scan omitted planning or selected subnet constraint'

: > "${TMP_DIR}/calls"
if selected=$(select_reality_sni_discovery asn 64500 198.51.100.0/24 </dev/null); then
  fail 'unannounced ASN subnet selected SNI'
fi
[[ "$(cat "${TMP_DIR}/calls")" == 'plan|64500|' ]] || fail 'unannounced ASN subnet was scanned'

: > "${TMP_DIR}/calls"
prepared_before=$(wc -l < "${TMP_DIR}/prepared")
for asn in '' 0 01 AS AS0 4294967296 --help '64500 --include-cidr 192.0.2.0/31'; do
  if selected=$(select_reality_sni_discovery asn "${asn}" 192.0.2.0/31 </dev/null); then
    fail "invalid ASN selected SNI: ${asn}"
  fi
done
[[ ! -s "${TMP_DIR}/calls" && "$(wc -l < "${TMP_DIR}/prepared")" == "${prepared_before}" ]] || fail 'invalid ASN started download or query'
PLAN_STATUS=2
if selected=$(select_reality_sni_discovery asn 64500 192.0.2.0/31 </dev/null); then
  fail 'failed ASN query selected SNI'
fi
[[ "$(cat "${TMP_DIR}/calls")" == 'plan|64500|' ]] || fail 'failed ASN query continued to scan'
PLAN_STATUS=0

DISCOVERY_PAYLOAD="${TMP_DIR}/discovery.json"
for status in 2 124 130 143; do
  DISCOVERY_STATUS=${status}
  rm -f -- "${TMP_DIR}/dns-candidates"
  result=0
  selected=$(select_reality_sni_discovery cidr 192.0.2.0/31 </dev/null) || result=$?
  [[ "${result}" != 0 && -z "${selected}" ]] || fail "failed discovery selected domain: ${status}"
  [[ ! -e "${TMP_DIR}/dns-candidates" ]] || fail 'failed discovery proceeded to DNS selection'
  case "${status}" in 130|143) [[ "${result}" == "${status}" ]] || fail 'discovery cancellation status lost' ;; esac
done
DISCOVERY_STATUS=3
jq '.scan.complete=false' "${TMP_DIR}/discovery.json" > "${TMP_DIR}/incomplete.json"
DISCOVERY_PAYLOAD="${TMP_DIR}/incomplete.json"
rm -f -- "${TMP_DIR}/dns-candidates"
if selected=$(select_reality_sni_discovery cidr 192.0.2.0/31 </dev/null); then
  fail 'incomplete report with WARN process exit selected domain'
fi
[[ ! -e "${TMP_DIR}/dns-candidates" && -z "${selected}" ]] || fail 'incomplete report proceeded to DNS selection'
DISCOVERY_PAYLOAD="${TMP_DIR}/discovery.json"
DNS_STATUS=1
if selected=$(select_reality_sni_discovery cidr 192.0.2.0/31 </dev/null); then
  fail 'fixed-IP discovery success bypassed failed full DNS check'
fi
[[ -z "${selected}" ]] || fail 'failed final DNS check leaked selected SNI'

while IFS= read -r prepared; do
  [[ ! -e "${prepared}" ]] || fail 'discovery selection leaked its private temporary directory'
done < "${TMP_DIR}/prepared"

DNS_STATUS=0
SB_SNI=unchanged.example.test
prompt_reality_target_discovery <<'INPUT' > "${TMP_DIR}/prompt-output"

192.0.2.0/31
INPUT
[[ "${SB_SNI}" == first.example.test ]] || fail 'CIDR prompt failed to commit checked SNI'
DISCOVERY_PAYLOAD="${TMP_DIR}/asn-discovery.json"
SB_SNI=unchanged.example.test
prompt_reality_target_discovery <<'INPUT' > "${TMP_DIR}/prompt-output"
2
AS64500
192.0.2.0/31
INPUT
[[ "${SB_SNI}" == first.example.test ]] || fail 'ASN prompt failed to preserve explicit scope or commit checked SNI'
DNS_STATUS=1
SB_SNI=unchanged.example.test
if prompt_reality_target_discovery <<'INPUT' > "${TMP_DIR}/prompt-output"
1
192.0.2.0/31
INPUT
then
  fail 'discovery prompt committed SNI after final DNS failure'
fi
[[ "${SB_SNI}" == unchanged.example.test ]] || fail 'failed final DNS check mutated existing SNI'
DNS_STATUS=0
SB_SNI=unchanged.example.test
if prompt_reality_target_discovery </dev/null > "${TMP_DIR}/prompt-output"; then
  fail 'discovery prompt accepted EOF'
fi
[[ "${SB_SNI}" == unchanged.example.test ]] || fail 'EOF changed existing SNI'

# Each installer lifecycle menu reaches the same discovery prompt and commits
# its result only on successful completion. Existing default paths are covered
# by reality_sni_auto_selection.sh.
prompt_reality_target_discovery() { SB_SNI=menu.example.test; }
SB_SNI=unchanged.example.test
prompt_reality_sni_install <<'INPUT' > "${TMP_DIR}/menu-output"
3
INPUT
[[ "${SB_SNI}" == menu.example.test ]] || fail 'installation menu did not expose discovery'
SB_SNI=unchanged.example.test
prompt_reality_sni_update <<'INPUT' > "${TMP_DIR}/menu-output"
4
INPUT
[[ "${SB_SNI}" == menu.example.test ]] || fail 'update menu did not expose discovery'
SB_SNI=unchanged.example.test
prompt_reality_sni_for_new_instance existing.example.test <<'INPUT' > "${TMP_DIR}/menu-output"
4
INPUT
[[ "${SB_SNI}" == menu.example.test ]] || fail 'new-instance menu did not expose discovery'
prompt_reality_target_discovery() { return 130; }
for menu in install update new_instance; do
  SB_SNI=unchanged.example.test
  result=0
  case "${menu}" in
    install) prompt_reality_sni_install <<< 3 > "${TMP_DIR}/menu-output" || result=$? ;;
    update) prompt_reality_sni_update <<< 4 > "${TMP_DIR}/menu-output" || result=$? ;;
    new_instance) prompt_reality_sni_for_new_instance existing.example.test <<< 4 > "${TMP_DIR}/menu-output" || result=$? ;;
  esac
  [[ "${result}" == 130 ]] || fail "${menu} lost discovery cancellation status"
  [[ "${SB_SNI}" == unchanged.example.test ]] || fail "${menu} changed SNI after cancellation"
done

printf 'REALITY discovery scope, reports, DNS recheck and menu tests passed.\n'
