# Client Export CN Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade exported sing-box bare-core client configs to use latest `sing-box` `rule_set` syntax for mainland China direct routing, with China DNS direct resolution and non-China traffic proxied by default.

**Architecture:** Extend the existing `build_singbox_client_config()` path inside `install.sh` rather than creating a second export mode. Reuse the current mixed-inbound and selector/urltest structure, then layer in `dns.servers`, `dns.rules`, `route.rule_set`, and `route.rules` that use Loyalsoldier `geoip-cn.srs` via jsDelivr plus official sing-box `geosite-cn.srs`.

**Tech Stack:** Bash, jq, sing-box remote binary rule sets (`.srs`), existing shell regression tests in `tests/`

---

## File Structure

- Modify: `install.sh`
  Extend exported client config generation to add CN DNS split and CN direct route rule sets using current sing-box syntax.
- Modify: `tests/export_client_config_multi_protocol.sh`
  Expand the existing export test to assert CN route rule sets and DNS split behavior.
- Create: `tests/export_client_config_cn_routing_rules.sh`
  Add a focused regression for exported `dns.rules` and `route.rules` structure so route behavior stays explicit and easier to debug.

### Task 1: Lock in failing coverage for CN route rule sets on the main export test

**Files:**
- Modify: `tests/export_client_config_multi_protocol.sh`
- Test: `tests/export_client_config_multi_protocol.sh`

- [ ] **Step 1: Extend the existing export regression with CN routing assertions**

```bash
if ! jq -e '.route.rule_set[] | select(.tag == "geoip-cn" and .type == "remote" and .format == "binary" and .url == "https://cdn.jsdelivr.net/gh/Loyalsoldier/geoip@release/srs/cn.srs")' "${EXPECTED_EXPORT_PATH}" >/dev/null; then
  printf 'expected route.rule_set to contain Loyalsoldier geoip-cn rule-set, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.route.rule_set[] | select(.tag == "geosite-cn" and .type == "remote" and .format == "binary")' "${EXPECTED_EXPORT_PATH}" >/dev/null; then
  printf 'expected route.rule_set to contain geosite-cn rule-set, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.route.rules[] | select(.rule_set == "geosite-cn" and .action == "route" and .outbound == "direct")' "${EXPECTED_EXPORT_PATH}" >/dev/null; then
  printf 'expected route.rules to direct geosite-cn traffic, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.route.rules[] | select(.rule_set == "geoip-cn" and .action == "route" and .outbound == "direct")' "${EXPECTED_EXPORT_PATH}" >/dev/null; then
  printf 'expected route.rules to direct geoip-cn traffic, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.dns.rules[] | select(.rule_set == "geosite-cn" and .server == "cn-dns")' "${EXPECTED_EXPORT_PATH}" >/dev/null; then
  printf 'expected dns.rules to send geosite-cn queries to cn-dns, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi
```

- [ ] **Step 2: Run the export regression and verify it fails before implementation**

Run: `bash tests/export_client_config_multi_protocol.sh`
Expected: FAIL because the current exported config still only contains the minimal DNS/route skeleton and no CN rule sets.

- [ ] **Step 3: Commit the failing regression**

```bash
git add tests/export_client_config_multi_protocol.sh
git commit -m "test: cover cn routing in client export"
```

### Task 2: Add a focused regression for DNS split and route structure

**Files:**
- Create: `tests/export_client_config_cn_routing_rules.sh`
- Test: `tests/export_client_config_cn_routing_rules.sh`

- [ ] **Step 1: Add a focused shell regression that inspects only DNS and route sections**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"

perl -0pe '
  s/^\s*main "\$@"\s*$//m;
  s|readonly SB_PROJECT_DIR="/root/sing-box-vps"|readonly SB_PROJECT_DIR="'"${TMP_DIR}"'/project"|;
  s|readonly SINGBOX_BIN_PATH="/usr/local/bin/sing-box"|readonly SINGBOX_BIN_PATH="'"${TMP_DIR}"'/bin/sing-box"|;
  s|readonly SBV_BIN_PATH="/usr/local/bin/sbv"|readonly SBV_BIN_PATH="'"${TMP_DIR}"'/bin/sbv"|;
  s|readonly SINGBOX_SERVICE_FILE="/etc/systemd/system/sing-box.service"|readonly SINGBOX_SERVICE_FILE="'"${TMP_DIR}"'/sing-box.service"|;
' "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/bin"

printf '#!/usr/bin/env bash\nprintf test-host\\n\n' > "${TMP_DIR}/bin/hostname"
printf '#!/usr/bin/env bash\nexit 0\n' > "${TMP_DIR}/bin/sing-box"
chmod +x "${TMP_DIR}/bin/hostname" "${TMP_DIR}/bin/sing-box"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

get_public_ip() { printf '203.0.113.10\n'; }

mkdir -p "${SB_PROTOCOL_STATE_DIR}"

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=anytls
PROTOCOL_STATE_VERSION=1
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/anytls.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=anytls_test-host
PORT=9443
DOMAIN=anytls.example.com
PASSWORD=anytls-password
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

load_protocol_state "anytls"
export_singbox_client_config >/dev/null

EXPORT_PATH="${SB_PROJECT_DIR}/client/sing-box-client.json"

jq -e '.dns.servers[] | select(.tag == "cn-dns" and .type == "https" and .server == "223.5.5.5" and .path == "/dns-query")' "${EXPORT_PATH}" >/dev/null
jq -e '.dns.servers[] | select(.tag == "remote-dns" and .type == "https" and .server == "1.1.1.1" and .path == "/dns-query")' "${EXPORT_PATH}" >/dev/null
jq -e '.dns.final == "remote-dns"' "${EXPORT_PATH}" >/dev/null
jq -e '.route.final == "proxy"' "${EXPORT_PATH}" >/dev/null
```

- [ ] **Step 2: Run the new regression and verify it fails before implementation**

Run: `bash tests/export_client_config_cn_routing_rules.sh`
Expected: FAIL because current export does not yet define `cn-dns`, `geosite-cn`, or CN direct route rules.

- [ ] **Step 3: Commit the focused failing regression**

```bash
git add tests/export_client_config_cn_routing_rules.sh
git commit -m "test: add focused cn routing export regression"
```

### Task 3: Implement remote rule-set definitions and DNS split with current sing-box syntax

**Files:**
- Modify: `install.sh`
- Test: `tests/export_client_config_multi_protocol.sh`
- Test: `tests/export_client_config_cn_routing_rules.sh`

- [ ] **Step 1: Add focused helpers for CN rule-set definitions**

```bash
build_client_cn_route_rule_sets_json() {
  jq -n '[
    {
      "tag": "geoip-cn",
      "type": "remote",
      "format": "binary",
      "url": "https://cdn.jsdelivr.net/gh/Loyalsoldier/geoip@release/srs/cn.srs"
    },
    {
      "tag": "geosite-cn",
      "type": "remote",
      "format": "binary",
      "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs"
    }
  ]'
}
```

- [ ] **Step 2: Add focused helpers for CN DNS and route rules**

```bash
build_client_cn_dns_rules_json() {
  jq -n '[
    {
      "rule_set": "geosite-cn",
      "server": "cn-dns"
    }
  ]'
}
```

```bash
build_client_cn_route_rules_json() {
  jq -n '[
    {
      "protocol": "dns",
      "action": "hijack-dns"
    },
    {
      "ip_is_private": true,
      "action": "route",
      "outbound": "direct"
    },
    {
      "rule_set": "geosite-cn",
      "action": "route",
      "outbound": "direct"
    },
    {
      "rule_set": "geoip-cn",
      "action": "route",
      "outbound": "direct"
    }
  ]'
}
```

- [ ] **Step 3: Replace the minimal DNS/route skeleton in `build_singbox_client_config()`**

```bash
client_rule_sets_json=$(build_client_cn_route_rule_sets_json)
client_dns_rules_json=$(build_client_cn_dns_rules_json)
client_route_rules_json=$(build_client_cn_route_rules_json)

jq -n \
  --argjson remote_outbounds "${remote_outbounds_json}" \
  --argjson remote_tags "${remote_tags_json}" \
  --argjson client_rule_sets "${client_rule_sets_json}" \
  --argjson client_dns_rules "${client_dns_rules_json}" \
  --argjson client_route_rules "${client_route_rules_json}" \
  --arg clash_api_secret "${clash_api_secret}" \
  '{
    "log": {
      "level": "info",
      "timestamp": true
    },
    "dns": {
      "servers": [
        {
          "type": "https",
          "tag": "cn-dns",
          "server": "223.5.5.5",
          "server_port": 443,
          "path": "/dns-query"
        },
        {
          "type": "https",
          "tag": "remote-dns",
          "server": "1.1.1.1",
          "server_port": 443,
          "path": "/dns-query"
        }
      ],
      "rules": $client_dns_rules,
      "final": "remote-dns",
      "strategy": "prefer_ipv4"
    },
    "inbounds": [
      {
        "type": "mixed",
        "tag": "mixed-in",
        "listen": "127.0.0.1",
        "listen_port": 2080
      }
    ],
    "outbounds": (
      [
        {
          "type": "selector",
          "tag": "proxy",
          "outbounds": (["auto"] + $remote_tags),
          "default": "auto"
        },
        {
          "type": "urltest",
          "tag": "auto",
          "outbounds": $remote_tags,
          "url": "https://www.gstatic.com/generate_204",
          "interval": "3m"
        }
      ] + $remote_outbounds + [
        { "type": "direct", "tag": "direct" },
        { "type": "block", "tag": "block" },
        { "type": "dns", "tag": "dns" }
      ]
    ),
    "route": {
      "rules": $client_route_rules,
      "rule_set": $client_rule_sets,
      "final": "proxy",
      "auto_detect_interface": true
    },
    "experimental": {
      "cache_file": {
        "enabled": true,
        "path": "cache.db"
      },
      "clash_api": {
        "external_controller": "127.0.0.1:9090",
        "secret": $clash_api_secret
      }
    }
  }'
```

- [ ] **Step 4: Run the two CN-routing regressions and verify they pass**

Run: `bash tests/export_client_config_multi_protocol.sh`
Expected: PASS

Run: `bash tests/export_client_config_cn_routing_rules.sh`
Expected: PASS

- [ ] **Step 5: Commit the CN routing implementation**

```bash
git add install.sh tests/export_client_config_multi_protocol.sh tests/export_client_config_cn_routing_rules.sh
git commit -m "feat: add cn routing to client export"
```

### Task 4: Regression sweep and version bump

**Files:**
- Modify: `install.sh`
- Modify: `README.md`
- Test: `tests/export_client_config_multi_protocol.sh`
- Test: `tests/export_client_config_cn_routing_rules.sh`
- Test: `tests/export_client_config_mixed_only_rejected.sh`
- Test: `tests/export_client_config_creates_backup.sh`
- Test: `tests/version_metadata_is_consistent.sh`
- Test: `tests/readme_mentions_current_versions.sh`

- [ ] **Step 1: Bump the script version once for this new feature turn and sync README**

```bash
# install.sh
# Version: 2026042311
readonly SCRIPT_VERSION="2026042311"
```

```markdown
- 脚本版本：`2026042311`
```

- [ ] **Step 2: Run the focused regression set**

Run: `bash tests/export_client_config_multi_protocol.sh`
Expected: PASS

Run: `bash tests/export_client_config_cn_routing_rules.sh`
Expected: PASS

Run: `bash tests/export_client_config_mixed_only_rejected.sh`
Expected: PASS

Run: `bash tests/export_client_config_creates_backup.sh`
Expected: PASS

Run: `bash tests/version_metadata_is_consistent.sh`
Expected: PASS

Run: `bash tests/readme_mentions_current_versions.sh`
Expected: PASS

- [ ] **Step 3: Run required repo verification for `install.sh` and `README.md` changes**

Run: `bash dev/verification/run.sh --changed-file install.sh --changed-file README.md`
Expected: verification succeeds; if remote mode triggers, the target `sing-box-test` reports `remote_status=success`.

- [ ] **Step 4: Commit the version sync and verification-ready state**

```bash
git add install.sh README.md tests/export_client_config_multi_protocol.sh tests/export_client_config_cn_routing_rules.sh
git commit -m "chore: finalize cn routing export metadata"
```
