#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
REAL_BASH=$(command -v bash)
REAL_JQ=$(command -v jq)
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
REMOTE_MIXED_STATE_FILE="${REMOTE_PROTOCOLS_DIR}/mixed.env"
REMOTE_HY2_STATE_FILE="${REMOTE_PROTOCOLS_DIR}/hy2.env"
REMOTE_ANYTLS_STATE_FILE="${REMOTE_PROTOCOLS_DIR}/anytls.env"
REMOTE_SOCKS_STATE_FILE="${REMOTE_PROTOCOLS_DIR}/socks.env"
REMOTE_SOCKS_STORE_FILE="${REMOTE_PROTOCOLS_DIR}/instances/socks.json"
REMOTE_HTTP_STATE_FILE="${REMOTE_PROTOCOLS_DIR}/http.env"
REMOTE_HTTP_STORE_FILE="${REMOTE_PROTOCOLS_DIR}/instances/http.json"
REMOTE_SHADOWSOCKS_STATE_FILE="${REMOTE_PROTOCOLS_DIR}/shadowsocks.env"
REMOTE_SHADOWSOCKS_STORE_FILE="${REMOTE_PROTOCOLS_DIR}/instances/shadowsocks.json"
REMOTE_TROJAN_STATE_FILE="${REMOTE_PROTOCOLS_DIR}/trojan.env"
REMOTE_TROJAN_STORE_FILE="${REMOTE_PROTOCOLS_DIR}/instances/trojan.json"
REMOTE_HYSTERIA_STATE_FILE="${REMOTE_PROTOCOLS_DIR}/hysteria.env"
REMOTE_HYSTERIA_STORE_FILE="${REMOTE_PROTOCOLS_DIR}/instances/hysteria.json"
REMOTE_VLESS_PLAIN_STATE_FILE="${REMOTE_PROTOCOLS_DIR}/vless-plain.env"
REMOTE_VLESS_PLAIN_STORE_FILE="${REMOTE_PROTOCOLS_DIR}/instances/vless-plain.json"
REMOTE_INDEX_FILE="${REMOTE_PROTOCOLS_DIR}/index.env"
REMOTE_ASSERT_LOG_FILE="${TMP_DIR}/remote-assert.log"
REMOTE_DISPATCH_LOG_FILE="${TMP_DIR}/remote-dispatch.log"
INSTALL_COUNT_FILE="${TMP_DIR}/install-count"
INSTALL_VERSION_LINE=$(sed -n 's/^readonly SCRIPT_VERSION=\"[^\"]*\"$/&/p' "${REPO_ROOT}/install.sh" | head -n 1)
UNINSTALL_HELPER_LINE=$(sed -n 's/^resolve_install_script() {$/&/p' "${REPO_ROOT}/uninstall.sh" | head -n 1)

printf '9443\n' > "${REMOTE_PORT_FILE}"
printf '11111111-1111-4111-8111-111111111111\n' > "${REMOTE_UUID_FILE}"
printf 'stale.example.com\n' > "${REMOTE_SNI_FILE}"
printf '1\n' > "${REMOTE_CONFIG_PRESENT_FILE}"
printf '1\n' > "${REMOTE_SERVICE_FILE_PRESENT_FILE}"
printf '1\n' > "${REMOTE_SBV_PRESENT_FILE}"
printf '1\n' > "${REMOTE_SERVICE_ACTIVE_FILE}"
: > "${REMOTE_ASSERT_LOG_FILE}"
: > "${REMOTE_DISPATCH_LOG_FILE}"
printf '0\n' > "${INSTALL_COUNT_FILE}"
mkdir -p "$(dirname "${REMOTE_INSTANCE_STATE_FILE}")"
cat > "${REMOTE_STATE_FILE}" <<'EOF'
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main
REALITY_PUBLIC_KEY=public-key-from-state
EOF
cat > "${REMOTE_INSTANCE_STATE_FILE}" <<'EOF'
INSTANCE_ID=main
PORT=9443
UUID=11111111-1111-4111-8111-111111111111
SNI=stale.example.com
EOF
cat > "${REMOTE_HY2_STATE_FILE}" <<'EOF'
DOMAIN=hy2.example.com
PASSWORD=hy2-password
OBFS_PASSWORD=hy2-obfs-password
EOF
cat > "${REMOTE_ANYTLS_STATE_FILE}" <<'EOF'
PORT=9443
DOMAIN=anytls.example.com
PASSWORD=anytls-pass
USER_NAME=anytls-user
TLS_MODE=manual
EOF
cat > "${REMOTE_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality
EOF
cat > "${REMOTE_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "vless",
      "listen_port": 9443,
      "users": [
        {
          "uuid": "11111111-1111-4111-8111-111111111111",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "server_name": "stale.example.com",
        "reality": {
          "short_id": [
            "abcd1234"
          ]
        }
      }
    }
  ]
}
EOF

cat > "${TMP_DIR}/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "is-active" && "${2:-}" == "--quiet" && "${3:-}" == "sing-box" ]]; then
  exit 0
fi
if [[ "${1:-}" == "is-active" && "${2:-}" == "sing-box" ]]; then
  printf 'active\n'
  exit 0
fi
if [[ "${1:-}" == "status" && "${2:-}" == "sing-box" ]]; then
  printf 'status ok\n'
  exit 0
fi
exit 0
EOF
chmod +x "${TMP_DIR}/systemctl"

cat > "${TMP_DIR}/journalctl" <<'EOF'
#!/usr/bin/env bash
printf 'journal ok\n'
EOF
chmod +x "${TMP_DIR}/journalctl"

cat > "${TMP_DIR}/sing-box" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  version)
    case "${VERIFY_CURRENT_SCENARIO:-}" in
      upgrade_rollback_1_13_to_1_14) printf 'sing-box version 1.13.18\n' ;;
      upgrade_1_13_to_1_14) printf 'sing-box version 1.14.0\n' ;;
      *) printf 'sing-box version 1.14.1\n' ;;
    esac
    exit 0
    ;;
  check)
    if [[ "${VERIFY_FAIL_SINGBOX_CHECK:-0}" == "1" ]]; then
      printf 'config broken\n' >&2
      exit 7
    fi
    printf 'config ok\n'
    exit 0
    ;;
  run)
    printf '%s\n' "${BASHPID}" > "${REMOTE_PROBE_CLIENT_PID_FILE:?}"
    exec tail -f /dev/null
    ;;
  *)
    printf 'unexpected sing-box call: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "${TMP_DIR}/sing-box"

cat > "${TMP_DIR}/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${VERIFY_PROTOCOL_PROBE_EXPECTED_MARKER:?}"
EOF
chmod +x "${TMP_DIR}/curl"

cat > "${TMP_DIR}/python3" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${BASHPID}" > "${REMOTE_PROBE_HTTP_PID_FILE:?}"
exec /usr/bin/python3 "$@"
EOF
chmod +x "${TMP_DIR}/python3"

cat > "${TMP_DIR}/ss" <<'EOF'
#!/usr/bin/env bash
if grep -Fqx 'INSTALLED_PROTOCOLS=hysteria' "${REMOTE_INDEX_FILE}" 2>/dev/null; then
  printf 'UNCONN 0 0 127.0.0.1:%s 0.0.0.0:*\n' "$(cat "${REMOTE_PORT_FILE}")"
else
  printf 'LISTEN 0 0 127.0.0.1:%s 0.0.0.0:*\n' "$(cat "${REMOTE_PORT_FILE}")"
fi
if [[ -s "${REMOTE_PROBE_CLIENT_PID_FILE:?}" ]] && kill -0 "$(cat "${REMOTE_PROBE_CLIENT_PID_FILE}")" 2>/dev/null; then
  printf 'LISTEN 0 0 127.0.0.1:19080 0.0.0.0:*\n'
fi
EOF
chmod +x "${TMP_DIR}/ss"

cat > "${TMP_DIR}/docker" <<DOCKER_EOF
#!${REAL_BASH}
if [[ "\${1:-}" == "image" && "\${2:-}" == "inspect" ]]; then
  exit 0
fi
if [[ "\${1:-}" == "run" && "\${2:-}" == "-d" && "\${3:-}" == "--privileged" ]]; then
  printf 'test-container\n'
  exit 0
fi
if [[ "\${1:-}" == "exec" && "\${3:-}" == "systemctl" && "\${4:-}" == "is-system-running" ]]; then
  printf 'running\n'
  exit 0
fi
if [[ "\${1:-}" == "exec" && "\${2:-}" == "-i" ]]; then
script_file="${TMP_DIR}/remote-script.sh"
cat <<'PAYLOAD_PRELUDE' > "\${script_file}"
VALID_REALITY_PRIVATE_KEY="IEwVBb_qLcYr1L_CTI5exTWbT7qRgZnr43xP8nC0dkM"
VALID_REALITY_PUBLIC_KEY="u9nRBiDRTmyxLQLkiVq-kYFPhRyeZkSo8p9c7s8Dfjo"

write_hy2_state() {
  mkdir -p "\$(dirname "\${REMOTE_HY2_STATE_FILE}")"
  cat > "\${REMOTE_HY2_STATE_FILE}" <<'STATE_EOF'
DOMAIN=hy2.example.com
PASSWORD=hy2-password
OBFS_PASSWORD=hy2-obfs-password
STATE_EOF
}

write_mixed_state() {
  mkdir -p "\$(dirname "\${REMOTE_MIXED_STATE_FILE}")"
  cat > "\${REMOTE_MIXED_STATE_FILE}" <<'STATE_EOF'
AUTH_ENABLED=y
USERNAME=mixed-user
PASSWORD=mixed-pass
STATE_EOF
}

write_anytls_state() {
  mkdir -p "\$(dirname "\${REMOTE_ANYTLS_STATE_FILE}")"
  cat > "\${REMOTE_ANYTLS_STATE_FILE}" <<'STATE_EOF'
PORT=9443
DOMAIN=anytls.example.com
PASSWORD=anytls-pass
USER_NAME=anytls-user
TLS_MODE=manual
STATE_EOF
}

write_socks_state() {
  mkdir -p "\$(dirname "\${REMOTE_SOCKS_STORE_FILE}")"
  cat > "\${REMOTE_SOCKS_STATE_FILE}" <<'STATE_EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
STATE_EOF
  cat > "\${REMOTE_SOCKS_STORE_FILE}" <<'STATE_EOF'
{
  "schema_version": 1,
  "protocol": "socks",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [{
    "id": "main",
    "name": "SOCKS verification",
    "tag": "socks-in",
    "listen": {"address": "127.0.0.1", "port": 1081},
    "authentication": {"enabled": true, "username": "socks-user", "password": "socks-pass"},
    "outbound_policy": "default",
    "dependencies": []
  }]
}
STATE_EOF
}

write_http_state() {
  mkdir -p "$(dirname "${REMOTE_HTTP_STORE_FILE}")"
  cat > "${REMOTE_HTTP_STATE_FILE}" <<'STATE_EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
STATE_EOF
  cat > "${REMOTE_HTTP_STORE_FILE}" <<'STATE_EOF'
{
  "schema_version": 1,
  "protocol": "http",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [{
    "id": "main",
    "name": "HTTP verification",
    "tag": "http-in",
    "listen": {"address": "127.0.0.1", "port": 1082},
    "authentication": {"enabled": true, "username": "http-user", "password": "http-pass"},
    "outbound_policy": "default",
    "tls": {"enabled": false},
    "dependencies": []
  }]
}
STATE_EOF
}

write_shadowsocks_state() {
  mkdir -p "$(dirname "${REMOTE_SHADOWSOCKS_STORE_FILE}")"
  cat > "${REMOTE_SHADOWSOCKS_STATE_FILE}" <<'STATE_EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
STATE_EOF
  cat > "${REMOTE_SHADOWSOCKS_STORE_FILE}" <<'STATE_EOF'
{
  "schema_version": 1,
  "protocol": "shadowsocks",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [{
    "id": "main",
    "name": "Shadowsocks verification",
    "tag": "ss-in",
    "listen": {"address": "127.0.0.1", "port": 1083, "network": ["tcp", "udp"]},
    "authentication": {"method": "2022-blake3-aes-128-gcm", "password": "MDEyMzQ1Njc4OWFiY2RlZg==", "users": []},
    "outbound_policy": "default",
    "dependencies": []
  }]
}
STATE_EOF
}

write_trojan_state() {
  mkdir -p "\$(dirname "\${REMOTE_TROJAN_STORE_FILE}")"
  cat > "\${REMOTE_TROJAN_STATE_FILE}" <<'STATE_EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
STATE_EOF
  cat > "\${REMOTE_TROJAN_STORE_FILE}" <<'STATE_EOF'
{
  "schema_version": 1,
  "protocol": "trojan",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [{
    "id": "main",
    "name": "Trojan verification",
    "tag": "trojan-in",
    "listen": {"address": "127.0.0.1", "port": 1084},
    "authentication": {"users": [{"name": "trojan-user", "password": "trojan-pass"}]},
    "tls": {"enabled": true, "server_name": "trojan.example",
      "certificate_path": "/root/sing-box-vps/trojan.crt",
      "key_path": "/root/sing-box-vps/trojan.key"},
    "client_trust": "system",
    "transport": {"type": "quic"},
    "outbound_policy": "default",
    "dependencies": []
  }]
}
STATE_EOF
}

write_hysteria_state() {
  mkdir -p "\$(dirname "\${REMOTE_HYSTERIA_STORE_FILE}")"
  cat > "\${REMOTE_HYSTERIA_STATE_FILE}" <<'STATE_EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
STATE_EOF
  cat > "\${REMOTE_HYSTERIA_STORE_FILE}" <<'STATE_EOF'
{
  "schema_version": 1,
  "protocol": "hysteria",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [{
    "id": "main",
    "name": "Hysteria verification",
    "tag": "hysteria-in",
    "listen": {"address": "127.0.0.1", "port": 1086},
    "authentication": {"users": [{"name": "hysteria-user", "auth_str": "hysteria-verification-auth"}]},
    "tls": {"enabled": true, "server_name": "hysteria.verification.invalid",
      "certificate_path": "/tmp/sing-box-vps-verification-hysteria.crt",
      "key_path": "/tmp/sing-box-vps-verification-hysteria.key"},
    "client_trust": "certificate",
    "bandwidth": {"up_mbps": 100, "down_mbps": 100},
    "obfs": {"enabled": false, "password": ""},
    "hysteria": {"connection_receive_window": "", "disable_path_mtu_discovery": false,
      "initial_packet_size": 0, "max_concurrent_streams": 0, "stream_receive_window": ""},
    "outbound_policy": "default",
    "dependencies": []
  }]
}
STATE_EOF
}

write_runtime_config() {
  cat > "\${REMOTE_CONFIG_FILE}" <<CONFIG_EOF
{
  "inbounds": [
    {
      "type": "vless",
      "listen_port": \$(cat "\${REMOTE_PORT_FILE}"),
      "users": [
        {
          "uuid": "\$(cat "\${REMOTE_UUID_FILE}")",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "server_name": "\$(cat "\${REMOTE_SNI_FILE}")",
        "reality": {
          "short_id": [
            "abcd1234"
          ]
        }
      }
    },
    {
      "type": "hysteria2",
      "listen_port": 9444,
      "users": [
        {
          "name": "hy2-user",
          "password": "config-password-should-not-be-used"
        }
      ],
      "tls": {
        "server_name": "config-domain-should-not-be-used"
      },
      "obfs": {
        "type": "salamander",
        "password": "config-obfs-should-not-be-used"
      }
    },
    {
      "type": "anytls",
      "listen_port": 9445,
      "users": [
        {
          "name": "anytls-user",
          "password": "config-password-should-not-be-used"
        }
      ],
      "tls": {
        "server_name": "config-anytls-domain-should-not-be-used"
      }
    },
    {
      "type": "mixed",
      "listen_port": 9446,
      "users": [
        {
          "username": "mixed-user",
          "password": "mixed-pass"
        }
      ]
    },
    {
      "type": "socks",
      "tag": "socks-in",
      "listen": "127.0.0.1",
      "listen_port": 1081,
      "users": [{"username": "socks-user", "password": "socks-pass"}]
    },
    {
      "type": "http",
      "tag": "http-in",
      "listen": "127.0.0.1",
      "listen_port": 1082,
      "users": [{"username": "http-user", "password": "http-pass"}]
    },
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "127.0.0.1",
      "listen_port": 1083,
      "network": ["tcp", "udp"],
      "method": "2022-blake3-aes-128-gcm",
      "password": "MDEyMzQ1Njc4OWFiY2RlZg==",
      "users": []
    },
    {
      "type": "trojan",
      "tag": "trojan-in",
      "listen": "127.0.0.1",
      "listen_port": 1084,
      "users": [{"name": "trojan-user", "password": "trojan-pass"}],
      "tls": {"enabled": true, "server_name": "trojan.example"},
      "transport": {"type": "quic"}
    },
    {
      "type": "hysteria",
      "tag": "hysteria-in",
      "listen": "127.0.0.1",
      "listen_port": 1086,
      "users": [{"name": "hysteria-user", "auth_str": "hysteria-verification-auth"}],
      "tls": {"enabled": true, "server_name": "hysteria.verification.invalid", "alpn": ["h3"]},
      "up_mbps": 100,
      "down_mbps": 100
    }
  ]
}
CONFIG_EOF
}

enable_multi_protocol_probe_fixture() {
  write_vless_state
  write_mixed_state
  write_hy2_state
  write_anytls_state
  write_socks_state
  write_http_state
  write_shadowsocks_state
  write_trojan_state
  write_hysteria_state
  command jq '.instances[].client_trust = "system"' "\${REMOTE_HYSTERIA_STORE_FILE}" > "\${REMOTE_HYSTERIA_STORE_FILE}.tmp"
  mv "\${REMOTE_HYSTERIA_STORE_FILE}.tmp" "\${REMOTE_HYSTERIA_STORE_FILE}"
  cat > "\${REMOTE_INDEX_FILE}" <<'INDEX_EOF'
INSTALLED_PROTOCOLS=vless-reality,mixed,hy2,anytls,socks,http,shadowsocks,trojan,hysteria,mystery-protocol
INDEX_EOF
  write_runtime_config
}

write_vless_state() {
  mkdir -p "\$(dirname "\${REMOTE_INSTANCE_STATE_FILE}")"
  cat > "\${REMOTE_STATE_FILE}" <<STATE_EOF
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main
REALITY_PUBLIC_KEY=public-key-from-state
STATE_EOF
  cat > "\${REMOTE_INSTANCE_STATE_FILE}" <<STATE_EOF
INSTANCE_ID=main
PORT=\$(cat "\${REMOTE_PORT_FILE}")
UUID=\$(cat "\${REMOTE_UUID_FILE}")
SNI=\$(cat "\${REMOTE_SNI_FILE}")
ALPN_MODE=off
TCP_FAST_OPEN=n
STATE_EOF
  cat > "\${REMOTE_CONFIG_FILE}" <<CONFIG_EOF
{
  "inbounds": [
    {
      "type": "vless",
      "listen_port": \$(cat "\${REMOTE_PORT_FILE}"),
      "users": [
        {
          "uuid": "\$(cat "\${REMOTE_UUID_FILE}")",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "server_name": "\$(cat "\${REMOTE_SNI_FILE}")",
        "reality": {
          "short_id": [
            "abcd1234"
          ]
        }
      }
    }
  ]
}
CONFIG_EOF
}

write_legacy_vless_state() {
  mkdir -p "\$(dirname "\${REMOTE_INSTANCE_STATE_FILE}")" "\$(dirname "\${REMOTE_EXPORT_FILE}")"
  cat > "\${REMOTE_STATE_FILE}" <<STATE_EOF
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=imported-1
INSTANCE_IDS=imported-1
REALITY_PRIVATE_KEY=${VALID_REALITY_PRIVATE_KEY}
REALITY_PUBLIC_KEY=${VALID_REALITY_PUBLIC_KEY}
STATE_EOF
  cat > "\${REMOTE_INSTANCE_STATE_FILE}" <<STATE_EOF
INSTANCE_ID=imported-1
NODE_NAME=cc-us-stl+vless
PORT=\$(cat "\${REMOTE_PORT_FILE}")
UUID=\$(cat "\${REMOTE_UUID_FILE}")
SNI=\$(cat "\${REMOTE_SNI_FILE}")
ALPN_MODE=off
TCP_FAST_OPEN=n
STATE_EOF
  cat > "\${REMOTE_INDEX_FILE}" <<'INDEX_EOF'
INSTALLED_PROTOCOLS=vless-reality
INDEX_EOF
  cat > "\${REMOTE_CONFIG_FILE}" <<CONFIG_EOF
{
  "inbounds": [
    {
      "type": "vless",
      "tag": "legacy-vless-in",
      "listen_port": \$(cat "\${REMOTE_PORT_FILE}"),
      "users": [
        {
          "uuid": "\$(cat "\${REMOTE_UUID_FILE}")"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "\$(cat "\${REMOTE_SNI_FILE}")",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "\$(cat "\${REMOTE_SNI_FILE}")",
            "server_port": 443
          },
          "private_key": "${VALID_REALITY_PRIVATE_KEY}",
          "short_id": [
            "aaaaaaaaaaaaaaaa",
            "bbbbbbbbbbbbbbbb"
          ]
        }
      }
    }
  ],
  "route": {
    "rules": []
  }
}
CONFIG_EOF
}

reset_runtime_artifacts() {
  printf '0\n' > "\${REMOTE_CONFIG_PRESENT_FILE}"
  printf '0\n' > "\${REMOTE_SERVICE_FILE_PRESENT_FILE}"
  printf '0\n' > "\${REMOTE_SBV_PRESENT_FILE}"
  printf '0\n' > "\${REMOTE_SERVICE_ACTIVE_FILE}"
  rm -f "\${REMOTE_CONFIG_FILE}"
  rm -rf "\${REMOTE_PROTOCOLS_DIR}"
}

install_runtime_artifacts() {
  printf '1\n' > "\${REMOTE_CONFIG_PRESENT_FILE}"
  printf '1\n' > "\${REMOTE_SERVICE_FILE_PRESENT_FILE}"
  printf '1\n' > "\${REMOTE_SBV_PRESENT_FILE}"
  printf '1\n' > "\${REMOTE_SERVICE_ACTIVE_FILE}"
  write_vless_state
  cat > "\${REMOTE_INDEX_FILE}" <<'INDEX_EOF'
INSTALLED_PROTOCOLS=vless-reality
INDEX_EOF
}

next_install_uuid() {
  local install_count
  install_count=\$(cat "\${INSTALL_COUNT_FILE}")
  install_count=\$((install_count + 1))
  printf '%s\n' "\${install_count}" > "\${INSTALL_COUNT_FILE}"

  case "\${install_count}" in
    1)
      printf '33333333-3333-4333-8333-333333333333\n'
      ;;
    2)
      printf '44444444-4444-4444-8444-444444444444\n'
      ;;
    *)
      printf '55555555-5555-4555-8555-555555555555\n'
      ;;
  esac
}

assert_input_sequence() {
  local target=\$1
  shift
  local expected_lines=("\$@")
  local actual_lines=()
  local index

  mapfile -t actual_lines

  if [[ "\${#actual_lines[@]}" -ne "\${#expected_lines[@]}" ]]; then
    printf 'unexpected input count for %s: expected %s, got %s\n' \
      "\${target}" "\${#expected_lines[@]}" "\${#actual_lines[@]}" >&2
    return 1
  fi

  for index in "\${!expected_lines[@]}"; do
    if [[ "\${actual_lines[\$index]}" != "\${expected_lines[\$index]}" ]]; then
      printf 'unexpected input for %s at line %s: expected <%s>, got <%s>\n' \
        "\${target}" "\$((index + 1))" "\${expected_lines[\$index]}" "\${actual_lines[\$index]}" >&2
      return 1
    fi
  done
}

bash() {
  local target=\${1:-}
  shift || true

  case "\${target}" in
    "\${VERIFY_REMOTE_INSTALL_SCRIPT:-__missing_install__}")
      if [[ "\$#" -eq 0 ]]; then
        mapfile -t actual_lines
        if [[ "\${actual_lines[0]:-}" == "1" && "\${actual_lines[1]:-}" == "1" ]]; then
          if [[ "\${#actual_lines[@]}" -ne 2 && "\${#actual_lines[@]}" -ne 3 ]]; then
            printf 'unexpected takeover input count for %s: %s\n' "\${target}" "\${#actual_lines[@]}" >&2
            return 1
          fi
          if [[ "\${#actual_lines[@]}" -eq 3 && "\${actual_lines[2]}" != "0" ]]; then
            printf 'unexpected takeover trailing input for %s: %s\n' "\${target}" "\${actual_lines[2]}" >&2
            return 1
          fi
          printf '443\n' > "\${REMOTE_PORT_FILE}"
          printf '11111111-1111-1111-1111-111111111111\n' > "\${REMOTE_UUID_FILE}"
          printf 'www.cloudflare.com\n' > "\${REMOTE_SNI_FILE}"
          printf '1\n' > "\${REMOTE_CONFIG_PRESENT_FILE}"
          printf '1\n' > "\${REMOTE_SERVICE_FILE_PRESENT_FILE}"
          printf '1\n' > "\${REMOTE_SBV_PRESENT_FILE}"
          printf '1\n' > "\${REMOTE_SERVICE_ACTIVE_FILE}"
          write_legacy_vless_state
          return 0
        fi

        if [[ "\${actual_lines[2]:-}" == "1" ]]; then
          [[ "\${#actual_lines[@]}" -eq 13 ]]
          [[ "\${actual_lines[0]}" == "1" ]]
          [[ "\${actual_lines[1]}" == "" ]]
          [[ "\${actual_lines[2]}" == "1" ]]
          [[ "\${actual_lines[3]}" == "" ]]
          [[ "\${actual_lines[4]}" == "443" ]]
          [[ "\${actual_lines[5]}" == "2" ]]
          [[ "\${actual_lines[6]}" == "www.cloudflare.com" ]]
          [[ "\${actual_lines[7]}" == "n" ]]
          [[ "\${actual_lines[8]}" == "1" ]]
          [[ "\${actual_lines[9]}" == "n" ]]
          [[ "\${actual_lines[10]}" == "n" ]]
          [[ "\${actual_lines[11]}" == "n" ]]
          [[ "\${actual_lines[12]}" == "0" ]]
          printf '443\n' > "\${REMOTE_PORT_FILE}"
          next_install_uuid > "\${REMOTE_UUID_FILE}"
          printf 'www.cloudflare.com\n' > "\${REMOTE_SNI_FILE}"
          install_runtime_artifacts
          return 0
        fi

        if [[ "\${actual_lines[2]:-}" == "4" ]]; then
          [[ "\${#actual_lines[@]}" -eq 14 ]]
          [[ "\${actual_lines[0]}" == "1" ]]
          [[ "\${actual_lines[1]}" == "" ]]
          [[ "\${actual_lines[2]}" == "4" ]]
          [[ "\${actual_lines[3]}" == "anytls.example.com" ]]
          [[ "\${actual_lines[4]}" == "y" ]]
          [[ "\${actual_lines[5]}" == "9443" ]]
          [[ "\${actual_lines[6]}" == "anytls-user" ]]
          [[ "\${actual_lines[7]}" == "anytls-pass" ]]
          [[ "\${actual_lines[8]}" == "2" ]]
          [[ -n "\${actual_lines[9]}" ]]
          [[ -n "\${actual_lines[10]}" ]]
          [[ "\${actual_lines[11]}" == "n" ]]
          [[ "\${actual_lines[12]}" == "n" ]]
          [[ "\${actual_lines[13]}" == "0" ]]
          printf '9443\n' > "\${REMOTE_PORT_FILE}"
          printf '1\n' > "\${REMOTE_CONFIG_PRESENT_FILE}"
          printf '1\n' > "\${REMOTE_SERVICE_FILE_PRESENT_FILE}"
          printf '1\n' > "\${REMOTE_SBV_PRESENT_FILE}"
          printf '1\n' > "\${REMOTE_SERVICE_ACTIVE_FILE}"
          write_anytls_state
          cat > "\${REMOTE_CONFIG_FILE}" <<'CONFIG_EOF'
{
  "inbounds": [
    {
      "type": "anytls",
      "listen_port": 9443,
      "users": [
        {
          "name": "anytls-user",
          "password": "anytls-pass"
        }
      ],
      "tls": {
        "server_name": "anytls.example.com"
      }
    }
  ]
}
CONFIG_EOF
          cat > "\${REMOTE_INDEX_FILE}" <<'INDEX_EOF'
INSTALLED_PROTOCOLS=anytls
INDEX_EOF
          return 0
        fi

        if [[ "\${actual_lines[2]:-}" == "5" ]]; then
          [[ "\${#actual_lines[@]}" -eq 10 ]]
          [[ "\${actual_lines[0]}" == "1" ]]
          [[ "\${actual_lines[1]}" == "" ]]
          [[ "\${actual_lines[2]}" == "5" ]]
          [[ "\${actual_lines[3]}" == "1081" ]]
          [[ "\${actual_lines[4]}" == "y" ]]
          [[ "\${actual_lines[5]}" == "socks-user" ]]
          [[ "\${actual_lines[6]}" == "socks-pass" ]]
          [[ "\${actual_lines[7]}" == "n" ]]
          [[ "\${actual_lines[8]}" == "n" ]]
          [[ "\${actual_lines[9]}" == "0" ]]
          printf '1081\n' > "\${REMOTE_PORT_FILE}"
          printf '1\n' > "\${REMOTE_CONFIG_PRESENT_FILE}"
          printf '1\n' > "\${REMOTE_SERVICE_FILE_PRESENT_FILE}"
          printf '1\n' > "\${REMOTE_SBV_PRESENT_FILE}"
          printf '1\n' > "\${REMOTE_SERVICE_ACTIVE_FILE}"
          write_socks_state
          cat > "\${REMOTE_CONFIG_FILE}" <<'CONFIG_EOF'
{
  "inbounds": [{
    "type": "socks",
    "tag": "socks-in",
    "listen": "127.0.0.1",
    "listen_port": 1081,
    "users": [{"username": "socks-user", "password": "socks-pass"}]
  }]
}
CONFIG_EOF
          cat > "\${REMOTE_INDEX_FILE}" <<'INDEX_EOF'
INSTALLED_PROTOCOLS=socks
INDEX_EOF
          return 0
        fi

        if [[ "\${actual_lines[2]:-}" == "6" ]]; then
          [[ "\${#actual_lines[@]}" -eq 11 ]]
          [[ "\${actual_lines[0]}" == "1" ]]
          [[ "\${actual_lines[1]}" == "" ]]
          [[ "\${actual_lines[2]}" == "6" ]]
          [[ "\${actual_lines[3]}" == "1082" ]]
          [[ "\${actual_lines[4]}" == "y" ]]
          [[ "\${actual_lines[5]}" == "http-user" ]]
          [[ "\${actual_lines[6]}" == "http-pass" ]]
          [[ "\${actual_lines[7]}" == "n" ]]
          [[ "\${actual_lines[8]}" == "n" ]]
          [[ "\${actual_lines[9]}" == "n" ]]
          [[ "\${actual_lines[10]}" == "0" ]]
          printf '1082\n' > "\${REMOTE_PORT_FILE}"
          printf '1\n' > "\${REMOTE_CONFIG_PRESENT_FILE}"
          printf '1\n' > "\${REMOTE_SERVICE_FILE_PRESENT_FILE}"
          printf '1\n' > "\${REMOTE_SBV_PRESENT_FILE}"
          printf '1\n' > "\${REMOTE_SERVICE_ACTIVE_FILE}"
          write_http_state
          cat > "\${REMOTE_CONFIG_FILE}" <<'CONFIG_EOF'
{
  "inbounds": [{
    "type": "http",
    "tag": "http-in",
    "listen": "127.0.0.1",
    "listen_port": 1082,
    "users": [{"username": "http-user", "password": "http-pass"}]
  }]
}
CONFIG_EOF
          cat > "\${REMOTE_INDEX_FILE}" <<'INDEX_EOF'
INSTALLED_PROTOCOLS=http
INDEX_EOF
          return 0
        fi

        if [[ "\${actual_lines[2]:-}" == "7" ]]; then
          [[ "\${#actual_lines[@]}" -eq 11 ]]
          [[ "\${actual_lines[0]}" == "1" ]]
          [[ "\${actual_lines[1]}" == "" ]]
          [[ "\${actual_lines[2]}" == "7" ]]
          [[ "\${actual_lines[3]}" == "1083" ]]
          [[ "\${actual_lines[4]}" == "" ]]
          [[ "\${actual_lines[5]}" == "n" ]]
          [[ "\${actual_lines[6]}" == "MDEyMzQ1Njc4OWFiY2RlZg==" ]]
          [[ "\${actual_lines[7]}" == "1" ]]
          [[ "\${actual_lines[8]}" == "n" ]]
          [[ "\${actual_lines[9]}" == "n" ]]
          [[ "\${actual_lines[10]}" == "0" ]]
          printf '1083\n' > "\${REMOTE_PORT_FILE}"
          printf '1\n' > "\${REMOTE_CONFIG_PRESENT_FILE}"
          printf '1\n' > "\${REMOTE_SERVICE_FILE_PRESENT_FILE}"
          printf '1\n' > "\${REMOTE_SBV_PRESENT_FILE}"
          printf '1\n' > "\${REMOTE_SERVICE_ACTIVE_FILE}"
          write_shadowsocks_state
          cat > "\${REMOTE_CONFIG_FILE}" <<'CONFIG_EOF'
{
  "inbounds": [{
    "type": "shadowsocks",
    "tag": "ss-in",
    "listen": "127.0.0.1",
    "listen_port": 1083,
    "network": ["tcp", "udp"],
    "method": "2022-blake3-aes-128-gcm",
    "password": "MDEyMzQ1Njc4OWFiY2RlZg==",
    "users": []
  }]
}
CONFIG_EOF
          cat > "\${REMOTE_INDEX_FILE}" <<'INDEX_EOF'
INSTALLED_PROTOCOLS=shadowsocks
INDEX_EOF
          return 0
        fi

        if [[ "\${actual_lines[2]:-}" == "13" ]]; then
          [[ "\${#actual_lines[@]}" -eq 22 ]]
          [[ "\${actual_lines[0]}" == "1" ]]
          [[ "\${actual_lines[1]}" == "" ]]
          [[ "\${actual_lines[2]}" == "13" ]]
          [[ "\${actual_lines[3]}" == "1086" ]]
          [[ "\${actual_lines[4]}" == "1" ]]
          [[ "\${actual_lines[5]}" == "hysteria-user" ]]
          [[ "\${actual_lines[6]}" == "hysteria-verification-auth" ]]
          [[ "\${actual_lines[7]}" == "hysteria.verification.invalid" ]]
          [[ "\${actual_lines[8]}" == "/tmp/sing-box-vps-verification-hysteria.crt" ]]
          [[ "\${actual_lines[9]}" == "/tmp/sing-box-vps-verification-hysteria.key" ]]
          [[ "\${actual_lines[10]}" == "1" ]]
          [[ "\${actual_lines[11]}" == "100" ]]
          [[ "\${actual_lines[12]}" == "100" ]]
          [[ "\${actual_lines[13]}" == "n" ]]
          [[ "\${actual_lines[14]}" == "0" ]]
          [[ "\${actual_lines[15]}" == "n" ]]
          [[ "\${actual_lines[16]}" == "0" ]]
          [[ "\${actual_lines[17]}" == "" ]]
          [[ "\${actual_lines[18]}" == "" ]]
          [[ "\${actual_lines[19]}" == "n" ]]
          [[ "\${actual_lines[20]}" == "n" ]]
          [[ "\${actual_lines[21]}" == "0" ]]
          printf '1086\n' > "\${REMOTE_PORT_FILE}"
          printf '1\n' > "\${REMOTE_CONFIG_PRESENT_FILE}"
          printf '1\n' > "\${REMOTE_SERVICE_FILE_PRESENT_FILE}"
          printf '1\n' > "\${REMOTE_SBV_PRESENT_FILE}"
          printf '1\n' > "\${REMOTE_SERVICE_ACTIVE_FILE}"
          write_hysteria_state
          cat > "\${REMOTE_CONFIG_FILE}" <<'CONFIG_EOF'
{
  "inbounds": [{
    "type": "hysteria",
    "tag": "hysteria-in",
    "listen": "127.0.0.1",
    "listen_port": 1086,
    "users": [{"name": "hysteria-user", "auth_str": "hysteria-verification-auth"}],
    "tls": {"enabled": true, "server_name": "hysteria.verification.invalid", "alpn": ["h3"]},
    "up_mbps": 100,
    "down_mbps": 100
  }]
}
CONFIG_EOF
          cat > "\${REMOTE_INDEX_FILE}" <<'INDEX_EOF'
INSTALLED_PROTOCOLS=hysteria
INDEX_EOF
          return 0
        fi

        printf 'unexpected install input: %s\n' "\${actual_lines[*]:-}" >&2
        return 1
      fi
      if [[ "\${1:-}" == "agent" && "\${2:-}" == "instance" && "\${3:-}" == "create" && "\${4:-}" == "http" ]]; then
        printf '%s' '{"ok":true,"protocol":"http","changed":true,"revision":1}'
        write_http_state
        command jq '.inbounds += [{
          "type":"http","tag":"http-in","listen":"127.0.0.1","listen_port":1082,
          "users":[{"username":"http-user","password":"http-pass"}]
        }]' "\${REMOTE_CONFIG_FILE}" > "\${REMOTE_CONFIG_FILE}.tmp"
        mv "\${REMOTE_CONFIG_FILE}.tmp" "\${REMOTE_CONFIG_FILE}"
        cat > "\${REMOTE_INDEX_FILE}" <<'INDEX_EOF'
INSTALLED_PROTOCOLS=vless-reality,http
INDEX_EOF
        return 0
      fi
      if [[ "\${1:-}" == "agent" && "\${2:-}" == "instance" && "\${3:-}" == "create" && "\${4:-}" == "shadowsocks" ]]; then
        printf '%s' '{"ok":true,"protocol":"shadowsocks","changed":true,"revision":1}'
        write_shadowsocks_state
        command jq '.inbounds += [{
          "type":"shadowsocks","tag":"ss-in","listen":"127.0.0.1","listen_port":1083,
          "network":["tcp","udp"],"method":"2022-blake3-aes-128-gcm",
          "password":"MDEyMzQ1Njc4OWFiY2RlZg==","users":[]
        }]' "\${REMOTE_CONFIG_FILE}" > "\${REMOTE_CONFIG_FILE}.tmp"
        mv "\${REMOTE_CONFIG_FILE}.tmp" "\${REMOTE_CONFIG_FILE}"
        cat > "\${REMOTE_INDEX_FILE}" <<'INDEX_EOF'
INSTALLED_PROTOCOLS=vless-reality,shadowsocks
INDEX_EOF
        return 0
      fi
      if [[ "\${1:-}" == "--internal-uninstall-purge" && "\${2:-}" == "--yes" ]]; then
        reset_runtime_artifacts
        return 0
      fi
      printf 'unexpected install.sh call: %s\n' "\$*" >&2
      return 1
      ;;
    /usr/local/bin/sbv)
      mapfile -t actual_lines
      if [[ "\${actual_lines[0]:-}" == "11" && "\${actual_lines[1]:-}" == "2" ]]; then
        mkdir -p "\$(dirname "\${REMOTE_EXPORT_FILE}")"
        cat > "\${REMOTE_EXPORT_FILE}" <<'EXPORT_EOF'
{
  "outbounds": [
    {
      "type": "vless",
      "tag": "cc-us-stl+vless",
      "tls": {
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        }
      }
    }
  ]
}
EXPORT_EOF
        printf 'sing-box 裸核客户端配置导出成功。\n'
        printf '文件路径: /root/sing-box-vps/client/sing-box-client.json\n'
        return 0
      fi

      if [[ "\${actual_lines[0]:-}" == "2" ]]; then
        [[ "\${#actual_lines[@]}" -eq 12 ]]
        [[ "\${actual_lines[1]}" == "1" ]]
        [[ "\${actual_lines[2]}" == "1" ]]
        [[ "\${actual_lines[3]}" == "" ]]
        [[ "\${actual_lines[4]}" == "8443" ]]
        [[ "\${actual_lines[5]}" == "22222222-2222-4222-8222-222222222222" ]]
        [[ "\${actual_lines[6]}" == "3" ]]
        [[ "\${actual_lines[7]}" == "www.apple.com" ]]
        [[ "\${actual_lines[8]}" == "" ]]
        [[ "\${actual_lines[9]}" == "1" ]]
        [[ "\${actual_lines[10]}" == "n" ]]
        [[ "\${actual_lines[11]}" == "0" ]]
        printf '8443\n' > "\${REMOTE_PORT_FILE}"
        printf '22222222-2222-4222-8222-222222222222\n' > "\${REMOTE_UUID_FILE}"
        printf 'www.apple.com\n' > "\${REMOTE_SNI_FILE}"
        write_vless_state
        return 0
      fi

      if [[ "\${actual_lines[0]:-}" == "9" && "\${actual_lines[1]:-}" == "0" ]]; then
        if [[ "\${VERIFY_CURRENT_SCENARIO:-}" == "runtime_smoke" ]]; then
          printf '运行状态摘要：\nsing-box: active\nWarp: 已开启 (selective)\n配置文件: /root/sing-box-vps/config.json\n'
        else
          printf '运行状态摘要：\nsing-box: active\nWarp: 未开启\n配置文件: /root/sing-box-vps/config.json\n'
        fi
        return 0
      fi

      printf 'unexpected sbv input: %s\n' "\${actual_lines[*]:-}" >&2
      return 1
      ;;
    "\${VERIFY_REMOTE_UNINSTALL_SCRIPT:-__missing_uninstall__}")
      reset_runtime_artifacts
      return 0
      ;;
    /root/Clouds/sing-box-vps/install.sh|/root/Clouds/sing-box-vps/uninstall.sh)
      printf 'unexpected stale remote checkout path: %s\n' "\${target}" >&2
      return 1
      ;;
  esac

  command bash "\${target}" "\$@"
}

test() {
  printf 'test:%s|%s|%s\n' "\${1:-}" "\${2:-}" "\${3:-}" >> "\${REMOTE_ASSERT_LOG_FILE}"

  if [[ "\${1:-}" == "-f" && "\${2:-}" == "/root/sing-box-vps/config.json" ]]; then
    [[ \$(cat "\${REMOTE_CONFIG_PRESENT_FILE}") == "1" ]]
    return
  fi

  if [[ "\${1:-}" == "-f" && "\${2:-}" == "/etc/systemd/system/sing-box.service" ]]; then
    [[ \$(cat "\${REMOTE_SERVICE_FILE_PRESENT_FILE}") == "1" ]]
    return
  fi

  if [[ "\${1:-}" == "-f" && "\${2:-}" == "/root/sing-box-vps/protocols/vless-reality.env" ]]; then
    [[ -f "\${REMOTE_STATE_FILE}" ]]
    return
  fi

  if [[ "\${1:-}" == "-f" && ( "\${2:-}" == "/root/sing-box-vps/protocols/vless-reality.d/main.env" || "\${2:-}" == "/root/sing-box-vps/protocols/vless-reality.d/imported-1.env" ) ]]; then
    [[ -f "\${REMOTE_INSTANCE_STATE_FILE}" ]]
    return
  fi

  if [[ "\${1:-}" == "-f" && "\${2:-}" == "/root/sing-box-vps/protocols/anytls.env" ]]; then
    [[ -f "\${REMOTE_ANYTLS_STATE_FILE}" ]]
    return
  fi

  if [[ "\${1:-}" == "-f" && "\${2:-}" == "/root/sing-box-vps/protocols/socks.env" ]]; then
    [[ -f "\${REMOTE_SOCKS_STATE_FILE}" ]]
    return
  fi

  if [[ "\${1:-}" == "-f" && "\${2:-}" == "/root/sing-box-vps/protocols/instances/socks.json" ]]; then
    [[ -f "\${REMOTE_SOCKS_STORE_FILE}" ]]
    return
  fi

  if [[ "\${1:-}" == "-f" && "\${2:-}" == "/root/sing-box-vps/protocols/http.env" ]]; then
    [[ -f "\${REMOTE_HTTP_STATE_FILE}" ]]
    return
  fi

  if [[ "\${1:-}" == "-f" && "\${2:-}" == "/root/sing-box-vps/protocols/instances/http.json" ]]; then
    [[ -f "\${REMOTE_HTTP_STORE_FILE}" ]]
    return
  fi

  if [[ "\${1:-}" == "-f" && "\${2:-}" == "/root/sing-box-vps/protocols/shadowsocks.env" ]]; then
    [[ -f "\${REMOTE_SHADOWSOCKS_STATE_FILE}" ]]
    return
  fi

  if [[ "\${1:-}" == "-f" && "\${2:-}" == "/root/sing-box-vps/protocols/instances/shadowsocks.json" ]]; then
    [[ -f "\${REMOTE_SHADOWSOCKS_STORE_FILE}" ]]
    return
  fi

  if [[ "\${1:-}" == "-f" && "\${2:-}" == "/root/sing-box-vps/protocols/trojan.env" ]]; then
    [[ -f "\${REMOTE_TROJAN_STATE_FILE}" ]]
    return
  fi

  if [[ "\${1:-}" == "-f" && "\${2:-}" == "/root/sing-box-vps/protocols/instances/trojan.json" ]]; then
    [[ -f "\${REMOTE_TROJAN_STORE_FILE}" ]]
    return
  fi

  if [[ "\${1:-}" == "-f" && "\${2:-}" == "/root/sing-box-vps/protocols/hysteria.env" ]]; then
    [[ -f "\${REMOTE_HYSTERIA_STATE_FILE}" ]]
    return
  fi

  if [[ "\${1:-}" == "-f" && "\${2:-}" == "/root/sing-box-vps/protocols/instances/hysteria.json" ]]; then
    [[ -f "\${REMOTE_HYSTERIA_STORE_FILE}" ]]
    return
  fi

  if [[ "\${1:-}" == "-f" && "\${2:-}" == "/root/sing-box-vps/protocols/index.env" ]]; then
    [[ -f "\${REMOTE_INDEX_FILE}" ]]
    return
  fi

  if [[ "\${1:-}" == "-f" && "\${2:-}" == "/root/sing-box-vps/client/sing-box-client.json" ]]; then
    [[ -f "\${REMOTE_EXPORT_FILE}" ]]
    return
  fi

  if [[ "\${1:-}" == "-d" && "\${2:-}" == "/root/sing-box-vps/protocols" ]]; then
    [[ -d "\${REMOTE_PROTOCOLS_DIR}" ]]
    return
  fi

  if [[ "\${1:-}" == "-x" && "\${2:-}" == "/usr/local/bin/sbv" ]]; then
    [[ \$(cat "\${REMOTE_SBV_PRESENT_FILE}") == "1" ]]
    return
  fi

  if [[ "\${1:-}" == "!" && "\${2:-}" == "-e" && "\${3:-}" == "/root/sing-box-vps/config.json" ]]; then
    [[ \$(cat "\${REMOTE_CONFIG_PRESENT_FILE}") == "0" ]]
    return
  fi

  if [[ "\${1:-}" == "!" && "\${2:-}" == "-e" && "\${3:-}" == "/etc/systemd/system/sing-box.service" ]]; then
    [[ \$(cat "\${REMOTE_SERVICE_FILE_PRESENT_FILE}") == "0" ]]
    return
  fi

  if [[ "\${1:-}" == "!" && "\${2:-}" == "-e" && "\${3:-}" == "/usr/local/bin/sbv" ]]; then
    [[ \$(cat "\${REMOTE_SBV_PRESENT_FILE}") == "0" ]]
    return
  fi

  if [[ "\${1:-}" == "!" && "\${2:-}" == "-f" && "\${3:-}" == "/root/sing-box-vps/protocols/index.env" ]]; then
    [[ ! -f "\${REMOTE_INDEX_FILE}" ]]
    return
  fi

  builtin test "\$@"
}

jq() {
  local args=("\$@")
  local last_index=\$(( \$# - 1 ))

  printf 'jq:%s|%s|%s\n' "\${1:-}" "\${2:-}" "\${3:-}" >> "\${REMOTE_ASSERT_LOG_FILE}"

  if [[ "\${1:-}" == "-r" && "\${2:-}" == ".inbounds[0].listen_port // empty" ]]; then
    cat "\${REMOTE_PORT_FILE}"
    return 0
  fi

  if [[ "\${1:-}" == "-r" && "\${2:-}" == ".inbounds[0].users[0].uuid // empty" ]]; then
    cat "\${REMOTE_UUID_FILE}"
    return 0
  fi

  if [[ "\${1:-}" == "-r" && "\${2:-}" == ".inbounds[0].users[0].password // empty" ]]; then
    printf 'anytls-pass\n'
    return 0
  fi

  if [[ "\${1:-}" == "-r" && "\${2:-}" == ".inbounds[0].users[0].name // empty" ]]; then
    printf 'anytls-user\n'
    return 0
  fi

  if [[ "\${1:-}" == "-r" && "\${2:-}" == ".inbounds[0].tls.server_name // empty" ]]; then
    if grep -Fqx 'INSTALLED_PROTOCOLS=anytls' "\${REMOTE_INDEX_FILE}" 2>/dev/null; then
      printf 'anytls.example.com\n'
      return 0
    fi
    cat "\${REMOTE_SNI_FILE}"
    return 0
  fi

  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/config.json" ]]; then
    args[\$last_index]="\${REMOTE_CONFIG_FILE}"
  fi

  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/client/sing-box-client.json" ]]; then
    args[\$last_index]="\${REMOTE_EXPORT_FILE}"
  fi

  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/instances/socks.json" ]]; then
    args[\$last_index]="\${REMOTE_SOCKS_STORE_FILE}"
  fi

  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/instances/http.json" ]]; then
    args[\$last_index]="\${REMOTE_HTTP_STORE_FILE}"
  fi

  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/instances/shadowsocks.json" ]]; then
    args[\$last_index]="\${REMOTE_SHADOWSOCKS_STORE_FILE}"
  fi

  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/instances/trojan.json" ]]; then
    args[\$last_index]="\${REMOTE_TROJAN_STORE_FILE}"
  fi

  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/instances/hysteria.json" ]]; then
    args[\$last_index]="\${REMOTE_HYSTERIA_STORE_FILE}"
  fi

  command "\${REAL_JQ}" "\${args[@]}"
}

sed() {
  local args=("\$@")
  local last_index=\$(( \$# - 1 ))

  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/vless-reality.env" ]]; then
    args[\$last_index]="\${REMOTE_STATE_FILE}"
  fi

  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/vless-reality.d/main.env" || "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/vless-reality.d/imported-1.env" ]]; then
    args[\$last_index]="\${REMOTE_INSTANCE_STATE_FILE}"
  fi

  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/index.env" ]]; then
    args[\$last_index]="\${REMOTE_INDEX_FILE}"
  fi

  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/socks.env" ]]; then
    args[\$last_index]="\${REMOTE_SOCKS_STATE_FILE}"
  fi

  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/http.env" ]]; then
    args[\$last_index]="\${REMOTE_HTTP_STATE_FILE}"
  fi

  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/shadowsocks.env" ]]; then
    args[\$last_index]="\${REMOTE_SHADOWSOCKS_STATE_FILE}"
  fi

  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/trojan.env" ]]; then
    args[\$last_index]="\${REMOTE_TROJAN_STATE_FILE}"
  fi

  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/hysteria.env" ]]; then
    args[\$last_index]="\${REMOTE_HYSTERIA_STATE_FILE}"
  fi

  command sed "\${args[@]}"
}

cp() {
  local args=("\$@")
  local source_index=\$(( \${#args[@]} - 2 ))

  if [[ "\${args[\$source_index]}" == "/root/sing-box-vps/config.json" ]]; then
    args[\$source_index]="\${REMOTE_CONFIG_FILE}"
  fi

  if [[ "\${args[\$source_index]}" == "/root/sing-box-vps/protocols/." ]]; then
    args[\$source_index]="\${REMOTE_PROTOCOLS_DIR}/."
  fi

  if [[ "\${args[\$source_index]}" == "/root/sing-box-vps/client/sing-box-client.json" ]]; then
    args[\$source_index]="\${REMOTE_EXPORT_FILE}"
  fi

  command cp "\${args[@]}"
}

grep() {
  local args=("\$@")
  local last_index=\$(( \$# - 1 ))

  printf 'grep:%s\n' "\$*" >> "\${REMOTE_ASSERT_LOG_FILE}"

  if [[ "\${args[\$last_index]}" == "/root/sing-box-vps/protocols/vless-reality.env" ]]; then
    args[\$last_index]="\${REMOTE_STATE_FILE}"
  fi

  if [[ "\${args[\$last_index]}" == "/root/sing-box-vps/protocols/vless-reality.d/main.env" || "\${args[\$last_index]}" == "/root/sing-box-vps/protocols/vless-reality.d/imported-1.env" ]]; then
    args[\$last_index]="\${REMOTE_INSTANCE_STATE_FILE}"
  fi

  if [[ "\${args[\$last_index]}" == "/root/sing-box-vps/protocols/anytls.env" ]]; then
    args[\$last_index]="\${REMOTE_ANYTLS_STATE_FILE}"
  fi

  if [[ "\${args[\$last_index]}" == "/root/sing-box-vps/protocols/socks.env" ]]; then
    args[\$last_index]="\${REMOTE_SOCKS_STATE_FILE}"
  fi

  if [[ "\${args[\$last_index]}" == "/root/sing-box-vps/protocols/http.env" ]]; then
    args[\$last_index]="\${REMOTE_HTTP_STATE_FILE}"
  fi

  if [[ "\${args[\$last_index]}" == "/root/sing-box-vps/protocols/instances/socks.json" ]]; then
    args[\$last_index]="\${REMOTE_SOCKS_STORE_FILE}"
  fi

  if [[ "\${args[\$last_index]}" == "/root/sing-box-vps/protocols/instances/http.json" ]]; then
    args[\$last_index]="\${REMOTE_HTTP_STORE_FILE}"
  fi

  if [[ "\${args[\$last_index]}" == "/root/sing-box-vps/protocols/shadowsocks.env" ]]; then
    args[\$last_index]="\${REMOTE_SHADOWSOCKS_STATE_FILE}"
  fi

  if [[ "\${args[\$last_index]}" == "/root/sing-box-vps/protocols/instances/shadowsocks.json" ]]; then
    args[\$last_index]="\${REMOTE_SHADOWSOCKS_STORE_FILE}"
  fi

  if [[ "\${args[\$last_index]}" == "/root/sing-box-vps/protocols/instances/hysteria.json" ]]; then
    args[\$last_index]="\${REMOTE_HYSTERIA_STORE_FILE}"
  fi

  if [[ "\${args[\$last_index]}" == "/root/sing-box-vps/protocols/index.env" ]]; then
    args[\$last_index]="\${REMOTE_INDEX_FILE}"
  fi

  if [[ "\${args[\$last_index]}" == "/root/sing-box-vps/protocols/trojan.env" ]]; then
    args[\$last_index]="\${REMOTE_TROJAN_STATE_FILE}"
  fi

  if [[ "\${args[\$last_index]}" == "/root/sing-box-vps/protocols/hysteria.env" ]]; then
    args[\$last_index]="\${REMOTE_HYSTERIA_STATE_FILE}"
  fi

  command grep "\${args[@]}"
}

stat() {
  local args=("\$@")
  local last_index=\$(( \$# - 1 ))
  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/instances/socks.json" ]]; then
    printf '600\n'
    return 0
  fi
  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/instances/http.json" ]]; then
    printf '600\n'
    return 0
  fi
  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/instances/shadowsocks.json" ]]; then
    printf '600\n'
    return 0
  fi
  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/instances/trojan.json" ]]; then
    printf '600\n'
    return 0
  fi
  if [[ "\${args[\$last_index]:-}" == "/root/sing-box-vps/protocols/instances/hysteria.json" ]]; then
    printf '600\n'
    return 0
  fi
  command stat "\$@"
}
PAYLOAD_PRELUDE
cat >> "\${script_file}"
perl -0pi -e 's|readonly SB_PROJECT_DIR="/root/sing-box-vps"|readonly SB_PROJECT_DIR="'"${REMOTE_ROOT_DIR}/root/sing-box-vps"'"|g' "\${script_file}"
perl -0pi -e 's|state_file=/root/sing-box-vps/protocols/vless-reality.env|state_file='"${REMOTE_STATE_FILE}"'|g' "\${script_file}"
perl -0pi -e 's|state_file=/root/sing-box-vps/protocols/mixed.env|state_file='"${REMOTE_MIXED_STATE_FILE}"'|g' "\${script_file}"
perl -0pi -e 's|state_file=/root/sing-box-vps/protocols/hy2.env|state_file='"${REMOTE_HY2_STATE_FILE}"'|g' "\${script_file}"
perl -0pi -e 's|state_file=/root/sing-box-vps/protocols/anytls.env|state_file='"${REMOTE_ANYTLS_STATE_FILE}"'|g' "\${script_file}"
perl -0pi -e 's|state_file=/root/sing-box-vps/protocols/http.env|state_file='"${REMOTE_HTTP_STATE_FILE}"'|g' "\${script_file}"
perl -0pi -e 's|store_file=/root/sing-box-vps/protocols/instances/http.json|store_file='"${REMOTE_HTTP_STORE_FILE}"'|g' "\${script_file}"
perl -0pi -e 's|state_file=/root/sing-box-vps/protocols/shadowsocks.env|state_file='"${REMOTE_SHADOWSOCKS_STATE_FILE}"'|g' "\${script_file}"
perl -0pi -e 's|store_file=/root/sing-box-vps/protocols/instances/shadowsocks.json|store_file='"${REMOTE_SHADOWSOCKS_STORE_FILE}"'|g' "\${script_file}"
perl -0pi -e 's|state_file=/root/sing-box-vps/protocols/trojan.env|state_file='"${REMOTE_TROJAN_STATE_FILE}"'|g' "\${script_file}"
perl -0pi -e 's|store_file=/root/sing-box-vps/protocols/instances/trojan.json|store_file='"${REMOTE_TROJAN_STORE_FILE}"'|g' "\${script_file}"
perl -0pi -e 's|state_file=/root/sing-box-vps/protocols/hysteria.env|state_file='"${REMOTE_HYSTERIA_STATE_FILE}"'|g' "\${script_file}"
perl -0pi -e 's|store_file=/root/sing-box-vps/protocols/instances/hysteria.json|store_file='"${REMOTE_HYSTERIA_STORE_FILE}"'|g' "\${script_file}"
perl -0pi -e 's|state_file=/root/sing-box-vps/protocols/vless-plain.env|state_file='"${REMOTE_VLESS_PLAIN_STATE_FILE}"'|g' "\${script_file}"
perl -0pi -e 's|store_file=/root/sing-box-vps/protocols/instances/vless-plain.json|store_file='"${REMOTE_VLESS_PLAIN_STORE_FILE}"'|g' "\${script_file}"
cat > "\${script_file}.wrapper" <<'WRAP_EOF'
eval "\$(declare -f verification_run_protocol_probes | sed '1s/verification_run_protocol_probes/verification_run_protocol_probes__original/')"
verification_run_protocol_probes() {
  local status=0
  if [[ ! -f "\${VERIFY_REMOTE_INSTALL_SCRIPT:-}" ]]; then
    verification_prepare_remote_local_tree
  fi
  enable_multi_protocol_probe_fixture
  printf '%s\n' "\${VERIFY_CURRENT_SCENARIO}" >> "\${REMOTE_DISPATCH_LOG_FILE}"
  set +e
  verification_run_protocol_probes__original "\$@"
  status=\$?
  set -e
  write_vless_state
  cat > "\${REMOTE_INDEX_FILE}" <<'INDEX_EOF'
INSTALLED_PROTOCOLS=vless-reality
INDEX_EOF
  return "\${status}"
}

eval "\$(declare -f verification_finalize_scenario | sed '1s/verification_finalize_scenario/verification_finalize_scenario__original/')"
verification_finalize_scenario() {
  verification_finalize_scenario__original "\$@"
  if [[ "\${VERIFY_CURRENT_SCENARIO:-}" == "fresh_install_vmess" ]]; then
    verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/protocols/instances/vmess.json" '{"schema_version":1,"protocol":"vmess","revision":1,"default_instance_id":"main","instances":[{"id":"main","name":"VMess verification","tag":"vmess-in","listen":{"address":"127.0.0.1","port":1085},"authentication":{"users":[{"name":"vmess-user","uuid":"11111111-1111-4111-8111-111111111111","alter_id":0,"security":"auto"}]},"tls":{"enabled":true,"server_name":"vmess.example"},"client_trust":"certificate","transport":{"type":"none"},"outbound_policy":"default","dependencies":[]}]}'
  fi
  if [[ "\${VERIFY_CURRENT_SCENARIO:-}" == "fresh_install_vless_plain" ]]; then
    verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/protocols/vless-plain.env" $'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2'
    verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/protocols/instances/vless-plain.json" '{"schema_version":1,"protocol":"vless-plain","revision":1,"default_instance_id":"main","instances":[{"id":"main","name":"VLESS verification","tag":"vless-plain-in","listen":{"address":"127.0.0.1","port":1086},"authentication":{"users":[{"name":"probe","uuid":"11111111-1111-4111-8111-111111111111","flow":""}]},"tls":{"enabled":false},"client_trust":"system","transport":{"type":"none"},"outbound_policy":"default","dependencies":[]}]}'
  fi
}

# Re-apply the final QUIC state after the original finalizer captures the
# fake runtime tree, which intentionally starts from the legacy Reality stub.
eval "\$(declare -f verification_finalize_scenario | sed '1s/verification_finalize_scenario/verification_finalize_scenario__with_vless_quic/')"
verification_finalize_scenario() {
  verification_finalize_scenario__with_vless_quic "\$@"
  if [[ "\${VERIFY_CURRENT_SCENARIO:-}" == "fresh_install_vless_plain" ]]; then
    verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/config.json" '{"inbounds":[{"type":"vless","tag":"vless-plain-in","listen":"127.0.0.1","listen_port":1086,"users":[{"name":"probe","uuid":"11111111-1111-1111-1111-111111111111"}],"tls":{"enabled":true,"server_name":"vless-plain.verification.invalid","alpn":["h3"]},"transport":{"type":"quic"}}]}'
    verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/protocols/vless-plain.env" $'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2'
    verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/protocols/instances/vless-plain.json" '{"schema_version":1,"protocol":"vless-plain","revision":2,"default_instance_id":"main","instances":[{"id":"main","name":"VLESS plain QUIC verification","tag":"vless-plain-in","listen":{"address":"127.0.0.1","port":1086},"authentication":{"users":[{"name":"probe","uuid":"11111111-1111-1111-1111-111111111111","flow":""}]},"tls":{"enabled":true,"server_name":"vless-plain.verification.invalid","certificate_path":"/tmp/vless-plain.crt","key_path":"/tmp/vless-plain.key"},"client_trust":"certificate","transport":{"type":"quic"},"outbound_policy":"default","dependencies":[]}]}'
  fi
}

# The runtime-smoke harness uses a lightweight fake sing-box process and
# cannot perform a real SOCKS5 UDP association.  The dedicated UDP probe
# test exercises that data-plane helper with a fake SOCKS relay; keep this
# artifact-dispatch harness focused on scenario routing and cleanup while
# mirroring every UDP call made by the real coexistence scenario.
verification_execute_protocol_udp_probe() {
  local protocol=\$1
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/\${protocol}/udp.result.env" \
    "PROTOCOL=\${protocol}" "RESULT=success"
}

# The artifact-dispatch harness does not have a privileged network namespace,
# so mirror the transparent helper calls with deterministic evidence. The
# dedicated Docker scenario exercises the real REDIRECT/TPROXY data planes;
# this fake keeps source dispatch and artifact extraction covered here.
verification_execute_redirect_probe() {
  local config_file=\$1 listener_port=\$2
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/transparent/redirect/result.env" \
    'COMPONENT=redirect-inbound' 'RESULT=success' \
    'DATA_PLANE=redirect_tcp_loopback' \
    'POLICY_SCOPE=verification_container_only' \
    'POLICY_OWNERSHIP=not_managed'
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/transparent/redirect/response.txt" \
    'redirect-marker'
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/transparent/redirect/iptables.with-redirect.txt" \
    'REDIRECT owner-scoped verification rule'
}

verification_execute_tproxy_probe() {
  local config_file=\$1 listener_port=\$2
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/transparent/tproxy/result.env" \
    'COMPONENT=tproxy-inbound' 'RESULT=success' \
    'DATA_PLANE=tproxy_tcp_udp_netns' \
    'POLICY_SCOPE=verification_container_only' \
    'POLICY_OWNERSHIP=not_managed'
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/transparent/tproxy/tcp-response.txt" \
    'tproxy-tcp-marker'
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/transparent/tproxy/udp-response.txt" \
    'tproxy-udp-marker'
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/transparent/tproxy/iptables.with-tproxy.txt" \
    'TPROXY tcp/udp verification rules'
}

verification_scenario_upgrade_1_13_to_1_14() {
  printf 'SCENARIO=upgrade_1_13_to_1_14\n'
  printf '%s\n' "\${VERIFY_CURRENT_SCENARIO}" >> "\${REMOTE_DISPATCH_LOG_FILE}"
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/upgrade.json" '{"ok":true,"installed":"1.14.0","transaction":{"status":"success","result_persisted":true}}'
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/transaction-result.json" '{"schema_version":"1.0","status":"success"}'
}

verification_scenario_multi_protocol_coexistence() {
  printf 'SCENARIO=multi_protocol_coexistence\n'
  printf '%s\n' "\${VERIFY_CURRENT_SCENARIO}" >> "\${REMOTE_DISPATCH_LOG_FILE}"
  verification_run_protocol_probes
  verification_execute_protocol_udp_probe naive /root/sing-box-vps/config.json
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/naive-tcp-uot/result.env" \
    'PROTOCOL=naive' 'RESULT=success' \
    'DATA_PLANE=naive_udp_over_tcp_loopback'
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/naive-udp-http3/result.env" \
    'PROTOCOL=naive' 'RESULT=success' \
    'DATA_PLANE=naive_http3_tcp_loopback'
  verification_execute_protocol_udp_probe anytls /root/sing-box-vps/config.json
  verification_execute_protocol_udp_probe hy2 /root/sing-box-vps/config.json
  verification_execute_protocol_udp_probe shadowsocks /root/sing-box-vps/config.json
  verification_execute_protocol_udp_probe trojan /root/sing-box-vps/config.json
  verification_execute_protocol_udp_probe tuic /root/sing-box-vps/config.json
  verification_execute_protocol_udp_probe vmess /root/sing-box-vps/config.json
  verification_execute_protocol_udp_probe snell /root/sing-box-vps/config.json
  verification_execute_redirect_probe /root/sing-box-vps/config.json 1094
  verification_execute_tproxy_probe /root/sing-box-vps/config.json 1095
}

verification_scenario_fresh_install_http() {
  printf 'SCENARIO=fresh_install_http\n'
  printf '%s\n' "\${VERIFY_CURRENT_SCENARIO}" >> "\${REMOTE_DISPATCH_LOG_FILE}"
  verification_run_protocol_probes
}

verification_scenario_fresh_install_shadowsocks() {
  printf 'SCENARIO=fresh_install_shadowsocks\n'
  printf '%s\n' "\${VERIFY_CURRENT_SCENARIO}" >> "\${REMOTE_DISPATCH_LOG_FILE}"
  verification_run_protocol_probes
}

verification_scenario_fresh_install_trojan() {
  printf 'SCENARIO=fresh_install_trojan\n'
  printf '%s\n' "\${VERIFY_CURRENT_SCENARIO}" >> "\${REMOTE_DISPATCH_LOG_FILE}"
  verification_run_protocol_probes
}

verification_scenario_fresh_install_vmess() {
  printf 'SCENARIO=fresh_install_vmess\n'
  printf '%s\n' "\${VERIFY_CURRENT_SCENARIO}" >> "\${REMOTE_DISPATCH_LOG_FILE}"
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/config.json" '{"inbounds":[{"type":"vmess","tag":"vmess-in","listen":"127.0.0.1","listen_port":1085,"users":[{"name":"vmess-user","uuid":"11111111-1111-4111-8111-111111111111","alterId":0,"security":"auto"}],"tls":{"enabled":true,"server_name":"vmess.example"}}]}'
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/protocols/vmess.env" $'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2'
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/protocols/instances/vmess.json" '{"schema_version":1,"protocol":"vmess","revision":1,"default_instance_id":"main","instances":[{"id":"main","name":"VMess verification","tag":"vmess-in","listen":{"address":"127.0.0.1","port":1085},"authentication":{"users":[{"name":"vmess-user","uuid":"11111111-1111-4111-8111-111111111111","alter_id":0,"security":"auto"}]},"tls":{"enabled":true,"server_name":"vmess.example"},"client_trust":"certificate","transport":{"type":"none"},"outbound_policy":"default","dependencies":[]}]}'
}

verification_scenario_fresh_install_vless_plain() {
  printf 'SCENARIO=fresh_install_vless_plain\n'
  printf '%s\n' "\${VERIFY_CURRENT_SCENARIO}" >> "\${REMOTE_DISPATCH_LOG_FILE}"
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/config.json" '{"inbounds":[{"type":"vless","tag":"vless-plain-in","listen":"127.0.0.1","listen_port":1086,"users":[{"name":"probe","uuid":"11111111-1111-4111-8111-111111111111"}],"tls":{"enabled":true,"server_name":"vless-plain.verification.invalid","alpn":["h3"]},"transport":{"type":"quic"}}]}'
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/protocols/vless-plain.env" $'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2'
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/protocols/instances/vless-plain.json" '{"schema_version":1,"protocol":"vless-plain","revision":2,"default_instance_id":"main","instances":[{"id":"main","name":"VLESS plain QUIC verification","tag":"vless-plain-in","listen":{"address":"127.0.0.1","port":1086},"authentication":{"users":[{"name":"probe","uuid":"11111111-1111-4111-8111-111111111111","flow":""}]},"tls":{"enabled":true,"server_name":"vless-plain.verification.invalid","certificate_path":"/tmp/vless-plain.crt","key_path":"/tmp/vless-plain.key"},"client_trust":"certificate","transport":{"type":"quic"},"outbound_policy":"default","dependencies":[]}]}'
  verification_execute_protocol_udp_probe vless-plain /root/sing-box-vps/config.json
}

verification_scenario_upgrade_rollback_1_13_to_1_14() {
  printf 'SCENARIO=upgrade_rollback_1_13_to_1_14\n'
  printf '%s\n' "\${VERIFY_CURRENT_SCENARIO}" >> "\${REMOTE_DISPATCH_LOG_FILE}"
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/config.before.sha256" 'before-config-hash'
  verification_run_protocol_probes
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/config.after.sha256" 'before-config-hash'
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/service.before.sha256" 'before-service-hash'
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/service.after.sha256" 'before-service-hash'
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/after.version.txt" 'sing-box version 1.13.18'
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/systemctl.status.txt" 'active'
  verification_write_artifact "\${VERIFY_CURRENT_SCENARIO_DIR}/transaction-result.json" '{"schema_version":"1.0","status":"rolled_back","rollback":{"attempted":true,"result":"success"}}'
}
WRAP_EOF
awk -v wrapper_file="\${script_file}.wrapper" '
  \$0 == "if ! mkdir \"\${LOCK_DIR}\" 2>/dev/null; then" {
    while ((getline line < wrapper_file) > 0) {
      print line
    }
    close(wrapper_file)
  }
  { print }
' "\${script_file}" > "\${script_file}.tmp"
mv "\${script_file}.tmp" "\${script_file}"
printf 'REMOTE_HOST=%s\n' "\${remote_host}"
# The fake payload must not touch host TUN/bridge or endpoint resources.
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
REMOTE_MIXED_STATE_FILE="${REMOTE_MIXED_STATE_FILE}" \
REMOTE_HY2_STATE_FILE="${REMOTE_HY2_STATE_FILE}" \
REMOTE_ANYTLS_STATE_FILE="${REMOTE_ANYTLS_STATE_FILE}" \
REMOTE_INDEX_FILE="${REMOTE_INDEX_FILE}" \
REMOTE_ASSERT_LOG_FILE="${REMOTE_ASSERT_LOG_FILE}" \
REMOTE_DISPATCH_LOG_FILE="${REMOTE_DISPATCH_LOG_FILE}" \
REMOTE_PROBE_CLIENT_PID_FILE="${TMP_DIR}/remote-probe-client.pid" \
REMOTE_PROBE_HTTP_PID_FILE="${TMP_DIR}/remote-probe-http.pid" \
INSTALL_COUNT_FILE="${INSTALL_COUNT_FILE}" \
REMOTE_SOCKS_STATE_FILE="${REMOTE_SOCKS_STATE_FILE}" \
REMOTE_SOCKS_STORE_FILE="${REMOTE_SOCKS_STORE_FILE}" \
REMOTE_HTTP_STATE_FILE="${REMOTE_HTTP_STATE_FILE}" \
REMOTE_HTTP_STORE_FILE="${REMOTE_HTTP_STORE_FILE}" \
REMOTE_SHADOWSOCKS_STATE_FILE="${REMOTE_SHADOWSOCKS_STATE_FILE}" \
REMOTE_SHADOWSOCKS_STORE_FILE="${REMOTE_SHADOWSOCKS_STORE_FILE}" \
REMOTE_TROJAN_STATE_FILE="${REMOTE_TROJAN_STATE_FILE}" \
REMOTE_TROJAN_STORE_FILE="${REMOTE_TROJAN_STORE_FILE}" \
REMOTE_HYSTERIA_STATE_FILE="${REMOTE_HYSTERIA_STATE_FILE}" \
REMOTE_HYSTERIA_STORE_FILE="${REMOTE_HYSTERIA_STORE_FILE}" \
REAL_JQ="${REAL_JQ}" \
VERIFY_REMOTE_SKIP_PRIVILEGED_RESOURCES=1 \
PATH="${TMP_DIR}:/usr/local/bin:/usr/bin:/bin" "${REAL_BASH}" "\${script_file}" "\${@:7}"
  exit \$?
fi
if [[ "\${1:-}" == "rm" && "\${2:-}" == "-f" ]]; then
  exit 0
fi
printf 'unexpected docker call: %s\n' "$*" >&2
exit 1
DOCKER_EOF
chmod +x "${TMP_DIR}/docker"

PATH="${TMP_DIR}:${PATH}" VERIFY_SKIP_LOCAL_TESTS=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" --changed-file install.sh > "${TMP_DIR}/stdout.txt"

run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout.txt")
grep -Fq 'runtime_smoke' "${run_dir}/scenarios.txt"
grep -Fq 'multi_protocol_coexistence' "${run_dir}/scenarios.txt"
grep -Fq 'fresh_install_http' "${run_dir}/scenarios.txt"
grep -Fq 'fresh_install_shadowsocks' "${run_dir}/scenarios.txt"
grep -Fq 'fresh_install_trojan' "${run_dir}/scenarios.txt"
grep -Fq 'fresh_install_vmess' "${run_dir}/scenarios.txt"
grep -Fq 'fresh_install_hysteria' "${run_dir}/scenarios.txt"
grep -Fq 'fresh_install_vless_plain' "${run_dir}/scenarios.txt"
grep -Fq 'upgrade_rollback_1_13_to_1_14' "${run_dir}/scenarios.txt"
grep -Fq 'remote_target=docker:test-container' "${run_dir}/summary.log"
grep -Fq 'remote_target=docker:test-container' "${TMP_DIR}/stdout.txt"
grep -Fq 'SCENARIO=runtime_smoke' "${run_dir}/remote.stdout.log"
grep -Fq 'SERVICE_ACTIVE=active' "${run_dir}/remote.stdout.log"
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/sing-box-check.txt" ]]
grep -Fqx 'sing-box version 1.14.1' "${run_dir}/remote-artifacts/scenarios/fresh_install_vless/sing-box.version.txt"
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_vless/wireguard-endpoint-system/result.env" ]]
grep -Fqx 'RESULT=blocked' \
  "${run_dir}/remote-artifacts/scenarios/fresh_install_vless/wireguard-endpoint-system/result.env"
grep -Fqx 'REASON=privileged_resource_probe_disabled' \
  "${run_dir}/remote-artifacts/scenarios/fresh_install_vless/wireguard-endpoint-system/result.env"
grep -Fqx 'sing-box version 1.14.1' "${run_dir}/remote-artifacts/scenarios/fresh_install_anytls/sing-box.version.txt"
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_http/config.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_http/protocols/instances/http.json" ]]
grep -Fqx 'RESULT=success' "${run_dir}/remote-artifacts/scenarios/fresh_install_http/protocol-probes/http/result.env"
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_shadowsocks/config.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_shadowsocks/protocols/instances/shadowsocks.json" ]]
grep -Fqx 'RESULT=success' "${run_dir}/remote-artifacts/scenarios/fresh_install_shadowsocks/protocol-probes/shadowsocks/result.env"
grep -Fqx 'RESULT=success' "${run_dir}/remote-artifacts/scenarios/fresh_install_trojan/protocol-probes/trojan/result.env"
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_vmess/config.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_vmess/protocols/instances/vmess.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_hysteria/config.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_hysteria/protocols/hysteria.env" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_hysteria/protocols/instances/hysteria.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_hysteria/listeners.ss-lunp.txt" ]]
grep -Fqx 'RESULT=success' "${run_dir}/remote-artifacts/scenarios/fresh_install_hysteria/protocol-probes/hysteria/result.env"
grep -Fqx 'RESULT=success' "${run_dir}/remote-artifacts/scenarios/fresh_install_hysteria/protocol-probes/hysteria/udp.result.env"
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_vless_plain/config.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_vless_plain/protocols/vless-plain.env" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/fresh_install_vless_plain/protocols/instances/vless-plain.json" ]]
jq -e '.inbounds[0].type=="vless" and .inbounds[0].transport=={type:"quic"} and
  .inbounds[0].tls.alpn==["h3"]' \
  "${run_dir}/remote-artifacts/scenarios/fresh_install_vless_plain/config.json" >/dev/null
jq -e '.revision==2 and .instances[0].transport=={type:"quic"} and
  .instances[0].client_trust=="certificate"' \
  "${run_dir}/remote-artifacts/scenarios/fresh_install_vless_plain/protocols/instances/vless-plain.json" >/dev/null
grep -Fqx 'RESULT=success' \
  "${run_dir}/remote-artifacts/scenarios/fresh_install_vless_plain/protocol-probes/vless-plain/udp.result.env"
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/listeners.ss-lntp.txt" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/vless-reality/client.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/vless-reality/probe.stdout.txt" ]]
grep -Fqx 'RESULT=success' "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/vless-reality/result.env"
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/mixed/client.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/mixed/probe.stdout.txt" ]]
grep -Fqx 'RESULT=success' "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/mixed/result.env"
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/hy2/client.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/hy2/probe.stdout.txt" ]]
grep -Fqx 'RESULT=success' "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/hy2/result.env"
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/anytls/client.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/anytls/probe.stdout.txt" ]]
grep -Fqx 'RESULT=success' "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/anytls/result.env"
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/http/client.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/http/probe.stdout.txt" ]]
grep -Fqx 'RESULT=success' "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/http/result.env"
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/trojan/client.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/trojan/probe.stdout.txt" ]]
grep -Fqx 'RESULT=success' "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/trojan/result.env"
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/hysteria/client.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/hysteria/probe.stdout.txt" ]]
grep -Fqx 'RESULT=success' "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/hysteria/result.env"
grep -Fqx 'RESULT=unsupported' "${run_dir}/remote-artifacts/scenarios/runtime_smoke/protocol-probes/mystery-protocol/result.env"
grep -Fqx 'STATUS=success' "${run_dir}/remote-artifacts/scenarios/multi_protocol_coexistence/result.env"
grep -Fqx 'RESULT=success' "${run_dir}/remote-artifacts/scenarios/multi_protocol_coexistence/protocol-probes/anytls/udp.result.env"
grep -Fqx 'RESULT=success' "${run_dir}/remote-artifacts/scenarios/multi_protocol_coexistence/protocol-probes/naive/udp.result.env"
grep -Fqx 'DATA_PLANE=naive_udp_over_tcp_loopback' \
  "${run_dir}/remote-artifacts/scenarios/multi_protocol_coexistence/protocol-probes/naive-tcp-uot/result.env"
grep -Fqx 'DATA_PLANE=naive_http3_tcp_loopback' \
  "${run_dir}/remote-artifacts/scenarios/multi_protocol_coexistence/protocol-probes/naive-udp-http3/result.env"
grep -Fqx 'RESULT=success' "${run_dir}/remote-artifacts/scenarios/multi_protocol_coexistence/protocol-probes/shadowsocks/udp.result.env"
grep -Fqx 'RESULT=success' "${run_dir}/remote-artifacts/scenarios/multi_protocol_coexistence/protocol-probes/trojan/udp.result.env"
grep -Fqx 'RESULT=success' "${run_dir}/remote-artifacts/scenarios/multi_protocol_coexistence/protocol-probes/vmess/udp.result.env"
grep -Fqx 'RESULT=success' "${run_dir}/remote-artifacts/scenarios/multi_protocol_coexistence/protocol-probes/snell/udp.result.env"
grep -Fqx 'RESULT=success' "${run_dir}/remote-artifacts/scenarios/multi_protocol_coexistence/transparent/redirect/result.env"
grep -Fqx 'POLICY_OWNERSHIP=not_managed' \
  "${run_dir}/remote-artifacts/scenarios/multi_protocol_coexistence/transparent/redirect/result.env"
grep -Fqx 'redirect-marker' \
  "${run_dir}/remote-artifacts/scenarios/multi_protocol_coexistence/transparent/redirect/response.txt"
grep -Fqx 'RESULT=success' "${run_dir}/remote-artifacts/scenarios/multi_protocol_coexistence/transparent/tproxy/result.env"
grep -Fqx 'POLICY_OWNERSHIP=not_managed' \
  "${run_dir}/remote-artifacts/scenarios/multi_protocol_coexistence/transparent/tproxy/result.env"
grep -Fqx 'tproxy-tcp-marker' \
  "${run_dir}/remote-artifacts/scenarios/multi_protocol_coexistence/transparent/tproxy/tcp-response.txt"
grep -Fqx 'tproxy-udp-marker' \
  "${run_dir}/remote-artifacts/scenarios/multi_protocol_coexistence/transparent/tproxy/udp-response.txt"
grep -Fqx 'STATUS=success' "${run_dir}/remote-artifacts/scenarios/upgrade_rollback_1_13_to_1_14/result.env"
[[ -f "${run_dir}/remote-artifacts/scenarios/upgrade_1_13_to_1_14/upgrade.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/upgrade_1_13_to_1_14/transaction-result.json" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/upgrade_rollback_1_13_to_1_14/config.before.sha256" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/upgrade_rollback_1_13_to_1_14/config.after.sha256" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/upgrade_rollback_1_13_to_1_14/service.before.sha256" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/upgrade_rollback_1_13_to_1_14/service.after.sha256" ]]
grep -Fqx 'sing-box version 1.13.18' "${run_dir}/remote-artifacts/scenarios/upgrade_rollback_1_13_to_1_14/after.version.txt"
[[ -f "${run_dir}/remote-artifacts/scenarios/upgrade_rollback_1_13_to_1_14/systemctl.status.txt" ]]
[[ -f "${run_dir}/remote-artifacts/scenarios/upgrade_rollback_1_13_to_1_14/transaction-result.json" ]]
grep -Fq 'remote_artifacts=extracted' "${run_dir}/summary.log"
grep -Fq "${INSTALL_VERSION_LINE}" "${TMP_DIR}/remote-script.sh"
grep -Fq "${UNINSTALL_HELPER_LINE}" "${TMP_DIR}/remote-script.sh"
grep -Fq 'verification_run_protocol_probes' "${TMP_DIR}/remote-script.sh"
grep -Fq 'verification_execute_redirect_probe' \
  "${REPO_ROOT}/dev/verification/remote/entrypoint.sh"
grep -Fq 'verification_execute_tproxy_probe' \
  "${REPO_ROOT}/dev/verification/remote/entrypoint.sh"
grep -Fq 'verification_execute_protocol_udp_probe naive /root/sing-box-vps/config.json' \
  "${REPO_ROOT}/dev/verification/remote/scenarios/multi_protocol_coexistence.sh"
grep -Fq 'DATA_PLANE=naive_http3_tcp_loopback' \
  "${REPO_ROOT}/dev/verification/remote/scenarios/multi_protocol_coexistence.sh"
grep -Fq 'verification_execute_redirect_probe /root/sing-box-vps/config.json 1094' \
  "${REPO_ROOT}/dev/verification/remote/scenarios/multi_protocol_coexistence.sh"
grep -Fq 'verification_execute_tproxy_probe /root/sing-box-vps/config.json 1095' \
  "${REPO_ROOT}/dev/verification/remote/scenarios/multi_protocol_coexistence.sh"
! grep -Fq 'verification_execute_single_protocol_probe vless-reality /root/sing-box-vps/config.json' "${TMP_DIR}/remote-script.sh"
grep -Fqx 'fresh_install_vless' "${REMOTE_DISPATCH_LOG_FILE}"
grep -Fqx 'reconfigure_existing_install' "${REMOTE_DISPATCH_LOG_FILE}"
grep -Fqx 'fresh_install_anytls' "${REMOTE_DISPATCH_LOG_FILE}"
grep -Fqx 'fresh_install_http' "${REMOTE_DISPATCH_LOG_FILE}"
grep -Fqx 'fresh_install_shadowsocks' "${REMOTE_DISPATCH_LOG_FILE}"
grep -Fqx 'fresh_install_trojan' "${REMOTE_DISPATCH_LOG_FILE}"
grep -Fqx 'fresh_install_vmess' "${REMOTE_DISPATCH_LOG_FILE}"
grep -Fqx 'fresh_install_hysteria' "${REMOTE_DISPATCH_LOG_FILE}"
grep -Fqx 'fresh_install_vless_plain' "${REMOTE_DISPATCH_LOG_FILE}"
grep -Fqx 'upgrade_1_13_to_1_14' "${REMOTE_DISPATCH_LOG_FILE}"
grep -Fqx 'runtime_smoke' "${REMOTE_DISPATCH_LOG_FILE}"
grep -Fqx 'multi_protocol_coexistence' "${REMOTE_DISPATCH_LOG_FILE}"
grep -Fqx 'upgrade_rollback_1_13_to_1_14' "${REMOTE_DISPATCH_LOG_FILE}"
grep -Fqx 'grep:-Fqx PORT=443 /root/sing-box-vps/protocols/vless-reality.d/imported-1.env' "${REMOTE_ASSERT_LOG_FILE}"
grep -Fqx 'grep:-Fqx SNI=www.cloudflare.com /root/sing-box-vps/protocols/vless-reality.d/imported-1.env' "${REMOTE_ASSERT_LOG_FILE}"
grep -Fqx 'jq:-r|.inbounds[0].listen_port // empty|/root/sing-box-vps/config.json' "${REMOTE_ASSERT_LOG_FILE}"
grep -Fqx 'UUID=11111111-1111-1111-1111-111111111111' "${REMOTE_INSTANCE_STATE_FILE}"

if PATH="${TMP_DIR}:${PATH}" VERIFY_SKIP_LOCAL_TESTS=1 VERIFY_FAIL_SINGBOX_CHECK=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" --changed-file install.sh > "${TMP_DIR}/stdout-fail.txt" 2> "${TMP_DIR}/stderr-fail.txt"; then
  printf 'expected runtime smoke to fail when sing-box check fails\n' >&2
  exit 1
fi

run_dir_fail=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout-fail.txt")
[[ -f "${run_dir_fail}/remote-artifacts/scenarios/fresh_install_vless/sing-box-check.txt" ]]
grep -Fq 'config broken' "${run_dir_fail}/remote-artifacts/scenarios/fresh_install_vless/sing-box-check.txt"
grep -Fq 'remote_status=failure' "${run_dir_fail}/summary.log"
