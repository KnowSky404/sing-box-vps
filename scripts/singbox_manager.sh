#!/usr/bin/env bash

# Fetch latest version of sing-box if version is 'latest'
get_latest_version() {
  if [[ "${SB_VERSION}" == "latest" ]]; then
    log_info "正在获取 sing-box 最新版本号..."
    SB_VERSION=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | jq -r .tag_name | sed 's/^v//')
    if [[ -z "${SB_VERSION}" ]]; then
      log_error "无法获取最新版本号，请手动指定版本。"
    fi
    log_success "最新版本为: ${SB_VERSION}"
  fi
}

# Download and install sing-box binary
install_binary() {
  local download_url="https://github.com/SagerNet/sing-box/releases/download/v${SB_VERSION}/sing-box-${SB_VERSION}-linux-${ARCH}.tar.gz"
  local temp_dir="/tmp/sing-box-install"
  local temp_file="${temp_dir}/sing-box.tar.gz"

  mkdir -p "${temp_dir}"
  log_info "开始下载 sing-box ${SB_VERSION} (${ARCH})..."
  if ! wget -O "${temp_file}" "${download_url}"; then
    log_error "下载 sing-box 失败，请检查网络连接。"
  fi

  log_info "正在解压并安装..."
  tar -xzf "${temp_file}" -C "${temp_dir}"
  # Find binary path in extracted files
  local bin_source=$(find "${temp_dir}" -name "sing-box" -type f)
  if [[ -z "${bin_source}" ]]; then
    log_error "在下载包中找不到二进制文件。"
  fi

  mv -f "${bin_source}" "${SINGBOX_BIN_PATH}"
  chmod +x "${SINGBOX_BIN_PATH}"
  
  # Clean up
  rm -rf "${temp_dir}"
  log_success "sing-box 二进制文件安装成功。"
}

# Create systemd service
setup_service() {
  log_info "正在配置 systemd 服务..."
  cat > "${SINGBOX_SERVICE_FILE}" <<EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=${SINGBOX_BIN_PATH} run -c ${SINGBOX_CONFIG_FILE}
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable sing-box >/dev/null 2>&1
  log_success "systemd 服务配置完成。"
}

# Run Phase 3 tasks
get_latest_version
install_binary
setup_service
