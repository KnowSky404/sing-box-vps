#!/usr/bin/env bash

set -euo pipefail

# Exercise the same prompts on Bash 4.3 and the current system Bash. Public
# institutions are data fixtures here; the checker boundary is mocked.
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf -- "${TMP_DIR}"' EXIT
mkdir -p "${TMP_DIR}/project"
sed -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  <(bash "${REPO_ROOT}/tests/install_fixture_source_helper.sh" --source) > "${TMP_DIR}/install.sh"
bash "${REPO_ROOT}/tests/install_fixture_source_helper.sh" --isolate "${TMP_DIR}/install.sh"
# shellcheck disable=SC1090
source "${TMP_DIR}/install.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

expected_domains() {
  case "$1" in
    HK) printf '%s\n' www.hsbc.com.hk www.hkbea.com www.gov.hk www.hku.hk www.cityu.edu.hk ;;
    US-LAX) printf '%s\n' www.cnb.com www.preferredbank.com lacity.gov www.ucla.edu www.usc.edu ;;
    DE-FRA) printf '%s\n' www.db.com www.frankfurter-volksbank.de frankfurt.de www.uni-frankfurt.de www.frankfurt-school.de ;;
    JP-TYO) printf '%s\n' www.smbctb.co.jp www.sbishinseibank.co.jp www.metro.tokyo.lg.jp www.keio.ac.jp www.waseda.jp ;;
    KR-SEL) printf '%s\n' www.sc.co.kr www.snu.ac.kr www.hanyang.ac.kr ;;
    *) return 1 ;;
  esac
}

[[ ${#SB_REALITY_REGION_CANDIDATES[@]} == 23 ]] || fail 'expected only checker-eligible regional candidates'
for region in HK US-LAX DE-FRA JP-TYO KR-SEL; do
  records=$(reality_region_candidate_records "${region}") || fail "missing regional pool: ${region}"
  actual_domains=''
  bank_count=0
  government_count=0
  university_count=0
  record_count=0
  while IFS='|' read -r record_region category institution domain extra; do
    [[ "${record_region}" == "${region}" && -n "${institution}" && -z "${extra}" ]] || fail 'invalid regional record shape'
    validate_reality_sni_syntax "${domain}" || fail "invalid preset domain: ${domain}"
    case "${category}" in
      bank) bank_count=$((bank_count + 1)) ;;
      government) government_count=$((government_count + 1)) ;;
      university) university_count=$((university_count + 1)) ;;
      *) fail "unexpected institution category: ${category}" ;;
    esac
    record_count=$((record_count + 1))
    actual_domains+="${domain}"$'\n'
  done <<< "${records}"
  expected_count=5
  expected_banks=2
  expected_government=1
  if [[ "${region}" == KR-SEL ]]; then
    expected_count=3
    expected_banks=1
    expected_government=0
  fi
  [[ "${record_count}" == "${expected_count}" && "${bank_count}" == "${expected_banks}" && "${government_count}" == "${expected_government}" && "${university_count}" == 2 ]] || fail "unbounded or incorrect category coverage: ${region}"
  [[ "${actual_domains%$'\n'}" == "$(expected_domains "${region}")" ]] || fail "regional domain identity/order mismatch: ${region}"
  [[ "$(printf '%s' "${actual_domains}" | sort -u | wc -l)" == "${expected_count}" ]] || fail "duplicate preset domain: ${region}"
done
for unknown in '' hk US DE JP KR kr-sel UNKNOWN 'HK US-LAX' 'HK;false'; do
  returned=''
  if returned=$(reality_region_candidate_records "${unknown}"); then
    fail "unknown region accepted: ${unknown}"
  fi
  [[ -z "${returned}" ]] || fail 'unknown region emitted candidate records'
done

# The preview supplies only seeds. Select the last checker-approved candidate,
# proving that a region choice cannot directly adopt its first hard-coded name.
CHECKER_STATUS=0
select_reality_sni_candidate() {
  printf '%s\n' "$@" > "${TMP_DIR}/checker-candidates"
  printf '%s\n' "$#" > "${TMP_DIR}/checker-count"
  printf '%s' "${!#}"
  return "${CHECKER_STATUS}"
}
region_choice=0
for region in HK US-LAX DE-FRA JP-TYO KR-SEL; do
  region_choice=$((region_choice + 1))
  SB_SNI=unchanged.example.test
  prompt_reality_region_candidates <<< "${region_choice}" > "${TMP_DIR}/region-output" || fail "region prompt failed: ${region}"
  [[ "$(cat "${TMP_DIR}/checker-candidates")" == "$(expected_domains "${region}")" ]] || fail "wrong checker arguments: ${region}"
  expected_count=$(expected_domains "${region}" | wc -l)
  [[ "$(cat "${TMP_DIR}/checker-count")" == "${expected_count}" ]] || fail 'regional prompt padded or truncated the verified candidate pool'
  [[ "${SB_SNI}" == "$(expected_domains "${region}" | tail -1)" ]] || fail 'region prompt did not adopt the checker-selected SNI'
  records=$(reality_region_candidate_records "${region}")
  while IFS='|' read -r record_region category institution domain; do
    grep -Fq -- "${domain}" "${TMP_DIR}/region-output" || fail 'preview omitted a candidate domain'
    grep -Fq -- "${institution}" "${TMP_DIR}/region-output" || fail 'preview omitted an institution identity'
  done <<< "${records}"
  grep -Fq CDN "${TMP_DIR}/region-output" || fail 'regional preview omitted the hosting-location caveat'
  for label in '1. HK 中国-香港' '2. US-LAX 美国-洛杉矶' '3. DE-FRA 德国-法兰克福' '4. JP-TYO 日本-东京' '5. KR-SEL 韩国-首尔'; do
    grep -Fxq "${label}" "${TMP_DIR}/region-output" || fail "inconsistent regional label: ${label}"
  done
done

for input in '' 0 $'9\n0'; do
  rm -f -- "${TMP_DIR}/checker-candidates"
  SB_SNI=unchanged.example.test
  if prompt_reality_region_candidates <<< "${input}" > "${TMP_DIR}/region-output"; then
    fail 'cancelled regional selection reported success'
  fi
  [[ "${SB_SNI}" == unchanged.example.test && ! -e "${TMP_DIR}/checker-candidates" ]] || fail 'cancelled selection probed or changed SNI'
done
rm -f -- "${TMP_DIR}/checker-candidates"
SB_SNI=unchanged.example.test
if prompt_reality_region_candidates </dev/null > "${TMP_DIR}/region-output"; then
  fail 'regional selection accepted EOF'
fi
[[ "${SB_SNI}" == unchanged.example.test && ! -e "${TMP_DIR}/checker-candidates" ]] || fail 'EOF probed or changed SNI'

# Even valid-looking stdout from a failed checker is not an accepted SNI.
for checker_status in 1 2 3 124 130 143; do
  CHECKER_STATUS=${checker_status}
  SB_SNI=unchanged.example.test
  result=0
  prompt_reality_region_candidates <<< 5 > "${TMP_DIR}/region-output" || result=$?
  [[ "${result}" == "${checker_status}" ]] || fail 'regional prompt lost the checker failure/interruption status'
  [[ "${SB_SNI}" == unchanged.example.test ]] || fail 'failed checker stdout bypassed acceptance'
done

# Run the actual lifecycle SNI menus through their new entries. Existing menu
# numbers/defaults retain their meanings and require no regional probe.
CHECKER_STATUS=0
SB_SNI=unchanged.example.test
prompt_reality_sni_install <<< $'4\n1' > "${TMP_DIR}/menu-output"
[[ "${SB_SNI}" == www.cityu.edu.hk ]] || fail 'installation SNI menu did not route to HK candidates'
SB_SNI=unchanged.example.test
prompt_reality_sni_update <<< $'5\n2' > "${TMP_DIR}/menu-output"
[[ "${SB_SNI}" == www.usc.edu ]] || fail 'update SNI menu did not route to US-LAX candidates'
SB_SNI=unchanged.example.test
prompt_reality_sni_for_new_instance existing.example.test <<< $'5\n3' > "${TMP_DIR}/menu-output"
[[ "${SB_SNI}" == www.frankfurt-school.de ]] || fail 'new-instance SNI menu did not route to DE-FRA candidates'

# Seoul is available from every existing regional entry, including an empty
# new-instance default that delegates to the installation SNI menu.
for menu in install update new_instance empty_new_instance; do
  SB_SNI=unchanged.example.test
  case "${menu}" in
    install) prompt_reality_sni_install <<< $'4\n5' > "${TMP_DIR}/menu-output" ;;
    update) prompt_reality_sni_update <<< $'5\n5' > "${TMP_DIR}/menu-output" ;;
    new_instance) prompt_reality_sni_for_new_instance existing.example.test <<< $'5\n5' > "${TMP_DIR}/menu-output" ;;
    empty_new_instance) prompt_reality_sni_for_new_instance '' <<< $'4\n5' > "${TMP_DIR}/menu-output" ;;
  esac
  [[ "${SB_SNI}" == www.hanyang.ac.kr ]] || fail "${menu} did not adopt the checker-selected Seoul candidate"
  [[ "$(cat "${TMP_DIR}/checker-candidates")" == "$(expected_domains KR-SEL)" ]] || fail "${menu} passed incorrect Seoul candidates"
done

rm -f -- "${TMP_DIR}/checker-candidates"
SB_SNI=existing.example.test
prompt_reality_sni_update <<< '' > "${TMP_DIR}/menu-output"
[[ "${SB_SNI}" == existing.example.test && ! -e "${TMP_DIR}/checker-candidates" ]] || fail 'update default no longer preserves SNI'
prompt_reality_sni_for_new_instance reuse.example.test <<< '' > "${TMP_DIR}/menu-output"
[[ "${SB_SNI}" == reuse.example.test && ! -e "${TMP_DIR}/checker-candidates" ]] || fail 'new-instance default no longer reuses SNI'

for checker_status in 1 130 143; do
  CHECKER_STATUS=${checker_status}
  for menu in install update new_instance empty_new_instance; do
    SB_SNI=unchanged.example.test
    result=0
    case "${menu}" in
      install) prompt_reality_sni_install <<< $'4\n5' > "${TMP_DIR}/menu-output" || result=$? ;;
      update) prompt_reality_sni_update <<< $'5\n5' > "${TMP_DIR}/menu-output" || result=$? ;;
      new_instance) prompt_reality_sni_for_new_instance existing.example.test <<< $'5\n5' > "${TMP_DIR}/menu-output" || result=$? ;;
      empty_new_instance) prompt_reality_sni_for_new_instance '' <<< $'4\n5' > "${TMP_DIR}/menu-output" || result=$? ;;
    esac
    [[ "${result}" == "${checker_status}" ]] || fail "${menu} lost regional failure/interruption status"
    [[ "${SB_SNI}" == unchanged.example.test ]] || fail "${menu} changed SNI after regional failure/interruption"
  done
done

printf 'REALITY regional candidate registry, checker handoff and menu tests passed.\n'
