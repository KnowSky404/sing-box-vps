#!/usr/bin/env bash

# Uninstall sing-box and cleanup all related files
uninstall_singbox() {
  log_info "正在停止 sing-box 服务..."
  systemctl stop sing-box &>/dev/null || true
  systemctl disable sing-box &>/dev/null || true

  log_info "正在删除相关文件..."
  rm -f "${SINGBOX_BIN_PATH}"
  rm -rf "${SINGBOX_CONFIG_DIR}"
  rm -f "${SINGBOX_SERVICE_FILE}"

  log_info "正在重载 systemd 守护进程..."
  systemctl daemon-reload

  log_success "sing-box 卸载与清理完成。"
}

# Run the uninstaller
uninstall_singbox
