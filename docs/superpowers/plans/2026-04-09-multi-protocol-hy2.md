# Multi-Protocol HY2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有 `install.sh` 单文件架构内，落地第一阶段多协议状态层，新增 `hy2` 协议，并完成按协议安装、更新、查看连接信息与旧单协议迁移。

**Architecture:** 保持当前单脚本入口，新增 `protocols/index.env` 与每协议独立 `*.env` 状态文件，作为协议真实来源；运行时通过“加载目标协议状态 -> 生成单个 inbound -> 汇总为完整 `inbounds`”的方式生成配置。保留现有 Warp、高级路由、服务管理逻辑为实例级能力，仅重构协议相关读取、写入、菜单交互和连接信息展示。

**Tech Stack:** Bash, jq, sing-box 1.13.x, systemd, shell regression tests

---

## File Structure

- Modify: `install.sh`
  - 新增协议状态常量、协议注册/加载/保存函数、旧配置迁移函数
  - 将配置生成改为多协议 `inbounds` 汇总
  - 新增 `hy2` 参数采集、状态保存、连接信息生成
  - 重写菜单 `1`、`3`、`8` 的协议级交互
- Create: `tests/legacy_single_protocol_migrates_to_state_layer.sh`
  - 验证旧 `config.json` 自动迁移为协议索引与状态文件
- Create: `tests/multi_protocol_hy2_config_generation.sh`
  - 验证多协议状态生成完整 `config.json`，包含 `hy2` inbound 与 `certificate_providers`
- Create: `tests/update_protocol_menu_updates_only_selected_protocol.sh`
  - 验证菜单 `3` 只更新目标协议状态，不污染其它协议
- Create: `tests/hy2_connection_info_shows_summary_and_link.sh`
  - 验证 `hy2` 连接信息摘要、链接与二维码分支

### Task 1: Add migration coverage for the new protocol state layer

**Files:**
- Create: `tests/legacy_single_protocol_migrates_to_state_layer.sh`
- Modify: `install.sh`

- [ ] **Step 1: Write the failing test**

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

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash
printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen_port": 443,
      "users": [{ "uuid": "11111111-1111-1111-1111-111111111111" }],
      "tls": {
        "server_name": "apple.com",
        "reality": {
          "private_key": "private-key",
          "short_id": ["aaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbb"]
        }
      }
    }
  ],
  "route": { "rules": [] }
}
EOF

cat > "${SB_KEY_FILE}" <<'EOF'
PRIVATE_KEY=private-key
PUBLIC_KEY=public-key
EOF

migrate_legacy_single_protocol_state_if_needed

test -f "${SB_PROTOCOL_INDEX_FILE}"
test -f "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'INSTALLED_PROTOCOLS="vless-reality"' "${SB_PROTOCOL_INDEX_FILE}"
grep -Fq 'UUID="11111111-1111-1111-1111-111111111111"' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/legacy_single_protocol_migrates_to_state_layer.sh`
Expected: FAIL with `migrate_legacy_single_protocol_state_if_needed: command not found` or missing protocol state files.

- [ ] **Step 3: Write minimal implementation**

```bash
readonly SB_PROTOCOL_STATE_DIR="${SB_PROJECT_DIR}/protocols"
readonly SB_PROTOCOL_INDEX_FILE="${SB_PROTOCOL_STATE_DIR}/index.env"

migrate_legacy_single_protocol_state_if_needed() {
  [[ -f "${SB_PROTOCOL_INDEX_FILE}" || ! -f "${SINGBOX_CONFIG_FILE}" ]] && return 0

  mkdir -p "${SB_PROTOCOL_STATE_DIR}"
  local legacy_type protocol
  legacy_type=$(jq -r '.inbounds[0].type // empty' "${SINGBOX_CONFIG_FILE}")

  case "${legacy_type}" in
    vless) protocol="vless-reality" ;;
    mixed) protocol="mixed" ;;
    *) return 0 ;;
  esac

  write_protocol_index "${protocol}"
  write_legacy_protocol_state "${protocol}"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/legacy_single_protocol_migrates_to_state_layer.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/plans/2026-04-09-multi-protocol-hy2.md tests/legacy_single_protocol_migrates_to_state_layer.sh install.sh
git commit -m "test: cover legacy protocol state migration"
```

### Task 2: Add failing coverage for multi-protocol config generation with hy2

**Files:**
- Create: `tests/multi_protocol_hy2_config_generation.sh`
- Modify: `install.sh`

- [ ] **Step 1: Write the failing test**

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

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash
printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

register_warp() { :; }
refresh_warp_route_assets() {
  SB_WARP_CUSTOM_DOMAINS_JSON='[]'
  SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON='[]'
  SB_WARP_LOCAL_RULE_SETS_JSON='[]'
  SB_WARP_REMOTE_RULE_SETS_JSON='[]'
  SB_WARP_RULE_SET_TAGS_JSON='[]'
}

mkdir -p "${SB_PROTOCOL_STATE_DIR}"

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS="vless-reality,hy2"
PROTOCOL_STATE_VERSION="1"
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED="1"
CONFIG_SCHEMA_VERSION="1"
NODE_NAME="vless_reality_test-host"
PORT="443"
UUID="11111111-1111-1111-1111-111111111111"
SNI="apple.com"
REALITY_PRIVATE_KEY="private-key"
REALITY_PUBLIC_KEY="public-key"
SHORT_ID_1="aaaaaaaaaaaaaaaa"
SHORT_ID_2="bbbbbbbbbbbbbbbb"
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/hy2.env" <<'EOF'
INSTALLED="1"
CONFIG_SCHEMA_VERSION="1"
NODE_NAME="hy2_test-host"
PORT="8443"
DOMAIN="hy2.example.com"
PASSWORD="hy2-password"
USER_NAME="hy2-user"
UP_MBPS="100"
DOWN_MBPS="100"
OBFS_ENABLED="y"
OBFS_TYPE="salamander"
OBFS_PASSWORD="obfs-pass"
TLS_MODE="manual"
CERT_PATH="/etc/ssl/certs/hy2.pem"
KEY_PATH="/etc/ssl/private/hy2.key"
MASQUERADE="https://example.com"
EOF

SB_ADVANCED_ROUTE="n"
SB_ENABLE_WARP="n"

generate_config

jq -e '.inbounds | length == 2' "${SINGBOX_CONFIG_FILE}" >/dev/null
jq -e '.inbounds[] | select(.type == "hysteria2") | .tls.certificate_path == "/etc/ssl/certs/hy2.pem"' "${SINGBOX_CONFIG_FILE}" >/dev/null
jq -e '.inbounds[] | select(.type == "hysteria2") | .obfs.type == "salamander"' "${SINGBOX_CONFIG_FILE}" >/dev/null
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/multi_protocol_hy2_config_generation.sh`
Expected: FAIL because `generate_config()` still emits a single inbound and has no `hysteria2` builder.

- [ ] **Step 3: Write minimal implementation**

```bash
list_installed_protocols() {
  [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]] || return 0
  grep '^INSTALLED_PROTOCOLS=' "${SB_PROTOCOL_INDEX_FILE}" | cut -d'=' -f2- | tr -d '"' | tr ',' '\n'
}

build_inbound_for_protocol() {
  local protocol=$1
  case "${protocol}" in
    vless-reality) build_vless_inbound_json ;;
    mixed) build_mixed_inbound_json ;;
    hy2) build_hy2_inbound_json ;;
  esac
}

generate_config() {
  local inbound_file provider_file protocol
  inbound_file=$(mktemp)
  provider_file=$(mktemp)

  while IFS= read -r protocol; do
    load_protocol_state "${protocol}"
    build_inbound_for_protocol "${protocol}" >> "${inbound_file}"
    build_certificate_provider_for_protocol "${protocol}" >> "${provider_file}" || true
  done < <(list_installed_protocols)

  jq -n \
    --slurpfile inbounds "${inbound_file}" \
    --slurpfile certificate_providers "${provider_file}" \
    '{inbounds: $inbounds, certificate_providers: $certificate_providers}'
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/multi_protocol_hy2_config_generation.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/multi_protocol_hy2_config_generation.sh install.sh
git commit -m "feat: generate multi-protocol config with hy2 inbound"
```

### Task 3: Add failing coverage for per-protocol update interaction

**Files:**
- Create: `tests/update_protocol_menu_updates_only_selected_protocol.sh`
- Modify: `install.sh`

- [ ] **Step 1: Write the failing test**

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

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash
printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

generate_config() { :; }
check_config_valid() { :; }
setup_service() { :; }
open_firewall_port() { :; }
systemctl() { :; }
display_status_summary() { :; }
show_post_config_connection_info() { :; }
check_port_conflict() { :; }
save_warp_route_settings() { :; }

mkdir -p "${SB_PROTOCOL_STATE_DIR}"
cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS="vless-reality,hy2"
PROTOCOL_STATE_VERSION="1"
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED="1"
CONFIG_SCHEMA_VERSION="1"
NODE_NAME="vless_reality_test-host"
PORT="443"
UUID="11111111-1111-1111-1111-111111111111"
SNI="apple.com"
REALITY_PRIVATE_KEY="private-key"
REALITY_PUBLIC_KEY="public-key"
SHORT_ID_1="aaaaaaaaaaaaaaaa"
SHORT_ID_2="bbbbbbbbbbbbbbbb"
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/hy2.env" <<'EOF'
INSTALLED="1"
CONFIG_SCHEMA_VERSION="1"
NODE_NAME="hy2_test-host"
PORT="8443"
DOMAIN="hy2.example.com"
PASSWORD="old-pass"
USER_NAME="hy2-user"
UP_MBPS="100"
DOWN_MBPS="100"
OBFS_ENABLED="n"
OBFS_TYPE=""
OBFS_PASSWORD=""
TLS_MODE="manual"
CERT_PATH="/etc/ssl/certs/hy2.pem"
KEY_PATH="/etc/ssl/private/hy2.key"
MASQUERADE=""
EOF

update_config_only <<'EOF'
2
9443

new-pass


n
n
EOF

grep -Fq 'PORT="9443"' "${SB_PROTOCOL_STATE_DIR}/hy2.env"
grep -Fq 'PASSWORD="new-pass"' "${SB_PROTOCOL_STATE_DIR}/hy2.env"
grep -Fq 'PORT="443"' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/update_protocol_menu_updates_only_selected_protocol.sh`
Expected: FAIL because `update_config_only()` still edits the single loaded protocol instead of selecting a target protocol state file.

- [ ] **Step 3: Write minimal implementation**

```bash
prompt_installed_protocol_selection() {
  local protocols=()
  mapfile -t protocols < <(list_installed_protocols)
  # render menu and return the selected protocol id
}

update_config_only() {
  local target_protocol
  target_protocol=$(prompt_installed_protocol_selection)
  load_protocol_state "${target_protocol}"
  prompt_protocol_update_fields "${target_protocol}"
  save_protocol_state "${target_protocol}"
  generate_config
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/update_protocol_menu_updates_only_selected_protocol.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/update_protocol_menu_updates_only_selected_protocol.sh install.sh
git commit -m "feat: add per-protocol update flow"
```

### Task 4: Add failing coverage for hy2 connection info output

**Files:**
- Create: `tests/hy2_connection_info_shows_summary_and_link.sh`
- Modify: `install.sh`

- [ ] **Step 1: Write the failing test**

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

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash
printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

QRENCODE_COUNT_FILE="${TMP_DIR}/qrencode.count"
printf '0\n' > "${QRENCODE_COUNT_FILE}"

SB_PROTOCOL="hy2"
SB_NODE_NAME="hy2_test-host"
SB_PORT="8443"
SB_HY2_DOMAIN="hy2.example.com"
SB_HY2_PASSWORD="hy2-password"
SB_HY2_USER_NAME="hy2-user"
SB_HY2_UP_MBPS="100"
SB_HY2_DOWN_MBPS="50"
SB_HY2_OBFS_ENABLED="y"
SB_HY2_OBFS_TYPE="salamander"
SB_HY2_OBFS_PASSWORD="obfs-pass"
SB_HY2_TLS_MODE="manual"

qrencode() {
  local current_count
  current_count=$(cat "${QRENCODE_COUNT_FILE}")
  printf '%s\n' "$((current_count + 1))" > "${QRENCODE_COUNT_FILE}"
}

output=$(show_connection_details "both" "203.0.113.10" 2>&1)

[[ "${output}" == *"Hysteria2 协议链接"* ]]
[[ "${output}" == *"域名: hy2.example.com"* ]]
[[ "${output}" == *"hy2://"* ]]
[[ "$(cat "${QRENCODE_COUNT_FILE}")" == "1" ]]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/hy2_connection_info_shows_summary_and_link.sh`
Expected: FAIL because `show_connection_details()` has no `hy2` branch.

- [ ] **Step 3: Write minimal implementation**

```bash
build_hy2_link() {
  local public_ip=$1
  local authority="${SB_HY2_DOMAIN:-${public_ip}}:${SB_PORT}"
  printf 'hy2://%s@%s?insecure=0#%s' "${SB_HY2_PASSWORD}" "${authority}" "${SB_NODE_NAME}"
}

show_hy2_connection_summary() {
  echo "域名: ${SB_HY2_DOMAIN}"
  echo "端口: ${SB_PORT}"
  echo "TLS: ${SB_HY2_TLS_MODE}"
  echo "混淆: ${SB_HY2_OBFS_ENABLED}"
  echo "带宽: ${SB_HY2_UP_MBPS} / ${SB_HY2_DOWN_MBPS} Mbps"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/hy2_connection_info_shows_summary_and_link.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/hy2_connection_info_shows_summary_and_link.sh install.sh
git commit -m "feat: show hy2 connection info"
```

### Task 5: Implement the protocol registry, install flow, and config composition

**Files:**
- Modify: `install.sh`
- Test: `tests/legacy_single_protocol_migrates_to_state_layer.sh`
- Test: `tests/multi_protocol_hy2_config_generation.sh`

- [ ] **Step 1: Add protocol constants and helpers**

```bash
readonly SB_PROTOCOL_STATE_DIR="${SB_PROJECT_DIR}/protocols"
readonly SB_PROTOCOL_INDEX_FILE="${SB_PROTOCOL_STATE_DIR}/index.env"
readonly SB_PROTOCOL_STATE_VERSION="1"
readonly SB_PROTOCOL_SCHEMA_VERSION="1"

normalize_protocol_id() {
  case "$1" in
    vless+reality|vless-reality|vless) printf 'vless-reality' ;;
    mixed) printf 'mixed' ;;
    hy2|hysteria2) printf 'hy2' ;;
    *) return 1 ;;
  esac
}
```

- [ ] **Step 2: Add state load/save helpers**

```bash
save_protocol_state() {
  local protocol
  protocol=$(normalize_protocol_id "$1")
  mkdir -p "${SB_PROTOCOL_STATE_DIR}"

  case "${protocol}" in
    hy2)
      cat > "${SB_PROTOCOL_STATE_DIR}/hy2.env" <<EOF
INSTALLED="1"
CONFIG_SCHEMA_VERSION="${SB_PROTOCOL_SCHEMA_VERSION}"
NODE_NAME="${SB_NODE_NAME}"
PORT="${SB_PORT}"
DOMAIN="${SB_HY2_DOMAIN}"
PASSWORD="${SB_HY2_PASSWORD}"
USER_NAME="${SB_HY2_USER_NAME}"
UP_MBPS="${SB_HY2_UP_MBPS}"
DOWN_MBPS="${SB_HY2_DOWN_MBPS}"
OBFS_ENABLED="${SB_HY2_OBFS_ENABLED}"
OBFS_TYPE="${SB_HY2_OBFS_TYPE}"
OBFS_PASSWORD="${SB_HY2_OBFS_PASSWORD}"
TLS_MODE="${SB_HY2_TLS_MODE}"
EOF
      ;;
  esac
}
```

- [ ] **Step 3: Refactor `generate_config()` to assemble all installed protocols**

```bash
build_config_inbounds_json() {
  local protocol object_file
  object_file=$(mktemp)

  while IFS= read -r protocol; do
    [[ -z "${protocol}" ]] && continue
    load_protocol_state "${protocol}"
    build_inbound_for_protocol "${protocol}" >> "${object_file}"
  done < <(list_installed_protocols)

  jq -s . "${object_file}"
}
```

- [ ] **Step 4: Re-run protocol state and config generation tests**

Run:
- `bash tests/legacy_single_protocol_migrates_to_state_layer.sh`
- `bash tests/multi_protocol_hy2_config_generation.sh`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add install.sh
git commit -m "feat: add protocol state registry"
```

### Task 6: Implement interactive install, per-protocol update, and connection menus

**Files:**
- Modify: `install.sh`
- Test: `tests/update_protocol_menu_updates_only_selected_protocol.sh`
- Test: `tests/hy2_connection_info_shows_summary_and_link.sh`
- Test: `tests/mixed_qr_menu_shows_hint.sh`
- Test: `tests/vless_link_only_skips_qr.sh`

- [ ] **Step 1: Add protocol selection and hy2 prompts**

```bash
prompt_protocol_install_selection() {
  echo "可安装协议:"
  echo "1. VLESS + REALITY"
  echo "2. Mixed (HTTP/HTTPS/SOCKS)"
  echo "3. Hysteria2"
  read -rp "请选择一个或多个协议 [1-3]，逗号分隔: " protocol_choices
}

prompt_hy2_config() {
  read -rp "Hysteria2 域名: " in_domain
  read -rp "端口 (默认 8443): " in_port
  read -rp "认证密码 (留空自动生成): " in_password
}
```

- [ ] **Step 2: Rewrite `update_config_only()` to choose the installed protocol first**

```bash
echo "已安装协议:"
echo "1. VLESS + REALITY"
echo "2. Hysteria2"
read -rp "请选择要修改的协议: " selected_protocol
```

- [ ] **Step 3: Update menu `8` to select protocol and dispatch protocol-specific info**

```bash
view_status_and_info() {
  local target_protocol
  display_service_summary
  target_protocol=$(prompt_installed_protocol_selection)
  load_protocol_state "${target_protocol}"
  show_connection_info_menu
}
```

- [ ] **Step 4: Re-run interaction and display tests**

Run:
- `bash tests/update_protocol_menu_updates_only_selected_protocol.sh`
- `bash tests/hy2_connection_info_shows_summary_and_link.sh`
- `bash tests/mixed_qr_menu_shows_hint.sh`
- `bash tests/vless_link_only_skips_qr.sh`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add install.sh
git commit -m "feat: add protocol-specific interaction flows"
```

### Task 7: Verify the integrated rollout

**Files:**
- Modify: `README.md`
- Test: `tests/legacy_single_protocol_migrates_to_state_layer.sh`
- Test: `tests/multi_protocol_hy2_config_generation.sh`
- Test: `tests/update_protocol_menu_updates_only_selected_protocol.sh`
- Test: `tests/hy2_connection_info_shows_summary_and_link.sh`
- Test: `tests/update_keeps_existing_config.sh`
- Test: `tests/update_skips_restart_when_config_invalid.sh`
- Test: `tests/post_install_shows_connection_info.sh`
- Test: `tests/mixed_qr_menu_shows_hint.sh`
- Test: `tests/vless_link_only_skips_qr.sh`

- [ ] **Step 1: Update user-facing docs for the new protocol set**

```markdown
- 支持 VLESS + REALITY、Mixed、Hysteria2
- 菜单 1 为协议安装入口
- 菜单 3 为按协议更新入口
- 状态目录新增 `/root/sing-box-vps/protocols/`
```

- [ ] **Step 2: Run the full targeted regression suite**

Run:
- `bash tests/legacy_single_protocol_migrates_to_state_layer.sh`
- `bash tests/multi_protocol_hy2_config_generation.sh`
- `bash tests/update_protocol_menu_updates_only_selected_protocol.sh`
- `bash tests/hy2_connection_info_shows_summary_and_link.sh`
- `bash tests/update_keeps_existing_config.sh`
- `bash tests/update_skips_restart_when_config_invalid.sh`
- `bash tests/post_install_shows_connection_info.sh`
- `bash tests/mixed_qr_menu_shows_hint.sh`
- `bash tests/vless_link_only_skips_qr.sh`

Expected: all PASS

- [ ] **Step 3: Commit**

```bash
git add README.md install.sh tests
git commit -m "feat: add multi-protocol hy2 management"
```
