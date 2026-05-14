#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"

sed \
  -e 's|main "\$@"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

ss() {
  cat <<'EOF'
Netid State  Recv-Q Send-Q Local Address:Port Peer Address:PortProcess
tcp   LISTEN 0      4096   0.0.0.0:60001    0.0.0.0:*    users:(("occupied",pid=1,fd=3))
tcp   LISTEN 0      4096   0.0.0.0:60002    0.0.0.0:*    users:(("occupied",pid=2,fd=3))
tcp   LISTEN 0      4096   0.0.0.0:60003    0.0.0.0:*    users:(("occupied",pid=3,fd=3))
EOF
}

assert_high_port() {
  local protocol=$1
  local port=$2

  if (( port < 60000 || port > 65535 )); then
    printf 'expected %s default port to be within 60000-65535, got %s\n' "${protocol}" "${port}" >&2
    exit 1
  fi

  case "${port}" in
    60001|60002|60003)
      printf 'expected %s default port to avoid occupied ports, got %s\n' "${protocol}" "${port}" >&2
      exit 1
      ;;
  esac
}

RANDOM=1
set_protocol_defaults "vless+reality"
if [[ "${SB_PORT}" != "443" ]]; then
  printf 'expected vless+reality default port to be 443, got %s\n' "${SB_PORT}" >&2
  exit 1
fi

RANDOM=1
set_protocol_defaults "mixed"
assert_high_port "mixed" "${SB_PORT}"

RANDOM=1
set_protocol_defaults "hy2"
assert_high_port "hy2" "${SB_PORT}"

RANDOM=1
set_protocol_defaults "anytls"
assert_high_port "anytls" "${SB_PORT}"
