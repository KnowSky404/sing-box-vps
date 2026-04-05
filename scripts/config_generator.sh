#!/usr/bin/env bash

# Generate UUID if not provided
generate_uuid() {
  if [[ -z "${SB_UUID}" ]]; then
    log_info "正在自动生成 UUID..."
    if command -v uuidgen &> /dev/null; then
      SB_UUID=$(uuidgen)
    else
      SB_UUID=$(cat /proc/sys/kernel/random/uuid)
    fi
  fi
  log_success "UUID: ${SB_UUID}"
}

# Generate REALITY Keypair
generate_keypair() {
  log_info "正在生成 REALITY 密钥对..."
  local keypair
  keypair=$("${SINGBOX_BIN_PATH}" generate reality-keypair)
  SB_PRIVATE_KEY=$(echo "${keypair}" | grep "PrivateKey" | awk '{print $2}')
  SB_PUBLIC_KEY=$(echo "${keypair}" | grep "PublicKey" | awk '{print $2}')
  
  if [[ -z "${SB_PRIVATE_KEY}" || -z "${SB_PUBLIC_KEY}" ]]; then
    log_error "密钥对生成失败。"
  fi
  log_success "密钥对生成成功。"
}

# Generate random ShortIDs (two 8-byte hex values)
generate_short_id() {
  log_info "正在生成 ShortIDs..."
  SB_SHORT_ID_1=$(openssl rand -hex 8)
  SB_SHORT_ID_2=$(openssl rand -hex 8)
  log_success "ShortID 1: ${SB_SHORT_ID_1}, ShortID 2: ${SB_SHORT_ID_2}"
}

# Generate JSON configuration
generate_config() {
  log_info "正在生成配置文件: ${SINGBOX_CONFIG_FILE}..."
  mkdir -p "${SINGBOX_CONFIG_DIR}"

  cat > "${SINGBOX_CONFIG_FILE}" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${SB_PORT},
      "sniff": true,
      "sniff_override_destination": true,
      "users": [
        {
          "uuid": "${SB_UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${SB_SNI}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${SB_SNI}",
            "server_port": 443
          },
          "private_key": "${SB_PRIVATE_KEY}",
          "short_id": [
            "${SB_SHORT_ID_1}",
            "${SB_SHORT_ID_2}"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ]
}
EOF
  log_success "配置文件生成成功。"
}

# Run Phase 3 Tasks
generate_uuid
generate_keypair
generate_short_id
generate_config
