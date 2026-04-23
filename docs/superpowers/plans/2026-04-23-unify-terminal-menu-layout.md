# Unified Terminal Menu Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify every numeric selection menu in `install.sh` under the same left-aligned console panel style already established by the main menu, removing the remaining centered legacy submenu layouts and one-off lightweight menu renderings.

**Architecture:** Keep the runtime logic in `install.sh`, but stop treating submenu layout as a page-by-page special case. First extend the terminal UI helper layer with a left-aligned submenu header and a lightweight menu section renderer, then migrate menus in two passes: standard submenus that already use `render_page_header()`, and lightweight selection menus embedded in install/update and node-info flows. Finish by bumping the script version once and running the focused shell regressions plus the required verification runner.

**Tech Stack:** Bash, ANSI terminal output helpers, shell regression tests in `tests/`, project verification runner in `dev/verification/run.sh`

---

## File Map

- Modify: `install.sh`
  - Owns `SCRIPT_VERSION`, terminal UI helpers, and every menu render path that needs to be unified.
- Modify: `tests/system_management_menu_renders.sh`
  - Existing regression for a standard submenu; should change from “centered padded title” expectations to “left-aligned submenu header” expectations.
- Modify: `tests/main_menu_renders_sectioned_layout.sh`
  - Existing regression for the visual baseline; should keep passing while submenu work lands.
- Create: `tests/node_info_action_menu_renders.sh`
  - Covers a lightweight two-option selection menu under menu `9`, proving small menus use the new left-aligned structure.
- Create: `tests/install_update_menu_renders_left_aligned.sh`
  - Covers the install/update flow menu(s), proving embedded lifecycle menus stop using centered legacy layout.
- Verify: `tests/narrow_terminal_menu_falls_back_to_single_column.sh`
  - Existing narrow-width regression; must stay green after helper changes.
- Verify: `tests/menu_renders_when_update_check_response_is_unexpected.sh`
  - Existing main-menu stability regression; must stay green.
- Verify: `tests/version_metadata_is_consistent.sh`
  - Existing version metadata regression after the one-time version bump.
- Modify: `README.md`
  - Sync displayed script version with `install.sh`.

## Task 1: Lock Down The New Rendering Baseline With Failing Tests

**Files:**
- Modify: `tests/system_management_menu_renders.sh`
- Create: `tests/node_info_action_menu_renders.sh`
- Create: `tests/install_update_menu_renders_left_aligned.sh`
- Verify: `tests/main_menu_renders_sectioned_layout.sh`

- [ ] **Step 1: Rewrite the standard submenu regression to expect a left-aligned submenu header**

In `tests/system_management_menu_renders.sh`, replace the old padded-title assertion with a flush-left assertion and keep the summary ordering checks:

```bash
title_text_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "系统管理") { print; exit }')
if [[ -z "${title_text_line}" || ! "${title_text_line}" =~ ^[^[:space:]] ]]; then
  printf 'expected system management header title to render flush-left, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" == *"作者: KnowSky404"* ]]; then
  printf 'expected submenu header to avoid main-menu brand metadata, got:\n%s\n' "${output}" >&2
  exit 1
fi

title_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "系统管理") { print NR; exit }')
summary_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "系统摘要") { print NR; exit }')
bbr_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "1. 开启 BBR") { print NR; exit }')

if ! (( title_line < summary_line && summary_line < bbr_line )); then
  printf 'expected summary block to remain between submenu title and options, got:\n%s\n' "${output}" >&2
  exit 1
fi
```

- [ ] **Step 2: Add a failing lightweight node-info menu regression**

Create `tests/node_info_action_menu_renders.sh` using `tests/menu_test_helper.sh` and assert the two-option node-info action menu is flush-left and grouped:

```bash
#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

output=$(show_node_info_action_menu <<'EOF'
0
EOF
)

plain_output=$(strip_ansi "${output}")
title_text_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "节点信息查看") { print; exit }')
section_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "操作选项") { print NR; exit }')
view_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "1. 查看连接链接 / 二维码") { print NR; exit }')
export_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "2. 导出 sing-box 裸核客户端配置") { print NR; exit }')

if [[ -z "${title_text_line}" || ! "${title_text_line}" =~ ^[^[:space:]] ]]; then
  printf 'expected node info action menu title to render flush-left, got:\n%s\n' "${output}" >&2
  exit 1
fi

if ! (( section_line < view_line && view_line < export_line )); then
  printf 'expected node info action menu options to stay grouped under the action section, got:\n%s\n' "${output}" >&2
  exit 1
fi
```

- [ ] **Step 3: Add a failing install/update embedded-menu regression**

Create `tests/install_update_menu_renders_left_aligned.sh` and assert the healthy-instance install/update menu uses a flush-left header instead of a centered page title:

```bash
#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

detect_existing_instance_state() { printf 'healthy'; }
load_current_config_state() { SB_PROTOCOL="vless+reality"; SB_PORT="443"; }

mkdir -p "$(dirname "${SINGBOX_BIN_PATH}")"
cat > "${SINGBOX_BIN_PATH}" <<'EOF'
#!/usr/bin/env bash
printf 'sing-box version 1.13.9\n'
EOF
chmod +x "${SINGBOX_BIN_PATH}"

output=$(install_or_update_singbox <<'EOF'
0
EOF
)

plain_output=$(strip_ansi "${output}")
title_text_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "sing-box 管理") { print; exit }')

if [[ -z "${title_text_line}" || ! "${title_text_line}" =~ ^[^[:space:]] ]]; then
  printf 'expected install/update menu title to render flush-left, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" != *"1. 更新 sing-box 二进制并保留当前配置"* ]]; then
  printf 'expected update option inside install/update menu, got:\n%s\n' "${output}" >&2
  exit 1
fi
```

- [ ] **Step 4: Run the focused menu regressions and confirm they fail against the current mixed layout**

Run: `bash tests/system_management_menu_renders.sh && bash tests/node_info_action_menu_renders.sh && bash tests/install_update_menu_renders_left_aligned.sh`

Expected: FAIL. `tests/system_management_menu_renders.sh` should fail on the flush-left title assertion first because standard submenus still use centered `render_page_header()`.

- [ ] **Step 5: Re-run the main-menu baseline to confirm the reference style remains stable before helper work**

Run: `bash tests/main_menu_renders_sectioned_layout.sh`

Expected: PASS with no output.

- [ ] **Step 6: Commit the failing test scaffolding**

```bash
git add tests/system_management_menu_renders.sh tests/node_info_action_menu_renders.sh tests/install_update_menu_renders_left_aligned.sh
git commit -m "test: cover unified terminal menu layout"
```

## Task 2: Add Shared Left-Aligned Submenu Helpers

**Files:**
- Modify: `install.sh`
- Verify: `tests/system_management_menu_renders.sh`
- Verify: `tests/main_menu_renders_sectioned_layout.sh`
- Verify: `tests/narrow_terminal_menu_falls_back_to_single_column.sh`

- [ ] **Step 1: Add a left-aligned page-header helper next to the existing UI rendering helpers**

In `install.sh`, add a helper after `render_main_menu_brand_block()` so submenus can share the main menu’s left edge without inheriting its brand metadata:

```bash
render_left_aligned_page_header() {
  local title=$1
  local subtitle=${2:-}
  local width divider

  width=$(term_columns)
  if (( width < 1 )); then
    width=1
  fi
  divider=$(repeat_char "═" "${width}")

  echo -e "${BLUE}${divider}${NC}"
  echo -e "${GREEN}${title}${NC}"
  if [[ -n "${subtitle}" ]]; then
    echo -e "${BLUE}${subtitle}${NC}"
  fi
  echo -e "${BLUE}${divider}${NC}"
}
```

- [ ] **Step 2: Add a lightweight menu section wrapper for small numeric menus**

Still in `install.sh`, add a small helper that standardizes the “section heading + choices” pattern for tiny menus without forcing a separate summary block:

```bash
render_menu_group_start() {
  local title=${1:-}

  if [[ -n "${title}" ]]; then
    render_section_title "${title}"
  else
    echo
  fi
}
```

This helper is intentionally small; the point is to stop lightweight menus from open-coding layout decisions.

- [ ] **Step 3: Keep `show_banner()` on the main-menu-specific brand block**

Do not route `show_banner()` through the new submenu helper. Ensure the code still looks like:

```bash
show_banner() {
  safe_clear_screen
  render_main_menu_brand_block
  echo
}
```

This preserves the main menu as the visual baseline while submenu helpers are introduced.

- [ ] **Step 4: Run the baseline regressions after helper-only changes**

Run: `bash tests/main_menu_renders_sectioned_layout.sh && bash tests/narrow_terminal_menu_falls_back_to_single_column.sh`

Expected: PASS with no output. Helper additions alone should not change behavior yet.

- [ ] **Step 5: Commit the helper layer**

```bash
git add install.sh
git commit -m "feat: add shared submenu layout helpers"
```

## Task 3: Migrate Standard Submenus Off The Centered Header Path

**Files:**
- Modify: `install.sh`
- Verify: `tests/system_management_menu_renders.sh`
- Verify: `tests/main_menu_renders_sectioned_layout.sh`
- Verify: `tests/narrow_terminal_menu_falls_back_to_single_column.sh`

- [ ] **Step 1: Switch the standard submenu entry points to the new left-aligned header**

Update these functions in `install.sh`:

- `configure_inbound_stack_mode()`
- `configure_outbound_stack_mode()`
- `stack_management_menu()`
- `system_management_menu()`
- `warp_management()`
- `show_connection_info_menu()`
- `media_check_menu()`

Each should replace:

```bash
render_page_header "系统管理" "维护内核优化与网络协议栈设置"
```

with:

```bash
render_left_aligned_page_header "系统管理" "维护内核优化与网络协议栈设置"
```

Do not change the business logic or option ordering inside these functions.

- [ ] **Step 2: Keep the existing summary blocks, section labels, and menu items intact**

For example, `system_management_menu()` should still render this structure after the header swap:

```bash
render_left_aligned_page_header "系统管理" "维护内核优化与网络协议栈设置"
render_section_title "系统摘要"
render_summary_item "BBR 状态" "${BBR_STATUS}"
render_section_title "操作选项"
render_menu_item "1" "开启 BBR"
render_menu_item "2" "协议栈管理"
echo "0. 返回主菜单"
```

The migration target is visual alignment, not menu restructuring.

- [ ] **Step 3: Run the standard submenu regressions**

Run: `bash tests/system_management_menu_renders.sh && bash tests/main_menu_renders_sectioned_layout.sh && bash tests/narrow_terminal_menu_falls_back_to_single_column.sh`

Expected: PASS with no output. `tests/system_management_menu_renders.sh` should now see a flush-left title while the main menu baseline remains unchanged.

- [ ] **Step 4: Commit the standard submenu migration**

```bash
git add install.sh tests/system_management_menu_renders.sh
git commit -m "feat: left align standard submenu headers"
```

## Task 4: Migrate Lightweight Selection Menus And Embedded Lifecycle Menus

**Files:**
- Modify: `install.sh`
- Verify: `tests/node_info_action_menu_renders.sh`
- Verify: `tests/install_update_menu_renders_left_aligned.sh`
- Verify: `tests/menu_renders_when_update_check_response_is_unexpected.sh`

- [ ] **Step 1: Switch the node-info action menu and connection display selector**

In `install.sh`, update:

- `show_node_info_action_menu()`
- `show_connection_info_menu()`

The node-info action menu should retain its current options but use the shared left-aligned structure:

```bash
render_left_aligned_page_header "节点信息查看" "选择要执行的节点信息操作"
render_menu_group_start "操作选项"
render_menu_item "1" "查看连接链接 / 二维码"
render_menu_item "2" "导出 sing-box 裸核客户端配置"
echo "0. 返回"
```

- [ ] **Step 2: Switch install/update lifecycle menus to the new header path**

In `install_or_update_singbox()`, update both the `healthy` and `incomplete` instance branches so they use `render_left_aligned_page_header()` instead of `render_page_header()`. Keep the existing summaries and option lines unchanged:

```bash
render_left_aligned_page_header "sing-box 管理" "更新核心或为现有实例补充协议"
render_section_title "安装摘要"
render_summary_item "当前版本" "${installed_ver}"
render_summary_item "当前协议" "$(protocol_display_name "${SB_PROTOCOL}")"
render_summary_item "当前端口" "${SB_PORT}"
```

and:

```bash
render_left_aligned_page_header "sing-box 管理" "发现现有实例缺少关键组件"
render_section_title "实例检测"
echo "检测到残缺的现有实例。"
render_section_title "操作选项"
```

- [ ] **Step 3: Switch the smallest selection menus that still branch by numeric choice**

In `install.sh`, update these functions to use `render_left_aligned_page_header()` plus `render_menu_group_start` where appropriate:

- `media_check_menu()`
- `set_warp_route_mode_interactive()`
- `show_connection_info_menu()`
- any remaining numeric-choice pages found via `rg -n 'render_page_header|render_menu_item "' install.sh`

At minimum, a lightweight menu should look like:

```bash
render_left_aligned_page_header "Warp 路由模式" "选择当前实例的 Warp 出口策略"
render_menu_group_start "模式选项"
render_menu_item "1" "全量流量走 Warp"
render_menu_item "2" "仅 AI/流媒体及自定义规则走 Warp"
```

- [ ] **Step 4: Run the lightweight-menu regressions**

Run: `bash tests/node_info_action_menu_renders.sh && bash tests/install_update_menu_renders_left_aligned.sh && bash tests/menu_renders_when_update_check_response_is_unexpected.sh`

Expected: PASS with no output.

- [ ] **Step 5: Commit the lightweight menu migration**

```bash
git add install.sh tests/node_info_action_menu_renders.sh tests/install_update_menu_renders_left_aligned.sh
git commit -m "feat: unify lightweight terminal selection menus"
```

## Task 5: Bump Version Metadata And Run Required Verification

**Files:**
- Modify: `install.sh`
- Modify: `README.md`
- Verify: `tests/version_metadata_is_consistent.sh`
- Verify: `tests/main_menu_renders_sectioned_layout.sh`
- Verify: `tests/system_management_menu_renders.sh`
- Verify: `tests/node_info_action_menu_renders.sh`
- Verify: `tests/install_update_menu_renders_left_aligned.sh`
- Verify: `tests/narrow_terminal_menu_falls_back_to_single_column.sh`
- Verify: `tests/menu_renders_when_update_check_response_is_unexpected.sh`
- Verify: `bash dev/verification/run.sh --changed-file install.sh --changed-file README.md --changed-file tests/system_management_menu_renders.sh --changed-file tests/node_info_action_menu_renders.sh --changed-file tests/install_update_menu_renders_left_aligned.sh`

- [ ] **Step 1: Bump the script version once for this code-bearing turn**

Update `install.sh` and `README.md` from `2026042311` to the next `YYYYMMDDXX` value for April 23, 2026 only if no later code-bearing version has landed locally; otherwise increment from the current checked-in version to the next available `YYYYMMDDXX` value on top of the checked-in version.

If `2026042311` is still current, the exact edits are:

```bash
# install.sh
# Version: 2026042312
readonly SCRIPT_VERSION="2026042312"
```

```markdown
- 脚本版本：`2026042312`
```

Use `2026042312` specifically when the repository still shows `2026042311`, because the project rule requires a single version bump for this conversation turn.

- [ ] **Step 2: Run the focused local regressions**

Run: `bash tests/version_metadata_is_consistent.sh && bash tests/main_menu_renders_sectioned_layout.sh && bash tests/system_management_menu_renders.sh && bash tests/node_info_action_menu_renders.sh && bash tests/install_update_menu_renders_left_aligned.sh && bash tests/narrow_terminal_menu_falls_back_to_single_column.sh && bash tests/menu_renders_when_update_check_response_is_unexpected.sh`

Expected: PASS with no output.

- [ ] **Step 3: Run the required project verification workflow for touched menu files**

Run: `bash dev/verification/run.sh --changed-file install.sh --changed-file README.md --changed-file tests/system_management_menu_renders.sh --changed-file tests/node_info_action_menu_renders.sh --changed-file tests/install_update_menu_renders_left_aligned.sh`

Expected: PASS. Because this turn changes `install.sh`, the project rules require the verification runner instead of stopping at local shell tests.

- [ ] **Step 4: Commit the version bump and verified menu refresh**

```bash
git add install.sh README.md tests/system_management_menu_renders.sh tests/node_info_action_menu_renders.sh tests/install_update_menu_renders_left_aligned.sh docs/superpowers/plans/2026-04-23-unify-terminal-menu-layout.md
git commit -m "feat: unify terminal menu layout"
```

## Self-Review Checklist

- Spec coverage:
  - All numeric menus unify to the main menu’s left-aligned baseline: Tasks 2-4
  - Standard submenus no longer use centered legacy headers: Task 3
  - Lightweight embedded menus are explicitly included: Task 4
  - Non-menu outputs remain out of scope: no task touches connection-detail/log/QR rendering
  - Single version bump for the code-bearing turn: Task 5
- Placeholder scan:
  - No `TODO`, `TBD`, “similar to above”, or “write tests later” placeholders remain.
- Type and name consistency:
  - `render_left_aligned_page_header()` is the shared submenu helper introduced in Task 2 and reused later.
  - `render_menu_group_start()` is the lightweight grouping helper introduced in Task 2 and reused later.
  - Menu function names match the current `install.sh` entry points discovered during plan writing.
