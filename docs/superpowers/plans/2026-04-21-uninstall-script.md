# 独立卸载脚本 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为项目新增独立 `uninstall.sh`，默认支持彻底删除，并让菜单卸载与独立卸载共享同一套删除逻辑。

**Architecture:** 由 `install.sh` 提供真实的彻底卸载实现与隐藏 CLI 入口，`uninstall.sh` 仅负责参数、模式提示和确认交互。测试分别覆盖删除行为本身和独立脚本的委托行为。

**Tech Stack:** Bash、现有 shell 测试脚本、README 版本元数据约束

---

### Task 1: 先写卸载行为失败测试

**Files:**
- Create: `tests/uninstall_purge_removes_runtime_artifacts.sh`

- [ ] **Step 1: 写失败测试**

```bash
perform_full_uninstall
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash tests/uninstall_purge_removes_runtime_artifacts.sh`
Expected: FAIL with `perform_full_uninstall: command not found`

- [ ] **Step 3: 提交**

```bash
git add tests/uninstall_purge_removes_runtime_artifacts.sh
git commit -m "test: cover purge uninstall behavior"
```

### Task 2: 再写独立入口失败测试

**Files:**
- Create: `tests/uninstall_script_runs_purge_mode.sh`

- [ ] **Step 1: 写失败测试**

```bash
cp "${REPO_ROOT}/uninstall.sh" "${TMP_REPO}/uninstall.sh"
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash tests/uninstall_script_runs_purge_mode.sh`
Expected: FAIL with `cannot stat .../uninstall.sh`

- [ ] **Step 3: 提交**

```bash
git add tests/uninstall_script_runs_purge_mode.sh
git commit -m "test: cover standalone uninstall entrypoint"
```

### Task 3: 实现共享的彻底卸载逻辑

**Files:**
- Modify: `install.sh`
- Test: `tests/uninstall_purge_removes_runtime_artifacts.sh`

- [ ] **Step 1: 写最小实现**

```bash
perform_full_uninstall() {
  log_info "正在彻底卸载 sing-box 环境..."
  systemctl stop sing-box &>/dev/null || true
  systemctl disable sing-box &>/dev/null || true
  rm -f "${SINGBOX_SERVICE_FILE}"
  systemctl daemon-reload
  rm -f "${SINGBOX_BIN_PATH}"
  rm -f "${SBV_BIN_PATH}"
  rm -rf "${SINGBOX_CONFIG_DIR}"
  print_success "sing-box、配置目录和全局命令 sbv 已彻底删除。"
}
```

- [ ] **Step 2: 给菜单卸载接上确认与共享逻辑**

Run: `bash tests/uninstall_purge_removes_runtime_artifacts.sh`
Expected: PASS

- [ ] **Step 3: 提交**

```bash
git add install.sh
git commit -m "feat: add shared purge uninstall flow"
```

### Task 4: 实现独立卸载脚本入口

**Files:**
- Create: `uninstall.sh`
- Modify: `install.sh`
- Test: `tests/uninstall_script_runs_purge_mode.sh`

- [ ] **Step 1: 写最小实现**

```bash
exec bash "${INSTALL_SCRIPT}" --internal-uninstall-purge --yes
```

- [ ] **Step 2: 运行测试确认通过**

Run: `bash tests/uninstall_script_runs_purge_mode.sh`
Expected: PASS

- [ ] **Step 3: 提交**

```bash
git add uninstall.sh install.sh
git commit -m "feat: add standalone uninstall script"
```

### Task 5: 更新文档和版本元数据

**Files:**
- Modify: `install.sh`
- Modify: `README.md`
- Test: `tests/version_metadata_is_consistent.sh`

- [ ] **Step 1: 递增脚本版本并补充 README 卸载命令**

```bash
# Version: 2026042102
readonly SCRIPT_VERSION="2026042102"
```

- [ ] **Step 2: 运行版本测试**

Run: `bash tests/version_metadata_is_consistent.sh`
Expected: PASS

- [ ] **Step 3: 提交**

```bash
git add install.sh README.md
git commit -m "docs: document standalone uninstall script"
```
