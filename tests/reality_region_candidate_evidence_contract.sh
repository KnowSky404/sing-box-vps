#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EVIDENCE="${REPO_ROOT}/docs/verification/reality-region-candidates.json"
TMP_DIR=$(mktemp -d)
trap 'rm -rf -- "${TMP_DIR}"' EXIT

# Snapshot changes must not disguise missing candidates, incomplete DNS coverage
# or even one failed endpoint as a successful development check.
bash "${REPO_ROOT}/tests/reality_region_candidate_evidence.sh"
for MUTATION in \
  '.checker.commit = "unreviewed"' \
  '.checker.sha256 = "wrong"' \
  '.candidates |= .[1:]' \
  '.candidates[0] = .candidates[1]' \
  '.candidates[0].domain = "unchecked.example.test"' \
  '.candidates[0].eligible = false' \
  '.candidates[0].report.selection.complete = false' \
  '.candidates[0].report.summary.basic_tls = "UNKNOWN"' \
  '.candidates[0].report.endpoints[0].checks |= map(select(.id != "cert_san"))' \
  '.candidates[0].report.endpoints[0].checks |= map(if .id == "alpn_h2" then .status = "FAIL" else . end)' \
  '.candidates[0].report.endpoints += [{ip:"192.0.2.1",family:4,checks:[]}]'; do
  jq "${MUTATION}" "${EVIDENCE}" > "${TMP_DIR}/invalid.json"
  if bash "${REPO_ROOT}/tests/reality_region_candidate_evidence.sh" "${TMP_DIR}/invalid.json" \
    > "${TMP_DIR}/output" 2>&1; then
    printf 'FAIL: invalid candidate evidence accepted: %s\n' "${MUTATION}" >&2
    exit 1
  fi
done
printf 'REALITY candidate evidence rejects unchecked, incomplete and failing records.\n'
