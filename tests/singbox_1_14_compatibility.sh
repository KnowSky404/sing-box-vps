#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install

fail() { printf '%s\n' "$1" >&2; exit 1; }

singbox_version_at_least 1.14.0 1.14.0 || fail '1.14.0 should satisfy itself'
if singbox_version_at_least 1.13.18 1.14.0; then fail '1.13.18 must not satisfy 1.14 capability'; fi
singbox_version_at_least 1.14.1 1.14.0 || fail 'newer versions should satisfy 1.14 capability'
SB_VERSION=1.14.0
[[ "$(resolve_config_target_singbox_version)" == 1.14.0 ]] || fail 'config target should resolve to 1.14.0'
singbox_config_supports_1_14 || fail '1.14 config capability should be enabled'
SB_VERSION=1.13.18
if singbox_config_supports_1_14; then fail '1.13 config capability should be disabled'; fi
detect_installed_singbox_version() { printf '1.14.0'; }
[[ "$(resolve_config_target_singbox_version)" == 1.14.0 ]] || fail 'installed binary version should take precedence over requested version'
detect_installed_singbox_version() { printf 'unexpected-version-output'; }
[[ "$(resolve_config_target_singbox_version)" == 1.13.18 ]] || fail 'invalid installed version output should fall back to requested version'
detect_installed_singbox_version() { :; }

SB_VERSION=1.14.0
set_protocol_defaults hy2
SB_PORT=443 SB_HY2_DOMAIN=hy2.example.com SB_HY2_PASSWORD=pass SB_HY2_USER_NAME=user
SB_HY2_TLS_MODE=acme SB_HY2_ACME_MODE=http SB_HY2_ACME_DOMAIN=hy2.example.com
build_hy2_inbound_json > "${TMP_DIR}/hy2-114.json"
build_hy2_certificate_provider_json > "${TMP_DIR}/hy2-provider-114.json"
jq -e '.tls.certificate_provider == "hy2-cert-provider" and (.tls.acme? == null)' "${TMP_DIR}/hy2-114.json" >/dev/null || fail '1.14 Hy2 must reference certificate_provider'
jq -e '.tag == "hy2-cert-provider" and .type == "acme"' "${TMP_DIR}/hy2-provider-114.json" >/dev/null || fail '1.14 Hy2 provider must be emitted'

set_protocol_defaults anytls
SB_PORT=8443 SB_ANYTLS_DOMAIN=anytls.example.com SB_ANYTLS_PASSWORD=pass SB_ANYTLS_USER_NAME=user
SB_ANYTLS_TLS_MODE=acme SB_ANYTLS_ACME_MODE=http SB_ANYTLS_ACME_DOMAIN=anytls.example.com
build_anytls_inbound_json > "${TMP_DIR}/anytls-114.json"
build_anytls_certificate_provider_json > "${TMP_DIR}/anytls-provider-114.json"
jq -e '.tls.certificate_provider == "anytls-cert-provider" and (.tls.acme? == null)' "${TMP_DIR}/anytls-114.json" >/dev/null || fail '1.14 AnyTLS must reference certificate_provider'
jq -e '.tag == "anytls-cert-provider" and .type == "acme"' "${TMP_DIR}/anytls-provider-114.json" >/dev/null || fail '1.14 AnyTLS provider must be emitted'

SB_VERSION=1.13.18
set_protocol_defaults hy2
SB_PORT=443 SB_HY2_DOMAIN=hy2.example.com SB_HY2_TLS_MODE=acme SB_HY2_ACME_MODE=http SB_HY2_ACME_DOMAIN=hy2.example.com
build_hy2_inbound_json > "${TMP_DIR}/hy2-113.json"
build_hy2_certificate_provider_json > "${TMP_DIR}/hy2-provider-113.json"
jq -e '.tls.acme.domain == ["hy2.example.com"] and (.tls.certificate_provider? == null)' "${TMP_DIR}/hy2-113.json" >/dev/null || fail '1.13 Hy2 must retain inline tls.acme'
[[ ! -s "${TMP_DIR}/hy2-provider-113.json" ]] || fail '1.13 must not emit certificate provider'

set_protocol_defaults anytls
SB_PORT=8443 SB_ANYTLS_DOMAIN=anytls.example.com SB_ANYTLS_TLS_MODE=acme SB_ANYTLS_ACME_MODE=http SB_ANYTLS_ACME_DOMAIN=anytls.example.com
build_anytls_inbound_json > "${TMP_DIR}/anytls-113.json"
build_anytls_certificate_provider_json > "${TMP_DIR}/anytls-provider-113.json"
jq -e '.tls.acme.domain == ["anytls.example.com"] and (.tls.certificate_provider? == null)' "${TMP_DIR}/anytls-113.json" >/dev/null || fail '1.13 AnyTLS must retain inline tls.acme'
[[ ! -s "${TMP_DIR}/anytls-provider-113.json" ]] || fail '1.13 must not emit certificate provider'

printf 'warp-tag|https://example.com/rules.srs|1d\n' > "${SB_WARP_REMOTE_RULESETS_FILE}"
SB_VERSION=1.14.0
build_remote_warp_rule_sets_json
jq -e '.[0].http_client.detour == "direct" and (.[0].download_detour? == null)' <<< "${SB_WARP_REMOTE_RULE_SETS_JSON}" >/dev/null || fail '1.14 WARP rule-set must use http_client.detour'
printf '%s\n' "${SB_WARP_REMOTE_RULE_SETS_JSON}" > "${TMP_DIR}/rule-sets-114.json"
SB_VERSION=1.13.18
build_remote_warp_rule_sets_json
jq -e '.[0].download_detour == "direct" and (.[0].http_client? == null)' <<< "${SB_WARP_REMOTE_RULE_SETS_JSON}" >/dev/null || fail '1.13 WARP rule-set must use download_detour'
printf '%s\n' "${SB_WARP_REMOTE_RULE_SETS_JSON}" > "${TMP_DIR}/rule-sets-113.json"

if [[ -n "${SINGBOX_BINARY_114:-}" ]]; then
  [[ -x "${SINGBOX_BINARY_114}" ]] || fail "1.14 validation binary is not executable: ${SINGBOX_BINARY_114}"
  jq -n \
    --slurpfile hy2 "${TMP_DIR}/hy2-114.json" \
    --slurpfile anytls "${TMP_DIR}/anytls-114.json" \
    --slurpfile hy2_provider "${TMP_DIR}/hy2-provider-114.json" \
    --slurpfile anytls_provider "${TMP_DIR}/anytls-provider-114.json" \
    --slurpfile rule_sets "${TMP_DIR}/rule-sets-114.json" \
    '{
      inbounds: ($hy2 + $anytls),
      outbounds: [{type: "direct", tag: "direct"}],
      route: {rule_set: $rule_sets[0], final: "direct"},
      certificate_providers: ($hy2_provider + $anytls_provider)
    }' > "${TMP_DIR}/server-114.json"
  "${SINGBOX_BINARY_114}" check -c "${TMP_DIR}/server-114.json" || fail 'real sing-box 1.14.0 rejected the generated server configuration'
fi

if [[ -n "${SINGBOX_BINARY_113:-}" ]]; then
  [[ -x "${SINGBOX_BINARY_113}" ]] || fail "1.13 validation binary is not executable: ${SINGBOX_BINARY_113}"
  jq -n \
    --slurpfile hy2 "${TMP_DIR}/hy2-113.json" \
    --slurpfile anytls "${TMP_DIR}/anytls-113.json" \
    --slurpfile rule_sets "${TMP_DIR}/rule-sets-113.json" \
    '{
      inbounds: ($hy2 + $anytls),
      outbounds: [{type: "direct", tag: "direct"}],
      route: {rule_set: $rule_sets[0], final: "direct"}
    }' > "${TMP_DIR}/server-113.json"
  "${SINGBOX_BINARY_113}" check -c "${TMP_DIR}/server-113.json" || fail 'real sing-box 1.13.18 rejected the generated server configuration'
fi

if [[ -n "${SINGBOX_BINARY_114:-}" && -f "${TMP_DIR}/server-113.json" ]]; then
  "${SINGBOX_BINARY_114}" check -c "${TMP_DIR}/server-113.json" || fail 'sing-box 1.14.0 rejected the preserved 1.13 server configuration'
fi

printf '%s\n' '1.14 compatibility checks passed'
