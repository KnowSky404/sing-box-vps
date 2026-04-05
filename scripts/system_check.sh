#!/usr/bin/env bash

# System dependency installation and environmental verification
install_dependencies() {
  log_info "正在安装必要的基础依赖..."

  case "${OS_NAME}" in
    debian|ubuntu)
      apt-get update -y
      apt-get install -y curl wget jq tar openssl uuid-runtime
      ;;
    centos|almalinux|rocky)
      yum install -y curl wget jq tar openssl util-linux
      ;;
    *)
      log_error "Unsupported OS: ${OS_NAME}. Please install dependencies manually."
      ;;
  esac

  log_success "基础依赖安装完成。"
}

# Final check for essential tools
verify_tools() {
  local tools=("curl" "wget" "jq" "tar" "openssl")
  for tool in "${tools[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
      log_error "Required tool '$tool' is not installed."
    fi
  done
}

# Run Phase 2 tasks
install_dependencies
verify_tools
