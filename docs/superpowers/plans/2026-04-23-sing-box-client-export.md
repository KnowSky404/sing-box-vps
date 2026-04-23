# Sing-box Client Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a menu-driven export that builds a complete sing-box bare-core client config from installed server protocol state, with a local `mixed` inbound plus `selector`, `urltest`, and `clash_api`.

**Architecture:** Keep the feature inside `install.sh` and reuse the existing protocol state layer under `/root/sing-box-vps/protocols`. Add focused helpers for filtering exportable protocols, building per-protocol outbound JSON, assembling the full client config, writing the exported file with backup, and extending menu `9` into a small node-info submenu.

**Tech Stack:** Bash, jq, existing shell regression tests in `tests/`

---

## File Structure

- Modify: `install.sh`
  Add client-export helpers, the new node-info submenu, export file handling, and the script version bump for the implementation turn.
- Create: `tests/export_client_config_multi_protocol.sh`
  Verify a multi-protocol export includes real outbounds, `urltest`, `selector`, `mixed` inbound, and `clash_api`.
- Create: `tests/export_client_config_mixed_only_rejected.sh`
  Verify mixed-only installs do not export a bare-core client config.
- Create: `tests/export_client_config_creates_backup.sh`
  Verify an existing export is backed up before overwrite.
- Modify: `tests/view_node_info_shows_all_installed_protocols.sh`
  Adapt the node-info path to the new submenu so the old connection-info behavior stays covered.

### Task 1: Lock in the node-info submenu behavior with tests

**Files:**
- Modify: `tests/view_node_info_shows_all_installed_protocols.sh`
- Test: `tests/view_node_info_shows_all_installed_protocols.sh`

- [ ] **Step 1: Update the existing regression to enter the new submenu first**

```bash
view_node_info <<'EOF'
1
1
0
0
EOF
```

- [ ] **Step 2: Run the regression and verify it fails before implementation**

Run: `bash tests/view_node_info_shows_all_installed_protocols.sh`
Expected: FAIL because menu `9` still goes directly to `show_connection_info_menu` and does not consume the extra submenu choice.

- [ ] **Step 3: Add the submenu entry points in `install.sh`**

```bash
show_node_info_actions_menu() {
  while true; do
    echo
    render_page_header "节点信息查看" "查看连接资料或导出 sing-box 客户端配置"
    render_section_title "操作选项"
    render_menu_item "1" "查看连接链接 / 二维码"
    render_menu_item "2" "导出 sing-box 裸核客户端配置"
    echo "0. 返回"
    read -rp "请选择 [0-2]: " node_info_choice

    case "${node_info_choice}" in
      1) show_connection_info_menu ;;
      2) export_singbox_client_config ;;
      0) return ;;
      *) log_warn "无效选项，请重新选择。" ;;
    esac
  done
}

view_node_info() {
  log_info "正在从配置文件中读取节点信息..."
  load_current_config_state
  show_node_info_actions_menu
}
```

- [ ] **Step 4: Re-run the regression and verify it passes**

Run: `bash tests/view_node_info_shows_all_installed_protocols.sh`
Expected: PASS

- [ ] **Step 5: Commit the submenu test and wiring**

```bash
git add tests/view_node_info_shows_all_installed_protocols.sh install.sh
git commit -m "feat: add node info action submenu"
```

### Task 2: Add a failing multi-protocol export test

**Files:**
- Create: `tests/export_client_config_multi_protocol.sh`
- Test: `tests/export_client_config_multi_protocol.sh`

- [ ] **Step 1: Create the failing regression for a `vless-reality + hy2 + anytls` export**

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
  -e 's|main \"\\$@\"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project/protocols" "${TMP_DIR}/bin"
printf '#!/usr/bin/env bash\nprintf test-host\\\\n\n' > "${TMP_DIR}/bin/hostname"
chmod +x "${TMP_DIR}/bin/hostname"
export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

get_public_ip() { printf '203.0.113.10\n'; }

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality,hy2,anytls
PROTOCOL_STATE_VERSION=1
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=vless_reality_test-host
PORT=443
UUID=11111111-1111-4111-8111-111111111111
SNI=reality.example.com
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/hy2.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=hy2_test-host
PORT=8443
DOMAIN=hy2.example.com
PASSWORD=hy2-pass
USER_NAME=hy2-user
UP_MBPS=100
DOWN_MBPS=50
OBFS_ENABLED=y
OBFS_TYPE=salamander
OBFS_PASSWORD=hy2-obfs
TLS_MODE=manual
ACME_MODE=http
ACME_EMAIL=
ACME_DOMAIN=
DNS_PROVIDER=cloudflare
CF_API_TOKEN=
CERT_PATH=/etc/ssl/certs/hy2.pem
KEY_PATH=/etc/ssl/private/hy2.key
MASQUERADE=
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/anytls.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=anytls_test-host
PORT=9443
DOMAIN=anytls.example.com
PASSWORD=anytls-pass
USER_NAME=anytls-user
TLS_MODE=manual
ACME_MODE=http
ACME_EMAIL=
ACME_DOMAIN=
DNS_PROVIDER=cloudflare
CF_API_TOKEN=
CERT_PATH=/etc/ssl/certs/anytls.pem
KEY_PATH=/etc/ssl/private/anytls.key
EOF

load_protocol_state "vless-reality"
export_singbox_client_config > "${TMP_DIR}/stdout.txt"

EXPORT_FILE="${SB_PROJECT_DIR}/client/sing-box-client.json"
[[ -f "${EXPORT_FILE}" ]]

jq -e '.inbounds[] | select(.type == "mixed" and .listen == "127.0.0.1" and .listen_port == 2080)' "${EXPORT_FILE}" >/dev/null
jq -e '.outbounds[] | select(.type == "selector" and .tag == "proxy" and .default == "auto")' "${EXPORT_FILE}" >/dev/null
jq -e '.outbounds[] | select(.type == "urltest" and .tag == "auto")' "${EXPORT_FILE}" >/dev/null
jq -e '.outbounds[] | select(.type == "vless" and .tag == "vless-reality-443")' "${EXPORT_FILE}" >/dev/null
jq -e '.outbounds[] | select(.type == "hysteria2" and .tag == "hy2-8443" and .obfs.type == "salamander")' "${EXPORT_FILE}" >/dev/null
jq -e '.outbounds[] | select(.type == "anytls" and .tag == "anytls-9443")' "${EXPORT_FILE}" >/dev/null
jq -e '.experimental.clash_api.external_controller == "127.0.0.1:9090"' "${EXPORT_FILE}" >/dev/null
```

- [ ] **Step 2: Run the new regression and verify it fails before implementation**

Run: `bash tests/export_client_config_multi_protocol.sh`
Expected: FAIL with `export_singbox_client_config: command not found` or missing export file/assertions.

- [ ] **Step 3: Commit the failing test**

```bash
git add tests/export_client_config_multi_protocol.sh
git commit -m "test: cover multi-protocol client export"
```

### Task 3: Implement exportable protocol filtering and per-protocol outbound builders

**Files:**
- Modify: `install.sh`
- Test: `tests/export_client_config_multi_protocol.sh`

- [ ] **Step 1: Add focused helpers for export filtering and stable outbound tags**

```bash
list_exportable_client_protocols() {
  local installed_protocols=() protocol
  mapfile -t installed_protocols < <(list_installed_protocols)

  for protocol in "${installed_protocols[@]}"; do
    case "${protocol}" in
      vless-reality|hy2|anytls) printf '%s\n' "${protocol}" ;;
    esac
  done
}

client_outbound_tag_for_protocol() {
  local protocol port
  protocol=$(normalize_protocol_id "$1")
  port=$2
  printf '%s-%s' "${protocol}" "${port}"
}
```

- [ ] **Step 2: Add one JSON builder per protocol and keep field emission minimal**

```bash
build_client_vless_reality_outbound() {
  local public_ip=$1
  local server_host short_id
  server_host=${SB_SNI:-${public_ip}}
  short_id=${SB_SHORT_ID_1:-${SB_SHORT_ID_2:-}}

  jq -n \
    --arg tag "$(client_outbound_tag_for_protocol "vless-reality" "${SB_PORT}")" \
    --arg server "${server_host}" \
    --argjson port "${SB_PORT}" \
    --arg uuid "${SB_UUID}" \
    --arg sni "${SB_SNI:-${server_host}}" \
    --arg public_key "${SB_PUBLIC_KEY}" \
    --arg short_id "${short_id}" \
    '{
      type: "vless",
      tag: $tag,
      server: $server,
      server_port: $port,
      uuid: $uuid,
      tls: {
        enabled: true,
        server_name: $sni,
        reality: {
          enabled: true,
          public_key: $public_key,
          short_id: $short_id
        }
      }
    }'
}
```

```bash
build_client_hy2_outbound() {
  local server_host
  server_host=${SB_HY2_DOMAIN:-$1}

  jq -n \
    --arg tag "$(client_outbound_tag_for_protocol "hy2" "${SB_PORT}")" \
    --arg server "${server_host}" \
    --argjson port "${SB_PORT}" \
    --arg password "${SB_HY2_PASSWORD}" \
    --arg sni "${SB_HY2_DOMAIN:-${server_host}}" \
    --arg up_mbps "${SB_HY2_UP_MBPS:-}" \
    --arg down_mbps "${SB_HY2_DOWN_MBPS:-}" \
    --arg obfs_enabled "${SB_HY2_OBFS_ENABLED:-n}" \
    --arg obfs_type "${SB_HY2_OBFS_TYPE:-}" \
    --arg obfs_password "${SB_HY2_OBFS_PASSWORD:-}" \
    '{
      type: "hysteria2",
      tag: $tag,
      server: $server,
      server_port: $port,
      password: $password,
      tls: {
        enabled: true,
        server_name: $sni
      }
    }
    | if $up_mbps != "" then .up_mbps = ($up_mbps | tonumber) else . end
    | if $down_mbps != "" then .down_mbps = ($down_mbps | tonumber) else . end
    | if $obfs_enabled == "y" then .obfs = {type: $obfs_type, password: $obfs_password} else . end'
}
```

```bash
build_client_anytls_outbound() {
  local server_host
  server_host=${SB_ANYTLS_DOMAIN:-$1}

  jq -n \
    --arg tag "$(client_outbound_tag_for_protocol "anytls" "${SB_PORT}")" \
    --arg server "${server_host}" \
    --argjson port "${SB_PORT}" \
    --arg password "${SB_ANYTLS_PASSWORD}" \
    --arg sni "${SB_ANYTLS_DOMAIN:-${server_host}}" \
    '{
      type: "anytls",
      tag: $tag,
      server: $server,
      server_port: $port,
      password: $password,
      tls: {
        enabled: true,
        server_name: $sni
      }
    }'
}
```

- [ ] **Step 3: Add a dispatcher that loads each protocol state and returns one outbound JSON object**

```bash
build_client_outbound_json_for_protocol() {
  local protocol public_ip
  protocol=$(normalize_protocol_id "$1")
  public_ip=$2
  load_protocol_state "${protocol}"

  case "${protocol}" in
    vless-reality) build_client_vless_reality_outbound "${public_ip}" ;;
    hy2) build_client_hy2_outbound "${public_ip}" ;;
    anytls) build_client_anytls_outbound "${public_ip}" ;;
    *) return 1 ;;
  esac
}
```

- [ ] **Step 4: Re-run the failing export test to confirm it now fails later in assembly**

Run: `bash tests/export_client_config_multi_protocol.sh`
Expected: FAIL on missing `export_singbox_client_config`/group outbounds/full config, not on missing per-protocol builders.

- [ ] **Step 5: Commit the builder layer**

```bash
git add install.sh
git commit -m "feat: add sing-box client outbound builders"
```

### Task 4: Implement full client-config assembly and file export

**Files:**
- Modify: `install.sh`
- Test: `tests/export_client_config_multi_protocol.sh`

- [ ] **Step 1: Add helpers for export path and full config assembly**

```bash
client_export_file_path() {
  printf '%s/client/sing-box-client.json' "${SB_PROJECT_DIR}"
}

build_singbox_client_config() {
  local public_ip exportable_protocols=() protocol outbound_json outbounds_json selector_members_json clash_secret
  public_ip=$(get_public_ip)
  mapfile -t exportable_protocols < <(list_exportable_client_protocols)
  [[ ${#exportable_protocols[@]} -gt 0 ]] || return 1

  outbounds_json='[]'
  selector_members_json='["auto"]'

  for protocol in "${exportable_protocols[@]}"; do
    outbound_json=$(build_client_outbound_json_for_protocol "${protocol}" "${public_ip}")
    outbounds_json=$(jq --argjson item "${outbound_json}" '. + [$item]' <<< "${outbounds_json}")
    selector_members_json=$(jq --arg tag "$(jq -r '.tag' <<< "${outbound_json}")" '. + [$tag]' <<< "${selector_members_json}")
  done

  clash_secret=$(openssl rand -hex 16)

  jq -n \
    --argjson proxy_outbounds "${selector_members_json}" \
    --argjson auto_outbounds "$(jq '. - ["auto"]' <<< "${selector_members_json}")" \
    --argjson protocol_outbounds "${outbounds_json}" \
    --arg clash_secret "${clash_secret}" \
    '{
      log: { level: "info", timestamp: true },
      dns: {
        servers: [
          { type: "tls", tag: "dns-remote", server: "1.1.1.1" },
          { type: "local", tag: "dns-local" }
        ],
        rules: [
          { outbound: "any", server: "dns-local" }
        ],
        final: "dns-remote"
      },
      inbounds: [
        {
          type: "mixed",
          tag: "mixed-in",
          listen: "127.0.0.1",
          listen_port: 2080
        }
      ],
      outbounds: (
        [
          {
            type: "selector",
            tag: "proxy",
            outbounds: $proxy_outbounds,
            default: "auto"
          },
          {
            type: "urltest",
            tag: "auto",
            outbounds: $auto_outbounds,
            url: "https://www.gstatic.com/generate_204",
            interval: "3m"
          }
        ] + $protocol_outbounds + [
          { type: "direct", tag: "direct" },
          { type: "block", tag: "block" },
          { type: "dns", tag: "dns-out" }
        ]
      ),
      route: {
        rules: [
          { protocol: "dns", action: "hijack-dns" }
        ],
        final: "proxy",
        auto_detect_interface: true
      },
      experimental: {
        cache_file: { enabled: true, path: "cache.db" },
        clash_api: {
          external_controller: "127.0.0.1:9090",
          secret: $clash_secret
        }
      }
    }'
}
```

- [ ] **Step 2: Add backup-aware write and top-level export command**

```bash
write_client_config_export() {
  local export_file export_dir rendered_json
  export_file=$(client_export_file_path)
  export_dir=$(dirname "${export_file}")
  rendered_json=$1

  mkdir -p "${export_dir}"
  if [[ -f "${export_file}" ]]; then
    cp "${export_file}" "${export_file}.bak"
  fi

  jq . <<< "${rendered_json}" > "${export_file}"
}

export_singbox_client_config() {
  local rendered_json export_file
  if ! rendered_json=$(build_singbox_client_config); then
    log_warn "当前无可导出的 sing-box 裸核客户端节点。"
    return 1
  fi

  write_client_config_export "${rendered_json}"
  export_file=$(client_export_file_path)

  echo
  log_success "已生成 sing-box 裸核客户端配置。"
  echo "文件路径: ${export_file}"
  echo "本地 Mixed 入口: 127.0.0.1:2080"
  echo "Clash API: 127.0.0.1:9090"
  echo
  printf '%s\n' "${rendered_json}"
}
```

- [ ] **Step 3: Wire the new submenu action to the export command**

```bash
case "${node_info_choice}" in
  1) show_connection_info_menu ;;
  2) export_singbox_client_config || true ;;
  0) return ;;
  *) log_warn "无效选项，请重新选择。" ;;
esac
```

- [ ] **Step 4: Run the multi-protocol export regression and verify it passes**

Run: `bash tests/export_client_config_multi_protocol.sh`
Expected: PASS

- [ ] **Step 5: Commit the assembled export feature**

```bash
git add install.sh tests/export_client_config_multi_protocol.sh
git commit -m "feat: export sing-box bare-core client config"
```

### Task 5: Cover mixed-only rejection and backup behavior

**Files:**
- Create: `tests/export_client_config_mixed_only_rejected.sh`
- Create: `tests/export_client_config_creates_backup.sh`
- Test: `tests/export_client_config_mixed_only_rejected.sh`
- Test: `tests/export_client_config_creates_backup.sh`

- [ ] **Step 1: Add the mixed-only rejection test**

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
  -e 's|main \"\\$@\"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project/protocols" "${TMP_DIR}/bin"
printf '#!/usr/bin/env bash\nprintf test-host\\\\n\n' > "${TMP_DIR}/bin/hostname"
chmod +x "${TMP_DIR}/bin/hostname"
export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=mixed
PROTOCOL_STATE_VERSION=1
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/mixed.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=mixed_test-host
PORT=1080
AUTH_ENABLED=y
USERNAME=test-user
PASSWORD=test-pass
EOF

if export_singbox_client_config > "${TMP_DIR}/stdout.txt" 2>&1; then
  printf 'expected mixed-only export to fail\n' >&2
  exit 1
fi

if [[ -f "${SB_PROJECT_DIR}/client/sing-box-client.json" ]]; then
  printf 'did not expect export file for mixed-only install\n' >&2
  exit 1
fi

grep -Fq '当前无可导出的 sing-box 裸核客户端节点' "${TMP_DIR}/stdout.txt"
```

- [ ] **Step 2: Add the backup overwrite test**

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
  -e 's|main \"\\$@\"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project/protocols" "${TMP_DIR}/project/client" "${TMP_DIR}/bin"
printf '#!/usr/bin/env bash\nprintf test-host\\\\n\n' > "${TMP_DIR}/bin/hostname"
chmod +x "${TMP_DIR}/bin/hostname"
export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

get_public_ip() { printf '203.0.113.10\n'; }

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=anytls
PROTOCOL_STATE_VERSION=1
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/anytls.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=anytls_test-host
PORT=443
DOMAIN=anytls.example.com
PASSWORD=anytls-pass
USER_NAME=anytls-user
TLS_MODE=manual
ACME_MODE=http
ACME_EMAIL=
ACME_DOMAIN=
DNS_PROVIDER=cloudflare
CF_API_TOKEN=
CERT_PATH=/etc/ssl/certs/anytls.pem
KEY_PATH=/etc/ssl/private/anytls.key
EOF

printf '{"legacy":true}\n' > "${SB_PROJECT_DIR}/client/sing-box-client.json"

load_protocol_state "anytls"
export_singbox_client_config >/dev/null

[[ -f "${SB_PROJECT_DIR}/client/sing-box-client.json.bak" ]]
grep -Fq '"legacy":true' "${SB_PROJECT_DIR}/client/sing-box-client.json.bak"
jq -e '.outbounds[] | select(.type == "anytls")' "${SB_PROJECT_DIR}/client/sing-box-client.json" >/dev/null
```

- [ ] **Step 3: Run both regressions and verify they fail before the backup/rejection handling exists**

Run: `bash tests/export_client_config_mixed_only_rejected.sh`
Expected: FAIL before rejection handling is in place.

Run: `bash tests/export_client_config_creates_backup.sh`
Expected: FAIL before backup handling is in place.

- [ ] **Step 4: Implement the final guardrails if still missing**

```bash
if [[ ${#exportable_protocols[@]} -eq 0 ]]; then
  return 1
fi

if [[ -f "${export_file}" ]]; then
  cp "${export_file}" "${export_file}.bak"
fi
```

- [ ] **Step 5: Re-run both regressions and verify they pass**

Run: `bash tests/export_client_config_mixed_only_rejected.sh`
Expected: PASS

Run: `bash tests/export_client_config_creates_backup.sh`
Expected: PASS

- [ ] **Step 6: Commit the guardrail coverage**

```bash
git add tests/export_client_config_mixed_only_rejected.sh tests/export_client_config_creates_backup.sh install.sh
git commit -m "test: cover client export guardrails"
```

### Task 6: Final verification and version bump

**Files:**
- Modify: `install.sh`
- Test: `tests/view_node_info_shows_all_installed_protocols.sh`
- Test: `tests/export_client_config_multi_protocol.sh`
- Test: `tests/export_client_config_mixed_only_rejected.sh`
- Test: `tests/export_client_config_creates_backup.sh`

- [ ] **Step 1: Bump `SCRIPT_VERSION` once for this implementation turn using the `YYYYMMDDXX` rule**

```bash
readonly SCRIPT_VERSION="2026042301"
```

- [ ] **Step 2: Run the focused local regression set**

Run: `bash tests/view_node_info_shows_all_installed_protocols.sh`
Expected: PASS

Run: `bash tests/export_client_config_multi_protocol.sh`
Expected: PASS

Run: `bash tests/export_client_config_mixed_only_rejected.sh`
Expected: PASS

Run: `bash tests/export_client_config_creates_backup.sh`
Expected: PASS

- [ ] **Step 3: Run the repo verification workflow required for `install.sh` changes**

Run: `bash dev/verification/run.sh`
Expected: local fast checks pass, and if the configured target triggers remote verification rules, the real remote flow also passes.

- [ ] **Step 4: Inspect the final diff**

Run: `git diff --stat HEAD~4..HEAD`
Expected: only `install.sh` and the intended `tests/*.sh` files are included for the feature.

- [ ] **Step 5: Commit the final version bump / verification-ready state**

```bash
git add install.sh tests/view_node_info_shows_all_installed_protocols.sh tests/export_client_config_multi_protocol.sh tests/export_client_config_mixed_only_rejected.sh tests/export_client_config_creates_backup.sh
git commit -m "feat: export sing-box bare-core client config"
```
