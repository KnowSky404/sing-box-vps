# Existing Instance Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add install-time instance detection that classifies environments as fresh, healthy, or incomplete, and supports explicit takeover of incomplete instances.

**Architecture:** `install.sh` gains a small detection layer ahead of the current install/update entrypoint. Detection summarizes runtime artifacts and state-cache health, then either reuses the current update flow or routes the user into a takeover/full-install choice. Takeover treats `config.json` as the source of truth, rebuilds state cache from it, restores missing runtime components, validates the config, and only then returns to normal management flow.

**Tech Stack:** Bash, existing shell-based test suite, `jq`, `systemctl`, sing-box CLI

---

### Task 1: Add detection-menu regression coverage

**Files:**
- Create: `tests/install_detects_incomplete_instance_and_prompts_takeover.sh`
- Modify: `tests/menu_test_helper.sh`
- Test: `tests/install_detects_incomplete_instance_and_prompts_takeover.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "${REPO_ROOT}/tests/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

mkdir -p "${TMP_DIR}/project"
touch "${TMP_DIR}/bin/sing-box"
touch "${TMP_DIR}/project/config.json"

SINGBOX_BIN_PATH="${TMP_DIR}/bin/sing-box"
SINGBOX_CONFIG_FILE="${TMP_DIR}/project/config.json"
SINGBOX_SERVICE_FILE="${TMP_DIR}/sing-box.service"
SB_PROTOCOL_INDEX_FILE="${TMP_DIR}/project/protocols/index.env"
SBV_BIN_PATH="${TMP_DIR}/bin/sbv-missing"

output=$(printf '0\n' | install_or_update_singbox 2>&1 || true)
clean_output=$(strip_ansi "${output}")

grep -Fq '检测到残缺的现有实例' <<< "${clean_output}"
grep -Fq '接管现有实例' <<< "${clean_output}"
grep -Fq '按全新安装处理' <<< "${clean_output}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/install_detects_incomplete_instance_and_prompts_takeover.sh`
Expected: FAIL because `install_or_update_singbox` still falls through to the old binary/config-only logic and never prints the incomplete-instance menu.

- [ ] **Step 3: Write minimal implementation**

```bash
detect_existing_instance_state() {
  if [[ -f "${SINGBOX_CONFIG_FILE}" ]]; then
    printf '%s' "incomplete"
    return 0
  fi

  printf '%s' "fresh"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/install_detects_incomplete_instance_and_prompts_takeover.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/install_detects_incomplete_instance_and_prompts_takeover.sh tests/menu_test_helper.sh install.sh
git commit -m "test: cover incomplete instance detection menu"
```

### Task 2: Add takeover state-rebuild coverage

**Files:**
- Create: `tests/install_takeover_rebuilds_protocol_state_from_config.sh`
- Test: `tests/install_takeover_rebuilds_protocol_state_from_config.sh`
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
  -e '/^main "\$@"$/d' \
  -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  -e "s|readonly SINGBOX_BIN_PATH=\"/usr/local/bin/sing-box\"|readonly SINGBOX_BIN_PATH=\"${TMP_DIR}/bin/sing-box\"|" \
  -e "s|readonly SBV_BIN_PATH=\"/usr/local/bin/sbv\"|readonly SBV_BIN_PATH=\"${TMP_DIR}/bin/sbv\"|" \
  -e "s|readonly SINGBOX_SERVICE_FILE=\"/etc/systemd/system/sing-box.service\"|readonly SINGBOX_SERVICE_FILE=\"${TMP_DIR}/sing-box.service\"|" \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/bin"
cat > "${TMP_DIR}/project/config.json" <<'EOF'
{"inbounds":[{"type":"anytls","listen_port":443,"users":[{"name":"demo","password":"secret"}],"tls":{"server_name":"edge.example.com","certificate_path":"/tmp/cert.pem","key_path":"/tmp/key.pem"}}]}
EOF

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
take_over_existing_instance

grep -Fq 'INSTALLED_PROTOCOLS=anytls' "${SB_PROTOCOL_INDEX_FILE}"
grep -Fq 'DOMAIN=edge.example.com' "$(protocol_state_file anytls)"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/install_takeover_rebuilds_protocol_state_from_config.sh`
Expected: FAIL because no takeover helper rebuilds missing index/state from `config.json`.

- [ ] **Step 3: Write minimal implementation**

```bash
rebuild_protocol_state_from_config() {
  migrate_legacy_single_protocol_state_if_needed
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/install_takeover_rebuilds_protocol_state_from_config.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/install_takeover_rebuilds_protocol_state_from_config.sh install.sh
git commit -m "test: cover takeover state rebuild"
```

### Task 3: Add takeover runtime-repair coverage

**Files:**
- Create: `tests/install_takeover_restores_missing_runtime_artifacts.sh`
- Modify: `install.sh`
- Test: `tests/install_takeover_restores_missing_runtime_artifacts.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"
sed \
  -e '/^main "\$@"$/d' \
  -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  -e "s|readonly SINGBOX_BIN_PATH=\"/usr/local/bin/sing-box\"|readonly SINGBOX_BIN_PATH=\"${TMP_DIR}/bin/sing-box\"|" \
  -e "s|readonly SBV_BIN_PATH=\"/usr/local/bin/sbv\"|readonly SBV_BIN_PATH=\"${TMP_DIR}/bin/sbv\"|" \
  -e "s|readonly SINGBOX_SERVICE_FILE=\"/etc/systemd/system/sing-box.service\"|readonly SINGBOX_SERVICE_FILE=\"${TMP_DIR}/sing-box.service\"|" \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/bin" "${TMP_DIR}/stub-bin"
cat > "${TMP_DIR}/project/config.json" <<'EOF'
{"inbounds":[{"type":"mixed","listen_port":1080,"users":[]}]}
EOF

cat > "${TMP_DIR}/stub-bin/curl" <<EOF
#!/usr/bin/env bash
printf '#!/usr/bin/env bash\nexit 0\n' > "\${@: -1}"
EOF
chmod +x "${TMP_DIR}/stub-bin/curl"
export PATH="${TMP_DIR}/stub-bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
take_over_existing_instance

test -x "${SINGBOX_BIN_PATH}"
test -f "${SINGBOX_SERVICE_FILE}"
test -x "${SBV_BIN_PATH}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/install_takeover_restores_missing_runtime_artifacts.sh`
Expected: FAIL because takeover does not yet restore missing binary, service, or `sbv`.

- [ ] **Step 3: Write minimal implementation**

```bash
ensure_takeover_runtime_artifacts() {
  [[ -x "${SINGBOX_BIN_PATH}" ]] || install_binary
  [[ -f "${SINGBOX_SERVICE_FILE}" ]] || setup_service
  [[ -x "${SBV_BIN_PATH}" ]] || ensure_sbv_command_installed
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/install_takeover_restores_missing_runtime_artifacts.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/install_takeover_restores_missing_runtime_artifacts.sh install.sh
git commit -m "test: cover takeover runtime repair"
```

### Task 4: Add invalid-config rejection coverage

**Files:**
- Create: `tests/install_takeover_rejects_invalid_config.sh`
- Modify: `install.sh`
- Test: `tests/install_takeover_rejects_invalid_config.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"
sed \
  -e '/^main "\$@"$/d' \
  -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  -e "s|readonly SINGBOX_BIN_PATH=\"/usr/local/bin/sing-box\"|readonly SINGBOX_BIN_PATH=\"${TMP_DIR}/bin/sing-box\"|" \
  -e "s|readonly SBV_BIN_PATH=\"/usr/local/bin/sbv\"|readonly SBV_BIN_PATH=\"${TMP_DIR}/bin/sbv\"|" \
  -e "s|readonly SINGBOX_SERVICE_FILE=\"/etc/systemd/system/sing-box.service\"|readonly SINGBOX_SERVICE_FILE=\"${TMP_DIR}/sing-box.service\"|" \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/bin"
printf '{invalid json\n' > "${TMP_DIR}/project/config.json"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

if take_over_existing_instance >/tmp/takeover.log 2>&1; then
  printf 'expected takeover to fail for invalid config\n' >&2
  exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/install_takeover_rejects_invalid_config.sh`
Expected: FAIL because takeover either does not exist or does not reject invalid config early enough.

- [ ] **Step 3: Write minimal implementation**

```bash
validate_takeover_config_source() {
  jq -e . "${SINGBOX_CONFIG_FILE}" >/dev/null 2>&1
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/install_takeover_rejects_invalid_config.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/install_takeover_rejects_invalid_config.sh install.sh
git commit -m "test: reject invalid configs during takeover"
```

### Task 5: Implement detection flow and hook it into install/update entrypoint

**Files:**
- Modify: `install.sh`
- Test: `tests/install_detects_incomplete_instance_and_prompts_takeover.sh`

- [ ] **Step 1: Implement detection and prompt helpers**

```bash
detect_existing_instance_state() {
  local has_bin="n" has_service="n" has_config="n" has_index="n" has_state="n" has_sbv="n"

  [[ -x "${SINGBOX_BIN_PATH}" ]] && has_bin="y"
  [[ -f "${SINGBOX_SERVICE_FILE}" ]] && has_service="y"
  [[ -f "${SINGBOX_CONFIG_FILE}" ]] && has_config="y"
  [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]] && has_index="y"
  [[ -x "${SBV_BIN_PATH}" ]] && has_sbv="y"
  if [[ -d "${SB_PROTOCOL_STATE_DIR}" ]] && compgen -G "${SB_PROTOCOL_STATE_DIR}/*.env" >/dev/null; then
    has_state="y"
  fi

  if [[ "${has_config}" == "n" && "${has_bin}" == "n" && "${has_service}" == "n" && "${has_index}" == "n" && "${has_state}" == "n" ]]; then
    printf '%s' "fresh"
    return 0
  fi

  if [[ "${has_config}" == "y" && "${has_bin}" == "y" && "${has_service}" == "y" && "${has_index}" == "y" && "${has_state}" == "y" && "${has_sbv}" == "y" ]]; then
    printf '%s' "healthy"
    return 0
  fi

  printf '%s' "incomplete"
}
```

- [ ] **Step 2: Update `install_or_update_singbox()` to use detection**

Run: `bash tests/install_detects_incomplete_instance_and_prompts_takeover.sh`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat: detect incomplete existing instances"
```

### Task 6: Implement takeover rebuild, runtime repair, and validation

**Files:**
- Modify: `install.sh`
- Test: `tests/install_takeover_rebuilds_protocol_state_from_config.sh`
- Test: `tests/install_takeover_restores_missing_runtime_artifacts.sh`
- Test: `tests/install_takeover_rejects_invalid_config.sh`

- [ ] **Step 1: Implement the takeover helpers**

```bash
take_over_existing_instance() {
  validate_takeover_config_source || log_error "检测到旧实例，但当前配置不可接管。"
  rebuild_protocol_state_from_config
  ensure_takeover_runtime_artifacts
  check_config_valid
  display_takeover_summary
}
```

- [ ] **Step 2: Route the incomplete-instance menu to takeover or fresh install**

Run: `bash tests/install_takeover_rebuilds_protocol_state_from_config.sh`
Expected: PASS

Run: `bash tests/install_takeover_restores_missing_runtime_artifacts.sh`
Expected: PASS

Run: `bash tests/install_takeover_rejects_invalid_config.sh`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat: add existing instance takeover flow"
```

### Task 7: Run focused regression verification and update docs/version metadata if behavior text changes

**Files:**
- Modify: `README.md`
- Modify: `install.sh`
- Test: `tests/version_metadata_is_consistent.sh`
- Test: `tests/initial_exit_installs_sbv_command.sh`
- Test: `tests/install_detects_incomplete_instance_and_prompts_takeover.sh`
- Test: `tests/install_takeover_rebuilds_protocol_state_from_config.sh`
- Test: `tests/install_takeover_restores_missing_runtime_artifacts.sh`
- Test: `tests/install_takeover_rejects_invalid_config.sh`

- [ ] **Step 1: Update user-facing text if the README or menus mention install behavior**

```markdown
- 残缺现场将提示“接管现有实例”或“按全新安装处理”
```

- [ ] **Step 2: Run the focused verification set**

Run: `bash tests/install_detects_incomplete_instance_and_prompts_takeover.sh`
Expected: PASS

Run: `bash tests/install_takeover_rebuilds_protocol_state_from_config.sh`
Expected: PASS

Run: `bash tests/install_takeover_restores_missing_runtime_artifacts.sh`
Expected: PASS

Run: `bash tests/install_takeover_rejects_invalid_config.sh`
Expected: PASS

Run: `bash tests/version_metadata_is_consistent.sh`
Expected: PASS

Run: `bash tests/initial_exit_installs_sbv_command.sh`
Expected: PASS

Run: `bash -n install.sh`
Expected: PASS with no output

- [ ] **Step 3: Commit**

```bash
git add install.sh README.md tests/install_detects_incomplete_instance_and_prompts_takeover.sh tests/install_takeover_rebuilds_protocol_state_from_config.sh tests/install_takeover_restores_missing_runtime_artifacts.sh tests/install_takeover_rejects_invalid_config.sh
git commit -m "feat: support existing instance takeover during install"
```
