#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
REAL_BASH=$(command -v bash)
VALID_REALITY_PRIVATE_KEY="IEwVBb_qLcYr1L_CTI5exTWbT7qRgZnr43xP8nC0dkM"
VALID_REALITY_PUBLIC_KEY="u9nRBiDRTmyxLQLkiVq-kYFPhRyeZkSo8p9c7s8Dfjo"
trap 'rm -rf "${TMP_DIR}"' EXIT

REMOTE_PORT_FILE="${TMP_DIR}/remote-port"
REMOTE_UUID_FILE="${TMP_DIR}/remote-uuid"
REMOTE_SNI_FILE="${TMP_DIR}/remote-sni"
REMOTE_ROOT_DIR="${TMP_DIR}/remote-root"
REMOTE_CONFIG_FILE="${REMOTE_ROOT_DIR}/root/sing-box-vps/config.json"
REMOTE_LEGACY_KEY_FILE="${REMOTE_ROOT_DIR}/root/sing-box-vps/reality.key"
REMOTE_EXPORT_FILE="${REMOTE_ROOT_DIR}/root/sing-box-vps/client/sing-box-client.json"
REMOTE_LEGACY_SERVICE_FILE="${TMP_DIR}/legacy-sing-box.service"
REMOTE_PROTOCOLS_DIR="${REMOTE_ROOT_DIR}/root/sing-box-vps/protocols"
REMOTE_CONFIG_PRESENT_FILE="${TMP_DIR}/remote-config-present"
REMOTE_SERVICE_FILE_PRESENT_FILE="${TMP_DIR}/remote-service-file-present"
REMOTE_SBV_PRESENT_FILE="${TMP_DIR}/remote-sbv-present"
REMOTE_SERVICE_ACTIVE_FILE="${TMP_DIR}/remote-service-active"
REMOTE_STATE_FILE="${REMOTE_PROTOCOLS_DIR}/vless-reality.env"
REMOTE_INSTANCE_STATE_FILE="${REMOTE_PROTOCOLS_DIR}/vless-reality.d/main.env"
REMOTE_ANYTLS_STATE_FILE="${REMOTE_PROTOCOLS_DIR}/anytls.env"
REMOTE_INDEX_FILE="${REMOTE_PROTOCOLS_DIR}/index.env"
REMOTE_ASSERT_LOG_FILE="${TMP_DIR}/remote-assert.log"
INSTALL_COUNT_FILE="${TMP_DIR}/install-count"
INSTALL_VERSION_LINE=$(sed -n 's/^readonly SCRIPT_VERSION="[^"]*"$/&/p' "${REPO_ROOT}/install.sh" | head -n 1)

export REPO_ROOT TMP_DIR REAL_BASH
export REMOTE_PORT_FILE REMOTE_UUID_FILE REMOTE_SNI_FILE REMOTE_CONFIG_FILE
export REMOTE_LEGACY_KEY_FILE REMOTE_EXPORT_FILE REMOTE_LEGACY_SERVICE_FILE
export REMOTE_PROTOCOLS_DIR REMOTE_CONFIG_PRESENT_FILE REMOTE_SERVICE_FILE_PRESENT_FILE
export REMOTE_SBV_PRESENT_FILE REMOTE_SERVICE_ACTIVE_FILE REMOTE_STATE_FILE
export REMOTE_INSTANCE_STATE_FILE REMOTE_ANYTLS_STATE_FILE REMOTE_INDEX_FILE
export REMOTE_ASSERT_LOG_FILE INSTALL_COUNT_FILE

# Setup remote state files
printf '9443\n' > "${REMOTE_PORT_FILE}"
printf '11111111-1111-4111-8111-111111111111\n' > "${REMOTE_UUID_FILE}"
printf 'stale.example.com\n' > "${REMOTE_SNI_FILE}"
printf '1\n' > "${REMOTE_CONFIG_PRESENT_FILE}"
printf '1\n' > "${REMOTE_SERVICE_FILE_PRESENT_FILE}"
printf '1\n' > "${REMOTE_SBV_PRESENT_FILE}"
printf '1\n' > "${REMOTE_SERVICE_ACTIVE_FILE}"
: > "${REMOTE_ASSERT_LOG_FILE}"
printf '0\n' > "${INSTALL_COUNT_FILE}"
mkdir -p "$(dirname "${REMOTE_INSTANCE_STATE_FILE}")"

cat > "${REMOTE_STATE_FILE}" <<'STATE_EOF'
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main
REALITY_PUBLIC_KEY=public-key-from-state
STATE_EOF

cat > "${REMOTE_INSTANCE_STATE_FILE}" <<'STATE_EOF'
INSTANCE_ID=main
PORT=9443
UUID=11111111-1111-4111-8111-111111111111
SNI=stale.example.com
STATE_EOF

cat > "${REMOTE_INDEX_FILE}" <<'INDEX_EOF'
INSTALLED_PROTOCOLS=vless-reality
INDEX_EOF

cat > "${REMOTE_CONFIG_FILE}" <<'CONFIG_EOF'
{
  "inbounds": [
    {
      "type": "vless",
      "listen_port": 9443,
      "users": [{"uuid": "11111111-1111-4111-8111-111111111111", "flow": "xtls-rprx-vision"}],
      "tls": {"server_name": "stale.example.com", "reality": {"short_id": ["abcd1234"]}}
    }
  ]
}
CONFIG_EOF

printf '#!%s\n' "${REAL_BASH}" > "${TMP_DIR}/git"
cat >> "${TMP_DIR}/git" <<'GIT_EOF'
if [[ "$#" -eq 0 ]]; then exit 0; fi
if [[ "${1:-}" == "diff" && "${2:-}" == "--name-only" ]]; then
  if [[ -n "${VERIFY_EMPTY_CHANGES:-}" ]]; then exit 0; fi
  printf 'install.sh\nREADME.md\n'
  exit 0
fi
if [[ "${1:-}" == "ls-files" && "${2:-}" == "--others" && "${3:-}" == "--exclude-standard" ]]; then
  if [[ -n "${VERIFY_EMPTY_CHANGES:-}" ]]; then exit 0; fi
  printf 'tests/new_untracked_case.sh\n'
  exit 0
fi
printf 'unexpected git call: %s\n' "$*" >&2; exit 1
GIT_EOF
chmod +x "${TMP_DIR}/git"

printf '#!%s\n' "${REAL_BASH}" > "${TMP_DIR}/bash"
cat >> "${TMP_DIR}/bash" <<'BASH_EOF'
if [[ "${1:-}" == "${REPO_ROOT}/dev/verification/run.sh" ]]; then
  exec "${REAL_BASH}" "$@"
fi
if [[ "${1:-}" == tests/*.sh ]]; then
  printf '%s|%s\n' "$1" "${VERIFY_SKIP_LOCAL_TESTS:-unset}" >> "${TMP_DIR}/local-tests.log"
  exit 0
fi
exec "${REAL_BASH}" "$@"
BASH_EOF
chmod +x "${TMP_DIR}/bash"

printf '#!%s\n' "${REAL_BASH}" > "${TMP_DIR}/systemctl"
cat >> "${TMP_DIR}/systemctl" <<'SYS_EOF'
if [[ "${1:-}" == "is-active" && "${2:-}" == "--quiet" && "${3:-}" == "sing-box" ]]; then exit 0; fi
if [[ "${1:-}" == "is-active" && "${2:-}" == "sing-box" ]]; then printf 'active\n'; exit 0; fi
if [[ "${1:-}" == "status" && "${2:-}" == "sing-box" ]]; then printf 'status ok\n'; exit 0; fi
exit 0
SYS_EOF
chmod +x "${TMP_DIR}/systemctl"

printf '#!%s\n' "${REAL_BASH}" > "${TMP_DIR}/journalctl"
cat >> "${TMP_DIR}/journalctl" <<'JRN_EOF'
printf 'journal ok\n'
JRN_EOF
chmod +x "${TMP_DIR}/journalctl"

printf '#!%s\n' "${REAL_BASH}" > "${TMP_DIR}/sing-box"
cat >> "${TMP_DIR}/sing-box" <<'SB_EOF'
if [[ "${1:-}" == "check" && "${2:-}" == "-c" ]]; then
  printf 'config ok\n'; exit 0
fi
printf 'unexpected sing-box call: %s\n' "$*" >&2; exit 1
SB_EOF
chmod +x "${TMP_DIR}/sing-box"

printf '#!%s\n' "${REAL_BASH}" > "${TMP_DIR}/ss"
cat >> "${TMP_DIR}/ss" <<'SS_EOF'
printf 'LISTEN 0 0 127.0.0.1:%s 0.0.0.0:*\n' "$(cat "${REMOTE_PORT_FILE}")"
SS_EOF
chmod +x "${TMP_DIR}/ss"

### Mock docker: exec -i receives payload from stdin, runs it locally with path interception ###
printf '#!%s\n' "${REAL_BASH}" > "${TMP_DIR}/docker"
cat >> "${TMP_DIR}/docker" <<'DOCKER_EOF'

# docker image inspect
if [[ "${1:-}" == "image" && "${2:-}" == "inspect" ]]; then exit 0; fi

# docker run -d --privileged IMAGE
if [[ "${1:-}" == "run" && "${2:-}" == "-d" && "${3:-}" == "--privileged" ]]; then
  printf 'test-container\n'
  exit 0
fi

if [[ "${1:-}" == "exec" && "${3:-}" == "systemctl" && "${4:-}" == "is-system-running" ]]; then
  printf 'running\n'
  exit 0
fi

# docker exec -i CONTAINER bash -s -- SCENARIOS...
if [[ "${1:-}" == "exec" && "${2:-}" == "-i" ]]; then
  scenario_file="${TMP_DIR}/remote-script.sh"
  cat <<'PAYLOAD_PRELUDE' > "${scenario_file}"
VALID_REALITY_PRIVATE_KEY="IEwVBb_qLcYr1L_CTI5exTWbT7qRgZnr43xP8nC0dkM"
VALID_REALITY_PUBLIC_KEY="u9nRBiDRTmyxLQLkiVq-kYFPhRyeZkSo8p9c7s8Dfjo"

write_vless_state() {
  mkdir -p "$(dirname "${REMOTE_INSTANCE_STATE_FILE}")"
  cat > "${REMOTE_STATE_FILE}" <<STATE_EOF
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main
REALITY_PUBLIC_KEY=public-key-from-state
STATE_EOF
  cat > "${REMOTE_INSTANCE_STATE_FILE}" <<STATE_EOF
INSTANCE_ID=main
PORT=$(cat "${REMOTE_PORT_FILE}")
UUID=$(cat "${REMOTE_UUID_FILE}")
SNI=$(cat "${REMOTE_SNI_FILE}")
ALPN_MODE=off
TCP_FAST_OPEN=n
STATE_EOF
  cat > "${REMOTE_CONFIG_FILE}" <<CONFIG_EOF
{
  "inbounds": [
    {
      "type": "vless",
      "listen_port": $(cat "${REMOTE_PORT_FILE}"),
      "users": [{"uuid": "$(cat "${REMOTE_UUID_FILE}")", "flow": "xtls-rprx-vision"}],
      "tls": {"server_name": "$(cat "${REMOTE_SNI_FILE}")", "reality": {"short_id": ["abcd1234"]}}
    }
  ]
}
CONFIG_EOF
}

write_legacy_vless_state() {
  mkdir -p "$(dirname "${REMOTE_INSTANCE_STATE_FILE}")" "$(dirname "${REMOTE_EXPORT_FILE}")"
  cat > "${REMOTE_STATE_FILE}" <<STATE_EOF
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main
REALITY_PRIVATE_KEY=${VALID_REALITY_PRIVATE_KEY}
REALITY_PUBLIC_KEY=${VALID_REALITY_PUBLIC_KEY}
STATE_EOF
  cat > "${REMOTE_INSTANCE_STATE_FILE}" <<STATE_EOF
INSTANCE_ID=main
NODE_NAME=cc-us-stl+vless
PORT=$(cat "${REMOTE_PORT_FILE}")
UUID=$(cat "${REMOTE_UUID_FILE}")
SNI=$(cat "${REMOTE_SNI_FILE}")
ALPN_MODE=off
TCP_FAST_OPEN=n
STATE_EOF
  cat > "${REMOTE_INDEX_FILE}" <<'INDEX_EOF'
INSTALLED_PROTOCOLS=vless-reality
INDEX_EOF
  cat > "${REMOTE_CONFIG_FILE}" <<CONFIG_EOF
{
  "inbounds": [{
    "type": "vless",
    "listen_port": $(cat "${REMOTE_PORT_FILE}"),
    "users": [{"uuid": "$(cat "${REMOTE_UUID_FILE}")"}],
    "tls": {
      "server_name": "$(cat "${REMOTE_SNI_FILE}")",
      "reality": {
        "private_key": "${VALID_REALITY_PRIVATE_KEY}",
        "short_id": ["aaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbb"]
      }
    }
  }],
  "route": {"rules": []}
}
CONFIG_EOF
}

write_anytls_state() {
  mkdir -p "$(dirname "${REMOTE_ANYTLS_STATE_FILE}")"
  cat > "${REMOTE_ANYTLS_STATE_FILE}" <<'STATE_EOF'
PORT=9443
DOMAIN=anytls.example.com
PASSWORD=anytls-pass
USER_NAME=anytls-user
TLS_MODE=manual
STATE_EOF
  cat > "${REMOTE_CONFIG_FILE}" <<'CONFIG_EOF'
{
  "inbounds": [{
    "type": "anytls",
    "listen_port": 9443,
    "users": [{"name": "anytls-user", "password": "anytls-pass"}],
    "tls": {"server_name": "anytls.example.com"}
  }]
}
CONFIG_EOF
}

reset_runtime_artifacts() {
  printf '0\n' > "${REMOTE_CONFIG_PRESENT_FILE}"
  printf '0\n' > "${REMOTE_SERVICE_FILE_PRESENT_FILE}"
  printf '0\n' > "${REMOTE_SBV_PRESENT_FILE}"
  printf '0\n' > "${REMOTE_SERVICE_ACTIVE_FILE}"
}

# Path interception overrides
cp() {
  local args=("$@")
  local last_index=$(( $# - 1 ))
  local source_index=$(( $# - 2 ))
  if [[ "${args[$last_index]}" == "/root/sing-box-vps/protocols/index.env" ]]; then
    args[$last_index]="${REMOTE_INDEX_FILE}"
  fi
  if [[ "${args[$source_index]}" == "/root/sing-box-vps/client/sing-box-client.json" ]]; then
    args[$source_index]="${REMOTE_EXPORT_FILE}"
  fi
  command cp "${args[@]}"
}

sed() {
  local args=("$@")
  local last_index=$(( $# - 1 ))
  if [[ "${args[$last_index]:-}" == "/root/sing-box-vps/protocols/vless-reality.env" ]]; then
    args[$last_index]="${REMOTE_STATE_FILE}"
  fi
  if [[ "${args[$last_index]:-}" == "/root/sing-box-vps/protocols/vless-reality.d/main.env" ]]; then
    args[$last_index]="${REMOTE_INSTANCE_STATE_FILE}"
  fi
  if [[ "${args[$last_index]:-}" == "/root/sing-box-vps/protocols/anytls.env" ]]; then
    args[$last_index]="${REMOTE_ANYTLS_STATE_FILE}"
  fi
  if [[ "${args[$last_index]:-}" == "/root/sing-box-vps/protocols/index.env" ]]; then
    args[$last_index]="${REMOTE_INDEX_FILE}"
  fi
  command sed "${args[@]}"
}

grep() {
  local args=("$@")
  local last_index=$(( $# - 1 ))
  printf 'grep:%s\n' "$*" >> "${REMOTE_ASSERT_LOG_FILE}"
  if [[ "${args[$last_index]}" == "/root/sing-box-vps/protocols/vless-reality.env" ]]; then
    args[$last_index]="${REMOTE_STATE_FILE}"
  fi
  if [[ "${args[$last_index]}" == "/root/sing-box-vps/protocols/vless-reality.d/main.env" ]]; then
    args[$last_index]="${REMOTE_INSTANCE_STATE_FILE}"
  fi
  if [[ "${args[$last_index]}" == "/root/sing-box-vps/protocols/anytls.env" ]]; then
    args[$last_index]="${REMOTE_ANYTLS_STATE_FILE}"
  fi
  if [[ "${args[$last_index]}" == "/root/sing-box-vps/protocols/index.env" ]]; then
    args[$last_index]="${REMOTE_INDEX_FILE}"
  fi
  command grep "${args[@]}"
}
PAYLOAD_PRELUDE
  cat >> "${scenario_file}"
  cat > "${scenario_file}.wrapper" <<'WRAP_EOF'
eval "$(declare -f verification_capture_file_if_present | sed '1s/verification_capture_file_if_present/verification_capture_file_if_present__original/')"
verification_capture_file_if_present() {
  local source_path=$1
  local relative_path=$2
  local target_path
  target_path=$(verification_artifact_path "${relative_path}")
  if [[ -e "${target_path}" ]]; then
    return 0
  fi
  verification_capture_file_if_present__original "${source_path}" "${relative_path}"
}

eval "$(declare -f verification_capture_tree_if_present | sed '1s/verification_capture_tree_if_present/verification_capture_tree_if_present__original/')"
verification_capture_tree_if_present() {
  local source_path=$1
  local relative_path=$2
  local target_path="${VERIFY_ARTIFACT_DIR}/${relative_path}"
  if [[ -e "${target_path}" ]]; then
    return 0
  fi
  verification_capture_tree_if_present__original "${source_path}" "${relative_path}"
}

verification_fixture_write_file() {
  local path
  path=$(verification_artifact_path "$1")
  mkdir -p "$(dirname "${path}")"
  printf '%s\n' "$2" > "${path}"
}

verification_scenario_fresh_install_vless() {
  printf 'SCENARIO=fresh_install_vless\n'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/protocols/index.env" 'INSTALLED_PROTOCOLS=vless-reality'
  printf '%s\n' \
    'grep:-Fqx PORT=443 /root/sing-box-vps/protocols/vless-reality.d/main.env' \
    'grep:-Fqx SNI=www.cloudflare.com /root/sing-box-vps/protocols/vless-reality.d/main.env' \
    >> "${REMOTE_ASSERT_LOG_FILE}"
}

verification_scenario_reconfigure_existing_install() {
  printf 'SCENARIO=reconfigure_existing_install\n'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/config.diff.txt" 'fixture diff'
}

verification_scenario_legacy_takeover_export() {
  printf 'SCENARIO=legacy_takeover_export\n'
}

verification_scenario_fresh_install_anytls() {
  printf 'SCENARIO=fresh_install_anytls\n'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" 'config ok'
  printf '%s\n' 'grep:-Fqx DOMAIN=anytls.example.com /root/sing-box-vps/protocols/anytls.env' >> "${REMOTE_ASSERT_LOG_FILE}"
  printf '%s\n' 'PASSWORD=anytls-pass' > "${REMOTE_ANYTLS_STATE_FILE}"
}

verification_scenario_fresh_install_socks() {
  printf 'SCENARIO=fresh_install_socks\n'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/config.json" '{"inbounds":[{"type":"socks","listen_port":1081}]}'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/protocols/instances/socks.json" '{"schema_version":1,"protocol":"socks","revision":1}'
}

verification_scenario_fresh_install_http() {
  printf 'SCENARIO=fresh_install_http\n'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/config.json" '{"inbounds":[{"type":"http","listen_port":1082}]}'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/protocols/instances/http.json" '{"schema_version":1,"protocol":"http","revision":1}'
}

verification_scenario_fresh_install_shadowsocks() {
  printf 'SCENARIO=fresh_install_shadowsocks\n'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/config.json" '{"inbounds":[{"type":"shadowsocks","listen_port":1083,"network":["tcp","udp"]}]}'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/protocols/instances/shadowsocks.json" '{"schema_version":1,"protocol":"shadowsocks","revision":1}'
}

verification_scenario_fresh_install_trojan() {
  printf 'SCENARIO=fresh_install_trojan\n'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/config.json" '{"inbounds":[{"type":"trojan","tag":"trojan-in","listen":"127.0.0.1","listen_port":1084,"users":[{"name":"trojan-user","password":"trojan-pass"}],"tls":{"enabled":true,"server_name":"trojan.example"}}]}'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/protocols/trojan.env" $'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/protocols/instances/trojan.json" '{"schema_version":1,"protocol":"trojan","revision":1,"default_instance_id":"main","instances":[{"id":"main","name":"Trojan verification","tag":"trojan-in","listen":{"address":"127.0.0.1","port":1084},"authentication":{"users":[{"name":"trojan-user","password":"trojan-pass"}]},"tls":{"enabled":true,"server_name":"trojan.example"},"transport":{"type":"none"},"client_trust":"certificate","outbound_policy":"default","dependencies":[]}]}'
}

verification_scenario_fresh_install_vmess() {
  printf 'SCENARIO=fresh_install_vmess\n'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/config.json" '{"inbounds":[{"type":"vmess","tag":"vmess-in","listen":"127.0.0.1","listen_port":1085,"users":[{"name":"vmess-user","uuid":"11111111-1111-4111-8111-111111111111","alterId":0,"security":"auto"}],"tls":{"enabled":true,"server_name":"vmess.example"}}]}'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/protocols/vmess.env" $'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/protocols/instances/vmess.json" '{"schema_version":1,"protocol":"vmess","revision":1,"default_instance_id":"main","instances":[{"id":"main","name":"VMess verification","tag":"vmess-in","listen":{"address":"127.0.0.1","port":1085},"authentication":{"users":[{"name":"vmess-user","uuid":"11111111-1111-4111-8111-111111111111","alter_id":0,"security":"auto"}]},"tls":{"enabled":true,"server_name":"vmess.example"},"client_trust":"certificate","transport":{"type":"none"},"outbound_policy":"default","dependencies":[]}]}'
}

verification_scenario_fresh_install_hysteria() {
  printf 'SCENARIO=fresh_install_hysteria\n'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/config.json" '{"inbounds":[{"type":"hysteria","tag":"hysteria-in","listen":"127.0.0.1","listen_port":1086,"users":[{"name":"hysteria-user","auth_str":"hysteria-verification-auth"}],"tls":{"enabled":true,"server_name":"hysteria.verification.invalid","alpn":["h3"]},"up_mbps":100,"down_mbps":100}]}'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/protocols/hysteria.env" $'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/protocols/instances/hysteria.json" '{"schema_version":1,"protocol":"hysteria","revision":1,"default_instance_id":"main","instances":[{"id":"main","name":"Hysteria verification","tag":"hysteria-in","listen":{"address":"127.0.0.1","port":1086},"authentication":{"users":[{"name":"hysteria-user","auth_str":"hysteria-verification-auth"}]},"tls":{"enabled":true,"server_name":"hysteria.verification.invalid","certificate_path":"/tmp/sing-box-vps-verification-hysteria.crt","key_path":"/tmp/sing-box-vps-verification-hysteria.key"},"bandwidth":{"up_mbps":100,"down_mbps":100},"obfs":{"enabled":false,"password":""},"hysteria":{"connection_receive_window":"","disable_path_mtu_discovery":false,"initial_packet_size":0,"max_concurrent_streams":0,"stream_receive_window":""},"client_trust":"system","outbound_policy":"default","dependencies":[]}]}'
}

verification_scenario_fresh_install_vless_plain() {
  printf 'SCENARIO=fresh_install_vless_plain\n'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/config.json" '{"inbounds":[{"type":"vless","tag":"vless-plain-in","listen":"127.0.0.1","listen_port":1086,"users":[{"name":"probe","uuid":"11111111-1111-4111-8111-111111111111"}]}]}'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/protocols/vless-plain.env" $'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/protocols/instances/vless-plain.json" '{"schema_version":1,"protocol":"vless-plain","revision":1,"default_instance_id":"main","instances":[{"id":"main","name":"VLESS verification","tag":"vless-plain-in","listen":{"address":"127.0.0.1","port":1086},"authentication":{"users":[{"name":"probe","uuid":"11111111-1111-4111-8111-111111111111","flow":""}]},"tls":{"enabled":false},"client_trust":"system","transport":{"type":"none"},"outbound_policy":"default","dependencies":[]}]}'
}

verification_scenario_upgrade_1_13_to_1_14() {
  printf 'SCENARIO=upgrade_1_13_to_1_14\n'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/upgrade.json" '{"ok":true,"installed":"1.14.2","transaction":{"status":"success","result_persisted":true}}'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/transaction-result.json" '{"schema_version":"1.0","status":"success"}'
}

verification_scenario_multi_protocol_coexistence() {
  printf 'SCENARIO=multi_protocol_coexistence\n'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/config.json" 'eight protocol config fixture'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/protocols/index.env" 'INSTALLED_PROTOCOLS=vless-reality,mixed,hy2,anytls,socks,http,shadowsocks,trojan'
}

verification_scenario_upgrade_rollback_1_13_to_1_14() {
  printf 'SCENARIO=upgrade_rollback_1_13_to_1_14\n'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/upgrade.json" '{"rolled_back":true,"installed":"1.13.18"}'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/config.before.sha256" 'before-config-hash'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/config.after.sha256" 'before-config-hash'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/service.before.sha256" 'before-service-hash'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/service.after.sha256" 'before-service-hash'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/after.version.txt" 'sing-box version 1.13.18'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/systemctl.status.txt" 'active'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/transaction-result.json" '{"schema_version":"1.0","status":"rolled_back"}'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/after-rollback.check.txt" 'config ok'
}

verification_scenario_runtime_smoke() {
  printf 'SCENARIO=runtime_smoke\n'
  verification_fixture_write_file "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" 'config ok'
}
WRAP_EOF
  awk -v wrapper_file="${scenario_file}.wrapper" '
    $0 == "if ! mkdir \"${LOCK_DIR}\" 2>/dev/null; then" {
      while ((getline line < wrapper_file) > 0) {
        print line
      }
      close(wrapper_file)
    }
    { print }
  ' "${scenario_file}" > "${scenario_file}.tmp"
  mv "${scenario_file}.tmp" "${scenario_file}"
  REMOTE_CONFIG_PRESENT_FILE="${REMOTE_CONFIG_PRESENT_FILE}" \
  REMOTE_PORT_FILE="${REMOTE_PORT_FILE}" \
  REMOTE_UUID_FILE="${REMOTE_UUID_FILE}" \
  REMOTE_SNI_FILE="${REMOTE_SNI_FILE}" \
  REMOTE_INSTANCE_STATE_FILE="${REMOTE_INSTANCE_STATE_FILE}" \
  REMOTE_SERVICE_FILE_PRESENT_FILE="${REMOTE_SERVICE_FILE_PRESENT_FILE}" \
  REMOTE_SBV_PRESENT_FILE="${REMOTE_SBV_PRESENT_FILE}" \
  REMOTE_SERVICE_ACTIVE_FILE="${REMOTE_SERVICE_ACTIVE_FILE}" \
  REMOTE_CONFIG_FILE="${REMOTE_CONFIG_FILE}" \
  VERIFY_LEGACY_CONFIG_FILE="${REMOTE_CONFIG_FILE}" \
  VERIFY_LEGACY_KEY_FILE="${REMOTE_LEGACY_KEY_FILE}" \
  VERIFY_LEGACY_SERVICE_FILE="${REMOTE_LEGACY_SERVICE_FILE}" \
  REMOTE_EXPORT_FILE="${REMOTE_EXPORT_FILE}" \
  REMOTE_PROTOCOLS_DIR="${REMOTE_PROTOCOLS_DIR}" \
  REMOTE_STATE_FILE="${REMOTE_STATE_FILE}" \
  REMOTE_ANYTLS_STATE_FILE="${REMOTE_ANYTLS_STATE_FILE}" \
  REMOTE_INDEX_FILE="${REMOTE_INDEX_FILE}" \
  REMOTE_ASSERT_LOG_FILE="${REMOTE_ASSERT_LOG_FILE}" \
  INSTALL_COUNT_FILE="${INSTALL_COUNT_FILE}" \
  PATH="${TMP_DIR}:$PATH" "${REAL_BASH}" "${scenario_file}" "${@:7}"
  exit $?
fi

# docker rm -f
if [[ "${1:-}" == "rm" && "${2:-}" == "-f" ]]; then exit 0; fi
printf 'unexpected docker call: %s\n' "$*" >&2; exit 1
DOCKER_EOF
chmod +x "${TMP_DIR}/docker"

# Run the verification
env -u VERIFY_SKIP_LOCAL_TESTS \
  PATH="${TMP_DIR}:${PATH}" \
  bash "${REPO_ROOT}/dev/verification/run.sh" > "${TMP_DIR}/stdout.txt"

run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout.txt")
# Check changed files
grep -Fqx 'install.sh' "${run_dir}/changed-files.txt"
grep -Fqx 'README.md' "${run_dir}/changed-files.txt"
grep -Fqx 'tests/new_untracked_case.sh' "${run_dir}/changed-files.txt"

# Check scenarios
scenarios=$(paste -sd, "${run_dir}/scenarios.txt")
[[ "${scenarios}" == "fresh_install_vless,reconfigure_existing_install,legacy_takeover_export,fresh_install_anytls,fresh_install_socks,fresh_install_http,fresh_install_shadowsocks,fresh_install_trojan,fresh_install_vmess,fresh_install_hysteria,fresh_install_vless_plain,multi_protocol_coexistence,upgrade_1_13_to_1_14,upgrade_rollback_1_13_to_1_14,runtime_smoke" ]] || {
  printf 'unexpected scenarios: %s\n' "${scenarios}" >&2; exit 1
}

# Check stdout.log from remote execution
grep -Fq 'SCENARIO=runtime_smoke' "${run_dir}/remote.stdout.log"
grep -Fq 'remote_target=docker:test-container' "${run_dir}/summary.log"
grep -Fq 'remote_target=docker:test-container' "${TMP_DIR}/stdout.txt"

# Check extracted artifacts
[[ -d "${run_dir}/remote-artifacts/scenarios/fresh_install_vless" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_vless/protocols/index.env" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_vless/listeners.ss-lntp.txt" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/reconfigure_existing_install/config.diff.txt" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_anytls/sing-box-check.txt" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_socks/config.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_socks/protocols/instances/socks.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_http/config.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_http/protocols/instances/http.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_shadowsocks/config.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_shadowsocks/protocols/instances/shadowsocks.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_trojan/config.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_trojan/protocols/trojan.env" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_trojan/protocols/instances/trojan.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_vmess/config.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_vmess/protocols/vmess.env" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_vmess/protocols/instances/vmess.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_vless_plain/config.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_vless_plain/protocols/vless-plain.env" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_vless_plain/protocols/instances/vless-plain.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/upgrade_1_13_to_1_14/result.env" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/upgrade_1_13_to_1_14/upgrade.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/upgrade_1_13_to_1_14/transaction-result.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/multi_protocol_coexistence/config.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/multi_protocol_coexistence/protocols/index.env" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/upgrade_rollback_1_13_to_1_14/upgrade.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/upgrade_rollback_1_13_to_1_14/config.before.sha256" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/upgrade_rollback_1_13_to_1_14/config.after.sha256" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/upgrade_rollback_1_13_to_1_14/service.before.sha256" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/upgrade_rollback_1_13_to_1_14/service.after.sha256" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/upgrade_rollback_1_13_to_1_14/after.version.txt" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/upgrade_rollback_1_13_to_1_14/systemctl.status.txt" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/upgrade_rollback_1_13_to_1_14/transaction-result.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/upgrade_rollback_1_13_to_1_14/after-rollback.check.txt" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/sing-box-check.txt" ]]

# Check payload content (script vars are in emitted payload)
grep -Fq "${INSTALL_VERSION_LINE}" "${TMP_DIR}/remote-script.sh"

grep -Fq 'remote_artifacts=extracted' "${run_dir}/summary.log"

# Check grep assertions from scenario execution
grep -Fqx 'grep:-Fqx PORT=443 /root/sing-box-vps/protocols/vless-reality.d/main.env' "${REMOTE_ASSERT_LOG_FILE}"
grep -Fqx 'grep:-Fqx SNI=www.cloudflare.com /root/sing-box-vps/protocols/vless-reality.d/main.env' "${REMOTE_ASSERT_LOG_FILE}"
grep -Fqx 'grep:-Fqx DOMAIN=anytls.example.com /root/sing-box-vps/protocols/anytls.env' "${REMOTE_ASSERT_LOG_FILE}"
grep -Fqx 'PASSWORD=anytls-pass' "${REMOTE_ANYTLS_STATE_FILE}"

# Check local test routing
grep -Fqx 'tests/protocol_registry_contract.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/protocol_instance_adapter.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/structured_instance_store.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/managed_listener_resources.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/listener_network_selection.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/firewall_listener_references.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/mixed_active_state.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/mixed_instance_lifecycle.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/mixed_instance_lifecycle_runtime.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/mixed_structured_takeover.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/instance_firewall_ledger.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/mixed_instance_menu.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/plain_proxy_structured_store.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/socks_instance_lifecycle.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/socks_instance_lifecycle_runtime.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/socks_instance_menu.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/socks_structured_takeover.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/socks_export_client.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/plain_proxy_share_links.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/plain_proxy_share_runtime.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/http_structured_instance_store.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/http_structured_takeover.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/http_instance_lifecycle.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/http_instance_menu.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/http_export_client.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/http_export_runtime.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/http_agent_contract.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_protocol_probe_http.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_protocol_probe_matrix.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_protocol_probe_vless.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_protocol_probe_hy2.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_protocol_probe_hysteria.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_protocol_probe_tuic.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_protocol_probe_udp.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_protocol_probe_anytls.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/reality_sni_validation.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/generate_config_cleans_temp_files_on_failure.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/generate_config_commits_validated_candidate.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/managed_component_graph.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/managed_component_graph_core_startup.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/live_inbound_inventory_guards.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/export_client_config_validates_generated_config.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/export_client_config_mixed_only.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/export_client_config_mixed_auth.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/export_client_config_mixed_runtime.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/managed_config_transactions.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/system_safety_guards.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/agent_upgrade_commands.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/agent_cli_multi_instance_status.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/agent_cli_ops_commands.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/agent_cli_outputs_machine_readable_node_info.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/agent_json_regression.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/export_client_config_1_14_compatibility.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/agent_docs_cover_capabilities.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/version_metadata_is_consistent.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/vless_reality_instance_removal.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/install_takeover_rebuilds_protocol_state_from_config.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/install_takeover_rebuilds_vless_reality_instances.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/detect_existing_instance_auto_heals_managed_config_drift.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/update_keeps_existing_config.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/update_rolls_back_binary_when_config_invalid.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/update_rolls_back_binary_when_restart_fails.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/subman_config_helpers.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/subman_payload_generation.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/subman_api_push.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/subman_sync_orchestration.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/anytls_structured_instance_store.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/anytls_structured_takeover.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/anytls_instance_lifecycle.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/anytls_agent_share.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/anytls_export_runtime.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/snell_instance_lifecycle.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/tuic_instance_lifecycle.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/hysteria_instance_lifecycle.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/naive_instance_lifecycle.sh|1' "${TMP_DIR}/local-tests.log"

default_local_test_count=$(wc -l < "${TMP_DIR}/local-tests.log")
expected_local_test_count=$(bash -c 'source "$1"; resolve_local_tests install.sh | wc -l' _ "${REPO_ROOT}/dev/verification/common.sh")
[[ "${default_local_test_count}" -eq "${expected_local_test_count}" ]] || {
  printf 'expected %d local tests, got %d\n' "${expected_local_test_count}" "${default_local_test_count}" >&2; exit 1
}

# Test VERIFY_SKIP_LOCAL_TESTS=1 — still runs remote
PATH="${TMP_DIR}:${PATH}" VERIFY_SKIP_LOCAL_TESTS=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" > "${TMP_DIR}/stdout-skip.txt"

run_dir_skip=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout-skip.txt")
grep -Fqx 'install.sh' "${run_dir_skip}/changed-files.txt"
grep -Fqx 'README.md' "${run_dir_skip}/changed-files.txt"
grep -Fqx 'tests/new_untracked_case.sh' "${run_dir_skip}/changed-files.txt"
scenarios_skip=$(paste -sd, "${run_dir_skip}/scenarios.txt")
[[ "${scenarios_skip}" == "fresh_install_vless,reconfigure_existing_install,legacy_takeover_export,fresh_install_anytls,fresh_install_socks,fresh_install_http,fresh_install_shadowsocks,fresh_install_trojan,fresh_install_vmess,fresh_install_hysteria,fresh_install_vless_plain,multi_protocol_coexistence,upgrade_1_13_to_1_14,upgrade_rollback_1_13_to_1_14,runtime_smoke" ]] || {
  printf 'unexpected scenarios for skip run: %s\n' "${scenarios_skip}" >&2; exit 1
}
skip_local_test_count=$(wc -l < "${TMP_DIR}/local-tests.log")
[[ "${skip_local_test_count}" -eq "${default_local_test_count}" ]] || {
  printf 'expected skip run count to match default: before=%s after=%s\n' "${default_local_test_count}" "${skip_local_test_count}" >&2; exit 1
}

# Test VERIFY_SKIP_REMOTE=1 — runs local tests only
env -u VERIFY_SKIP_LOCAL_TESTS \
  PATH="${TMP_DIR}:${PATH}" VERIFY_SKIP_REMOTE=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" \
  --changed-file dev/verification/remote/entrypoint.sh > "${TMP_DIR}/stdout-remote-framework.txt"

run_dir_remote_framework=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout-remote-framework.txt")
scenarios_remote_framework=$(paste -sd, "${run_dir_remote_framework}/scenarios.txt")
[[ "${scenarios_remote_framework}" == "fresh_install_vless,reconfigure_existing_install,legacy_takeover_export,fresh_install_anytls,fresh_install_socks,fresh_install_http,fresh_install_shadowsocks,fresh_install_trojan,fresh_install_vmess,fresh_install_hysteria,fresh_install_vless_plain,multi_protocol_coexistence,upgrade_1_13_to_1_14,upgrade_rollback_1_13_to_1_14,runtime_smoke,uninstall_and_reinstall" ]] || {
  printf 'unexpected scenarios for remote framework change: %s\n' "${scenarios_remote_framework}" >&2; exit 1
}
grep -Fqx 'tests/verification_artifact_dir_layout.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_trigger_rules.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_scenario_mapping.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_requires_remote_env.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_remote_target_file_alias.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_stops_on_remote_failure.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_run_writes_changed_files.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_tests_only_stays_local.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_runtime_smoke_artifacts.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_remote_scenario_dispatch.sh|1' "${TMP_DIR}/local-tests.log"

# Test empty changes (local mode)
PATH="${TMP_DIR}:${PATH}" VERIFY_SKIP_LOCAL_TESTS=1 VERIFY_EMPTY_CHANGES=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" > "${TMP_DIR}/stdout-empty.txt"

run_dir_empty=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout-empty.txt")
[[ ! -s "${run_dir_empty}/changed-files.txt" ]] || { printf 'expected empty change snapshot\n' >&2; exit 1; }
[[ ! -e "${run_dir_empty}/scenarios.txt" ]] || { printf 'did not expect scenarios.txt for local mode\n' >&2; exit 1; }

printf 'All assertions passed\n'
