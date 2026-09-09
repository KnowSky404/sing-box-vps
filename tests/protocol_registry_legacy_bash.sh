#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "${REPO_ROOT}/install.sh"

# This test is deliberately dependency-free so it also runs in the official
# Bash 4.2 container used for the CentOS 7 shell compatibility boundary.
for mapping in \
  'vless:vless-reality' 'vless+reality:vless-reality' 'vless-reality:vless-reality' \
  'vless-plain:vless-plain' \
  'mixed:mixed' 'hy2:hy2' 'hysteria2:hy2' 'anytls:anytls' 'trojan:trojan' 'vmess:vmess' 'snell:snell' 'tuic:tuic' 'hysteria:hysteria' 'naive:naive' 'shadowtls:shadowtls'; do
  input=${mapping%%:*}
  expected=${mapping#*:}
  actual=$(normalize_protocol_id "${input}")
  [[ "${actual}" == "${expected}" ]]
  protocol_registry_require_handlers "${input}"
done

for invalid in '' unknown '../mixed' '$(false)' 'mixed;false'; do
  if normalize_protocol_id "${invalid}"; then
    printf 'registry accepted an unsupported input\n' >&2
    exit 1
  fi
done

for runtime in vless+reality mixed hy2 anytls trojan vmess snell tuic hysteria naive shadowtls; do
  validate_protocol "${runtime}"
done
if validate_protocol vless; then
  printf 'legacy alias changed runtime validation semantics\n' >&2
  exit 1
fi
printf 'registry shell compatibility: Bash %s passed\n' "${BASH_VERSION}"
