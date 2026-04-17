# Main Menu Brand Left Align Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the main menu brand information back into a compact left-aligned header block so the logo, author, project URL, and menu body share the same visual starting edge.

**Architecture:** Keep the change isolated to the main menu by introducing a main-menu-specific brand renderer in `install.sh`, while leaving the shared centered `render_page_header()` path untouched for submenus. Update the main menu shell regression test to assert the new top brand block and the removal of footer branding, then bump script metadata once for the code-bearing turn.

**Tech Stack:** Bash, ANSI terminal output helpers, shell regression tests

---

## File Map

- `install.sh`
  - Owns `SCRIPT_VERSION`, the main menu banner/footer rendering helpers, and the `main()` menu layout.
- `tests/main_menu_renders_sectioned_layout.sh`
  - Verifies the main menu header/body/footer ordering in a testable shell environment.
- `README.md`
  - Mirrors the current script version shown to users and is covered by `tests/version_metadata_is_consistent.sh`.
- `tests/version_metadata_is_consistent.sh`
  - Existing regression test for version comment/constant/README sync; no code change expected, but it must be run after the version bump.

### Task 1: Rebuild The Main Menu Brand Block

**Files:**
- Modify: `install.sh`
- Modify: `tests/main_menu_renders_sectioned_layout.sh`
- Verify: `tests/system_management_menu_renders.sh`
- Verify: `tests/menu_renders_when_update_check_response_is_unexpected.sh`
- Verify: `tests/narrow_terminal_menu_falls_back_to_single_column.sh`

- [ ] **Step 1: Rewrite the main menu regression to expect a top-left brand block**

Replace the header assertions in `tests/main_menu_renders_sectioned_layout.sh` so the test expects:

- the title line to start flush-left instead of being padded
- a combined author/project line directly under the title
- a combined subtitle/version line directly under the author/project line
- no author/project lines after `0. 退出`

Use this assertion block:

```bash
banner_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "sing-box-vps 一键安装管理脚本") { print NR; exit }')
brand_info_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "作者: KnowSky404 · 项目: https://github.com/KnowSky404/sing-box-vps") { print NR; exit }')
brand_meta_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "专为 VPS 稳定部署与安全运维设计 · 版本: ") { print NR; exit }')
deployment_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "部署管理") { print NR; exit }')
exit_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "0. 退出") { print NR; exit }')

banner_text=$(printf '%s\n' "${plain_output}" | awk 'index($0, "sing-box-vps 一键安装管理脚本") { print; exit }')
if [[ -z "${banner_text}" || ! "${banner_text}" =~ ^[^[:space:]] ]]; then
  printf 'expected main banner title to render flush-left, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ -z "${brand_info_line}" || -z "${brand_meta_line}" ]]; then
  printf 'expected compact brand info block at the top of the main menu, got:\n%s\n' "${output}" >&2
  exit 1
fi

if ! (( banner_line < brand_info_line && brand_info_line < brand_meta_line && brand_meta_line < deployment_line )); then
  printf 'expected title, author/project, and subtitle/version to appear before the deployment section, got:\n%s\n' "${output}" >&2
  exit 1
fi

if printf '%s\n' "${plain_output}" | awk '
  NR > '"${exit_line}"' && index($0, "作者: KnowSky404") { exit 0 }
  NR > '"${exit_line}"' && index($0, "项目: https://github.com/KnowSky404/sing-box-vps") { exit 0 }
  END { exit 1 }
'; then
  printf 'expected main menu footer to stop repeating author/project info, got:\n%s\n' "${output}" >&2
  exit 1
fi
```

- [ ] **Step 2: Run the updated main menu test and verify it fails against the current centered header**

Run: `bash tests/main_menu_renders_sectioned_layout.sh`

Expected: FAIL with the new flush-left or top brand block assertion because `show_banner()` still centers the header and `render_main_menu_footer()` still prints author/project at the bottom.

- [ ] **Step 3: Implement a dedicated left-aligned brand renderer for the main menu**

In `install.sh`, replace the current centered `show_banner()` path with a main-menu-specific helper and turn the footer into a no-op:

```bash
render_main_menu_brand_block() {
  local width divider

  width=$(term_columns)
  if (( width < 1 )); then
    width=1
  fi
  divider=$(repeat_char "═" "${width}")

  echo -e "${BLUE}${divider}${NC}"
  echo -e "${GREEN}sing-box-vps 一键安装管理脚本${NC}"
  echo -e "${YELLOW}作者: ${PROJECT_AUTHOR} · 项目: ${PROJECT_URL}${NC}"
  echo -e "${BLUE}专为 VPS 稳定部署与安全运维设计 · 版本: ${SCRIPT_VERSION}${NC}"
  echo -e "${BLUE}${divider}${NC}"
}

show_banner() {
  safe_clear_screen
  render_main_menu_brand_block
  echo
}

render_main_menu_footer() {
  :
}
```

Keep `render_page_header()` unchanged so submenu tests keep the current centered compact header behavior.

- [ ] **Step 4: Run the main menu and submenu regressions**

Run: `bash tests/main_menu_renders_sectioned_layout.sh && bash tests/system_management_menu_renders.sh && bash tests/menu_renders_when_update_check_response_is_unexpected.sh && bash tests/narrow_terminal_menu_falls_back_to_single_column.sh`

Expected: PASS with no output. The main menu test should now see the top brand block, and the submenu regressions should stay green because they still use `render_page_header()`.

- [ ] **Step 5: Commit the brand block change**

```bash
git add install.sh tests/main_menu_renders_sectioned_layout.sh
git commit -m "feat: left align main menu brand block"
```

### Task 2: Bump Version Metadata And Run Final Verification

**Files:**
- Modify: `install.sh`
- Modify: `README.md`
- Verify: `tests/version_metadata_is_consistent.sh`
- Verify: `tests/main_menu_renders_sectioned_layout.sh`
- Verify: `tests/system_management_menu_renders.sh`
- Verify: `tests/menu_renders_when_update_check_response_is_unexpected.sh`
- Verify: `tests/narrow_terminal_menu_falls_back_to_single_column.sh`

- [ ] **Step 1: Bump the script version once for this code-changing turn**

Update the version metadata in `install.sh` and `README.md` from `2026041505` to `2026041701`:

```bash
# install.sh
# Version: 2026041701
readonly SCRIPT_VERSION="2026041701"
```

```markdown
- 脚本版本：`2026041701`
```

Use `2026041701` specifically so the version follows the required `YYYYMMDDXX` format and increments once for the April 17, 2026 implementation turn.

- [ ] **Step 2: Run version consistency and final regression tests**

Run: `bash tests/version_metadata_is_consistent.sh && bash tests/main_menu_renders_sectioned_layout.sh && bash tests/system_management_menu_renders.sh && bash tests/menu_renders_when_update_check_response_is_unexpected.sh && bash tests/narrow_terminal_menu_falls_back_to_single_column.sh`

Expected: PASS with no output. `tests/version_metadata_is_consistent.sh` should confirm the install comment, `SCRIPT_VERSION`, and README metadata are identical.

- [ ] **Step 3: Commit the version bump and verification-ready state**

```bash
git add install.sh README.md
git commit -m "chore: bump script version for menu brand refresh"
```

## Self-Review Checklist

- Spec coverage:
  - Left-aligned main menu brand block: Task 1
  - Author/project moved from footer to top brand block: Task 1
  - Submenus unchanged: Task 1 regression run
  - Single version bump for this turn: Task 2
- Placeholder scan: no `TODO`, `TBD`, or implied "write tests later" steps remain.
- Type and name consistency:
  - `render_main_menu_brand_block()` is introduced once and then used by `show_banner()`
  - `render_page_header()` remains the submenu path throughout the plan
