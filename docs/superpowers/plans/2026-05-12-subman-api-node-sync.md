# SubMan API Node Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a node information action that pushes current `sing-box-vps` VLESS and Hysteria2 node share links to an already deployed SubMan Server API.

**Architecture:** Keep the integration inside `install.sh`, matching the repository's current single-entrypoint architecture. Store SubMan API settings in `/root/sing-box-vps/subman.env`, generate SubMan node payloads from existing protocol state and share-link builders, then upsert nodes with `PUT /api/nodes/by-key/:externalKey`.

**Tech Stack:** Bash, `curl`, `jq`, existing shell test harness in `tests/menu_test_helper.sh`, SubMan Server API.

---

## File Structure

- Modify: `install.sh`
  - Add SubMan config helpers near other state/config helpers.
  - Add SubMan payload builders near existing node/client export builders.
  - Add SubMan API push orchestration near `export_singbox_client_config`.
  - Add menu action `3. 推送节点到 SubMan`.
  - Bump `SCRIPT_VERSION` once for the implementation turn.
- Modify: `README.md`
  - Sync script version.
  - Mention SubMan node push in features, menu, and key paths.
- Modify: `tests/node_info_action_menu_renders.sh`
  - Update expected menu ordering for the new third action.
- Create: `tests/subman_config_helpers.sh`
  - Cover config path, URL normalization, config writing, and config prompting.
- Create: `tests/subman_payload_generation.sh`
  - Cover VLESS and Hysteria2 payload shape and mixed skip behavior.
- Create: `tests/subman_api_push.sh`
  - Cover API success, failure, and token non-leak behavior using a fake `curl`.

## Task 1: Render SubMan Menu Action

**Files:**
- Modify: `tests/node_info_action_menu_renders.sh`
- Modify: `install.sh`

- [ ] **Step 1: Update the failing menu test**

Replace the action assertions in `tests/node_info_action_menu_renders.sh` with:

```bash
view_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "1. 查看连接链接 / 二维码") { print NR; exit }')
export_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "2. 导出 sing-box 裸核客户端配置") { print NR; exit }')
subman_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "3. 推送节点到 SubMan") { print NR; exit }')

if ! (( section_line < view_line && view_line < export_line && export_line < subman_line )); then
  printf 'expected node info action menu options to stay grouped under the action section, got:\n%s\n' "${output}" >&2
  exit 1
fi
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
bash tests/node_info_action_menu_renders.sh
```

Expected: fail because `3. 推送节点到 SubMan` is not rendered.

- [ ] **Step 3: Add the menu item and action stub**

In `install.sh`, update `show_node_info_action_menu()` to:

```bash
    render_menu_item "1" "查看连接链接 / 二维码"
    render_menu_item "2" "导出 sing-box 裸核客户端配置"
    render_menu_item "3" "推送节点到 SubMan"
    echo "0. 返回"
    read -rp "请选择 [0-3]: " node_info_choice

    case "${node_info_choice}" in
      1) show_connection_info_menu ;;
      2) export_singbox_client_config || true ;;
      3) push_nodes_to_subman || true ;;
      0) return ;;
      *) log_warn "无效选项，请重新选择。" ;;
    esac
```

Add this temporary stub above `show_node_info_action_menu()`:

```bash
push_nodes_to_subman() {
  log_warn "SubMan 节点推送功能尚未完成。"
  return 1
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run:

```bash
bash tests/node_info_action_menu_renders.sh
```

Expected: pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add install.sh tests/node_info_action_menu_renders.sh
git commit -m "feat: add subman node sync menu action"
```

## Task 2: Add SubMan Config Helpers

**Files:**
- Create: `tests/subman_config_helpers.sh`
- Modify: `install.sh`

- [ ] **Step 1: Write the failing config helper test**

Create `tests/subman_config_helpers.sh`:

```bash
#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

expected_path="${TMP_DIR}/project/subman.env"
actual_path=$(subman_config_file_path)
if [[ "${actual_path}" != "${expected_path}" ]]; then
  printf 'expected subman config path %s, got %s\n' "${expected_path}" "${actual_path}" >&2
  exit 1
fi

normalized=$(normalize_subman_api_url "  https://subman.example.com///  ")
if [[ "${normalized}" != "https://subman.example.com" ]]; then
  printf 'expected normalized URL without trailing slash, got %s\n' "${normalized}" >&2
  exit 1
fi

SUBMAN_API_URL="https://subman.example.com"
SUBMAN_API_TOKEN="secret-token"
SUBMAN_NODE_PREFIX="edge-1"
write_subman_config

if [[ ! -f "${expected_path}" ]]; then
  printf 'expected subman config file to be written\n' >&2
  exit 1
fi

mode=$(stat -c '%a' "${expected_path}")
if [[ "${mode}" != "600" ]]; then
  printf 'expected subman config mode 600, got %s\n' "${mode}" >&2
  exit 1
fi

SUBMAN_API_URL=""
SUBMAN_API_TOKEN=""
SUBMAN_NODE_PREFIX=""
load_subman_config

if [[ "${SUBMAN_API_URL}" != "https://subman.example.com" ]]; then
  printf 'expected loaded API URL, got %s\n' "${SUBMAN_API_URL}" >&2
  exit 1
fi

if [[ "${SUBMAN_API_TOKEN}" != "secret-token" ]]; then
  printf 'expected loaded API token\n' >&2
  exit 1
fi

if [[ "${SUBMAN_NODE_PREFIX}" != "edge-1" ]]; then
  printf 'expected loaded node prefix, got %s\n' "${SUBMAN_NODE_PREFIX}" >&2
  exit 1
fi

rm -f "${expected_path}"
prompt_subman_config_if_needed <<'EOF'
https://subman.example.com/
prompt-token

EOF

if [[ "${SUBMAN_API_URL}" != "https://subman.example.com" ]]; then
  printf 'expected prompted URL to be normalized, got %s\n' "${SUBMAN_API_URL}" >&2
  exit 1
fi

if [[ "${SUBMAN_API_TOKEN}" != "prompt-token" ]]; then
  printf 'expected prompted token\n' >&2
  exit 1
fi

if [[ "${SUBMAN_NODE_PREFIX}" != "test-host" ]]; then
  printf 'expected empty prompted prefix to default to hostname, got %s\n' "${SUBMAN_NODE_PREFIX}" >&2
  exit 1
fi
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
bash tests/subman_config_helpers.sh
```

Expected: fail because `subman_config_file_path` is not defined.

- [ ] **Step 3: Add config globals and helpers**

In `install.sh`, near other global variables, add:

```bash
SUBMAN_API_URL=""
SUBMAN_API_TOKEN=""
SUBMAN_NODE_PREFIX=""
```

Near the protocol state helper functions, add:

```bash
subman_config_file_path() {
  printf '%s/subman.env' "${SB_PROJECT_DIR}"
}

normalize_subman_api_url() {
  local url
  url=$(trim_whitespace "${1:-}")
  while [[ "${url}" == */ ]]; do
    url=${url%/}
  done
  printf '%s' "${url}"
}

load_subman_config() {
  local config_file
  config_file=$(subman_config_file_path)

  SUBMAN_API_URL=""
  SUBMAN_API_TOKEN=""
  SUBMAN_NODE_PREFIX=""

  [[ -f "${config_file}" ]] || return 0

  # shellcheck disable=SC1090
  source "${config_file}"
  SUBMAN_API_URL=$(normalize_subman_api_url "${SUBMAN_API_URL:-}")
  SUBMAN_API_TOKEN=${SUBMAN_API_TOKEN:-}
  SUBMAN_NODE_PREFIX=$(trim_whitespace "${SUBMAN_NODE_PREFIX:-}")
}

write_subman_config() {
  local config_file config_dir tmp_file
  config_file=$(subman_config_file_path)
  config_dir=$(dirname "${config_file}")
  mkdir -p "${config_dir}"
  tmp_file=$(mktemp "${config_dir}/.subman.env.tmp.XXXXXX")
  chmod 600 "${tmp_file}"
  {
    write_env_assignment "SUBMAN_API_URL" "${SUBMAN_API_URL}"
    write_env_assignment "SUBMAN_API_TOKEN" "${SUBMAN_API_TOKEN}"
    write_env_assignment "SUBMAN_NODE_PREFIX" "${SUBMAN_NODE_PREFIX}"
  } > "${tmp_file}"
  mv "${tmp_file}" "${config_file}"
  chmod 600 "${config_file}"
}

prompt_subman_config_if_needed() {
  local input_url input_token input_prefix

  load_subman_config

  while [[ -z "${SUBMAN_API_URL}" ]]; do
    read -rp "SubMan API 地址: " input_url
    SUBMAN_API_URL=$(normalize_subman_api_url "${input_url}")
    [[ -z "${SUBMAN_API_URL}" ]] && log_warn "SubMan API 地址不能为空。"
  done

  while [[ -z "${SUBMAN_API_TOKEN}" ]]; do
    read -rp "SubMan API Token: " input_token
    SUBMAN_API_TOKEN=$(trim_whitespace "${input_token}")
    [[ -z "${SUBMAN_API_TOKEN}" ]] && log_warn "SubMan API Token 不能为空。"
  done

  if [[ -z "${SUBMAN_NODE_PREFIX}" ]]; then
    read -rp "SubMan 节点前缀 (默认: $(hostname)): " input_prefix
    SUBMAN_NODE_PREFIX=$(trim_whitespace "${input_prefix}")
    [[ -z "${SUBMAN_NODE_PREFIX}" ]] && SUBMAN_NODE_PREFIX=$(hostname)
  fi

  write_subman_config
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run:

```bash
bash tests/subman_config_helpers.sh
```

Expected: pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add install.sh tests/subman_config_helpers.sh
git commit -m "feat: add subman api config helpers"
```

## Task 3: Generate SubMan Node Payloads

**Files:**
- Create: `tests/subman_payload_generation.sh`
- Modify: `install.sh`

- [ ] **Step 1: Write the failing payload test**

Create `tests/subman_payload_generation.sh`:

```bash
#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

SUBMAN_NODE_PREFIX="edge-1"

SB_PROTOCOL="vless+reality"
SB_NODE_NAME="edge-1 vless"
SB_PORT="443"
SB_UUID="11111111-1111-1111-1111-111111111111"
SB_SNI="www.cloudflare.com"
SB_PUBLIC_KEY="public-key"
SB_SHORT_ID_1="abcd1234"

if [[ "$(subman_type_for_protocol "vless-reality")" != "vless" ]]; then
  printf 'expected vless-reality to map to vless\n' >&2
  exit 1
fi

vless_payload=$(build_subman_node_payload "vless-reality" "203.0.113.10")
if [[ "$(jq -r '.type' <<< "${vless_payload}")" != "vless" ]]; then
  printf 'expected vless payload type\n%s\n' "${vless_payload}" >&2
  exit 1
fi
if [[ "$(jq -r '.raw' <<< "${vless_payload}")" != vless://* ]]; then
  printf 'expected vless raw link\n%s\n' "${vless_payload}" >&2
  exit 1
fi
if [[ "$(jq -r '.enabled' <<< "${vless_payload}")" != "true" ]]; then
  printf 'expected enabled true\n%s\n' "${vless_payload}" >&2
  exit 1
fi
if ! jq -e '.tags | index("sing-box-vps") and index("edge-1")' <<< "${vless_payload}" >/dev/null; then
  printf 'expected sing-box-vps and prefix tags\n%s\n' "${vless_payload}" >&2
  exit 1
fi

SB_PROTOCOL="hy2"
SB_NODE_NAME="edge-1 hy2"
SB_PORT="8443"
SB_HY2_DOMAIN="hy2.example.com"
SB_HY2_PASSWORD="hy2-password"
SB_HY2_OBFS_ENABLED="y"
SB_HY2_OBFS_TYPE="salamander"
SB_HY2_OBFS_PASSWORD="obfs-password"

if [[ "$(subman_type_for_protocol "hy2")" != "hysteria2" ]]; then
  printf 'expected hy2 to map to hysteria2\n' >&2
  exit 1
fi

hy2_payload=$(build_subman_node_payload "hy2" "203.0.113.10")
if [[ "$(jq -r '.type' <<< "${hy2_payload}")" != "hysteria2" ]]; then
  printf 'expected hysteria2 payload type\n%s\n' "${hy2_payload}" >&2
  exit 1
fi
if [[ "$(jq -r '.raw' <<< "${hy2_payload}")" != hy2://* ]]; then
  printf 'expected hy2 raw link\n%s\n' "${hy2_payload}" >&2
  exit 1
fi

if subman_type_for_protocol "mixed" >/dev/null; then
  printf 'expected mixed to be unsupported for SubMan sync\n' >&2
  exit 1
fi

if [[ "$(subman_external_key_for_protocol "hy2")" != "sing-box-vps:edge-1:hy2" ]]; then
  printf 'expected stable hy2 external key\n' >&2
  exit 1
fi
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
bash tests/subman_payload_generation.sh
```

Expected: fail because `subman_type_for_protocol` is not defined.

- [ ] **Step 3: Add payload helpers**

In `install.sh`, near existing link builders, add:

```bash
subman_node_prefix() {
  local prefix
  prefix=$(trim_whitespace "${SUBMAN_NODE_PREFIX:-}")
  [[ -z "${prefix}" ]] && prefix=$(hostname)
  printf '%s' "${prefix}"
}

subman_type_for_protocol() {
  local protocol
  protocol=$(normalize_protocol_id "$1")

  case "${protocol}" in
    vless-reality) printf 'vless' ;;
    hy2) printf 'hysteria2' ;;
    *) return 1 ;;
  esac
}

subman_external_key_for_protocol() {
  local protocol prefix
  protocol=$(normalize_protocol_id "$1")
  prefix=$(subman_node_prefix)
  printf 'sing-box-vps:%s:%s' "${prefix}" "${protocol}"
}

build_subman_raw_for_protocol() {
  local protocol public_ip
  protocol=$(normalize_protocol_id "$1")
  public_ip=$2

  case "${protocol}" in
    vless-reality) build_vless_link "${public_ip}" ;;
    hy2) build_hy2_link "${public_ip}" ;;
    *) return 1 ;;
  esac
}

build_subman_node_payload() {
  local protocol public_ip node_type raw_link node_name prefix
  protocol=$(normalize_protocol_id "$1")
  public_ip=$2
  node_type=$(subman_type_for_protocol "${protocol}") || return 1
  raw_link=$(build_subman_raw_for_protocol "${protocol}" "${public_ip}") || return 1
  prefix=$(subman_node_prefix)
  node_name=$(trim_whitespace "${SB_NODE_NAME:-}")
  [[ -z "${node_name}" ]] && node_name="${prefix} ${protocol}"

  jq -n \
    --arg name "${node_name}" \
    --arg type "${node_type}" \
    --arg raw "${raw_link}" \
    --arg prefix "${prefix}" \
    '{
      "name": $name,
      "type": $type,
      "raw": $raw,
      "enabled": true,
      "tags": ["sing-box-vps", $prefix],
      "source": "single"
    }'
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run:

```bash
bash tests/subman_payload_generation.sh
```

Expected: pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add install.sh tests/subman_payload_generation.sh
git commit -m "feat: build subman node payloads"
```

## Task 4: Implement SubMan API Push

**Files:**
- Create: `tests/subman_api_push.sh`
- Modify: `install.sh`

- [ ] **Step 1: Write the failing API push test**

Create `tests/subman_api_push.sh`:

```bash
#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120

cat > "${TMP_DIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${CURL_ARGS_LOG}"

status="${FAKE_CURL_STATUS:-200}"
body="${FAKE_CURL_BODY:-{\"message\":\"ok\"}}"

if [[ "${status}" == "000" ]]; then
  printf 'network failed\n' >&2
  exit 7
fi

printf '%sHTTP_STATUS:%s' "${body}" "${status}"
EOF
chmod +x "${TMP_DIR}/bin/curl"

source_testable_install

export CURL_ARGS_LOG="${TMP_DIR}/curl-args.log"
export FAKE_CURL_STATUS="200"
export FAKE_CURL_BODY='{"message":"Node updated successfully"}'

SUBMAN_API_URL="https://subman.example.com"
SUBMAN_API_TOKEN="secret-token"
payload='{"name":"edge vless","type":"vless","raw":"vless://example","enabled":true,"tags":["sing-box-vps"],"source":"single"}'

push_output=$(push_subman_node "sing-box-vps:edge:vless-reality" "${payload}")
if [[ "${push_output}" != *"HTTP 200"* ]]; then
  printf 'expected success output to mention HTTP 200, got:\n%s\n' "${push_output}" >&2
  exit 1
fi

if ! grep -Fq "https://subman.example.com/api/nodes/by-key/sing-box-vps:edge:vless-reality" "${CURL_ARGS_LOG}"; then
  printf 'expected curl to call SubMan by-key endpoint, got:\n%s\n' "$(cat "${CURL_ARGS_LOG}")" >&2
  exit 1
fi

export FAKE_CURL_STATUS="500"
export FAKE_CURL_BODY='{"error":"bad"}'
if push_subman_node "sing-box-vps:edge:vless-reality" "${payload}" >"${TMP_DIR}/failure.out" 2>&1; then
  printf 'expected HTTP 500 to fail\n' >&2
  exit 1
fi

failure_output=$(cat "${TMP_DIR}/failure.out")
if [[ "${failure_output}" != *"HTTP 500"* ]]; then
  printf 'expected failure output to mention HTTP 500, got:\n%s\n' "${failure_output}" >&2
  exit 1
fi
if [[ "${failure_output}" == *"secret-token"* ]]; then
  printf 'expected failure output not to leak token, got:\n%s\n' "${failure_output}" >&2
  exit 1
fi
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
bash tests/subman_api_push.sh
```

Expected: fail because `push_subman_node` is still a stub or undefined.

- [ ] **Step 3: Implement API call helper**

Replace the temporary `push_nodes_to_subman` stub with real API helpers. Add `push_subman_node()` before the orchestrator:

```bash
push_subman_node() {
  local external_key=$1
  local payload_json=$2
  local api_url response body http_status curl_status

  api_url="$(normalize_subman_api_url "${SUBMAN_API_URL}")/api/nodes/by-key/${external_key}"

  response=$(curl -sS -X PUT "${api_url}" \
    -H "Authorization: Bearer ${SUBMAN_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${payload_json}" \
    -w 'HTTP_STATUS:%{http_code}' 2>&1) || curl_status=$?

  if [[ -n "${curl_status:-}" ]]; then
    log_warn "SubMan API 请求失败: curl exit ${curl_status}. ${response}"
    return 1
  fi

  http_status=${response##*HTTP_STATUS:}
  body=${response%HTTP_STATUS:*}

  if [[ ! "${http_status}" =~ ^2[0-9][0-9]$ ]]; then
    log_warn "SubMan API 返回 HTTP ${http_status}: ${body}"
    return 1
  fi

  log_success "SubMan 节点已同步: ${external_key} (HTTP ${http_status})"
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run:

```bash
bash tests/subman_api_push.sh
```

Expected: pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add install.sh tests/subman_api_push.sh
git commit -m "feat: push nodes to subman api"
```

## Task 5: Orchestrate Installed Protocol Sync

**Files:**
- Create: `tests/subman_sync_orchestration.sh`
- Modify: `install.sh`

- [ ] **Step 1: Write the failing orchestration test**

Create `tests/subman_sync_orchestration.sh`:

```bash
#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

mkdir -p "${SB_PROTOCOL_STATE_DIR}"
cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality,mixed,hy2,anytls
PROTOCOL_STATE_VERSION=1
EOF

cat > "$(protocol_state_file vless-reality)" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME='edge vless'
PORT=443
UUID=11111111-1111-1111-1111-111111111111
SNI=www.cloudflare.com
REALITY_PUBLIC_KEY=public-key
SHORT_ID_1=abcd1234
EOF

cat > "$(protocol_state_file mixed)" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME='edge mixed'
PORT=2080
AUTH_ENABLED=y
USERNAME=user
PASSWORD=pass
EOF

cat > "$(protocol_state_file hy2)" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME='edge hy2'
PORT=8443
DOMAIN=hy2.example.com
PASSWORD=hy2-password
OBFS_ENABLED=n
OBFS_TYPE=
OBFS_PASSWORD=
EOF

cat > "$(protocol_state_file anytls)" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME='edge anytls'
PORT=9443
DOMAIN=anytls.example.com
PASSWORD=anytls-password
USER_NAME=anytls-user
EOF

write_subman_config() { :; }
prompt_subman_config_if_needed() {
  SUBMAN_API_URL="https://subman.example.com"
  SUBMAN_API_TOKEN="secret-token"
  SUBMAN_NODE_PREFIX="edge"
}
get_public_ip() {
  printf '203.0.113.10'
}

PUSHED_KEYS=()
push_subman_node() {
  PUSHED_KEYS+=("$1")
  jq -e '.raw | test("^(vless|hy2)://")' <<< "$2" >/dev/null
}

output=$(push_nodes_to_subman 2>&1)
if [[ "${output}" != *"已同步: 2"* ]]; then
  printf 'expected two synced nodes, got:\n%s\n' "${output}" >&2
  exit 1
fi
if [[ "${output}" != *"已跳过: 2"* ]]; then
  printf 'expected mixed and anytls skipped, got:\n%s\n' "${output}" >&2
  exit 1
fi
if [[ "${PUSHED_KEYS[*]}" != *"sing-box-vps:edge:vless-reality"* || "${PUSHED_KEYS[*]}" != *"sing-box-vps:edge:hy2"* ]]; then
  printf 'expected vless and hy2 keys, got: %s\n' "${PUSHED_KEYS[*]}" >&2
  exit 1
fi
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
bash tests/subman_sync_orchestration.sh
```

Expected: fail because `push_nodes_to_subman` does not yet orchestrate installed protocols.

- [ ] **Step 3: Implement `push_nodes_to_subman()`**

In `install.sh`, implement:

```bash
push_nodes_to_subman() {
  local original_protocol_state public_ip protocol external_key payload
  local installed_protocols=()
  local synced_count=0
  local skipped_count=0
  local failed_count=0

  prompt_subman_config_if_needed

  public_ip=$(get_public_ip)
  if [[ -z "${public_ip}" ]]; then
    log_warn "未获取到公网 IP，无法生成 SubMan 节点链接。"
    return 1
  fi

  original_protocol_state=$(runtime_protocol_to_state "${SB_PROTOCOL}" 2>/dev/null || true)
  mapfile -t installed_protocols < <(list_installed_protocols)

  if [[ ${#installed_protocols[@]} -eq 0 ]]; then
    log_warn "当前未检测到已安装协议，无法推送到 SubMan。"
    return 1
  fi

  for protocol in "${installed_protocols[@]}"; do
    if ! subman_type_for_protocol "${protocol}" >/dev/null; then
      log_warn "协议不支持推送到 SubMan，已跳过: $(protocol_display_name "$(state_protocol_to_runtime "${protocol}")")"
      skipped_count=$((skipped_count + 1))
      continue
    fi

    if ! protocol_state_exists "${protocol}"; then
      log_warn "协议状态文件缺失，已跳过 SubMan 推送: ${protocol}"
      skipped_count=$((skipped_count + 1))
      continue
    fi

    load_protocol_state "${protocol}"
    external_key=$(subman_external_key_for_protocol "${protocol}")

    if ! payload=$(build_subman_node_payload "${protocol}" "${public_ip}"); then
      log_warn "生成 SubMan 节点失败，已跳过: ${protocol}"
      failed_count=$((failed_count + 1))
      continue
    fi

    if push_subman_node "${external_key}" "${payload}"; then
      synced_count=$((synced_count + 1))
    else
      failed_count=$((failed_count + 1))
    fi
  done

  if [[ -n "${original_protocol_state}" ]] && protocol_state_exists "${original_protocol_state}"; then
    load_protocol_state "${original_protocol_state}"
  fi

  printf 'SubMan 推送完成：已同步: %s，已跳过: %s，失败: %s\n' "${synced_count}" "${skipped_count}" "${failed_count}"

  if (( synced_count == 0 || failed_count > 0 )); then
    return 1
  fi
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run:

```bash
bash tests/subman_sync_orchestration.sh
```

Expected: pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add install.sh tests/subman_sync_orchestration.sh
git commit -m "feat: sync installed nodes to subman"
```

## Task 6: Documentation and Version Metadata

**Files:**
- Modify: `install.sh`
- Modify: `README.md`
- Test: `tests/version_metadata_is_consistent.sh`
- Test: `tests/readme_mentions_current_versions.sh`

- [ ] **Step 1: Bump script version**

Change `install.sh`:

```bash
readonly SCRIPT_VERSION="2026051203"
```

Change `README.md`:

```markdown
- 脚本版本：`2026051203`
```

- [ ] **Step 2: Document SubMan support in README**

Add a feature bullet after the protocol display/client export bullet:

```markdown
- **SubMan 同步**：可将当前 VPS 的 VLESS / Hysteria2 节点通过已部署的 SubMan API 幂等推送到 SubMan 节点库，便于后续聚合与发布订阅。
```

Add to key paths:

```markdown
- **SubMan API 配置**: `/root/sing-box-vps/subman.env`
```

Update the node/status menu line to mention SubMan:

```markdown
7.  **状态与节点信息**：先查看服务摘要，再选择已安装协议查看链接/二维码、导出裸核客户端配置或推送节点到 SubMan。
```

- [ ] **Step 3: Run metadata tests**

Run:

```bash
bash tests/version_metadata_is_consistent.sh
bash tests/readme_mentions_current_versions.sh
```

Expected: both pass.

- [ ] **Step 4: Commit**

Run:

```bash
git add install.sh README.md
git commit -m "docs: document subman node sync"
```

## Task 7: Full Verification

**Files:**
- No source files changed unless verification reveals a bug.

- [ ] **Step 1: Run focused tests**

Run:

```bash
bash tests/node_info_action_menu_renders.sh
bash tests/subman_config_helpers.sh
bash tests/subman_payload_generation.sh
bash tests/subman_api_push.sh
bash tests/subman_sync_orchestration.sh
bash tests/version_metadata_is_consistent.sh
bash tests/readme_mentions_current_versions.sh
```

Expected: all pass.

- [ ] **Step 2: Run default verification workflow**

Run:

```bash
bash dev/verification/run.sh
```

Expected: pass. Because `install.sh` changed, expect the repository verification workflow to select the appropriate local and remote checks according to `dev/verification/run.sh`.

- [ ] **Step 3: Fix any verification failures**

If a focused or verification test fails, inspect the failing output, make the smallest fix in the relevant file, rerun the failing command, then rerun the focused test suite from Step 1.

- [ ] **Step 4: Commit verification fixes if needed**

Only if Step 3 changed files, run:

```bash
git add install.sh README.md tests/subman_config_helpers.sh tests/subman_payload_generation.sh tests/subman_api_push.sh tests/subman_sync_orchestration.sh tests/node_info_action_menu_renders.sh
git commit -m "fix: stabilize subman node sync"
```

