# Remove Legacy Entrypoints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove obsolete single-protocol entrypoints so `install.sh` is the only maintained runtime path.

**Architecture:** Treat `install.sh` as the single source of truth, then delete dead entrypoint files and update repository references that still point at the legacy path. Keep runtime behavior unchanged by limiting edits to dead-file removal, metadata/test cleanup, and documentation cleanup.

**Tech Stack:** Bash, ripgrep, existing shell test suite, git

---

### Task 1: Audit legacy entrypoint references

**Files:**
- Modify: `docs/superpowers/plans/2026-04-15-remove-legacy-entrypoints.md`

- [ ] **Step 1: Capture repository references to legacy entrypoints**

```bash
rg -n "main\\.sh|scripts/config_generator\\.sh|scripts/singbox_manager\\.sh|scripts/system_check\\.sh|scripts/uninstaller\\.sh" /root/Clouds/sing-box-vps
```

- [ ] **Step 2: Confirm `install.sh` does not source deleted files**

```bash
rg -n "source .*scripts/|scripts/" /root/Clouds/sing-box-vps/install.sh
```

- [ ] **Step 3: Use the audit results to define the final deletion set**

Deletion target:

```text
main.sh
scripts/config_generator.sh
scripts/singbox_manager.sh
scripts/system_check.sh
scripts/uninstaller.sh
```

- [ ] **Step 4: Commit the audit-backed plan and execution state**

```bash
git add docs/superpowers/plans/2026-04-15-remove-legacy-entrypoints.md
git commit -m "docs: add legacy entrypoint removal plan"
```

### Task 2: Update tests and docs to the single source of truth

**Files:**
- Modify: `AGENTS.md`
- Modify: `GEMINI.md`
- Modify: `tests/version_metadata_is_consistent.sh`
- Modify: `tests/support_version_targets_1_13_7.sh`

- [ ] **Step 1: Rewrite project structure docs to stop naming `main.sh` as the main entrypoint**

```markdown
- `install.sh`: 用户分发的一体化安装与管理脚本主入口。
- `scripts/`: 历史遗留目录，已移除，不再作为运行时入口。
```

- [ ] **Step 2: Rewrite version metadata test to validate only `install.sh`**

```bash
INSTALL_FILE="${REPO_ROOT}/install.sh"
install_script_version=$(sed -n 's/^readonly SCRIPT_VERSION="\\([0-9]\\+\\)"$/\\1/p' "${INSTALL_FILE}" | head -n 1)

if [[ -z "${install_script_version}" ]]; then
  printf 'missing install.sh SCRIPT_VERSION constant\n' >&2
  exit 1
fi

readme_script_version=$(sed -n 's/^- 脚本版本：`\\([0-9]\\+\\)`$/\\1/p' "${README_FILE}" | head -n 1)
if [[ "${install_script_version}" != "${readme_script_version}" ]]; then
  printf 'README and install.sh SCRIPT_VERSION differ: %s vs %s\n' \
    "${readme_script_version}" "${install_script_version}" >&2
  exit 1
fi
```

- [ ] **Step 3: Rewrite support-version test to validate only `install.sh`**

```bash
INSTALL_FILE="${REPO_ROOT}/install.sh"
install_support_version=$(sed -n 's/^readonly SB_SUPPORT_MAX_VERSION="\\([0-9.]*\\)"$/\\1/p' "${INSTALL_FILE}" | head -n 1)

if [[ "${install_support_version}" != "${EXPECTED_VERSION}" ]]; then
  printf 'install.sh SB_SUPPORT_MAX_VERSION expected %s, got %s\n' "${EXPECTED_VERSION}" "${install_support_version}" >&2
  exit 1
fi
```

- [ ] **Step 4: Commit the reference cleanup**

```bash
git add AGENTS.md GEMINI.md tests/version_metadata_is_consistent.sh tests/support_version_targets_1_13_7.sh
git commit -m "test: align metadata checks with install entrypoint"
```

### Task 3: Delete the legacy entrypoint implementation

**Files:**
- Delete: `main.sh`
- Delete: `scripts/config_generator.sh`
- Delete: `scripts/singbox_manager.sh`
- Delete: `scripts/system_check.sh`
- Delete: `scripts/uninstaller.sh`

- [ ] **Step 1: Remove the obsolete top-level entrypoint**

```text
Delete /root/Clouds/sing-box-vps/main.sh
```

- [ ] **Step 2: Remove legacy helper scripts only used by the deleted entrypoint**

```text
Delete /root/Clouds/sing-box-vps/scripts/config_generator.sh
Delete /root/Clouds/sing-box-vps/scripts/singbox_manager.sh
Delete /root/Clouds/sing-box-vps/scripts/system_check.sh
Delete /root/Clouds/sing-box-vps/scripts/uninstaller.sh
```

- [ ] **Step 3: Commit the file removals**

```bash
git add main.sh scripts/config_generator.sh scripts/singbox_manager.sh scripts/system_check.sh scripts/uninstaller.sh
git commit -m "refactor: remove legacy single-protocol entrypoints"
```

### Task 4: Update remaining repository documentation and version metadata

**Files:**
- Modify: `README.md`
- Modify: `install.sh`

- [ ] **Step 1: Remove stale structure language from the README**

```markdown
- **单一真源**：统一以 `install.sh` 作为安装与维护入口，避免历史旧入口与当前实现漂移。
```

- [ ] **Step 2: Update any README sections that imply split runtime entrypoints**

```markdown
脚本会自动：
1. 下载并配置适配的 `sing-box`。
2. 生成并维护多协议配置。
3. 安装 `sbv` 作为后续管理命令。
```

- [ ] **Step 3: Bump `install.sh` script version once for this implementation turn**

```bash
readonly SCRIPT_VERSION="YYYYMMDDNN"
```

- [ ] **Step 4: Commit docs and metadata updates**

```bash
git add README.md install.sh
git commit -m "docs: remove legacy entrypoint references"
```

### Task 5: Verify the single-entrypoint state

**Files:**
- Test: `tests/version_metadata_is_consistent.sh`
- Test: `tests/support_version_targets_1_13_7.sh`

- [ ] **Step 1: Re-run the legacy reference audit and expect no runtime references**

```bash
rg -n "main\\.sh|scripts/config_generator\\.sh|scripts/singbox_manager\\.sh|scripts/system_check\\.sh|scripts/uninstaller\\.sh" /root/Clouds/sing-box-vps
```

Expected:

```text
Only intentional historical references remain in specs/plans or no matches are returned.
```

- [ ] **Step 2: Run the version metadata test**

```bash
bash /root/Clouds/sing-box-vps/tests/version_metadata_is_consistent.sh
```

Expected:

```text
PASS (no output, exit 0)
```

- [ ] **Step 3: Run the support-version test**

```bash
bash /root/Clouds/sing-box-vps/tests/support_version_targets_1_13_7.sh
```

Expected:

```text
PASS (no output, exit 0)
```

- [ ] **Step 4: Review final diff and commit remaining verification-driven adjustments**

```bash
git status --short
git diff --stat
```
