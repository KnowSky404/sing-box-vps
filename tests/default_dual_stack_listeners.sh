#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# Source at file scope for Bash 4.2's readonly registry arrays.
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

check_count=0
core_check_count=0
assert_equal() {
  local label=$1 actual=$2 expected=$3
  check_count=$((check_count + 1))
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'FAIL %s: expected %q, got %q\n' "${label}" "${expected}" "${actual}" >&2
    exit 1
  fi
}

check_core_config() {
  local label=$1 config=$2
  [[ -n "${SINGBOX_BINARY_114:-}" ]] || return 0
  if ! "${SINGBOX_BINARY_114}" check -c "${config}" > "${TMP_DIR}/core-check.log" 2>&1; then
    printf 'FAIL %s sing-box check\n' "${label}" >&2
    cat "${TMP_DIR}/core-check.log" >&2
    return 1
  fi
  check_count=$((check_count + 1))
  core_check_count=$((core_check_count + 1))
}

detect_host_ip_stack() { printf dual; }
pick_random_high_port() { printf 38443; }
generate_snell_psk() { printf 'fixture-snell-psk'; }
trojan_generate_password() { printf 'fixture-password'; }
tuic_generate_uuid() { printf '11111111-1111-4111-8111-111111111111'; }
curl() { printf 'unexpected network access in dual-stack defaults test\n' >&2; return 99; }
printf '{"inbounds":[]}\n' > "${SINGBOX_CONFIG_FILE}"

protocols=(mixed socks http shadowsocks trojan vmess vless-plain anytls hy2 snell tuic hysteria naive shadowtls)
# A previous instance must not leak its listener into another protocol's defaults.
for protocol in vless-reality "${protocols[@]}"; do
  SB_MIXED_LISTEN_ADDRESS=198.51.100.7
  set_protocol_defaults "${protocol}"
  assert_equal "${protocol} fresh defaults" "${SB_MIXED_LISTEN_ADDRESS}" '::'
done

# Exercise every real create dispatcher with blank input at its listener prompt.
# Stop at the following port prompt: later credential/TLS choices are independent
# of the listener default and must not cause network or service operations here.
read() {
  if [[ "${1:-}" != -rp && "${1:-}" != -rsp ]]; then builtin read "$@"; return $?; fi
  local target=${@: -1} value=''
  if [[ "$*" == *监听地址* ]]; then value=${TEST_ADDRESS_INPUT:-}; fi
  printf -v "${target}" '%s' "${value}"
}
prompt_port() {
  printf '%s' "${address}" > "${TMP_DIR}/selected-listener"
  return 1
}
snapshot="${TMP_DIR}/snapshot.json"
record="${TMP_DIR}/record.json"
for protocol in "${protocols[@]}"; do
  structured_instance_store_empty_json "${protocol}" > "${snapshot}"
  for explicit_address in '' 0.0.0.0 ::1 198.51.100.8; do
    TEST_ADDRESS_INPUT=${explicit_address}
    rm -f -- "${TMP_DIR}/selected-listener" "${record}"
    if plain_proxy_management_build_record "${protocol}" "${snapshot}" create '' "${record}" \
        > "${TMP_DIR}/create.stdout" 2> "${TMP_DIR}/create.stderr"; then
      printf 'cancelled %s creation unexpectedly succeeded\n' "${protocol}" >&2
      exit 1
    fi
    if [[ ! -f "${TMP_DIR}/selected-listener" ]]; then
      printf '%s creation failed before the listener was accepted\n' "${protocol}" >&2
      cat "${TMP_DIR}/create.stderr" >&2
      exit 1
    fi
    assert_equal "${protocol} listener input ${explicit_address:-blank}" \
      "$(cat "${TMP_DIR}/selected-listener")" "${explicit_address:-::}"
    [[ ! -e "${record}" ]]
  done
done

# Complete representative records through the production validators. Stub only
# independent credential and TLS input; all listener resolution, record creation,
# validation and public-consent branches remain real.
prompt_port() { printf '%s' "$2"; }
read() {
  if [[ "${1:-}" != -rp && "${1:-}" != -rsp ]]; then builtin read "$@"; return $?; fi
  local target=${@: -1} value=''
  if [[ "$*" == *监听地址* ]]; then value=${TEST_ADDRESS_INPUT:-}; fi
  printf -v "${target}" '%s' "${value}"
}
prompt_yes_no() {
  if [[ "$1" == *公网暴露* ]]; then printf '%s' "${TEST_PUBLIC_CONSENT:-y}"
  else printf '%s' "${2:-n}"; fi
}
prompt_choice() {
  if [[ "$1" == *TLS*模式* ]]; then printf 2
  else printf '%s' "$4"; fi
}
ensure_mixed_auth_credentials() { SB_MIXED_USERNAME=fixture-user; SB_MIXED_PASSWORD=fixture-password; }
plain_proxy_management_prompt_tls() { SB_HTTP_TLS_JSON='{"enabled":false}'; }
hy2_prompt_users() { SB_HY2_AUTH_JSON='[{"name":"fixture-user","password":"fixture-password"}]'; }
prompt_optional_domain() { printf 'fixture.example.com'; }
prompt_required_path() {
  if [[ "$1" == *私钥* ]]; then printf '%s' "${TMP_DIR}/fixture.key"
  else printf '%s' "${TMP_DIR}/fixture.crt"; fi
}
prompt_update_optional_positive_integer() { :; }
prompt_hy2_masquerade_url() { printf '%s' "${2:-}"; }
shadowtls_prompt_version_and_auth() { :; }
shadowtls_prompt_handshake() { SB_SHADOWTLS_HANDSHAKE_JSON=$1; }
shadowtls_prompt_handshake_map() { SB_SHADOWTLS_HANDSHAKE_FOR_SERVER_NAME_JSON=$1; }
shadowtls_prompt_client_tls() { SB_SHADOWTLS_CLIENT_TLS_JSON=$1; }
openssl req -x509 -newkey rsa:2048 -nodes -keyout "${TMP_DIR}/fixture.key" \
  -out "${TMP_DIR}/fixture.crt" -subj /CN=fixture.example.com -days 1 >/dev/null 2>&1

for protocol in mixed socks http hy2 shadowtls; do
  structured_instance_store_empty_json "${protocol}" > "${snapshot}"
  TEST_ADDRESS_INPUT=''
  plain_proxy_management_build_record "${protocol}" "${snapshot}" create '' "${record}" \
    > "${TMP_DIR}/record.stdout" 2> "${TMP_DIR}/record.stderr"
  assert_equal "${protocol} created record" "$(jq -r '.listen.address' "${record}")" '::'
  assert_equal "${protocol} public consent flag" "${PLAIN_PROXY_MANAGEMENT_ALLOW_PUBLIC}" y
  if [[ "${protocol}" == shadowtls ]]; then
    assert_equal 'ShadowTLS private detour' "$(jq -r '.detour.listen.address' "${record}")" 127.0.0.1
  fi
  created_store="${TMP_DIR}/${protocol}-created-store.json"
  jq -n --arg protocol "${protocol}" --slurpfile record "${record}" \
    '{schema_version:1,protocol:$protocol,revision:1,default_instance_id:$record[0].id,instances:$record}' \
    > "${created_store}"
  render_structured_instance_inbounds "${protocol}" "${created_store}" | \
    jq -s --argjson rules "$(render_structured_instance_route_rules "${protocol}" "${created_store}")" \
      '{inbounds:.,outbounds:[{type:"direct",tag:"direct"}],route:{rules:$rules,final:"direct"}}' \
      > "${TMP_DIR}/${protocol}-server.json"
  assert_equal "${protocol} rendered listener" \
    "$(jq -r '.inbounds[0].listen' "${TMP_DIR}/${protocol}-server.json")" '::'
  if [[ "${protocol}" == shadowtls ]]; then
    assert_equal 'ShadowTLS rendered private detour' \
      "$(jq -r '.inbounds[1].listen' "${TMP_DIR}/${protocol}-server.json")" 127.0.0.1
  fi
  check_core_config "${protocol} server" "${TMP_DIR}/${protocol}-server.json"
  id=$(jq -r '.id' "${record}")
  for retained_address in 0.0.0.0 127.0.0.1 2001:db8::8; do
    jq -n --arg protocol "${protocol}" --arg address "${retained_address}" --slurpfile record "${record}" \
      '{schema_version:1,protocol:$protocol,revision:1,default_instance_id:$record[0].id,
        instances:[$record[0] | .listen.address=$address]}' > "${snapshot}"
    plain_proxy_management_build_record "${protocol}" "${snapshot}" replace "${id}" "${record}" \
      > "${TMP_DIR}/record.stdout" 2> "${TMP_DIR}/record.stderr"
    assert_equal "${protocol} replacement preserves ${retained_address}" \
      "$(jq -r '.listen.address' "${record}")" "${retained_address}"
  done
done

# A dual-stack default still requires explicit public-exposure consent.
structured_instance_store_empty_json mixed > "${snapshot}"
TEST_PUBLIC_CONSENT=n
rm -f -- "${record}"
status=0
plain_proxy_management_build_record mixed "${snapshot}" create '' "${record}" \
  > "${TMP_DIR}/declined.stdout" 2> "${TMP_DIR}/declined.stderr" || status=$?
assert_equal 'declined public listener status' "${status}" 2
[[ ! -e "${record}" ]]

agent_capabilities_json > "${TMP_DIR}/capabilities.json"
assert_equal 'Mixed capability listener default' \
  "$(jq -r '.features.mixed_instances.default_new_listener' "${TMP_DIR}/capabilities.json")" '::'
assert_equal 'Plain-proxy capability listener default' \
  "$(jq -r '.features.plain_proxy_instances.default_new_listener' "${TMP_DIR}/capabilities.json")" '::'

if [[ -z "${SINGBOX_BINARY_114:-}" ]]; then
  printf 'sing-box check not run: set SINGBOX_BINARY_114 to the supported core\n'
fi
printf 'Default dual-stack listener checks passed (%s cases, %s sing-box checks)\n' \
  "${check_count}" "${core_check_count}"
