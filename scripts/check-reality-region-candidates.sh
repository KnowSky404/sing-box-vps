#!/usr/bin/env bash

# Explicit public-network development check; never invoked by installation/CI.
set -euo pipefail
umask 077

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [[ $# != 1 || ${1:-} == -* ]]; then
  printf 'usage: bash %s NEW_OUTPUT_DIRECTORY\n' "${BASH_SOURCE[0]}" >&2
  exit 2
fi
# Sourcing the guarded runtime defines the pinned downloader and report contract
# without entering the installer or touching its managed storage.
source "${REPO_ROOT}/install.sh"

mkdir -m 700 -- "$1"
OUTPUT_DIR=$(cd -- "$1" && pwd -P)
WORK_DIR=$(mktemp -d "${OUTPUT_DIR}/.checker.XXXXXXXX")
CHECKER_PID=''
cleanup() {
  local status=$?
  trap - EXIT
  if [[ -n "${CHECKER_PID}" ]]; then
    stop_reality_checker_process_tree "${CHECKER_PID}" || status=1
    if wait "${CHECKER_PID}"; then :; fi
  fi
  rm -rf -- "${WORK_DIR}" || status=1
  exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

prepare_reality_target_checker "${WORK_DIR}/checker.sh"
STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
FAILED=0
for RECORD in "${SB_REALITY_REGION_CANDIDATES[@]}"; do
  IFS='|' read -r REGION CATEGORY INSTITUTION DOMAIN <<< "${RECORD}"
  validate_reality_sni_syntax "${DOMAIN}"
  mkdir -m 700 -- "${OUTPUT_DIR}/${DOMAIN}"
  REPORT="${OUTPUT_DIR}/${DOMAIN}/report.json"
  printf 'Checking %s %s (public DNS, all A/AAAA, 90s deadline)\n' "${REGION}" "${DOMAIN}" >&2
  STATUS=0
  TMPDIR="${WORK_DIR}" timeout --signal=TERM --kill-after=2 90 \
    bash "${WORK_DIR}/checker.sh" check "${DOMAIN}" --json --timeout 3 \
    > "${REPORT}" 2> "${OUTPUT_DIR}/${DOMAIN}/stderr" &
  CHECKER_PID=$!
  wait "${CHECKER_PID}" || STATUS=$?
  CHECKER_PID=''
  case "${STATUS}" in 129|130|137|143) exit "${STATUS}" ;; esac
  ELIGIBLE=false
  if validate_reality_target_report "${REPORT}" "${DOMAIN}" "${STATUS}"; then
    ELIGIBLE=true
  else
    FAILED=$((FAILED + 1))
  fi
  DIGEST=$(sha256sum -- "${REPORT}")
  jq -n --arg region "${REGION}" --arg category "${CATEGORY}" \
    --arg institution "${INSTITUTION}" --arg domain "${DOMAIN}" \
    --arg observed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg report_sha256 "${DIGEST%% *}" --argjson exit_code "${STATUS}" \
    --argjson eligible "${ELIGIBLE}" --rawfile raw "${REPORT}" '
    {region:$region,category:$category,institution:$institution,domain:$domain,
     observed_at:$observed_at,report_sha256:$report_sha256,exit_code:$exit_code,
     eligible:$eligible,
     report:(try ($raw | fromjson | {
       schema_version,tool_version,target,sni,port,selection,summary,
       endpoints:[.endpoints[] | {ip,family,checks:[.checks[] | {id,status}]}],
       risks,unknowns}) catch null)}
  ' > "${OUTPUT_DIR}/${DOMAIN}/record.json"
  printf '%s: eligible=%s, checker exit=%s\n' "${DOMAIN}" "${ELIGIBLE}" "${STATUS}" >&2
done

jq -s --arg started_at "${STARTED_AT}" --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg version "${SB_REALITY_CHECKER_VERSION}" --arg commit "${SB_REALITY_CHECKER_COMMIT}" \
  --arg sha256 "${SB_REALITY_CHECKER_SHA256}" '
  {schema_version:"1",started_at:$started_at,completed_at:$completed_at,
   checker:{version:$version,commit:$commit,sha256:$sha256,
            arguments:["check","<domain>","--json","--timeout","3"],deadline_seconds:90},
   scope:"public DNS from the development network; no REALITY handshake or production acceptance",
   policy:"All basic TLS and compatibility checks must PASS on every DNS endpoint. WARN retains ancillary risks and requires installation-time consent.",
   candidates:.}
' "${OUTPUT_DIR}"/*/record.json > "${OUTPUT_DIR}/summary.json"
printf 'Evidence: %s/summary.json; ineligible candidates: %s\n' "${OUTPUT_DIR}" "${FAILED}" >&2
(( FAILED == 0 ))
