# Reality Multi-Instance Rate Limit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add VLESS + REALITY multi-instance management with optional per-instance upstream/downstream Mbps limits while preserving existing single-instance installs.

**Architecture:** Keep `vless-reality` as one protocol in `protocols/index.env`, but split its runtime state into a protocol-level file plus per-instance files under `protocols/vless-reality.d/`. Generate one VLESS inbound per REALITY instance, expose every instance in links/client export/SubMan, and refresh an idempotent QoS layer from instance rate-limit fields.

**Tech Stack:** Bash, jq, sing-box 1.13.x config JSON, shell regression tests, Linux `tc`/`nftables` QoS hooks

---

## File Structure

- Modify: `install.sh`
  - Add REALITY instance state helpers.
  - Migrate legacy `vless-reality.env` into `vless-reality.d/main.env`.
  - Generate multiple VLESS inbounds from REALITY instances.
  - Add create/update/remove flows for individual REALITY instances.
  - Update link generation, client export, SubMan sync, firewall opening, and status display to iterate REALITY instances.
  - Add idempotent QoS refresh hooks driven by `RATE_LIMIT_UP_MBPS` and `RATE_LIMIT_DOWN_MBPS`.
  - Bump `SCRIPT_VERSION` once.
- Modify: `README.md`
  - Sync the script version displayed to users.
- Create: `tests/vless_reality_legacy_state_migrates_to_instances.sh`
  - Covers schema v1 single-instance state migration to `main.env`.
- Create: `tests/vless_reality_multi_instance_config_generation.sh`
  - Covers multiple REALITY instance files producing multiple VLESS inbounds.
- Create: `tests/vless_reality_rate_limit_prompt_states.sh`
  - Covers blank/up-only/down-only/both-direction rate-limit state persistence.
- Create: `tests/additional_install_vless_adds_reality_instance.sh`
  - Covers choosing installed REALITY from the add-protocol menu creates a new instance instead of skipping.
- Create: `tests/vless_reality_node_info_shows_instances.sh`
  - Covers node information output for every REALITY instance and limit summary.
- Create: `tests/export_client_config_multi_reality_instances.sh`
  - Covers client export contains one outbound per REALITY instance.
- Create: `tests/vless_reality_instance_removal.sh`
  - Covers removing one REALITY instance while preserving the protocol when other instances remain.
- Create: `tests/vless_reality_qos_plan_generation.sh`
  - Covers QoS refresh uses only instances with at least one non-empty rate-limit direction.

## Implementation Notes

- Use `main` as the migrated/default instance ID.
- Keep the default instance inbound tag as `vless-in` to reduce blast radius.
- Use `vless-reality-${INSTANCE_ID}` for non-default instance inbound tags.
- Store empty rate-limit fields as empty env values. Do not persist sentinel strings such as `none` or `unlimited`.
- Treat `RATE_LIMIT_UP_MBPS` and `RATE_LIMIT_DOWN_MBPS` independently; each must be empty or a positive integer.
- Preserve legacy links after migration: same UUID, port, SNI, public key, short id, and node name.
- Defer destructive cleanup of user-owned QoS rules. Only remove rules carrying this script's marker/prefix.

### Task 1: Add REALITY instance migration coverage

**Files:**
- Create: `tests/vless_reality_legacy_state_migrates_to_instances.sh`
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

mkdir -p "${TMP_DIR}/project/protocols" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality
PROTOCOL_STATE_VERSION=1
INSTALLED_SINGBOX_VERSION=1.13.9
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=vless_reality_test-host
PORT=443
UUID=11111111-1111-1111-1111-111111111111
SNI=apple.com
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
EOF

migrate_vless_reality_state_to_instances_if_needed

main_state="${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env"

if [[ ! -f "${main_state}" ]]; then
  printf 'expected migrated main instance state at %s\n' "${main_state}" >&2
  exit 1
fi

grep -Fq 'CONFIG_SCHEMA_VERSION=2' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'DEFAULT_INSTANCE_ID=main' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'INSTANCE_IDS=main' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'REALITY_PRIVATE_KEY=private-key' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'REALITY_PUBLIC_KEY=public-key' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"

grep -Fq 'INSTANCE_ID=main' "${main_state}"
grep -Fq 'NODE_NAME=vless_reality_test-host' "${main_state}"
grep -Fq 'PORT=443' "${main_state}"
grep -Fq 'UUID=11111111-1111-1111-1111-111111111111' "${main_state}"
grep -Fq 'SNI=apple.com' "${main_state}"
grep -Fq 'SHORT_ID_1=aaaaaaaaaaaaaaaa' "${main_state}"
grep -Fq 'SHORT_ID_2=bbbbbbbbbbbbbbbb' "${main_state}"
grep -Eq '^RATE_LIMIT_UP_MBPS=$' "${main_state}"
grep -Eq '^RATE_LIMIT_DOWN_MBPS=$' "${main_state}"

if ! compgen -G "${SB_PROTOCOL_STATE_DIR}/vless-reality.env.bak.*" >/dev/null; then
  printf 'expected legacy vless-reality.env backup to be created\n' >&2
  exit 1
fi
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `bash tests/vless_reality_legacy_state_migrates_to_instances.sh`

Expected: FAIL with `migrate_vless_reality_state_to_instances_if_needed: command not found`.

- [ ] **Step 3: Implement REALITY instance state helpers**

Add these functions near the existing protocol state helpers in `install.sh`:

```bash
vless_reality_instance_dir() {
  printf '%s/vless-reality.d' "${SB_PROTOCOL_STATE_DIR}"
}

validate_vless_reality_instance_id() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

vless_reality_instance_state_file() {
  local instance_id=$1
  validate_vless_reality_instance_id "${instance_id}" || return 1
  printf '%s/%s.env' "$(vless_reality_instance_dir)" "${instance_id}"
}

normalize_csv_list() {
  local value=$1
  value=${value//\"/}
  value=${value//\'/}
  value=${value//\\,/,}
  printf '%s' "${value}"
}

load_vless_reality_protocol_state() {
  local state_file
  state_file=$(protocol_state_file "vless-reality")

  VLESS_REALITY_DEFAULT_INSTANCE_ID="main"
  VLESS_REALITY_INSTANCE_IDS=""
  SB_PRIVATE_KEY=""
  SB_PUBLIC_KEY=""

  [[ -f "${state_file}" ]] || return 0

  # shellcheck disable=SC1090
  source "${state_file}"
  VLESS_REALITY_DEFAULT_INSTANCE_ID="${DEFAULT_INSTANCE_ID:-main}"
  VLESS_REALITY_INSTANCE_IDS=$(normalize_csv_list "${INSTANCE_IDS:-}")
  SB_PRIVATE_KEY="${REALITY_PRIVATE_KEY:-${SB_PRIVATE_KEY:-}}"
  SB_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-${SB_PUBLIC_KEY:-}}"
}

save_vless_reality_protocol_state() {
  local state_file
  state_file=$(protocol_state_file "vless-reality")
  ensure_protocol_state_dir

  {
    write_env_assignment "INSTALLED" "1"
    write_env_assignment "CONFIG_SCHEMA_VERSION" "2"
    write_env_assignment "DEFAULT_INSTANCE_ID" "${VLESS_REALITY_DEFAULT_INSTANCE_ID:-main}"
    write_env_assignment "INSTANCE_IDS" "${VLESS_REALITY_INSTANCE_IDS:-main}"
    write_env_assignment "REALITY_PRIVATE_KEY" "${SB_PRIVATE_KEY}"
    write_env_assignment "REALITY_PUBLIC_KEY" "${SB_PUBLIC_KEY}"
  } > "${state_file}"
}

load_vless_reality_instance_state() {
  local instance_id=$1
  local state_file
  state_file=$(vless_reality_instance_state_file "${instance_id}") || return 1

  SB_VLESS_INSTANCE_ID="${instance_id}"
  SB_NODE_NAME=""
  SB_PORT=""
  SB_UUID=""
  SB_SNI=""
  SB_SHORT_ID_1=""
  SB_SHORT_ID_2=""
  SB_VLESS_RATE_LIMIT_UP_MBPS=""
  SB_VLESS_RATE_LIMIT_DOWN_MBPS=""

  [[ -f "${state_file}" ]] || return 1

  # shellcheck disable=SC1090
  source "${state_file}"
  SB_VLESS_INSTANCE_ID="${INSTANCE_ID:-${instance_id}}"
  SB_NODE_NAME="${NODE_NAME:-}"
  SB_PORT="${PORT:-}"
  SB_UUID="${UUID:-}"
  SB_SNI="${SNI:-}"
  SB_SHORT_ID_1="${SHORT_ID_1:-}"
  SB_SHORT_ID_2="${SHORT_ID_2:-}"
  SB_VLESS_RATE_LIMIT_UP_MBPS="${RATE_LIMIT_UP_MBPS:-}"
  SB_VLESS_RATE_LIMIT_DOWN_MBPS="${RATE_LIMIT_DOWN_MBPS:-}"
}

save_vless_reality_instance_state() {
  local instance_id=${SB_VLESS_INSTANCE_ID:-main}
  local state_file
  validate_vless_reality_instance_id "${instance_id}" || log_error "REALITY 实例 ID 非法: ${instance_id}"
  mkdir -p "$(vless_reality_instance_dir)"
  state_file=$(vless_reality_instance_state_file "${instance_id}") || return 1

  {
    write_env_assignment "INSTANCE_ID" "${instance_id}"
    write_env_assignment "ENABLED" "1"
    write_env_assignment "NODE_NAME" "${SB_NODE_NAME}"
    write_env_assignment "PORT" "${SB_PORT}"
    write_env_assignment "UUID" "${SB_UUID}"
    write_env_assignment "SNI" "${SB_SNI}"
    write_env_assignment "SHORT_ID_1" "${SB_SHORT_ID_1}"
    write_env_assignment "SHORT_ID_2" "${SB_SHORT_ID_2}"
    write_env_assignment "RATE_LIMIT_UP_MBPS" "${SB_VLESS_RATE_LIMIT_UP_MBPS:-}"
    write_env_assignment "RATE_LIMIT_DOWN_MBPS" "${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}"
  } > "${state_file}"
}

migrate_vless_reality_state_to_instances_if_needed() {
  local state_file instance_dir main_state backup_state_file
  state_file=$(protocol_state_file "vless-reality")
  instance_dir=$(vless_reality_instance_dir)
  main_state="${instance_dir}/main.env"

  [[ -f "${state_file}" ]] || return 0
  [[ ! -f "${main_state}" ]] || return 0

  # shellcheck disable=SC1090
  source "${state_file}"

  if [[ "${CONFIG_SCHEMA_VERSION:-1}" != "1" || -z "${PORT:-}" || -z "${UUID:-}" ]]; then
    return 0
  fi

  backup_state_file="${state_file}.bak.$(date +%Y%m%d%H%M%S)"
  cp "${state_file}" "${backup_state_file}"

  SB_PRIVATE_KEY="${REALITY_PRIVATE_KEY:-}"
  SB_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-}"
  VLESS_REALITY_DEFAULT_INSTANCE_ID="main"
  VLESS_REALITY_INSTANCE_IDS="main"
  save_vless_reality_protocol_state

  SB_VLESS_INSTANCE_ID="main"
  SB_NODE_NAME="${NODE_NAME:-$(default_node_name_for_protocol "vless+reality")}"
  SB_PORT="${PORT:-443}"
  SB_UUID="${UUID:-}"
  SB_SNI="${SNI:-}"
  SB_SHORT_ID_1="${SHORT_ID_1:-}"
  SB_SHORT_ID_2="${SHORT_ID_2:-}"
  SB_VLESS_RATE_LIMIT_UP_MBPS=""
  SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
  save_vless_reality_instance_state
}
```

- [ ] **Step 4: Wire migration into existing state loading**

Call `migrate_vless_reality_state_to_instances_if_needed` inside `migrate_legacy_single_protocol_state_if_needed` after legacy protocol state creation, and inside `load_protocol_state` before loading `vless-reality`.

- [ ] **Step 5: Run the test and verify it passes**

Run: `bash tests/vless_reality_legacy_state_migrates_to_instances.sh`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add install.sh tests/vless_reality_legacy_state_migrates_to_instances.sh
git commit -m "feat: migrate reality state to instances"
```

### Task 2: Generate multiple REALITY inbounds

**Files:**
- Create: `tests/vless_reality_multi_instance_config_generation.sh`
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

mkdir -p "${TMP_DIR}/project/protocols/vless-reality.d" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "version" ]]; then
  printf 'sing-box version 1.13.9\n'
  exit 0
fi

exit 0
EOF
chmod +x "${TMP_DIR}/bin/sing-box"

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

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality
PROTOCOL_STATE_VERSION=1
INSTALLED_SINGBOX_VERSION=1.13.9
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main,limited-10m
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" <<'EOF'
INSTANCE_ID=main
ENABLED=1
NODE_NAME=main-node
PORT=443
UUID=11111111-1111-1111-1111-111111111111
SNI=apple.com
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/limited-10m.env" <<'EOF'
INSTANCE_ID=limited-10m
ENABLED=1
NODE_NAME=limited-node
PORT=8443
UUID=22222222-2222-2222-2222-222222222222
SNI=www.cloudflare.com
SHORT_ID_1=cccccccccccccccc
SHORT_ID_2=dddddddddddddddd
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=10
EOF

generate_config

jq -e '
  (.inbounds | length) == 2 and
  any(.inbounds[]; .type == "vless" and .tag == "vless-in" and .listen_port == 443 and .users[0].uuid == "11111111-1111-1111-1111-111111111111") and
  any(.inbounds[]; .type == "vless" and .tag == "vless-reality-limited-10m" and .listen_port == 8443 and .users[0].name == "limited-10m" and .tls.server_name == "www.cloudflare.com")
' "${SINGBOX_CONFIG_FILE}" >/dev/null
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `bash tests/vless_reality_multi_instance_config_generation.sh`

Expected: FAIL because only one VLESS inbound is generated or the new helper functions are missing.

- [ ] **Step 3: Implement instance iteration and inbound generation**

Add:

```bash
list_vless_reality_instance_ids() {
  load_vless_reality_protocol_state
  if [[ -n "${VLESS_REALITY_INSTANCE_IDS}" ]]; then
    tr ',' '\n' <<< "${VLESS_REALITY_INSTANCE_IDS}" | sed '/^$/d'
    return 0
  fi

  find "$(vless_reality_instance_dir)" -maxdepth 1 -type f -name '*.env' 2>/dev/null \
    | sed 's|.*/||; s|\.env$||' \
    | sort
}

vless_reality_inbound_tag_for_instance() {
  local instance_id=$1
  if [[ "${instance_id}" == "${VLESS_REALITY_DEFAULT_INSTANCE_ID:-main}" ]]; then
    printf 'vless-in'
  else
    printf 'vless-reality-%s' "${instance_id}"
  fi
}

build_vless_inbound_json_for_instance() {
  local instance_id=$1 tag
  load_vless_reality_protocol_state
  load_vless_reality_instance_state "${instance_id}" || return 1
  ensure_vless_reality_materials
  tag=$(vless_reality_inbound_tag_for_instance "${instance_id}")

  jq -n \
    --arg tag "${tag}" \
    --arg instance_id "${instance_id}" \
    --arg listen "$(stack_inbound_listen_address)" \
    --arg port "${SB_PORT}" \
    --arg uuid "${SB_UUID}" \
    --arg sni "${SB_SNI}" \
    --arg priv_key "${SB_PRIVATE_KEY}" \
    --arg sid1 "${SB_SHORT_ID_1}" \
    --arg sid2 "${SB_SHORT_ID_2}" \
    '{
      "type": "vless",
      "tag": $tag,
      "listen": $listen,
      "listen_port": ($port | tonumber),
      "users": [ { "name": $instance_id, "uuid": $uuid, "flow": "xtls-rprx-vision" } ],
      "tls": {
        "enabled": true,
        "server_name": $sni,
        "reality": {
          "enabled": true,
          "handshake": { "server": $sni, "server_port": 443 },
          "private_key": $priv_key,
          "short_id": [ $sid1, $sid2 ]
        }
      }
    }'
}
```

Change `build_vless_inbound_json` to iterate:

```bash
build_vless_inbound_json() {
  local instance_id
  migrate_vless_reality_state_to_instances_if_needed
  while IFS= read -r instance_id; do
    [[ -z "${instance_id}" ]] && continue
    build_vless_inbound_json_for_instance "${instance_id}"
  done < <(list_vless_reality_instance_ids)
}
```

- [ ] **Step 4: Update route rule generation for all VLESS inbounds**

For `vless-reality`, emit one sniff rule per instance and one direct SNI rule per unique SNI:

```bash
build_vless_reality_route_rules_json() {
  local tmp_rules tmp_snis instance_id inbound_tag
  tmp_rules=$(mktemp)
  tmp_snis=$(mktemp)

  load_vless_reality_protocol_state
  while IFS= read -r instance_id; do
    [[ -z "${instance_id}" ]] && continue
    load_vless_reality_instance_state "${instance_id}" || continue
    inbound_tag=$(vless_reality_inbound_tag_for_instance "${instance_id}")
    jq -n --arg inbound_tag "${inbound_tag}" '{ "inbound": $inbound_tag, "action": "sniff" }' >> "${tmp_rules}"
    [[ -n "${SB_SNI}" ]] && printf '%s\n' "${SB_SNI}" >> "${tmp_snis}"
  done < <(list_vless_reality_instance_ids)

  sort -u "${tmp_snis}" | while IFS= read -r sni; do
    [[ -z "${sni}" ]] && continue
    jq -n --arg sni "${sni}" '{ "domain": [ $sni ], "action": "direct" }' >> "${tmp_rules}"
  done

  jq -s '.' "${tmp_rules}"
  rm -f "${tmp_rules}" "${tmp_snis}"
}
```

Call it from `build_protocol_route_rules` for `vless-reality`.

- [ ] **Step 5: Run the test and verify it passes**

Run: `bash tests/vless_reality_multi_instance_config_generation.sh`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add install.sh tests/vless_reality_multi_instance_config_generation.sh
git commit -m "feat: generate multiple reality inbounds"
```

### Task 3: Persist flexible REALITY rate-limit fields from prompts

**Files:**
- Create: `tests/vless_reality_rate_limit_prompt_states.sh`
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

cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "generate" && "${2:-}" == "reality-keypair" ]]; then
  printf 'PrivateKey: private-key\n'
  printf 'PublicKey: public-key\n'
  exit 0
fi

exit 0
EOF
chmod +x "${TMP_DIR}/bin/sing-box"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

check_port_conflict() { :; }
prompt_reality_sni_install() { SB_SNI="apple.com"; }
prompt_reality_sni_update() { SB_SNI="${SB_SNI:-apple.com}"; }

run_case() {
  local case_name=$1 input=$2 expected_up=$3 expected_down=$4
  rm -rf "${SB_PROTOCOL_STATE_DIR}"
  mkdir -p "${SB_PROTOCOL_STATE_DIR}"

  prompt_vless_reality_install <<< "${input}"
  save_protocol_state "vless-reality"

  state_file="${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env"
  if [[ ! -f "${state_file}" ]]; then
    printf '[%s] expected %s to exist\n' "${case_name}" "${state_file}" >&2
    exit 1
  fi

  if ! grep -Eq "^RATE_LIMIT_UP_MBPS=${expected_up}$" "${state_file}"; then
    printf '[%s] expected up=%s, got:\n%s\n' "${case_name}" "${expected_up}" "$(cat "${state_file}")" >&2
    exit 1
  fi

  if ! grep -Eq "^RATE_LIMIT_DOWN_MBPS=${expected_down}$" "${state_file}"; then
    printf '[%s] expected down=%s, got:\n%s\n' "${case_name}" "${expected_down}" "$(cat "${state_file}")" >&2
    exit 1
  fi
}

run_case "unlimited" $'443\nn\n' "" ""
run_case "down-only" $'443\ny\n\n20\n' "" "20"
run_case "up-only" $'443\ny\n5\n\n' "5" ""
run_case "both" $'443\ny\n5\n20\n' "5" "20"
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `bash tests/vless_reality_rate_limit_prompt_states.sh`

Expected: FAIL because prompts do not save `vless-reality.d/main.env` or rate fields.

- [ ] **Step 3: Add rate-limit validation and prompt helper**

Add:

```bash
validate_optional_positive_integer() {
  local value=$1
  [[ -z "${value}" || "${value}" =~ ^[1-9][0-9]*$ ]]
}

prompt_vless_reality_rate_limit_fields() {
  local in_limit in_up in_down

  SB_VLESS_RATE_LIMIT_UP_MBPS="${SB_VLESS_RATE_LIMIT_UP_MBPS:-}"
  SB_VLESS_RATE_LIMIT_DOWN_MBPS="${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}"

  read -rp "[VLESS + REALITY] 是否配置限速 [y/n] (默认 n): " in_limit
  in_limit=${in_limit:-n}
  if [[ "${in_limit}" != "y" && "${in_limit}" != "Y" ]]; then
    SB_VLESS_RATE_LIMIT_UP_MBPS=""
    SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
    return 0
  fi

  while true; do
    read -rp "[VLESS + REALITY] 上行带宽 Mbps (留空表示上行不限速): " in_up
    in_up=$(trim_whitespace "${in_up}")
    validate_optional_positive_integer "${in_up}" && break
    log_warn "上行带宽必须为空或正整数。"
  done

  while true; do
    read -rp "[VLESS + REALITY] 下行带宽 Mbps (留空表示下行不限速): " in_down
    in_down=$(trim_whitespace "${in_down}")
    validate_optional_positive_integer "${in_down}" && break
    log_warn "下行带宽必须为空或正整数。"
  done

  SB_VLESS_RATE_LIMIT_UP_MBPS="${in_up}"
  SB_VLESS_RATE_LIMIT_DOWN_MBPS="${in_down}"

  if [[ -z "${SB_VLESS_RATE_LIMIT_UP_MBPS}" && -z "${SB_VLESS_RATE_LIMIT_DOWN_MBPS}" ]]; then
    log_warn "上下行均为空，将按不限速保存。"
  fi
}
```

- [ ] **Step 4: Update install state save path**

Change `prompt_vless_reality_install` to set:

```bash
SB_VLESS_INSTANCE_ID="main"
SB_NODE_NAME="$(default_node_name_for_protocol "vless+reality")"
prompt_vless_reality_rate_limit_fields
```

Change `save_vless_reality_state` to save protocol state and current instance state:

```bash
save_vless_reality_state() {
  ensure_vless_reality_materials
  VLESS_REALITY_DEFAULT_INSTANCE_ID="${VLESS_REALITY_DEFAULT_INSTANCE_ID:-main}"
  VLESS_REALITY_INSTANCE_IDS="${VLESS_REALITY_INSTANCE_IDS:-${SB_VLESS_INSTANCE_ID:-main}}"
  save_vless_reality_protocol_state
  save_vless_reality_instance_state
}
```

Avoid recursive persistence in `ensure_vless_reality_materials`: remove the internal call to `save_vless_reality_state`; callers save after prompts/material generation.

- [ ] **Step 5: Run the test and verify it passes**

Run: `bash tests/vless_reality_rate_limit_prompt_states.sh`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add install.sh tests/vless_reality_rate_limit_prompt_states.sh
git commit -m "feat: store reality instance rate limits"
```

### Task 4: Allow additional install to add REALITY instances

**Files:**
- Create: `tests/additional_install_vless_adds_reality_instance.sh`
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

mkdir -p "${TMP_DIR}/project/protocols/vless-reality.d" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "version" ]]; then
  printf 'sing-box version 1.13.9\n'
  exit 0
fi
if [[ "${1:-}" == "generate" && "${2:-}" == "reality-keypair" ]]; then
  printf 'PrivateKey: private-key\n'
  printf 'PublicKey: public-key\n'
  exit 0
fi
exit 0
EOF
chmod +x "${TMP_DIR}/bin/sing-box"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

get_os_info() { :; }
get_arch() { ARCH="amd64"; }
install_dependencies() { :; }
get_latest_version() { :; }
install_binary() { :; }
check_config_valid() { :; }
setup_service() { :; }
open_firewall_port() { :; }
display_status_summary() { :; }
show_post_config_connection_info() { :; }
systemctl() { :; }
check_port_conflict() { :; }
save_warp_route_settings() { :; }
validate_config_file() { return 0; }
refresh_vless_reality_qos_rules() { printf 'qos refreshed\n' > "${TMP_DIR}/qos.called"; }
prompt_reality_sni_install() { SB_SNI="${SB_SNI:-apple.com}"; }

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality
PROTOCOL_STATE_VERSION=1
INSTALLED_SINGBOX_VERSION=1.13.9
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" <<'EOF'
INSTANCE_ID=main
ENABLED=1
NODE_NAME=main-node
PORT=443
UUID=11111111-1111-1111-1111-111111111111
SNI=apple.com
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=
EOF

cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{ "inbounds": [], "route": { "rules": [] } }
EOF

install_protocols_interactive additional <<'EOF'
1
limited-10m
limited-node
8443
y

10
EOF

limited_state="${SB_PROTOCOL_STATE_DIR}/vless-reality.d/limited-10m.env"
if [[ ! -f "${limited_state}" ]]; then
  printf 'expected limited instance state to be created\n' >&2
  exit 1
fi

grep -Fq 'INSTANCE_IDS=main,limited-10m' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'NODE_NAME=limited-node' "${limited_state}"
grep -Fq 'PORT=8443' "${limited_state}"
grep -Eq '^RATE_LIMIT_UP_MBPS=$' "${limited_state}"
grep -Fq 'RATE_LIMIT_DOWN_MBPS=10' "${limited_state}"

jq -e 'any(.inbounds[]; .tag == "vless-reality-limited-10m" and .listen_port == 8443)' "${SINGBOX_CONFIG_FILE}" >/dev/null
test -f "${TMP_DIR}/qos.called"
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `bash tests/additional_install_vless_adds_reality_instance.sh`

Expected: FAIL because installed `vless-reality` is skipped.

- [ ] **Step 3: Add instance append helpers**

Add:

```bash
vless_reality_instance_id_exists() {
  local target=$1 instance_id
  while IFS= read -r instance_id; do
    [[ "${instance_id}" == "${target}" ]] && return 0
  done < <(list_vless_reality_instance_ids)
  return 1
}

append_vless_reality_instance_id() {
  local instance_id=$1 ids=()
  local existing
  while IFS= read -r existing; do
    [[ -n "${existing}" ]] && ids+=("${existing}")
  done < <(list_vless_reality_instance_ids)
  if ! protocol_array_contains "${instance_id}" "${ids[@]}"; then
    ids+=("${instance_id}")
  fi
  VLESS_REALITY_INSTANCE_IDS=$(IFS=,; printf '%s' "${ids[*]}")
}
```

- [ ] **Step 4: Add `prompt_vless_reality_instance_create`**

```bash
prompt_vless_reality_instance_create() {
  local in_id in_node in_port default_id default_sni

  migrate_vless_reality_state_to_instances_if_needed
  load_vless_reality_protocol_state
  default_id="reality-$(date +%H%M%S)"
  while true; do
    read -rp "[VLESS + REALITY] 新实例 ID (默认 ${default_id}): " in_id
    SB_VLESS_INSTANCE_ID=$(trim_whitespace "${in_id:-${default_id}}")
    if ! validate_vless_reality_instance_id "${SB_VLESS_INSTANCE_ID}"; then
      log_warn "实例 ID 只能包含小写字母、数字和短横线。"
      continue
    fi
    if vless_reality_instance_id_exists "${SB_VLESS_INSTANCE_ID}"; then
      log_warn "实例 ID 已存在: ${SB_VLESS_INSTANCE_ID}"
      continue
    fi
    break
  done

  read -rp "[VLESS + REALITY] 节点名称 (默认 ${SB_VLESS_INSTANCE_ID}): " in_node
  SB_NODE_NAME=$(trim_whitespace "${in_node:-${SB_VLESS_INSTANCE_ID}}")

  while true; do
    read -rp "[VLESS + REALITY] 端口: " in_port
    SB_PORT=$(trim_whitespace "${in_port}")
    [[ -n "${SB_PORT}" ]] || { log_warn "端口不能为空。"; continue; }
    check_port_conflict "${SB_PORT}"
    break
  done

  default_sni=""
  if load_vless_reality_instance_state "${VLESS_REALITY_DEFAULT_INSTANCE_ID:-main}" 2>/dev/null; then
    default_sni="${SB_SNI}"
  fi
  SB_SNI="${default_sni}"
  prompt_reality_sni_install

  SB_UUID=""
  SB_SHORT_ID_1=""
  SB_SHORT_ID_2=""
  prompt_vless_reality_rate_limit_fields
  ensure_vless_reality_materials
  append_vless_reality_instance_id "${SB_VLESS_INSTANCE_ID}"
  save_vless_reality_protocol_state
  save_vless_reality_instance_state
}
```

- [ ] **Step 5: Update additional install selection**

In `prompt_protocol_install_selection`, when `protocol == vless-reality` and it is already installed in additional mode, add it to `selected_protocols` instead of skipping, and show it as `新增 VLESS + REALITY 节点`.

In `install_protocols_interactive additional`, if selected protocol is installed `vless-reality`, call `prompt_vless_reality_instance_create` and do not append duplicate protocol to `installed_protocols`.

- [ ] **Step 6: Run the test and verify it passes**

Run: `bash tests/additional_install_vless_adds_reality_instance.sh`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add install.sh tests/additional_install_vless_adds_reality_instance.sh
git commit -m "feat: add reality instances from install menu"
```

### Task 5: Show and export all REALITY instances

**Files:**
- Create: `tests/vless_reality_node_info_shows_instances.sh`
- Create: `tests/export_client_config_multi_reality_instances.sh`
- Modify: `install.sh`

- [ ] **Step 1: Write node info failing test**

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

mkdir -p "${TMP_DIR}/project/protocols/vless-reality.d" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

get_public_ip() { printf '203.0.113.10\n'; }
qrencode() { printf 'qr:%s\n' "$*"; }

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality
PROTOCOL_STATE_VERSION=1
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main,limited-10m
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" <<'EOF'
INSTANCE_ID=main
ENABLED=1
NODE_NAME=main-node
PORT=443
UUID=11111111-1111-1111-1111-111111111111
SNI=apple.com
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/limited-10m.env" <<'EOF'
INSTANCE_ID=limited-10m
ENABLED=1
NODE_NAME=limited-node
PORT=8443
UUID=22222222-2222-2222-2222-222222222222
SNI=www.cloudflare.com
SHORT_ID_1=cccccccccccccccc
SHORT_ID_2=dddddddddddddddd
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=10
EOF

output=$(show_all_connection_details "link")

grep -Fq 'main | 443 | 不限速' <<< "${output}"
grep -Fq 'limited-10m | 8443 | 上行不限速 / 下行 10 Mbps' <<< "${output}"
grep -Fq 'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443' <<< "${output}"
grep -Fq 'vless://22222222-2222-2222-2222-222222222222@203.0.113.10:8443' <<< "${output}"
```

- [ ] **Step 2: Write client export failing test**

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

mkdir -p "${TMP_DIR}/project/protocols/vless-reality.d" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash

exit 0
EOF
chmod +x "${TMP_DIR}/bin/sing-box"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

get_public_ip() { printf '203.0.113.10\n'; }

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality
PROTOCOL_STATE_VERSION=1
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main,limited-10m
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" <<'EOF'
INSTANCE_ID=main
ENABLED=1
NODE_NAME=main-node
PORT=443
UUID=11111111-1111-1111-1111-111111111111
SNI=apple.com
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/limited-10m.env" <<'EOF'
INSTANCE_ID=limited-10m
ENABLED=1
NODE_NAME=limited-node
PORT=8443
UUID=22222222-2222-2222-2222-222222222222
SNI=www.cloudflare.com
SHORT_ID_1=cccccccccccccccc
SHORT_ID_2=dddddddddddddddd
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=10
EOF

build_singbox_client_config >/dev/null

client_file="${SB_PROJECT_DIR}/client/sing-box-client.json"
jq -e '
  [.outbounds[] | select(.type == "vless")] as $vless |
  ($vless | length) == 2 and
  any($vless[]; .tag == "main-node" and .server_port == 443) and
  any($vless[]; .tag == "limited-node" and .server_port == 8443)
' "${client_file}" >/dev/null
```

- [ ] **Step 3: Run both tests and verify they fail**

Run:

```bash
bash tests/vless_reality_node_info_shows_instances.sh
bash tests/export_client_config_multi_reality_instances.sh
```

Expected: both FAIL because only the loaded/global VLESS state is shown/exported.

- [ ] **Step 4: Add link and summary helpers**

Add:

```bash
vless_reality_rate_limit_summary() {
  local up=${SB_VLESS_RATE_LIMIT_UP_MBPS:-}
  local down=${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}
  if [[ -z "${up}" && -z "${down}" ]]; then
    printf '不限速'
  elif [[ -z "${up}" ]]; then
    printf '上行不限速 / 下行 %s Mbps' "${down}"
  elif [[ -z "${down}" ]]; then
    printf '上行 %s Mbps / 下行不限速' "${up}"
  else
    printf '上行 %s Mbps / 下行 %s Mbps' "${up}" "${down}"
  fi
}

build_vless_link_for_instance() {
  local instance_id=$1 public_ip=$2 address_label=${3:-}
  load_vless_reality_protocol_state
  load_vless_reality_instance_state "${instance_id}" || return 1
  build_vless_link "${public_ip}" "${address_label}"
}
```

- [ ] **Step 5: Update connection info display**

When `show_all_connection_details` reaches `vless-reality`, iterate `list_vless_reality_instance_ids`, load each instance, print:

```bash
echo "${SB_VLESS_INSTANCE_ID} | ${SB_PORT} | $(vless_reality_rate_limit_summary)"
show_connection_details_for_detected_addresses "${mode}"
```

Ensure `show_connection_details_for_detected_addresses` uses the currently loaded instance.

- [ ] **Step 6: Update client export**

Change `build_client_outbound_json_for_protocol "vless-reality"` to emit all instance outbounds. The easiest local change is to add:

```bash
build_client_vless_reality_outbounds_jsonl() {
  local public_ip=$1 instance_id
  while IFS= read -r instance_id; do
    [[ -z "${instance_id}" ]] && continue
    load_vless_reality_protocol_state
    load_vless_reality_instance_state "${instance_id}" || continue
    build_client_vless_reality_outbound "${public_ip}"
  done < <(list_vless_reality_instance_ids)
}
```

Then in `build_singbox_client_config`, special-case `vless-reality` by appending every JSON line returned by this helper and every tag from those outbounds.

- [ ] **Step 7: Run both tests and verify they pass**

Run:

```bash
bash tests/vless_reality_node_info_shows_instances.sh
bash tests/export_client_config_multi_reality_instances.sh
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add install.sh tests/vless_reality_node_info_shows_instances.sh tests/export_client_config_multi_reality_instances.sh
git commit -m "feat: expose all reality instances"
```

### Task 6: Modify and remove individual REALITY instances

**Files:**
- Create: `tests/vless_reality_instance_removal.sh`
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

mkdir -p "${TMP_DIR}/project/protocols/vless-reality.d" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "version" ]]; then
  printf 'sing-box version 1.13.9\n'
  exit 0
fi
exit 0
EOF
chmod +x "${TMP_DIR}/bin/sing-box"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

setup_service() { :; }
open_all_protocol_ports() { :; }
systemctl() { :; }
validate_config_file() { return 0; }
check_config_valid() { :; }
refresh_vless_reality_qos_rules() { printf 'qos refreshed\n' > "${TMP_DIR}/qos.called"; }
register_warp() { :; }
refresh_warp_route_assets() {
  SB_WARP_CUSTOM_DOMAINS_JSON='[]'
  SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON='[]'
  SB_WARP_LOCAL_RULE_SETS_JSON='[]'
  SB_WARP_REMOTE_RULE_SETS_JSON='[]'
  SB_WARP_RULE_SET_TAGS_JSON='[]'
}

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality,hy2
PROTOCOL_STATE_VERSION=1
INSTALLED_SINGBOX_VERSION=1.13.9
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main,limited-10m
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" <<'EOF'
INSTANCE_ID=main
ENABLED=1
NODE_NAME=main-node
PORT=443
UUID=11111111-1111-1111-1111-111111111111
SNI=apple.com
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/limited-10m.env" <<'EOF'
INSTANCE_ID=limited-10m
ENABLED=1
NODE_NAME=limited-node
PORT=8443
UUID=22222222-2222-2222-2222-222222222222
SNI=www.cloudflare.com
SHORT_ID_1=cccccccccccccccc
SHORT_ID_2=dddddddddddddddd
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=10
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/hy2.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=hy2-node
PORT=9443
DOMAIN=hy2.example.com
PASSWORD=hy2-pass
USER_NAME=hy2-user
UP_MBPS=
DOWN_MBPS=
OBFS_ENABLED=n
OBFS_TYPE=
OBFS_PASSWORD=
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

remove_protocol_menu <<'EOF'
1
2
y
EOF

if [[ -f "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/limited-10m.env" ]]; then
  printf 'expected limited instance to be removed\n' >&2
  exit 1
fi

test -f "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env"
grep -Fq 'INSTANCE_IDS=main' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'INSTALLED_PROTOCOLS=vless-reality,hy2' "${SB_PROTOCOL_INDEX_FILE}"
test -f "${TMP_DIR}/qos.called"
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `bash tests/vless_reality_instance_removal.sh`

Expected: FAIL because remove deletes the whole protocol or has no instance submenu.

- [ ] **Step 3: Add instance selection and removal helpers**

```bash
prompt_vless_reality_instance_selection() {
  local instances=() instance_id index choice
  mapfile -t instances < <(list_vless_reality_instance_ids)
  if [[ ${#instances[@]} -eq 0 ]]; then
    log_error "当前未检测到 REALITY 实例。"
  fi

  echo -e "\n${BLUE}--- REALITY 实例 ---${NC}"
  index=1
  for instance_id in "${instances[@]}"; do
    load_vless_reality_instance_state "${instance_id}" || continue
    echo "${index}. ${SB_NODE_NAME} | ${instance_id} | ${SB_PORT} | $(vless_reality_rate_limit_summary)"
    index=$((index + 1))
  done
  echo "0. 返回"
  read -rp "请选择 REALITY 实例: " choice
  [[ "${choice}" == "0" ]] && return 1
  [[ "${choice}" =~ ^[0-9]+$ && "${choice}" -ge 1 && "${choice}" -le ${#instances[@]} ]] || {
    log_warn "无效选项。"
    return 1
  }
  SELECTED_VLESS_INSTANCE_ID="${instances[$((choice - 1))]}"
}

remove_vless_reality_instance_id_from_list() {
  local remove_id=$1 ids=() instance_id
  while IFS= read -r instance_id; do
    [[ -z "${instance_id}" || "${instance_id}" == "${remove_id}" ]] && continue
    ids+=("${instance_id}")
  done < <(list_vless_reality_instance_ids)
  VLESS_REALITY_INSTANCE_IDS=$(IFS=,; printf '%s' "${ids[*]}")
}
```

- [ ] **Step 4: Special-case remove flow for REALITY**

When selected protocol is `vless-reality` and more than one instance exists:

1. Call `prompt_vless_reality_instance_selection`.
2. Confirm removal of selected instance.
3. Move that instance file to `.bak.YYYYMMDDHHMMSS`.
4. Remove instance ID from `INSTANCE_IDS`.
5. If default instance was removed, set default to first remaining instance.
6. Save protocol state.
7. Regenerate config, validate, setup service, refresh QoS, restart.
8. Do not remove `vless-reality` from protocol index.

- [ ] **Step 5: Run the test and verify it passes**

Run: `bash tests/vless_reality_instance_removal.sh`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add install.sh tests/vless_reality_instance_removal.sh
git commit -m "feat: remove individual reality instances"
```

### Task 7: Add QoS refresh planning and hooks

**Files:**
- Create: `tests/vless_reality_qos_plan_generation.sh`
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

mkdir -p "${TMP_DIR}/project/protocols/vless-reality.d" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality
PROTOCOL_STATE_VERSION=1
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main,down-only,up-only,both
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
EOF

write_instance() {
  local id=$1 port=$2 up=$3 down=$4
  cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/${id}.env" <<EOF
INSTANCE_ID=${id}
ENABLED=1
NODE_NAME=${id}
PORT=${port}
UUID=11111111-1111-1111-1111-111111111111
SNI=apple.com
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
RATE_LIMIT_UP_MBPS=${up}
RATE_LIMIT_DOWN_MBPS=${down}
EOF
}

write_instance main 443 "" ""
write_instance down-only 8443 "" 20
write_instance up-only 9443 5 ""
write_instance both 10443 5 20

plan=$(build_vless_reality_qos_plan)

grep -Fq '8443|down||20' <<< "${plan}"
grep -Fq '9443|up|5|' <<< "${plan}"
grep -Fq '10443|both|5|20' <<< "${plan}"

if grep -Fq '443|' <<< "${plan}"; then
  printf 'expected unlimited main instance to be excluded from QoS plan, got:\n%s\n' "${plan}" >&2
  exit 1
fi
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `bash tests/vless_reality_qos_plan_generation.sh`

Expected: FAIL because `build_vless_reality_qos_plan` is missing.

- [ ] **Step 3: Add QoS plan generation**

```bash
build_vless_reality_qos_plan() {
  local instance_id up down direction
  migrate_vless_reality_state_to_instances_if_needed
  while IFS= read -r instance_id; do
    [[ -z "${instance_id}" ]] && continue
    load_vless_reality_instance_state "${instance_id}" || continue
    up="${SB_VLESS_RATE_LIMIT_UP_MBPS:-}"
    down="${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}"
    [[ -z "${up}" && -z "${down}" ]] && continue
    if [[ -n "${up}" && -n "${down}" ]]; then
      direction="both"
    elif [[ -n "${up}" ]]; then
      direction="up"
    else
      direction="down"
    fi
    printf '%s|%s|%s|%s\n' "${SB_PORT}" "${direction}" "${up}" "${down}"
  done < <(list_vless_reality_instance_ids)
}
```

- [ ] **Step 4: Add idempotent QoS refresh hook**

Add a conservative first implementation:

```bash
refresh_vless_reality_qos_rules() {
  local plan
  plan=$(build_vless_reality_qos_plan)
  if [[ -z "${plan}" ]]; then
    log_info "REALITY 未配置限速，跳过 QoS 规则。"
    return 0
  fi

  if ! command -v tc >/dev/null 2>&1; then
    log_warn "未检测到 tc，REALITY 限速规则未应用。"
    return 0
  fi

  log_warn "REALITY 限速计划已生成，但当前版本仅完成规则规划；真实 tc/nftables 应用将在后续任务接入。"
  log_info "${plan}"
}
```

Call `refresh_vless_reality_qos_rules` after successful config validation in install, update, remove, and config generation flows. This task intentionally lands the testable planning layer before applying kernel rules.

- [ ] **Step 5: Run the test and verify it passes**

Run: `bash tests/vless_reality_qos_plan_generation.sh`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add install.sh tests/vless_reality_qos_plan_generation.sh
git commit -m "feat: plan reality qos limits"
```

### Task 8: Version bump, verification, and docs sync

**Files:**
- Modify: `install.sh`
- Modify: `README.md`
- Modify: `docs/superpowers/plans/2026-05-20-reality-multi-instance-rate-limit.md`

- [ ] **Step 1: Bump script version once**

Change both occurrences in `install.sh`:

```bash
# Version: 2026052001
readonly SCRIPT_VERSION="2026052001"
```

Change README version:

```markdown
- 脚本版本：`2026052001`
```

- [ ] **Step 2: Run focused tests**

Run:

```bash
bash tests/vless_reality_legacy_state_migrates_to_instances.sh
bash tests/vless_reality_multi_instance_config_generation.sh
bash tests/vless_reality_rate_limit_prompt_states.sh
bash tests/additional_install_vless_adds_reality_instance.sh
bash tests/vless_reality_node_info_shows_instances.sh
bash tests/export_client_config_multi_reality_instances.sh
bash tests/vless_reality_instance_removal.sh
bash tests/vless_reality_qos_plan_generation.sh
bash tests/version_metadata_is_consistent.sh
```

Expected: all PASS.

- [ ] **Step 3: Run repository verification**

Run: `bash dev/verification/run.sh`

Expected: PASS. If it detects remote verification requirements, let it run the configured remote target from `dev/verification-target.env`.

- [ ] **Step 4: Commit**

```bash
git add install.sh README.md docs/superpowers/plans/2026-05-20-reality-multi-instance-rate-limit.md
git commit -m "chore: bump version for reality rate limits"
```

## Self-Review Checklist

- Spec coverage:
  - Multi-instance state: Tasks 1-2.
  - Existing install compatibility: Tasks 1 and 3.
  - Additional install creates new REALITY instance: Task 4.
  - Flexible up/down rate fields: Tasks 3 and 7.
  - Node display/export/SubMan groundwork: Task 5 covers node display and client export; SubMan should follow the same instance iteration pattern when implementing push changes.
  - Remove/update per instance: Task 6 covers removal; update should use the same instance selection helper added there.
  - Version and verification: Task 8.
- Placeholder scan:
  - The plan contains no `TBD` or empty implementation tasks.
  - QoS real kernel rule application is intentionally staged behind a tested plan layer because applying `tc` safely needs environment-specific validation.
- Type consistency:
  - Instance variables consistently use `SB_VLESS_INSTANCE_ID`, `SB_VLESS_RATE_LIMIT_UP_MBPS`, and `SB_VLESS_RATE_LIMIT_DOWN_MBPS`.
  - Protocol-level variables consistently use `VLESS_REALITY_DEFAULT_INSTANCE_ID` and `VLESS_REALITY_INSTANCE_IDS`.
