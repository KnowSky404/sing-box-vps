#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export SBV_TEST_MODE=1
source "${REPO_ROOT}/install.sh"

migrate_vless_reality_state_to_instances_if_needed() {
  return 0
}

list_vless_reality_instance_ids() {
  printf '%s\n' main limited
}

load_vless_reality_instance_state() {
  case "$1" in
    main)
      SB_VLESS_INSTANCE_ID="main"
      SB_NODE_NAME="main-vless"
      SB_PORT="443"
      SB_UUID="uuid-main"
      SB_SNI="www.cloudflare.com"
      SB_SHORT_ID_1="aaaa"
      SB_SHORT_ID_2="bbbb"
      SB_VLESS_RATE_LIMIT_UP_MBPS=""
      SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
      SB_VLESS_ALPN_MODE="h2_http1"
      SB_VLESS_TCP_FAST_OPEN="y"
      ;;
    limited)
      SB_VLESS_INSTANCE_ID="limited"
      SB_NODE_NAME="limited-vless"
      SB_PORT="444"
      SB_UUID="uuid-limited"
      SB_SNI="www.cloudflare.com"
      SB_SHORT_ID_1="cccc"
      SB_SHORT_ID_2="dddd"
      SB_VLESS_RATE_LIMIT_UP_MBPS="40"
      SB_VLESS_RATE_LIMIT_DOWN_MBPS="100"
      SB_VLESS_ALPN_MODE="http1"
      SB_VLESS_TCP_FAST_OPEN="y"
      ;;
    *)
      return 1
      ;;
  esac
}

SB_VLESS_INSTANCE_ID="new"
SB_NODE_NAME="new-vless"
SB_PORT="445"
SB_UUID="uuid-new"
SB_SNI="www.cloudflare.com"
SB_SHORT_ID_1="eeee"
SB_SHORT_ID_2="ffff"
SB_VLESS_RATE_LIMIT_UP_MBPS="1"
SB_VLESS_RATE_LIMIT_DOWN_MBPS="2"
SB_VLESS_ALPN_MODE="off"
SB_VLESS_TCP_FAST_OPEN="n"

if ! vless_reality_bandwidth_profile_exists "" ""; then
  printf 'FAIL: unlimited profile should be detected as duplicate\n' >&2
  exit 1
fi

if ! vless_reality_bandwidth_profile_exists "40" "100"; then
  printf 'FAIL: 40/100 profile should be detected as duplicate\n' >&2
  exit 1
fi

if vless_reality_bandwidth_profile_exists "40" ""; then
  printf 'FAIL: 40/unlimited profile should not be detected as duplicate\n' >&2
  exit 1
fi

if vless_reality_bandwidth_profile_exists "" "100"; then
  printf 'FAIL: unlimited/100 profile should not be detected as duplicate\n' >&2
  exit 1
fi

if ! vless_reality_bandwidth_profile_exists "40" "100" "main"; then
  printf 'FAIL: excluding main should still find limited profile\n' >&2
  exit 1
fi

if vless_reality_bandwidth_profile_exists "40" "100" "limited"; then
  printf 'FAIL: excluding limited should hide 40/100 duplicate\n' >&2
  exit 1
fi

if [[ "${SB_VLESS_INSTANCE_ID}" != "new" || "${SB_NODE_NAME}" != "new-vless" || "${SB_VLESS_RATE_LIMIT_UP_MBPS}" != "1" || "${SB_VLESS_RATE_LIMIT_DOWN_MBPS}" != "2" ]]; then
  printf 'FAIL: duplicate scan did not restore caller state\n' >&2
  exit 1
fi

if [[ "${SB_VLESS_ALPN_MODE}" != "off" || "${SB_VLESS_TCP_FAST_OPEN}" != "n" ]]; then
  printf 'FAIL: duplicate scan did not restore advanced caller state: alpn=%s tfo=%s\n' \
    "${SB_VLESS_ALPN_MODE}" "${SB_VLESS_TCP_FAST_OPEN}" >&2
  exit 1
fi
