#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "${REPO_ROOT}/install.sh"
EVIDENCE=${1:-${REPO_ROOT}/docs/verification/reality-region-candidates.json}
TMP_DIR=$(mktemp -d)
trap 'rm -rf -- "${TMP_DIR}"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
jq -e --arg version "${SB_REALITY_CHECKER_VERSION}" --arg commit "${SB_REALITY_CHECKER_COMMIT}" \
  --arg sha256 "${SB_REALITY_CHECKER_SHA256}" --argjson count "${#SB_REALITY_REGION_CANDIDATES[@]}" '
  .schema_version == "1" and
  (.started_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
  (.completed_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
  .started_at <= .completed_at and
  .checker.version == $version and .checker.commit == $commit and .checker.sha256 == $sha256 and
  .checker.arguments == ["check","<domain>","--json","--timeout","3"] and
  .checker.deadline_seconds == 90 and
  (.candidates | type == "array" and length == $count and
    (map(.domain) | unique | length == $count) and
    all(.[]; .eligible == true and
      (.report_sha256 | test("^[0-9a-f]{64}$")) and
      (.observed_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))))
' "${EVIDENCE}" >/dev/null || fail 'missing, stale or invalid checker evidence metadata'

for RECORD in "${SB_REALITY_REGION_CANDIDATES[@]}"; do
  IFS='|' read -r REGION CATEGORY INSTITUTION DOMAIN <<< "${RECORD}"
  jq -e --arg region "${REGION}" --arg category "${CATEGORY}" \
    --arg institution "${INSTITUTION}" --arg domain "${DOMAIN}" '
    .candidates[] | select(.region == $region and .category == $category and
      .institution == $institution and .domain == $domain)
  ' "${EVIDENCE}" > "${TMP_DIR}/record.json" || fail "unchecked or changed candidate: ${DOMAIN}"
  STATUS=$(jq -r '.exit_code' "${TMP_DIR}/record.json")
  jq '.report' "${TMP_DIR}/record.json" > "${TMP_DIR}/report.json"
  validate_reality_target_report "${TMP_DIR}/report.json" "${DOMAIN}" "${STATUS}" ||
    fail "candidate lacks complete passing TLS/compatibility evidence: ${DOMAIN}"
done

printf 'REALITY regional candidates all have pinned public-checker evidence (%s domains).\n' "${#SB_REALITY_REGION_CANDIDATES[@]}"
