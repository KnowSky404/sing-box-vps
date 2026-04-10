# System Management And Stack Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a system management menu, persist inbound/outbound stack modes, apply them to sing-box config generation, and render IPv4/IPv6 node info correctly.

**Architecture:** Keep the feature inside `install.sh` to match the existing project structure, but separate concerns into small helper functions for capability detection, stack-mode persistence, config generation, and menu handling. Drive each behavior with shell tests first, then implement the minimum code needed for the tests to pass.

**Tech Stack:** Bash, jq, existing shell test scripts in `tests/`, sing-box 1.13.x config generation

---

### Task 1: Add Menu Regression Tests

**Files:**
- Modify: `tests/menu_renders_when_update_check_response_is_unexpected.sh`
- Create: `tests/system_management_menu_renders.sh`
- Test: `tests/menu_renders_when_update_check_response_is_unexpected.sh`
- Test: `tests/system_management_menu_renders.sh`

- [ ] **Step 1: Write the failing tests**

```bash
# in tests/menu_renders_when_update_check_response_is_unexpected.sh
if [[ "${output}" != *"4. 系统管理"* ]]; then
  printf 'expected system management menu entry to render, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" == *"开启 BBR 拥塞控制算法"* ]]; then
  printf 'expected BBR entry to move out of the main menu, got:\n%s\n' "${output}" >&2
  exit 1
fi
```

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
  -e "s|readonly SINGBOX_SERVICE_FILE=\"/etc/systemd/system/sing-box.service\"|readonly SINGBOX_SERVICE_FILE=\"${TMP_DIR}/sing-box.service\"|" \
  -e 's|main \"\$@\"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/bin"
export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

output=$(system_management_menu <<'EOF'
0
EOF
)

if [[ "${output}" != *"1. 开启 BBR"* ]]; then
  printf 'expected BBR option inside system management, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"2. 协议栈管理"* ]]; then
  printf 'expected stack mode option inside system management, got:\n%s\n' "${output}" >&2
  exit 1
fi
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/menu_renders_when_update_check_response_is_unexpected.sh && bash tests/system_management_menu_renders.sh`
Expected: FAIL because the main menu still exposes BBR directly and `system_management_menu` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```bash
system_management_menu() {
  while true; do
    echo -e "\n${BLUE}--- 系统管理 ---${NC}"
    echo "1. 开启 BBR"
    echo "2. 协议栈管理"
    echo "0. 返回主菜单"
    read -rp "请选择 [0-2]: " system_choice

    case "${system_choice}" in
      1) enable_bbr ;;
      2) stack_management_menu ;;
      0) return ;;
      *) log_warn "无效选项，请重新选择。" ;;
    esac
  done
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/menu_renders_when_update_check_response_is_unexpected.sh && bash tests/system_management_menu_renders.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/menu_renders_when_update_check_response_is_unexpected.sh tests/system_management_menu_renders.sh
git commit -m "feat: add system management menu"
```

### Task 2: Add Stack State Persistence And Capability Detection

**Files:**
- Modify: `install.sh`
- Create: `tests/stack_mode_options_follow_system_capability.sh`
- Create: `tests/warp_enabled_disables_outbound_stack_changes.sh`
- Test: `tests/stack_mode_options_follow_system_capability.sh`
- Test: `tests/warp_enabled_disables_outbound_stack_changes.sh`

- [ ] **Step 1: Write the failing tests**

```bash
# stack capability test assertions
if [[ "${output}" != *"1. IPv4 Only"* || "${output}" != *"3. Dual Stack"* ]]; then
  printf 'expected dual-stack inbound options, got:\n%s\n' "${output}" >&2
  exit 1
fi
```

```bash
# warp lock test assertions
if [[ "${output}" != *"当前已开启 Warp，出站协议栈设置不生效，已禁止修改。"* ]]; then
  printf 'expected warp outbound lock hint, got:\n%s\n' "${output}" >&2
  exit 1
fi
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/stack_mode_options_follow_system_capability.sh && bash tests/warp_enabled_disables_outbound_stack_changes.sh`
Expected: FAIL because capability detection and stack persistence functions do not exist.

- [ ] **Step 3: Write minimal implementation**

```bash
readonly SB_STACK_STATE_FILE="${SB_PROJECT_DIR}/stack-mode.env"

STACK_STATE_VERSION="1"
SB_INBOUND_STACK_MODE=""
SB_OUTBOUND_STACK_MODE=""

detect_host_ip_stack() {
  local has_v4="n" has_v6="n"

  while IFS= read -r line; do
    [[ "${line}" == *" inet "* ]] && has_v4="y"
    [[ "${line}" == *" inet6 "* ]] && has_v6="y"
  done < <(ip -o addr show scope global 2>/dev/null || true)

  if [[ "${has_v4}" == "y" && "${has_v6}" == "y" ]]; then
    printf 'dual'
  elif [[ "${has_v6}" == "y" ]]; then
    printf 'ipv6'
  else
    printf 'ipv4'
  fi
}
```

```bash
save_stack_mode_state() {
  mkdir -p "${SB_PROJECT_DIR}"
  cat > "${SB_STACK_STATE_FILE}" <<EOF
STACK_STATE_VERSION=1
INBOUND_STACK_MODE=${SB_INBOUND_STACK_MODE}
OUTBOUND_STACK_MODE=${SB_OUTBOUND_STACK_MODE}
EOF
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/stack_mode_options_follow_system_capability.sh && bash tests/warp_enabled_disables_outbound_stack_changes.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/stack_mode_options_follow_system_capability.sh tests/warp_enabled_disables_outbound_stack_changes.sh
git commit -m "feat: persist stack mode settings"
```

### Task 3: Apply Stack Modes To Config Generation

**Files:**
- Modify: `install.sh`
- Create: `tests/inbound_stack_mode_updates_listen_address.sh`
- Create: `tests/outbound_stack_mode_updates_dns_and_direct_strategy.sh`
- Test: `tests/inbound_stack_mode_updates_listen_address.sh`
- Test: `tests/outbound_stack_mode_updates_dns_and_direct_strategy.sh`

- [ ] **Step 1: Write the failing tests**

```bash
if ! jq -e '.inbounds[] | select(.tag == "vless-in") | .listen == "0.0.0.0"' "${SINGBOX_CONFIG_FILE}" >/dev/null; then
  printf 'expected ipv4 inbound listen address in config\n' >&2
  exit 1
fi
```

```bash
if ! jq -e '.dns.strategy == "prefer_ipv6"' "${SINGBOX_CONFIG_FILE}" >/dev/null; then
  printf 'expected dns.strategy to follow outbound stack mode\n' >&2
  exit 1
fi

if ! jq -e '.outbounds[] | select(.tag == "direct") | .domain_resolver.strategy == "prefer_ipv6"' "${SINGBOX_CONFIG_FILE}" >/dev/null; then
  printf 'expected direct outbound resolver strategy to follow outbound stack mode\n' >&2
  exit 1
fi
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/inbound_stack_mode_updates_listen_address.sh && bash tests/outbound_stack_mode_updates_dns_and_direct_strategy.sh`
Expected: FAIL because config generation still hardcodes `listen` and lacks stack-aware DNS/direct settings.

- [ ] **Step 3: Write minimal implementation**

```bash
stack_inbound_listen_address() {
  case "${SB_INBOUND_STACK_MODE}" in
    ipv4_only) printf '0.0.0.0' ;;
    *) printf '::' ;;
  esac
}
```

```bash
"dns": {
  "servers": [
    { "type": "local", "tag": "local-dns" }
  ],
  "strategy": $outbound_stack_mode
},
"outbounds": [
  {
    "type": "direct",
    "tag": "direct",
    "domain_resolver": {
      "server": "local-dns",
      "strategy": $outbound_stack_mode
    }
  }
]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/inbound_stack_mode_updates_listen_address.sh && bash tests/outbound_stack_mode_updates_dns_and_direct_strategy.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/inbound_stack_mode_updates_listen_address.sh tests/outbound_stack_mode_updates_dns_and_direct_strategy.sh
git commit -m "feat: apply stack mode to config generation"
```

### Task 4: Render IPv4 And IPv6 Node Information

**Files:**
- Modify: `install.sh`
- Create: `tests/dual_stack_node_info_shows_ipv4_and_ipv6_links.sh`
- Create: `tests/ipv6_links_wrap_host_in_brackets.sh`
- Test: `tests/dual_stack_node_info_shows_ipv4_and_ipv6_links.sh`
- Test: `tests/ipv6_links_wrap_host_in_brackets.sh`

- [ ] **Step 1: Write the failing tests**

```bash
if [[ "${output}" != *"IPv4 地址"* || "${output}" != *"IPv6 地址"* ]]; then
  printf 'expected dual-stack node info labels, got:\n%s\n' "${output}" >&2
  exit 1
fi
```

```bash
if [[ "${output}" != *"@[2001:db8::1]:"* ]]; then
  printf 'expected IPv6 share link host to be bracketed, got:\n%s\n' "${output}" >&2
  exit 1
fi
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/dual_stack_node_info_shows_ipv4_and_ipv6_links.sh && bash tests/ipv6_links_wrap_host_in_brackets.sh`
Expected: FAIL because node info still only renders one address form.

- [ ] **Step 3: Write minimal implementation**

```bash
format_link_host() {
  local address=$1
  if [[ "${address}" == *:* ]]; then
    printf '[%s]' "${address}"
  else
    printf '%s' "${address}"
  fi
}
```

```bash
show_connection_details_for_address() {
  local label=$1
  local address=$2
  echo -e "\n${BLUE}${label}:${NC} ${address}"
  show_connection_details "${mode}" "${address}"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/dual_stack_node_info_shows_ipv4_and_ipv6_links.sh && bash tests/ipv6_links_wrap_host_in_brackets.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/dual_stack_node_info_shows_ipv4_and_ipv6_links.sh tests/ipv6_links_wrap_host_in_brackets.sh
git commit -m "feat: render dual-stack node information"
```

### Task 5: Run Full Verification

**Files:**
- Modify: `install.sh`
- Modify: `tests/*.sh`

- [ ] **Step 1: Run targeted new tests**

Run: `bash tests/system_management_menu_renders.sh && bash tests/stack_mode_options_follow_system_capability.sh && bash tests/warp_enabled_disables_outbound_stack_changes.sh && bash tests/inbound_stack_mode_updates_listen_address.sh && bash tests/outbound_stack_mode_updates_dns_and_direct_strategy.sh && bash tests/dual_stack_node_info_shows_ipv4_and_ipv6_links.sh && bash tests/ipv6_links_wrap_host_in_brackets.sh`
Expected: PASS

- [ ] **Step 2: Run existing affected regressions**

Run: `bash tests/menu_renders_when_update_check_response_is_unexpected.sh && bash tests/view_status_shows_summary_only.sh && bash tests/view_node_info_shows_all_installed_protocols.sh && bash tests/post_install_shows_connection_info.sh`
Expected: PASS

- [ ] **Step 3: Run the full shell test suite**

Run: `for test_script in tests/*.sh; do bash "$test_script" >/tmp/test.out 2>&1 || { cat /tmp/test.out; echo "FAILED: $test_script"; exit 1; }; done`
Expected: PASS with no failures reported

- [ ] **Step 4: Commit**

```bash
git add install.sh tests docs/superpowers/specs/2026-04-10-system-management-stack-mode-design.md docs/superpowers/plans/2026-04-10-system-management-stack-mode.md
git commit -m "feat: add system and stack management"
```
