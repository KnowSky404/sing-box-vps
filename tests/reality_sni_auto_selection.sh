#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"

sed \
  -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  -e 's|main \"\$@\"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

SB_REALITY_SNI_CANDIDATES=(
  "slow.example.com"
  "fast.example.com"
  "failed.example.com"
)

probe_reality_sni_candidate() {
  case "${1:-}" in
    slow.example.com) printf '120' ;;
    fast.example.com) printf '45' ;;
    failed.example.com) return 1 ;;
    *) return 1 ;;
  esac
}

selected_sni=$(select_reality_sni_candidate)
if [[ "${selected_sni}" != "fast.example.com" ]]; then
  printf 'expected fastest successful SNI fast.example.com, got: %s\n' "${selected_sni}" >&2
  exit 1
fi

probe_reality_sni_candidate() {
  return 1
}

selected_sni=$(select_reality_sni_candidate)
if [[ "${selected_sni}" != "${SB_REALITY_SNI_FALLBACK}" ]]; then
  printf 'expected fallback SNI %s, got: %s\n' "${SB_REALITY_SNI_FALLBACK}" "${selected_sni}" >&2
  exit 1
fi
