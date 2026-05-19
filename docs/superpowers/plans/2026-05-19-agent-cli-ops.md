# Agent CLI Ops Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add machine-readable agent commands for config validation, diagnostics, guarded service restart, and non-interactive SubMan sync.

**Architecture:** Extend the existing `agent_cli()` dispatcher in `install.sh` with focused helper functions that return JSON. Keep interactive functions unchanged and add a non-interactive SubMan sync wrapper that reuses existing payload and HTTP helpers without prompting.

**Tech Stack:** Bash, jq, systemctl, sing-box CLI, existing shell test harness.

---

## File Structure

- Modify `install.sh`: add agent helper functions, dispatch cases, help text, and version bump.
- Add `tests/agent_cli_ops_commands.sh`: focused tests for the new machine-readable commands.
- Modify `README.md`: document the new commands and bump script version.
- Modify `docs/agents/sing-box-vps-agent-runbook.md`: document safe agent usage.

### Task 1: Add Tests For Agent Ops Commands

**Files:**
- Create: `tests/agent_cli_ops_commands.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/agent_cli_ops_commands.sh`:

```bash
#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120

cat > "${TMP_DIR}/bin/sing-box" <<'STUB'
#!/usr/bin/env bash

case "${1:-}" in
  version)
    printf 'sing-box version 1.13.12\n'
    ;;
  check)
    if [[ -f "${SINGBOX_CHECK_FAIL_FILE:-}" ]]; then
      printf 'config invalid\n'
      printf 'bad route\n' >&2
      exit 23
    fi
    printf 'config ok\n'
    exit 0
    ;;
esac
STUB
chmod +x "${TMP_DIR}/bin/sing-box"

cat > "${TMP_DIR}/bin/systemctl" <<'STUB'
#!/usr/bin/env bash

state_file="${SYSTEMCTL_STATE_FILE:?missing state file}"
restart_count_file="${SYSTEMCTL_RESTART_COUNT_FILE:?missing restart count file}"

case "${1:-} ${2:-}" in
  "is-active sing-box")
    cat "${state_file}"
    ;;
  "restart sing-box")
    count=$(cat "${restart_count_file}")
    printf '%s\n' "$((count + 1))" > "${restart_count_file}"
    printf 'active\n' > "${state_file}"
    ;;
  *)
    exit 0
    ;;
esac
STUB
chmod +x "${TMP_DIR}/bin/systemctl"

source_testable_install

mkdir -p "${SB_PROTOCOL_STATE_DIR}"
touch "${SINGBOX_CONFIG_FILE}"
cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF_INDEX'
INSTALLED_PROTOCOLS=vless-reality
PROTOCOL_STATE_VERSION=1
EOF_INDEX

SYSTEMCTL_STATE_FILE="${TMP_DIR}/systemctl.state"
SYSTEMCTL_RESTART_COUNT_FILE="${TMP_DIR}/systemctl.restart.count"
printf 'inactive\n' > "${SYSTEMCTL_STATE_FILE}"
printf '0\n' > "${SYSTEMCTL_RESTART_COUNT_FILE}"
export SYSTEMCTL_STATE_FILE SYSTEMCTL_RESTART_COUNT_FILE

check_json=$(agent_cli check --json)
jq -e '
  .ok == true
  and .exit_code == 0
  and .config_file == env.SINGBOX_CONFIG_FILE
  and (.stdout | contains("config ok"))
' <<< "${check_json}" >/dev/null

SINGBOX_CHECK_FAIL_FILE="${TMP_DIR}/fail-check"
touch "${SINGBOX_CHECK_FAIL_FILE}"
export SINGBOX_CHECK_FAIL_FILE

if fail_json=$(agent_cli check --json); then
  printf 'expected check command to fail when sing-box check fails\n' >&2
  exit 1
fi
jq -e '
  .ok == false
  and .exit_code == 23
  and (.stdout | contains("config invalid"))
  and (.stderr | contains("bad route"))
' <<< "${fail_json}" >/dev/null

doctor_json=$(agent_cli doctor --json)
jq -e '
  .status.service.active_state == "inactive"
  and .diagnostics.config_file_exists == true
  and .diagnostics.protocol_index_exists == true
  and .diagnostics.protocol_state_dir_exists == true
  and .diagnostics.check.ok == false
' <<< "${doctor_json}" >/dev/null

unset SINGBOX_CHECK_FAIL_FILE
rm -f "${TMP_DIR}/fail-check"

if restart_missing_yes_json=$(agent_cli service restart --json); then
  printf 'expected service restart without --yes to fail\n' >&2
  exit 1
fi
jq -e '
  .ok == false
  and .error == "confirmation_required"
' <<< "${restart_missing_yes_json}" >/dev/null

restart_json=$(agent_cli service restart --json --yes)
jq -e '
  .ok == true
  and .action == "service_restart"
  and .check.ok == true
  and .service.before == "inactive"
  and .service.after == "active"
' <<< "${restart_json}" >/dev/null

if [[ "$(cat "${SYSTEMCTL_RESTART_COUNT_FILE}")" != "1" ]]; then
  printf 'expected exactly one restart call, got %s\n' "$(cat "${SYSTEMCTL_RESTART_COUNT_FILE}")" >&2
  exit 1
fi

if subman_json=$(agent_cli subman-sync --json); then
  printf 'expected missing SubMan config to fail non-interactively\n' >&2
  exit 1
fi
jq -e '
  .ok == false
  and .error == "subman_config_missing"
' <<< "${subman_json}" >/dev/null
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/agent_cli_ops_commands.sh`

Expected: FAIL because `agent_cli` does not recognize `check`, `doctor`, `service`, or `subman-sync`.

### Task 2: Implement Agent Ops Commands

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add JSON helpers and dispatcher cases**

In `install.sh`, add helper functions near existing agent helpers:

```bash
agent_json_error() {
  local error=$1
  local message=$2
  jq -n --arg error "${error}" --arg message "${message}" '{ok: false, error: $error, message: $message}'
}

agent_singbox_check_json() {
  local stdout_file stderr_file exit_code
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)

  if "${SINGBOX_BIN_PATH}" check -c "${SINGBOX_CONFIG_FILE}" >"${stdout_file}" 2>"${stderr_file}"; then
    exit_code=0
  else
    exit_code=$?
  fi

  jq -n \
    --arg config_file "${SINGBOX_CONFIG_FILE}" \
    --arg stdout "$(cat "${stdout_file}")" \
    --arg stderr "$(cat "${stderr_file}")" \
    --argjson exit_code "${exit_code}" \
    '{
      ok: ($exit_code == 0),
      exit_code: $exit_code,
      config_file: $config_file,
      stdout: $stdout,
      stderr: $stderr
    }'

  rm -f "${stdout_file}" "${stderr_file}"
  return "${exit_code}"
}

agent_doctor_json() {
  local status_json check_json check_status=0
  status_json=$(agent_status_json)
  check_json=$(agent_singbox_check_json) || check_status=$?

  jq -n \
    --argjson status "${status_json}" \
    --argjson check "${check_json}" \
    --arg config_file "${SINGBOX_CONFIG_FILE}" \
    --arg protocol_index "${SB_PROTOCOL_INDEX_FILE}" \
    --arg protocol_state_dir "${SB_PROTOCOL_STATE_DIR}" \
    --arg service_file "${SINGBOX_SERVICE_FILE}" \
    --argjson check_status "${check_status}" \
    '{
      status: $status,
      diagnostics: {
        config_file_exists: ($config_file | test("^") and (input_filename | not))
      }
    }'
}
```

Then replace the placeholder `agent_doctor_json` body with explicit Bash file tests passed to jq:

```bash
agent_doctor_json() {
  local status_json check_json check_status=0
  local config_exists=false index_exists=false state_dir_exists=false service_file_exists=false

  [[ -f "${SINGBOX_CONFIG_FILE}" ]] && config_exists=true
  [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]] && index_exists=true
  [[ -d "${SB_PROTOCOL_STATE_DIR}" ]] && state_dir_exists=true
  [[ -f "${SINGBOX_SERVICE_FILE}" ]] && service_file_exists=true

  status_json=$(agent_status_json)
  check_json=$(agent_singbox_check_json) || check_status=$?

  jq -n \
    --argjson status "${status_json}" \
    --argjson check "${check_json}" \
    --argjson config_exists "${config_exists}" \
    --argjson index_exists "${index_exists}" \
    --argjson state_dir_exists "${state_dir_exists}" \
    --argjson service_file_exists "${service_file_exists}" \
    --argjson check_status "${check_status}" \
    '{
      status: $status,
      diagnostics: {
        config_file_exists: $config_exists,
        protocol_index_exists: $index_exists,
        protocol_state_dir_exists: $state_dir_exists,
        service_file_exists: $service_file_exists,
        check_exit_code: $check_status,
        check: $check
      }
    }'
}
```

Add:

```bash
agent_service_cli() {
  local command=${1:-}
  local json_flag=${2:-}
  local yes_flag=${3:-}
  local before_state after_state check_json

  if [[ "${command}" != "restart" ]]; then
    agent_json_error "unknown_service_command" "未知 service 子命令: ${command}"
    return 1
  fi
  agent_require_json_flag "${json_flag}" || return 1
  if [[ "${yes_flag}" != "--yes" ]]; then
    agent_json_error "confirmation_required" "service restart 需要 --yes 确认。"
    return 1
  fi

  before_state=$(systemctl is-active sing-box 2>/dev/null || true)
  if ! check_json=$(agent_singbox_check_json); then
    after_state=$(systemctl is-active sing-box 2>/dev/null || true)
    jq -n \
      --arg action "service_restart" \
      --arg before "${before_state:-unknown}" \
      --arg after "${after_state:-unknown}" \
      --argjson check "${check_json}" \
      '{ok: false, action: $action, skipped: true, reason: "config_check_failed", service: {before: $before, after: $after}, check: $check}'
    return 1
  fi

  systemctl restart sing-box
  after_state=$(systemctl is-active sing-box 2>/dev/null || true)
  jq -n \
    --arg action "service_restart" \
    --arg before "${before_state:-unknown}" \
    --arg after "${after_state:-unknown}" \
    --argjson check "${check_json}" \
    '{ok: true, action: $action, service: {before: $before, after: $after}, check: $check}'
}
```

Add a non-interactive SubMan wrapper:

```bash
agent_subman_sync_json() {
  if [[ ! -f "${SB_SUBMAN_CONFIG_FILE}" ]]; then
    agent_json_error "subman_config_missing" "未找到 SubMan 配置，请先在交互菜单中配置 SubMan。"
    return 1
  fi

  load_subman_config
  if [[ -z "${SB_SUBMAN_API_URL}" || -z "${SB_SUBMAN_API_TOKEN}" ]]; then
    agent_json_error "subman_config_missing" "SubMan API URL 或 Token 为空。"
    return 1
  fi

  agent_push_nodes_to_subman_json
}
```

Implement `agent_push_nodes_to_subman_json` by copying the loop from `push_nodes_to_subman`, but do not call `prompt_subman_config_if_needed`; collect `synced_count`, `skipped_count`, and `failed_count`, and return:

```bash
jq -n \
  --argjson synced "${synced_count}" \
  --argjson skipped "${skipped_count}" \
  --argjson failed "${failed_count}" \
  '{ok: ($synced > 0 and $failed == 0), synced: $synced, skipped: $skipped, failed: $failed}'
```

Update `agent_cli()` cases:

```bash
check)
  agent_require_json_flag "${1:-}" || return 1
  agent_singbox_check_json
  ;;
doctor)
  agent_require_json_flag "${1:-}" || return 1
  agent_doctor_json
  ;;
service)
  agent_service_cli "$@"
  ;;
subman-sync)
  agent_require_json_flag "${1:-}" || return 1
  agent_subman_sync_json
  ;;
```

Update `agent_print_help()` to include the new commands.

- [ ] **Step 2: Run test to verify it passes**

Run: `bash tests/agent_cli_ops_commands.sh`

Expected: PASS.

### Task 3: Document Commands And Bump Version

**Files:**
- Modify: `install.sh`
- Modify: `README.md`
- Modify: `docs/agents/sing-box-vps-agent-runbook.md`

- [ ] **Step 1: Update docs and version metadata**

Set both `install.sh` version comment and `SCRIPT_VERSION` to `2026051902`.

Set README script version to `2026051902`.

Add the new commands to the README Agent 非交互命令 section:

```bash
sbv agent check --json
sbv agent doctor --json
sbv agent service restart --json --yes
sbv agent subman-sync --json
```

Add bullets explaining:

- `check` validates the server config with `sing-box check`.
- `doctor` returns read-only diagnostics and embedded config-check output.
- `service restart` requires `--yes`, validates first, and only restarts on valid config.
- `subman-sync` runs SubMan sync non-interactively and returns structured errors when config is missing.

Update the agent runbook with the same operational safety notes.

- [ ] **Step 2: Run focused tests**

Run:

```bash
bash tests/agent_cli_outputs_machine_readable_node_info.sh
bash tests/agent_cli_ops_commands.sh
bash tests/version_metadata_is_consistent.sh
```

Expected: all PASS.

### Task 4: Full Verification And Commit

**Files:**
- Commit all files changed in Tasks 1-3.

- [ ] **Step 1: Run project verification**

Run: `bash dev/verification/run.sh`

Expected: exits 0 and latest `summary.log` shows `remote_status=success` when remote mode is selected.

- [ ] **Step 2: Check diff hygiene**

Run: `git diff --check`

Expected: no output, exit 0.

- [ ] **Step 3: Commit implementation**

Run:

```bash
git add install.sh README.md docs/agents/sing-box-vps-agent-runbook.md tests/agent_cli_ops_commands.sh docs/superpowers/plans/2026-05-19-agent-cli-ops.md
git commit -m "feat: add agent ops cli commands"
```
