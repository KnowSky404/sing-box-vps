# Connection Info Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split status output from connection credential output so only first install and explicit config regeneration show links/QR automatically, while menu `8` lets the user choose links, QR, or both.

**Architecture:** Keep all behavior in `install.sh` and decompose the current `display_info()` flow into focused helper functions: one for summary output, one for protocol-specific link rendering, one for QR rendering, and one for the interactive connection menu. Preserve the existing install/update logic and add shell regression tests for the new display rules.

**Tech Stack:** Bash, jq, qrencode, shell regression tests in `tests/`

---

### Task 1: Write regression coverage for the new display rules

**Files:**
- Modify: `tests/update_keeps_existing_config.sh`
- Create: `tests/post_install_shows_connection_info.sh`
- Create: `tests/mixed_qr_menu_shows_hint.sh`

- [ ] **Step 1: Write the failing test for post-install auto display**

```bash
POST_CONFIG_COUNT_FILE="${TMP_DIR}/post_config.count"
printf '0\n' > "${POST_CONFIG_COUNT_FILE}"

show_post_config_connection_info() {
  local current_count
  current_count=$(cat "${POST_CONFIG_COUNT_FILE}")
  printf '%s\n' "$((current_count + 1))" > "${POST_CONFIG_COUNT_FILE}"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/post_install_shows_connection_info.sh`
Expected: FAIL because the current install path still calls the old `display_info()` flow instead of the dedicated post-config renderer.

- [ ] **Step 3: Write the failing test for Mixed QR behavior**

```bash
QRENCODE_COUNT_FILE="${TMP_DIR}/qrencode.count"
printf '0\n' > "${QRENCODE_COUNT_FILE}"

qrencode() {
  local current_count
  current_count=$(cat "${QRENCODE_COUNT_FILE}")
  printf '%s\n' "$((current_count + 1))" > "${QRENCODE_COUNT_FILE}"
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `bash tests/mixed_qr_menu_shows_hint.sh`
Expected: FAIL because the old implementation has no connection info submenu and no Mixed QR suppression path.

- [ ] **Step 5: Commit**

```bash
git add tests/update_keeps_existing_config.sh tests/post_install_shows_connection_info.sh tests/mixed_qr_menu_shows_hint.sh
git commit -m "test: cover connection info display flows"
```

### Task 2: Split summary output from connection output in `install.sh`

**Files:**
- Modify: `install.sh`
- Test: `tests/post_install_shows_connection_info.sh`

- [ ] **Step 1: Write the failing summary/connection split expectation**

```bash
display_status_summary() { :; }
show_post_config_connection_info() { :; }
show_connection_info_menu() { :; }
```

- [ ] **Step 2: Run the post-install regression test and verify it still fails**

Run: `bash tests/post_install_shows_connection_info.sh`
Expected: FAIL because install still ends with `display_info`.

- [ ] **Step 3: Implement the minimal split in `install.sh`**

```bash
view_status_and_info() {
  log_info "正在从配置文件中读取信息..."
  load_current_config_state
  display_status_summary
  show_connection_info_menu
}

display_status_summary() {
  local public_ip
  local protocol_name
  public_ip=$(curl -s https://api.ip.sb/ip || curl -s https://ifconfig.me)
  protocol_name=$(protocol_display_name "${SB_PROTOCOL}")
  # only summary fields here
}
```

- [ ] **Step 4: Update install/config-regeneration call sites**

```bash
install_or_reconfigure_singbox() {
  # ...
  systemctl restart sing-box
  display_status_summary
  show_post_config_connection_info
}

update_config_only() {
  # ...
  systemctl restart sing-box
  display_status_summary
  show_post_config_connection_info
}

update_singbox_binary_preserving_config() {
  # ...
  systemctl restart sing-box
  display_status_summary
  log_info "连接信息未自动展示，如需查看请进入菜单 8。"
}
```

- [ ] **Step 5: Run regression test to verify it passes**

Run: `bash tests/post_install_shows_connection_info.sh`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add install.sh tests/post_install_shows_connection_info.sh
git commit -m "refactor: split status and connection info display"
```

### Task 3: Implement the protocol-specific connection info menu

**Files:**
- Modify: `install.sh`
- Test: `tests/mixed_qr_menu_shows_hint.sh`

- [ ] **Step 1: Write the failing Mixed QR test expectation**

```bash
if (( qrencode_calls != 0 )); then
  printf 'expected mixed QR path to skip qrencode, got %s\n' "${qrencode_calls}" >&2
  exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/mixed_qr_menu_shows_hint.sh`
Expected: FAIL

- [ ] **Step 3: Implement the connection artifact helpers**

```bash
build_vless_link() {
  printf 'vless://%s@%s:%s?security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&flow=xtls-rprx-vision#%s' \
    "${SB_UUID}" "${1}" "${SB_PORT}" "${SB_SNI}" "${SB_PUBLIC_KEY}" "${SB_SHORT_ID_1}" "${SB_NODE_NAME}"
}

build_mixed_http_link() {
  printf 'http://%s:%s@%s:%s' "${SB_MIXED_USERNAME}" "${SB_MIXED_PASSWORD}" "${1}" "${SB_PORT}"
}
```

- [ ] **Step 4: Implement the menu and protocol-specific renderers**

```bash
show_connection_info_menu() {
  while true; do
    echo "1. 仅链接"
    echo "2. 仅二维码"
    echo "3. 链接 + 二维码"
    echo "0. 返回"
    read -rp "请选择 [0-3]: " info_choice
    case "${info_choice}" in
      1) show_connection_details "link" ;;
      2) show_connection_details "qr" ;;
      3) show_connection_details "both" ;;
      0) return ;;
      *) log_warn "无效选项，请重新选择。" ;;
    esac
  done
}
```

- [ ] **Step 5: Add the Mixed QR hint path**

```bash
show_qr_info() {
  if [[ "${SB_PROTOCOL}" == "mixed" ]]; then
    log_info "Mixed 协议当前不提供二维码，请使用链接方式手动配置客户端。"
    return 0
  fi

  echo "1. REALITY 协议二维码"
  qrencode -t ansiutf8 "$(build_vless_link "${1}")"
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bash tests/mixed_qr_menu_shows_hint.sh`
Expected: PASS

Run: `bash tests/update_keeps_existing_config.sh`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add install.sh tests/mixed_qr_menu_shows_hint.sh tests/update_keeps_existing_config.sh
git commit -m "feat: add interactive connection info display"
```

### Task 4: Final verification

**Files:**
- Modify: `install.sh` (if needed)
- Test: `tests/update_keeps_existing_config.sh`
- Test: `tests/update_skips_restart_when_config_invalid.sh`
- Test: `tests/post_install_shows_connection_info.sh`
- Test: `tests/mixed_qr_menu_shows_hint.sh`

- [ ] **Step 1: Run syntax verification**

Run: `bash -n install.sh && bash -n tests/update_keeps_existing_config.sh && bash -n tests/update_skips_restart_when_config_invalid.sh && bash -n tests/post_install_shows_connection_info.sh && bash -n tests/mixed_qr_menu_shows_hint.sh`
Expected: exit 0

- [ ] **Step 2: Run behavior verification**

Run: `bash tests/update_keeps_existing_config.sh && bash tests/update_skips_restart_when_config_invalid.sh && bash tests/post_install_shows_connection_info.sh && bash tests/mixed_qr_menu_shows_hint.sh`
Expected: exit 0

- [ ] **Step 3: Commit any final fixes**

```bash
git add install.sh tests/update_keeps_existing_config.sh tests/update_skips_restart_when_config_invalid.sh tests/post_install_shows_connection_info.sh tests/mixed_qr_menu_shows_hint.sh
git commit -m "test: verify connection info display flows"
```
