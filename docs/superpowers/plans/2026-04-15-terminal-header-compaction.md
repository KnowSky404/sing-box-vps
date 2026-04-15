# Terminal Header Compaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compress the terminal menu header so the main menu shows more content within one screen while moving author/project info to a low-priority footer on the main menu only.

**Architecture:** Reuse the existing terminal UI helper layer in `install.sh`, but split the current header responsibilities into a compact main-menu header, a lightweight main-menu footer, and a leaner submenu header. Keep all existing menu numbering and business logic unchanged while updating tests to verify the new information placement.

**Tech Stack:** Bash, ANSI terminal output, existing shell tests in `tests/`

---

## File Map

- Modify: `install.sh`
  - Compact the shared header renderer
  - Add a main-menu-only footer renderer for author/project info
  - Remove author/project info from the top banner
  - Suppress version/author/project info from submenu headers
- Modify: `tests/main_menu_renders_sectioned_layout.sh`
  - Assert main-menu header no longer carries author/project lines
  - Assert main-menu footer now contains author/project info
- Modify: `tests/system_management_menu_renders.sh`
  - Assert submenu output does not include author/project info
- Modify: `README.md`
  - Sync script version after the next code change
- Modify: `tests/version_metadata_is_consistent.sh`
  - No logic change expected; only metadata sync if needed

### Task 1: Add failing tests for compact header and footer placement

**Files:**
- Modify: `tests/main_menu_renders_sectioned_layout.sh`
- Modify: `tests/system_management_menu_renders.sh`

- [ ] **Step 1: Add a failing main-menu assertion that author/project are no longer in the header block**

```bash
header_block=$(printf '%s\n' "${plain_output}" | sed -n '1,8p')

if [[ "${header_block}" == *"作者: KnowSky404"* ]]; then
  printf 'expected main-menu header block to stop rendering author info at the top, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${header_block}" == *"项目: https://github.com/KnowSky404/sing-box-vps"* ]]; then
  printf 'expected main-menu header block to stop rendering project info at the top, got:\n%s\n' "${output}" >&2
  exit 1
fi
```

- [ ] **Step 2: Add a failing main-menu assertion that author/project now exist near the footer**

```bash
footer_block=$(printf '%s\n' "${plain_output}" | tail -n 6)

if [[ "${footer_block}" != *"作者: KnowSky404"* ]]; then
  printf 'expected main-menu footer to render author info near the bottom, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${footer_block}" != *"项目: https://github.com/KnowSky404/sing-box-vps"* ]]; then
  printf 'expected main-menu footer to render project info near the bottom, got:\n%s\n' "${output}" >&2
  exit 1
fi
```

- [ ] **Step 3: Add a failing submenu assertion that system-management output excludes author/project lines**

```bash
if [[ "${plain_output}" == *"作者: KnowSky404"* ]]; then
  printf 'expected submenu header to omit author info, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" == *"项目: https://github.com/KnowSky404/sing-box-vps"* ]]; then
  printf 'expected submenu header to omit project info, got:\n%s\n' "${output}" >&2
  exit 1
fi
```

- [ ] **Step 4: Run the updated tests to verify they fail against the current layout**

Run:

```bash
bash tests/main_menu_renders_sectioned_layout.sh
bash tests/system_management_menu_renders.sh
```

Expected:

- both commands exit non-zero
- main-menu test fails because author/project are still in the top banner
- system-management test may still pass or fail depending on the current submenu banner; if it already passes, keep the assertion because it documents the intended boundary

- [ ] **Step 5: Commit the header-compaction test updates**

```bash
git add tests/main_menu_renders_sectioned_layout.sh tests/system_management_menu_renders.sh
git commit -m "test: cover terminal header compaction"
```

### Task 2: Compact the main-menu header and move metadata into a footer

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Replace the current main-menu banner composition with a compact 2-3 line header**

```bash
show_banner() {
  safe_clear_screen
  render_page_header "sing-box-vps 一键安装管理脚本" "专为 VPS 稳定部署与安全运维设计"
  print_centered_text "版本: ${SCRIPT_VERSION}" "${GREEN}"
}
```

- [ ] **Step 2: Add a main-menu-only footer renderer for author and project information**

```bash
render_main_menu_footer() {
  echo
  echo -e "${BLUE}作者:${NC} KnowSky404"
  echo -e "${BLUE}项目:${NC} https://github.com/KnowSky404/sing-box-vps"
}
```

- [ ] **Step 3: Call the new footer renderer only from the main-menu flow**

```bash
render_section_title "脚本维护"
render_menu_item "11" "更新管理脚本 (sbv)" "" "${SCRIPT_VER_STATUS}"
render_menu_item "12" "卸载管理脚本 (sbv)"
render_menu_item "13" "配置 Cloudflare Warp" "(解锁/防送中)"
echo "0. 退出"
render_main_menu_footer
read -rp "请选择 [0-14]: " choice
```

- [ ] **Step 4: Run the main-menu test and shell syntax check**

Run:

```bash
bash tests/main_menu_renders_sectioned_layout.sh
bash -n install.sh
```

Expected:

- both commands exit `0`
- the main-menu test confirms the header/footer information move and section layout remains intact

- [ ] **Step 5: Commit the compact main-menu header/footer change**

```bash
git add install.sh
git commit -m "feat: compact terminal menu header"
```

### Task 3: Slim submenu headers and sync metadata

**Files:**
- Modify: `install.sh`
- Modify: `README.md`

- [ ] **Step 1: Add a submenu header path that omits version, author, and project metadata**

```bash
render_submenu_header() {
  local title=$1
  local subtitle=${2:-}

  echo
  render_page_header "${title}" "${subtitle}"
}
```

- [ ] **Step 2: Update submenu pages to use the leaner header path**

```bash
render_submenu_header "系统管理" "维护内核优化与网络协议栈设置"
render_section_title "系统摘要"
render_summary_item "BBR 状态" "${BBR_STATUS}"
```

Apply the same pattern to the existing submenu pages that currently call the shared page-header path directly.

- [ ] **Step 3: Bump the script version once and sync README**

```bash
# install.sh
# Version: 2026041505
readonly SCRIPT_VERSION="2026041505"

# README.md
- 脚本版本：`2026041505`
```

- [ ] **Step 4: Run the submenu test and metadata checks**

Run:

```bash
bash tests/system_management_menu_renders.sh
bash tests/version_metadata_is_consistent.sh
bash tests/readme_mentions_current_versions.sh
```

Expected:

- all commands exit `0`
- system-management output no longer includes author/project lines
- metadata tests confirm `install.sh` and `README.md` remain synchronized

- [ ] **Step 5: Commit the submenu header compaction and version sync**

```bash
git add install.sh README.md tests/system_management_menu_renders.sh tests/version_metadata_is_consistent.sh
git commit -m "feat: slim terminal submenu headers"
```

## Self-Review

- Spec coverage:
  - Compact main-menu header: covered by Task 2
  - Move author/project to main-menu footer: covered by Task 2
  - Hide author/project in submenus: covered by Task 3
  - Keep current menu logic intact: preserved throughout all tasks
  - Version sync after code changes: covered by Task 3
- Placeholder scan:
  - No `TODO`/`TBD` placeholders remain
  - All tasks include exact files, commands, and expected outcomes
- Type consistency:
  - `render_page_header`, `render_main_menu_footer`, and `render_submenu_header` are used consistently

