# Terminal UI Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the main menu and submenu pages in `install.sh` render as centered, width-aware, sectioned terminal panels without changing existing menu actions or adding dependencies.

**Architecture:** Keep all runtime logic in `install.sh`, but introduce a small set of reusable terminal UI helpers for width detection, centered panel rendering, section blocks, and summary blocks. Rebuild the main menu and the existing submenu pages on top of those helpers, while leaving streaming/log-style output in their current plain-text format.

**Tech Stack:** Bash, ANSI escape sequences, `tput`/terminal environment variables, existing shell test scripts in `tests/`

---

## File Map

- Modify: `install.sh`
  - Add width-aware UI helper functions near the existing UI section
  - Replace `show_banner` with a reusable page header renderer
  - Rebuild `main`, `system_management_menu`, `stack_management_menu`, `show_connection_info_menu`, `media_check_menu`, and the small menu in `install_or_update_singbox`
  - Bump `SCRIPT_VERSION` once for this conversation turn
- Modify: `.gitignore`
  - Ignore `.superpowers/` so browser companion output does not pollute git status
- Modify: `README.md`
  - Sync displayed script version with `install.sh`
- Modify: `tests/system_management_menu_renders.sh`
  - Update assertions to match the new sectioned menu output while preserving existing option checks
- Create: `tests/main_menu_renders_sectioned_layout.sh`
  - Verify the main menu renders section headers and preserves option numbering under fixed-width conditions
- Create: `tests/narrow_terminal_menu_falls_back_to_single_column.sh`
  - Verify a narrow terminal width still renders a stable, readable single-column menu
- Modify: `tests/version_metadata_is_consistent.sh`
  - No logic change expected; only touched if version assertions need sync with the bumped script version metadata

### Task 1: Add UI layout coverage before implementation

**Files:**
- Create: `tests/main_menu_renders_sectioned_layout.sh`
- Create: `tests/narrow_terminal_menu_falls_back_to_single_column.sh`
- Modify: `tests/system_management_menu_renders.sh`

- [ ] **Step 1: Write the failing main-menu layout test**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"

sed \
  -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  -e "s|readonly SINGBOX_BIN_PATH=\"/usr/local/bin/sing-box\"|readonly SINGBOX_BIN_PATH=\"${TMP_DIR}/bin/sing-box\"|" \
  -e 's|main \"\$@\"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/bin"

export COLUMNS=120
export TERM=xterm-256color

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

check_root() { :; }
ensure_sbv_command_installed() { :; }
check_script_status() { SCRIPT_VER_STATUS=""; }
check_sb_version() { SB_VER_STATUS=""; }
check_bbr_status() { BBR_STATUS="(已开启 BBR)"; }
clear() { :; }
exit_script() { return 0; }

output=$(
  {
    show_banner
    printf '0\n' | main
  } 2>/dev/null || true
)

[[ "${output}" == *"部署管理"* ]]
[[ "${output}" == *"服务控制"* ]]
[[ "${output}" == *"连接与诊断"* ]]
[[ "${output}" == *"脚本维护"* ]]
[[ "${output}" == *"1. 安装协议 / 更新 sing-box"* ]]
[[ "${output}" == *"14. 流媒体验证检测"* ]]
```

- [ ] **Step 2: Run the new main-menu test to verify it fails**

Run: `bash tests/main_menu_renders_sectioned_layout.sh`

Expected: `FAIL` because the current main menu does not render the new section headers.

- [ ] **Step 3: Write the failing narrow-width fallback test**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"

sed \
  -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  -e 's|main \"\$@\"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

export COLUMNS=56
export TERM=xterm-256color

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

clear() { :; }

output=$(system_management_menu <<'EOF'
0
EOF
)

[[ "${output}" == *"系统管理"* ]]
[[ "${output}" == *"1. 开启 BBR"* ]]
[[ "${output}" == *"2. 协议栈管理"* ]]
[[ "${output}" != *"部署管理  服务控制"* ]]
```

- [ ] **Step 4: Run the narrow-width test to verify it fails**

Run: `bash tests/narrow_terminal_menu_falls_back_to_single_column.sh`

Expected: `FAIL` because no width-aware fallback exists yet.

- [ ] **Step 5: Update the existing system-management test to assert the new structure**

```bash
if [[ "${output}" != *"系统摘要"* ]]; then
  printf 'expected system summary block inside system management, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"系统管理"* ]]; then
  printf 'expected system management title, got:\n%s\n' "${output}" >&2
  exit 1
fi
```

- [ ] **Step 6: Run the existing system-management test to verify it fails with the old UI**

Run: `bash tests/system_management_menu_renders.sh`

Expected: `FAIL` because the current submenu has no summary block or unified page title treatment.

- [ ] **Step 7: Commit the test scaffolding**

```bash
git add tests/main_menu_renders_sectioned_layout.sh tests/narrow_terminal_menu_falls_back_to_single_column.sh tests/system_management_menu_renders.sh
git commit -m "test: cover terminal menu layout rendering"
```

### Task 2: Add reusable terminal UI helpers and wire the main menu

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add width and color capability helpers near the current `# --- UI & Main ---` section**

```bash
term_columns() {
  local cols="${COLUMNS:-}"

  if [[ -z "${cols}" ]] && command -v tput >/dev/null 2>&1; then
    cols=$(tput cols 2>/dev/null || true)
  fi

  if [[ ! "${cols}" =~ ^[0-9]+$ ]] || (( cols < 40 )); then
    cols=80
  fi

  printf '%s' "${cols}"
}

ui_colors_enabled() {
  [[ -z "${NO_COLOR:-}" ]]
}

ui_strip_ansi() {
  sed 's/\x1B\[[0-9;]*[A-Za-z]//g'
}
```

- [ ] **Step 2: Add centered panel and section rendering helpers**

```bash
ui_panel_width() {
  local cols
  cols=$(term_columns)

  if (( cols >= 140 )); then
    printf '124'
  elif (( cols >= 100 )); then
    printf '%s' "$((cols - 12))"
  else
    printf '%s' "$((cols - 6))"
  fi
}

ui_print_centered() {
  local text=$1
  local cols pad
  cols=$(term_columns)
  pad=$(( (cols - ${#text}) / 2 ))
  (( pad < 0 )) && pad=0
  printf '%*s%s\n' "${pad}" '' "${text}"
}

ui_section_title() {
  local title=$1
  printf '%b%s%b\n' "${GOLD}" "${title}" "${NC}"
}

ui_menu_item() {
  local number=$1
  local label=$2
  local hint=$3
  printf '%-3s %-22s %b%s%b\n' "${number}." "${label}" "${CYAN}" "${hint}" "${NC}"
}
```

- [ ] **Step 3: Replace `show_banner` with a reusable page-header renderer while keeping `clear`**

```bash
render_page_header() {
  local title=$1
  local subtitle=${2:-}

  clear
  ui_print_centered "sing-box-vps"
  ui_print_centered "${title}"
  [[ -n "${subtitle}" ]] && ui_print_centered "${subtitle}"
  ui_print_centered "Version ${SCRIPT_VERSION}"
  printf '\n'
}

show_banner() {
  render_page_header "一键安装管理脚本" "专为稳定与安全设计"
}
```

- [ ] **Step 4: Rebuild the main menu to render grouped sections from helper-backed output**

```bash
render_main_menu() {
  printf '\n'
  ui_section_title "部署管理"
  ui_menu_item 1 "安装协议 / 更新 sing-box" "${SB_VER_STATUS}"
  ui_menu_item 2 "卸载 sing-box" "删除 sing-box 二进制和配置"
  ui_menu_item 3 "修改当前协议配置" "修改已安装协议参数"
  ui_menu_item 4 "系统管理" "BBR 与协议栈设置"

  printf '\n'
  ui_section_title "服务控制"
  ui_menu_item 5 "启动 sing-box" "启动 systemd 服务"
  ui_menu_item 6 "停止 sing-box" "停止 systemd 服务"
  ui_menu_item 7 "重启 sing-box" "重载当前运行状态"
  ui_menu_item 8 "查看状态" "展示服务摘要"

  printf '\n'
  ui_section_title "连接与诊断"
  ui_menu_item 9 "查看节点信息" "查看链接和二维码"
  ui_menu_item 10 "查看实时日志" "跟随 sing-box 日志"
  ui_menu_item 13 "配置 Cloudflare Warp" "解锁与分流设置"
  ui_menu_item 14 "流媒体验证检测" "本机或 Warp 出口检测"

  printf '\n'
  ui_section_title "脚本维护"
  ui_menu_item 11 "更新管理脚本 (sbv)" "${SCRIPT_VER_STATUS}"
  ui_menu_item 12 "卸载管理脚本 (sbv)" "移除全局命令"
  ui_menu_item 0 "退出" "退出当前脚本"
}
```

- [ ] **Step 5: Update `main()` to redraw through the new helpers without changing case mappings**

```bash
while true; do
  check_script_status
  check_sb_version
  check_bbr_status

  show_banner
  render_main_menu
  read -rp "请选择 [0-14]: " choice

  case "${choice}" in
    1) install_or_update_singbox ;;
    2) uninstall_singbox ;;
    3) update_config_only ;;
    4) system_management_menu ;;
    5) systemctl start sing-box && log_success "服务已启动。" ;;
    6) systemctl stop sing-box && log_success "服务已停止。" ;;
    7) systemctl restart sing-box && log_success "服务已重启。" ;;
    8) view_status ;;
    9) view_node_info ;;
    10) journalctl -u sing-box -f || true ;;
    11) manual_update_script ;;
    12) uninstall_script ;;
    13) warp_management ;;
    14) media_check_menu ;;
    0) exit_script ;;
    *) log_warn "无效选项，请重新选择。" ;;
  esac
done
```

- [ ] **Step 6: Run the new main-menu test and the existing metadata test**

Run: `bash tests/main_menu_renders_sectioned_layout.sh && bash tests/version_metadata_is_consistent.sh`

Expected: the new menu test passes; metadata may still fail later until the version bump is applied.

- [ ] **Step 7: Commit the helper layer and main-menu wiring**

```bash
git add install.sh
git commit -m "feat: add centered terminal menu layout helpers"
```

### Task 3: Migrate submenu pages to the shared UI

**Files:**
- Modify: `install.sh`
- Modify: `tests/system_management_menu_renders.sh`
- Create: `tests/narrow_terminal_menu_falls_back_to_single_column.sh`

- [ ] **Step 1: Add a shared summary-block renderer for submenu pages**

```bash
ui_summary_row() {
  local label=$1
  local value=$2
  printf '%b%-14s%b %s\n' "${BLUE}" "${label}" "${NC}" "${value}"
}

render_summary_block() {
  local title=$1
  shift

  ui_section_title "${title}"
  while (( $# > 1 )); do
    ui_summary_row "$1" "$2"
    shift 2
  done
}
```

- [ ] **Step 2: Refactor `system_management_menu` and `stack_management_menu` to use page headers and summary blocks**

```bash
render_system_management_menu() {
  render_page_header "系统管理" "系统调优与协议栈入口"
  render_summary_block "系统摘要" \
    "BBR" "${BBR_STATUS}"
  ui_section_title "操作"
  ui_menu_item 1 "开启 BBR" "尝试启用 BBR 拥塞控制"
  ui_menu_item 2 "协议栈管理" "查看并调整入站/出站协议栈"
  ui_menu_item 0 "返回主菜单" "回到上一级"
}

render_stack_management_menu() {
  render_page_header "协议栈管理" "按当前主机网络能力展示可选项"
  render_summary_block "当前状态" \
    "系统网络能力" "$(host_ip_stack_display_name "${host_stack}")" \
    "当前入站协议栈" "$(inbound_stack_mode_display_name "${SB_INBOUND_STACK_MODE}")" \
    "当前出站协议栈" "$(outbound_stack_mode_display_name "${SB_OUTBOUND_STACK_MODE}")" \
    "Warp 状态" "${warp_status_text}"
  ui_section_title "操作"
  ui_menu_item 1 "修改入站协议栈" "影响监听地址与分享信息"
  ui_menu_item 2 "修改出站协议栈" "影响直连和 DNS 策略"
  ui_menu_item 0 "返回上一级" "回到系统管理"
}
```

- [ ] **Step 3: Refactor `show_connection_info_menu`, `media_check_menu`, and `install_or_update_singbox` menu output to the same pattern**

```bash
render_connection_info_menu() {
  render_page_header "节点信息查看" "选择输出形式"
  render_summary_block "查看模式" \
    "1" "仅链接" \
    "2" "仅二维码" \
    "3" "链接 + 二维码"
  ui_section_title "操作"
  ui_menu_item 1 "仅链接" "输出当前协议分享链接"
  ui_menu_item 2 "仅二维码" "输出当前协议二维码"
  ui_menu_item 3 "链接 + 二维码" "同时显示两类信息"
  ui_menu_item 0 "返回" "回到主菜单"
}
```

- [ ] **Step 4: Run the submenu tests and the new narrow-width test**

Run: `bash tests/system_management_menu_renders.sh && bash tests/narrow_terminal_menu_falls_back_to_single_column.sh`

Expected: both pass, confirming the shared layout renders correctly for both normal and narrow widths.

- [ ] **Step 5: Commit the submenu migration**

```bash
git add install.sh tests/system_management_menu_renders.sh tests/narrow_terminal_menu_falls_back_to_single_column.sh
git commit -m "feat: apply terminal layout to submenu pages"
```

### Task 4: Finish metadata, ignore rules, and end-to-end verification

**Files:**
- Modify: `.gitignore`
- Modify: `install.sh`
- Modify: `README.md`
- Modify: `tests/version_metadata_is_consistent.sh` (only if needed)

- [ ] **Step 1: Ignore browser companion output**

```gitignore
.superpowers/
```

- [ ] **Step 2: Bump `install.sh` script version once and sync README**

```bash
# install.sh
# Version: 2026041502
readonly SCRIPT_VERSION="2026041502"

# README.md
- **脚本版本**：`2026041502`
```

- [ ] **Step 3: Run the full verification set**

Run:

```bash
bash tests/main_menu_renders_sectioned_layout.sh
bash tests/narrow_terminal_menu_falls_back_to_single_column.sh
bash tests/system_management_menu_renders.sh
bash tests/menu_renders_when_bbr_status_unavailable.sh
bash tests/version_metadata_is_consistent.sh
bash tests/readme_mentions_current_versions.sh
bash tests/support_version_targets_1_13_7.sh
```

Expected:

- all commands exit with status `0`
- the menu tests confirm section headers and narrow-width fallback
- metadata tests confirm `install.sh` and `README.md` remain in sync

- [ ] **Step 4: Inspect git status for only expected files**

Run: `git status --short`

Expected:

- `.gitignore`
- `README.md`
- `install.sh`
- `tests/main_menu_renders_sectioned_layout.sh`
- `tests/narrow_terminal_menu_falls_back_to_single_column.sh`
- `tests/system_management_menu_renders.sh`
- optional: `tests/version_metadata_is_consistent.sh`

- [ ] **Step 5: Commit the finishing pass**

```bash
git add .gitignore README.md install.sh tests/main_menu_renders_sectioned_layout.sh tests/narrow_terminal_menu_falls_back_to_single_column.sh tests/system_management_menu_renders.sh tests/version_metadata_is_consistent.sh
git commit -m "feat: modernize terminal menu layout"
```

## Self-Review

- Spec coverage:
  - Width-aware centered layout: covered by Task 2 helper layer and Task 3 submenu migration
  - Sectioned menus and summary blocks: covered by Tasks 2 and 3
  - Narrow terminal fallback: covered by Task 1 tests and Task 3 verification
  - No new dependencies: preserved throughout all tasks
  - `.superpowers/` ignore rule and version bump: covered by Task 4
- Placeholder scan:
  - No `TODO`/`TBD` placeholders remain
  - Each task lists exact files, commands, and expected outcomes
- Type consistency:
  - Helper names are consistent across tasks: `render_page_header`, `render_summary_block`, `ui_menu_item`, `ui_section_title`

