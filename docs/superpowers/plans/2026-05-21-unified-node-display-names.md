# Unified Node Display Names Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make node names consistent across connection viewing, client export, SubMan sync, and agent JSON, and prevent duplicate VLESS REALITY bandwidth profiles.

**Architecture:** Add one display-name helper in `install.sh` and route every display/export/sync consumer through it. Keep persisted `SB_NODE_NAME` unchanged as the base name, and add a VLESS REALITY-only duplicate bandwidth check during additional instance creation.

**Tech Stack:** Bash, jq, existing `install.sh` state files, existing remote verification workflow.

---

## File Structure

- Modify: `install.sh`
  - Replace VLESS-only name suffix helpers with protocol-neutral bandwidth and display-name helpers.
  - Update link builders, client export tags, SubMan payload names, and agent JSON names to call the shared helper.
  - Add VLESS REALITY bandwidth tuple duplicate detection in additional instance creation.
  - Increment `SCRIPT_VERSION`.
- Modify: `README.md`
  - Sync displayed script version.
- Create: `tests/unified_node_display_names.sh`
  - Source `install.sh` with `SBV_TEST_MODE=1` and assert display helper, outbound tags, SubMan payload names, and agent JSON names.
- Create: `tests/vless_reality_duplicate_bandwidth.sh`
  - Build temporary REALITY instance state and assert duplicate bandwidth detection.

## Task 1: Add Unified Display Name Helpers

**Files:**
- Modify: `install.sh:631-663`
- Create: `tests/unified_node_display_names.sh`

- [ ] **Step 1: Write the failing display-name test**

Create `tests/unified_node_display_names.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export SBV_TEST_MODE=1
source "${REPO_ROOT}/install.sh"

assert_eq() {
  local actual=$1 expected=$2 message=$3
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "${message}" "${expected}" "${actual}" >&2
    exit 1
  fi
}

SB_NODE_NAME="hk-vps-vless"
SB_PROTOCOL="vless+reality"
SB_VLESS_RATE_LIMIT_UP_MBPS="40"
SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
assert_eq "$(display_node_name_for_protocol "vless-reality" "${SB_NODE_NAME}" "IPv6")" "hk-vps-vless-U40M-v6" "vless upload-only name"

SB_VLESS_RATE_LIMIT_UP_MBPS=""
SB_VLESS_RATE_LIMIT_DOWN_MBPS="100"
assert_eq "$(display_node_name_for_protocol "vless-reality" "${SB_NODE_NAME}" "IPv4")" "hk-vps-vless-D100M-v4" "vless download-only name"

SB_VLESS_RATE_LIMIT_UP_MBPS="40"
SB_VLESS_RATE_LIMIT_DOWN_MBPS="100"
assert_eq "$(display_node_name_for_protocol "vless-reality" "${SB_NODE_NAME}" "")" "hk-vps-vless-U40M-D100M" "vless both-limits name"

SB_NODE_NAME="hk-vps-hy2"
SB_HY2_UP_MBPS="20"
SB_HY2_DOWN_MBPS="80"
assert_eq "$(display_node_name_for_protocol "hy2" "${SB_NODE_NAME}" "IPv4")" "hk-vps-hy2-U20M-D80M-v4" "hy2 bandwidth name"

SB_NODE_NAME="hk-vps-anytls"
assert_eq "$(display_node_name_for_protocol "anytls" "${SB_NODE_NAME}" "IPv6")" "hk-vps-anytls-v6" "anytls stack name"

SB_NODE_NAME="hk-vps-mixed"
assert_eq "$(display_node_name_for_protocol "mixed" "${SB_NODE_NAME}" "地址")" "hk-vps-mixed" "unknown stack omitted"
```

- [ ] **Step 2: Run the test and confirm it fails**

Run:

```bash
bash tests/unified_node_display_names.sh
```

Expected: FAIL with `display_node_name_for_protocol: command not found`.

- [ ] **Step 3: Implement helper functions**

In `install.sh`, replace `vless_reality_rate_limit_name_suffix()` with protocol-neutral helpers while preserving `vless_reality_display_node_name()` as a compatibility wrapper:

```bash
bandwidth_limit_name_suffix() {
  local up_mbps=${1:-}
  local down_mbps=${2:-}
  local parts=()

  [[ -n "${up_mbps}" ]] && parts+=("U${up_mbps}M")
  [[ -n "${down_mbps}" ]] && parts+=("D${down_mbps}M")

  if [[ ${#parts[@]} -eq 0 ]]; then
    printf ''
  else
    local IFS='-'
    printf '%s' "${parts[*]}"
  fi
}

display_node_name_for_protocol() {
  local protocol=$1
  local base_name=${2:-}
  local address_label=${3:-}
  local up_mbps="" down_mbps="" bandwidth_suffix="" name

  protocol=$(normalize_protocol_id "${protocol}" 2>/dev/null || printf '%s' "${protocol}")
  base_name=$(normalize_node_name "${base_name}")
  [[ -z "${base_name}" ]] && return 0

  case "${protocol}" in
    vless-reality)
      up_mbps="${SB_VLESS_RATE_LIMIT_UP_MBPS:-}"
      down_mbps="${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}"
      ;;
    hy2)
      up_mbps="${SB_HY2_UP_MBPS:-}"
      down_mbps="${SB_HY2_DOWN_MBPS:-}"
      ;;
  esac

  bandwidth_suffix=$(bandwidth_limit_name_suffix "${up_mbps}" "${down_mbps}")
  name="${base_name}"
  [[ -n "${bandwidth_suffix}" ]] && name="${name}-${bandwidth_suffix}"
  node_name_for_network_stack "${name}" "${address_label}"
}

vless_reality_display_node_name() {
  local base_name=$1
  local address_label=${2:-}
  display_node_name_for_protocol "vless-reality" "${base_name}" "${address_label}"
}
```

- [ ] **Step 4: Run the display-name test**

Run:

```bash
bash tests/unified_node_display_names.sh
```

Expected: PASS.

- [ ] **Step 5: Commit helper and test**

Run:

```bash
git add install.sh tests/unified_node_display_names.sh
git commit -m "feat: add unified node display names"
```

- [ ] **Step 6: Review the commit**

Run:

```bash
git show --check HEAD
git show --stat --oneline HEAD
```

Expected: no whitespace errors; only `install.sh` and `tests/unified_node_display_names.sh` changed.

## Task 2: Route Consumers Through Unified Names

**Files:**
- Modify: `install.sh:5641-6278`
- Modify: `install.sh:6920-6998`
- Modify: `tests/unified_node_display_names.sh`

- [ ] **Step 1: Extend the failing consumer test**

Append assertions to `tests/unified_node_display_names.sh`:

```bash
SB_PROTOCOL="hy2"
SB_NODE_NAME="hk-vps-hy2"
SB_PORT="8443"
SB_HY2_PASSWORD="secret"
SB_HY2_DOMAIN=""
SB_HY2_OBFS_ENABLED="n"
SB_HY2_OBFS_TYPE=""
SB_HY2_OBFS_PASSWORD=""
SB_HY2_UP_MBPS="20"
SB_HY2_DOWN_MBPS="80"
hy2_link=$(build_hy2_link "203.0.113.10" "IPv4")
[[ "${hy2_link}" == *"#hk-vps-hy2-U20M-D80M-v4" ]] || {
  printf 'FAIL: hy2 link did not use unified display name: %s\n' "${hy2_link}" >&2
  exit 1
}

hy2_outbound=$(build_client_hy2_outbound "203.0.113.10")
assert_eq "$(jq -r '.tag' <<< "${hy2_outbound}")" "hk-vps-hy2-U20M-D80M" "hy2 client tag"

SB_PROTOCOL="anytls"
SB_NODE_NAME="hk-vps-anytls"
SB_PORT="9443"
SB_ANYTLS_PASSWORD="secret"
SB_ANYTLS_DOMAIN=""
anytls_outbound=$(build_client_anytls_outbound "203.0.113.10")
assert_eq "$(jq -r '.tag' <<< "${anytls_outbound}")" "hk-vps-anytls" "anytls client tag"

SUBMAN_NODE_PREFIX="hk-vps"
SB_PROTOCOL="hy2"
SB_NODE_NAME="hk-vps-hy2"
SB_PORT="8443"
SB_HY2_PASSWORD="secret"
SB_HY2_UP_MBPS="20"
SB_HY2_DOWN_MBPS="80"
subman_payload=$(build_subman_node_payload "hy2" "203.0.113.10" "IPv4")
assert_eq "$(jq -r '.name' <<< "${subman_payload}")" "hk-vps-hy2-U20M-D80M-v4" "subman payload name"

agent_links=$(agent_link_json_for_current_protocol "203.0.113.10")
assert_eq "$(jq -r '.name' <<< "${agent_links}")" "hk-vps-hy2-U20M-D80M-v4" "agent link name"
```

- [ ] **Step 2: Run the test and confirm it fails**

Run:

```bash
bash tests/unified_node_display_names.sh
```

Expected: FAIL because Hy2 link/client/SubMan/agent paths still use raw `SB_NODE_NAME`.

- [ ] **Step 3: Update link and SubMan names**

Change:

```bash
node_name=$(node_name_for_network_stack "${SB_NODE_NAME}" "${address_label}")
```

to:

```bash
node_name=$(display_node_name_for_protocol "hy2" "${SB_NODE_NAME}" "${address_label}")
```

In `build_subman_node_payload()`, replace the VLESS-specific branch with:

```bash
node_name=$(trim_whitespace "$(display_node_name_for_protocol "${protocol}" "${SB_NODE_NAME:-}" "${address_label}")")
```

- [ ] **Step 4: Update client outbound tags**

Change `client_outbound_tag_for_protocol()` to:

```bash
client_outbound_tag_for_protocol() {
  local protocol address_label=${2:-}
  protocol=$(normalize_protocol_id "$1")
  if [[ -n "${SB_NODE_NAME:-}" ]]; then
    display_node_name_for_protocol "${protocol}" "${SB_NODE_NAME}" "${address_label}"
    return 0
  fi

  printf '%s' "$(default_node_name_for_protocol "$(state_protocol_to_runtime "${protocol}")")"
}
```

Keep client export address-label-free by default, so exported tags include bandwidth but not `v4`/`v6`.

- [ ] **Step 5: Update agent JSON names**

In `agent_node_summary_json_for_current_protocol()`, initialize:

```bash
node_name=$(display_node_name_for_protocol "${protocol}" "${SB_NODE_NAME}" "")
```

and remove the VLESS-only reassignment.

In `agent_link_json_for_current_protocol()`, initialize after `address_label` detection:

```bash
node_name=$(display_node_name_for_protocol "${protocol}" "${SB_NODE_NAME}" "${address_label}")
```

and remove the VLESS-only reassignment.

- [ ] **Step 6: Run the consumer test**

Run:

```bash
bash tests/unified_node_display_names.sh
```

Expected: PASS.

- [ ] **Step 7: Commit consumer routing**

Run:

```bash
git add install.sh tests/unified_node_display_names.sh
git commit -m "fix: use unified names for node consumers"
```

- [ ] **Step 8: Review the commit**

Run:

```bash
git show --check HEAD
git show --stat --oneline HEAD
```

Expected: no whitespace errors; only intended files changed.

## Task 3: Reject Duplicate VLESS REALITY Bandwidth Profiles

**Files:**
- Modify: `install.sh:880-950`
- Modify: `install.sh:2188-2244`
- Create: `tests/vless_reality_duplicate_bandwidth.sh`

- [ ] **Step 1: Write the failing duplicate-detection test**

Create `tests/vless_reality_duplicate_bandwidth.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "${TMP_ROOT}"' EXIT

export SBV_TEST_MODE=1
export SB_PROJECT_DIR="${TMP_ROOT}/project"
source "${REPO_ROOT}/install.sh"

mkdir -p "$(vless_reality_instance_dir)"
SB_PRIVATE_KEY="priv"
SB_PUBLIC_KEY="pub"
VLESS_REALITY_DEFAULT_INSTANCE_ID="main"
VLESS_REALITY_INSTANCE_IDS="main,limited"
save_vless_reality_protocol_state

SB_VLESS_INSTANCE_ID="main"
SB_NODE_NAME="main-vless"
SB_PORT="443"
SB_UUID="uuid-main"
SB_SNI="www.cloudflare.com"
SB_SHORT_ID_1="aaaa"
SB_SHORT_ID_2="bbbb"
SB_VLESS_RATE_LIMIT_UP_MBPS=""
SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
save_vless_reality_instance_state

SB_VLESS_INSTANCE_ID="limited"
SB_NODE_NAME="limited-vless"
SB_PORT="444"
SB_UUID="uuid-limited"
SB_SNI="www.cloudflare.com"
SB_SHORT_ID_1="cccc"
SB_SHORT_ID_2="dddd"
SB_VLESS_RATE_LIMIT_UP_MBPS="40"
SB_VLESS_RATE_LIMIT_DOWN_MBPS="100"
save_vless_reality_instance_state

if ! vless_reality_bandwidth_profile_exists "" ""; then
  printf 'FAIL: unlimited profile should be detected as duplicate\n' >&2
  exit 1
fi

if ! vless_reality_bandwidth_profile_exists "40" "100"; then
  printf 'FAIL: 40/100 profile should be detected as duplicate\n' >&2
  exit 1
fi

if vless_reality_bandwidth_profile_exists "40" ""; then
  printf 'FAIL: 40/unlimited profile should not be detected as duplicate\n' >&2
  exit 1
fi

if vless_reality_bandwidth_profile_exists "" "100"; then
  printf 'FAIL: unlimited/100 profile should not be detected as duplicate\n' >&2
  exit 1
fi
```

- [ ] **Step 2: Run the test and confirm it fails**

Run:

```bash
bash tests/vless_reality_duplicate_bandwidth.sh
```

Expected: FAIL with `vless_reality_bandwidth_profile_exists: command not found`.

- [ ] **Step 3: Implement duplicate helper**

Add near `vless_reality_instance_id_exists()`:

```bash
vless_reality_bandwidth_profile_exists() {
  local target_up=${1:-}
  local target_down=${2:-}
  local exclude_instance_id=${3:-}
  local instance_id saved_instance_id saved_node_name saved_port saved_uuid saved_sni
  local saved_short_id_1 saved_short_id_2 saved_rate_limit_up saved_rate_limit_down

  saved_instance_id="${SB_VLESS_INSTANCE_ID:-}"
  saved_node_name="${SB_NODE_NAME:-}"
  saved_port="${SB_PORT:-}"
  saved_uuid="${SB_UUID:-}"
  saved_sni="${SB_SNI:-}"
  saved_short_id_1="${SB_SHORT_ID_1:-}"
  saved_short_id_2="${SB_SHORT_ID_2:-}"
  saved_rate_limit_up="${SB_VLESS_RATE_LIMIT_UP_MBPS:-}"
  saved_rate_limit_down="${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}"

  migrate_vless_reality_state_to_instances_if_needed
  while IFS= read -r instance_id; do
    [[ -z "${instance_id}" ]] && continue
    [[ -n "${exclude_instance_id}" && "${instance_id}" == "${exclude_instance_id}" ]] && continue
    load_vless_reality_instance_state "${instance_id}" || continue
    if [[ "${SB_VLESS_RATE_LIMIT_UP_MBPS:-}" == "${target_up}" && "${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}" == "${target_down}" ]]; then
      SB_VLESS_INSTANCE_ID="${saved_instance_id}"
      SB_NODE_NAME="${saved_node_name}"
      SB_PORT="${saved_port}"
      SB_UUID="${saved_uuid}"
      SB_SNI="${saved_sni}"
      SB_SHORT_ID_1="${saved_short_id_1}"
      SB_SHORT_ID_2="${saved_short_id_2}"
      SB_VLESS_RATE_LIMIT_UP_MBPS="${saved_rate_limit_up}"
      SB_VLESS_RATE_LIMIT_DOWN_MBPS="${saved_rate_limit_down}"
      return 0
    fi
  done < <(list_vless_reality_instance_ids)

  SB_VLESS_INSTANCE_ID="${saved_instance_id}"
  SB_NODE_NAME="${saved_node_name}"
  SB_PORT="${saved_port}"
  SB_UUID="${saved_uuid}"
  SB_SNI="${saved_sni}"
  SB_SHORT_ID_1="${saved_short_id_1}"
  SB_SHORT_ID_2="${saved_short_id_2}"
  SB_VLESS_RATE_LIMIT_UP_MBPS="${saved_rate_limit_up}"
  SB_VLESS_RATE_LIMIT_DOWN_MBPS="${saved_rate_limit_down}"
  return 1
}
```

- [ ] **Step 4: Integrate create-time validation**

After `prompt_vless_reality_rate_limit_fields` in `prompt_vless_reality_instance_create()`, add:

```bash
if vless_reality_bandwidth_profile_exists "${SB_VLESS_RATE_LIMIT_UP_MBPS}" "${SB_VLESS_RATE_LIMIT_DOWN_MBPS}" "${SB_VLESS_INSTANCE_ID}"; then
  log_warn "已存在相同类型且带宽配置完全相同的 VLESS + REALITY 节点，已取消创建。"
  return 0
fi
```

- [ ] **Step 5: Run duplicate test**

Run:

```bash
bash tests/vless_reality_duplicate_bandwidth.sh
```

Expected: PASS.

- [ ] **Step 6: Run both focused tests**

Run:

```bash
bash tests/unified_node_display_names.sh
bash tests/vless_reality_duplicate_bandwidth.sh
```

Expected: both PASS.

- [ ] **Step 7: Commit duplicate validation**

Run:

```bash
git add install.sh tests/vless_reality_duplicate_bandwidth.sh
git commit -m "fix: reject duplicate reality bandwidth profiles"
```

- [ ] **Step 8: Review the commit**

Run:

```bash
git show --check HEAD
git show --stat --oneline HEAD
```

Expected: no whitespace errors; only intended files changed.

## Task 4: Version Sync and Full Verification

**Files:**
- Modify: `install.sh:4`
- Modify: `install.sh:11`
- Modify: `README.md:7`

- [ ] **Step 1: Increment script version once**

Change `SCRIPT_VERSION` from `2026052107` to `2026052108` in both top-of-file locations in `install.sh`.

Change README displayed script version from `2026052107` to `2026052108`.

- [ ] **Step 2: Run focused tests**

Run:

```bash
bash tests/unified_node_display_names.sh
bash tests/vless_reality_duplicate_bandwidth.sh
```

Expected: both PASS.

- [ ] **Step 3: Run required verification workflow**

Run:

```bash
bash dev/verification/run.sh
```

Expected: PASS. If the workflow selects remote verification via `dev/verification-target.env`, allow it to run against the configured test target.

- [ ] **Step 4: Commit version sync**

Run:

```bash
git add install.sh README.md
git commit -m "chore: bump script version to 2026052108"
```

- [ ] **Step 5: Review the commit**

Run:

```bash
git show --check HEAD
git show --stat --oneline HEAD
git status --short
```

Expected: no whitespace errors and clean worktree.

## Self-Review

- Spec coverage: the plan covers unified names, all named consumers, duplicate bandwidth validation, version sync, and required verification.
- Placeholder scan: no placeholder markers remain.
- Type consistency: helper names are stable across tasks: `bandwidth_limit_name_suffix`, `display_node_name_for_protocol`, and `vless_reality_bandwidth_profile_exists`.
