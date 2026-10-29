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

if ! validate_reality_sni_syntax "www.example.com"; then
  printf 'expected valid domain syntax to pass\n' >&2
  exit 1
fi

for invalid_sni in "" "https://www.example.com" "www.example.com:443" "www.example.com/path" "bad_domain.example.com" "-bad.example.com"; do
  if validate_reality_sni_syntax "${invalid_sni}"; then
    printf 'expected invalid SNI syntax to fail: %s\n' "${invalid_sni}" >&2
    exit 1
  fi
done

probe_reality_sni_tls() {
  case "${1:-}" in
    manual.example.com) return 0 ;;
    broken.example.com)
      printf 'stubbed TLS failure'
      return 1
      ;;
    *)
      printf 'unexpected SNI probe: %s' "${1:-}"
      return 1
      ;;
  esac
}

SB_SNI="old.example.com"
read_manual_reality_sni_with_validation "manual.example.com" "REALITY SNI: " <<'EOF' >/dev/null
broken.example.com
n
manual.example.com
EOF

if [[ "${SB_SNI}" != "manual.example.com" ]]; then
  printf 'expected retry after failed manual validation, got %s\n' "${SB_SNI}" >&2
  exit 1
fi

SB_SNI="old.example.com"
read_manual_reality_sni_with_validation "manual.example.com" "REALITY SNI: " <<'EOF' >/dev/null
broken.example.com
y
EOF

if [[ "${SB_SNI}" != "broken.example.com" ]]; then
  printf 'expected manual validation warning to allow explicit continue, got %s\n' "${SB_SNI}" >&2
  exit 1
fi

SB_SNI="old.example.com"
read_manual_reality_sni_with_validation "" "REALITY SNI: " <<'EOF_INPUT' >/dev/null
https://invalid.example.com/path
y
manual.example.com
EOF_INPUT
[[ "${SB_SNI}" == manual.example.com ]] || {
  printf 'invalid syntax must not be accepted with a warning override\n' >&2
  exit 1
}

SB_SNI="old.example.com"
if read_manual_reality_sni_with_validation "" "REALITY SNI: " </dev/null >/dev/null; then
  printf 'expected manual SNI EOF to fail\n' >&2
  exit 1
fi
[[ "${SB_SNI}" == old.example.com ]] || exit 1

SB_SNI="alpn.example.com"
SB_VLESS_ALPN_MODE="off"
probe_reality_sni_alpn() {
  printf 'ALPN probe should not run when disabled\n' >&2
  return 1
}
validate_current_reality_sni_alpn_or_warn >/dev/null

SB_VLESS_ALPN_MODE="http1"
ALPN_PROBE_FILE="${TMP_DIR}/alpn-probe.txt"
probe_reality_sni_alpn() {
  printf '%s:%s' "${1}" "${2}" > "${ALPN_PROBE_FILE}"
  return 0
}
validate_current_reality_sni_alpn_or_warn >/dev/null

alpn_probe_seen=$(cat "${ALPN_PROBE_FILE}")
if [[ "${alpn_probe_seen}" != "alpn.example.com:http1" ]]; then
  printf 'expected ALPN probe for current SNI and mode, got %s\n' "${alpn_probe_seen}" >&2
  exit 1
fi

SB_VLESS_ALPN_MODE="h2_http1"
probe_reality_sni_alpn() {
  printf 'stubbed ALPN failure'
  return 1
}
validate_current_reality_sni_alpn_or_warn <<'EOF' >/dev/null
n
EOF

if [[ "${SB_VLESS_ALPN_MODE}" != "off" ]]; then
  printf 'expected ALPN rejection to reset mode to off, got %s\n' "${SB_VLESS_ALPN_MODE}" >&2
  exit 1
fi
