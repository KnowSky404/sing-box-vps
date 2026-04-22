# 远程验证工作流 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为仓库新增一个按改动范围自动决定是否执行 SSH 远程验证的本地调度入口，并落地第一版远程场景、产物归档和失败保留策略。

**Architecture:** 以 `dev/verification/` 作为新工作流的实现边界：本地调度脚本负责识别改动、跑现有本地测试、生成结果目录和发起 SSH；远程剧本负责持锁、标准清理、场景执行和产物回传。测试优先覆盖“触发规则、场景映射、产物目录、失败即停”等核心决策，再逐步补齐远程场景。

**Tech Stack:** Bash、现有 shell 测试脚本、SSH、`systemctl`、`journalctl`、`git diff`

---

### Task 1: 建立验证调度骨架和触发规则测试

**Files:**
- Create: `dev/verification/common.sh`
- Create: `dev/verification/run.sh`
- Create: `tests/verification_trigger_rules.sh`
- Create: `tests/verification_artifact_dir_layout.sh`

- [ ] **Step 1: 写触发规则失败测试**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# shellcheck disable=SC1091
source "${REPO_ROOT}/dev/verification/common.sh"

assert_decision() {
  local expected=$1
  shift
  local actual
  actual=$(determine_verification_mode "$@")
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'expected %s, got %s for files: %s\n' "${expected}" "${actual}" "$*" >&2
    exit 1
  fi
}

assert_decision remote install.sh
assert_decision remote utils/common.sh
assert_decision local tests/install_hy2_protocol_creates_state.sh
assert_decision local README.md docs/superpowers/specs/2026-04-22-remote-validation-workflow-design.md
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash tests/verification_trigger_rules.sh`
Expected: FAIL with `No such file or directory` for `dev/verification/common.sh`

- [ ] **Step 3: 写产物目录失败测试**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

# shellcheck disable=SC1091
source "${REPO_ROOT}/dev/verification/common.sh"

RESULT_ROOT="${TMP_DIR}/verification-runs"
run_dir=$(create_run_dir "${RESULT_ROOT}")

case "${run_dir}" in
  "${RESULT_ROOT}"/20????????????) ;;
  *)
    printf 'unexpected run dir: %s\n' "${run_dir}" >&2
    exit 1
    ;;
esac

[[ -d "${run_dir}" ]] || {
  printf 'expected run dir to exist: %s\n' "${run_dir}" >&2
  exit 1
}
```

- [ ] **Step 4: 运行测试确认失败**

Run: `bash tests/verification_artifact_dir_layout.sh`
Expected: FAIL with `No such file or directory` for `dev/verification/common.sh`

- [ ] **Step 5: 写最小实现骨架**

```bash
#!/usr/bin/env bash

set -euo pipefail

readonly VERIFICATION_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly REPO_ROOT=$(cd "${VERIFICATION_ROOT}/../.." && pwd)

determine_verification_mode() {
  local file
  for file in "$@"; do
    case "${file}" in
      install.sh|uninstall.sh|utils/*|configs/*)
        printf 'remote\n'
        return 0
        ;;
    esac
  done

  printf 'local\n'
}

create_run_dir() {
  local root=${1:-"${REPO_ROOT}/dev/verification-runs"}
  local stamp
  stamp=$(date '+%Y%m%d%H%M%S')
  mkdir -p "${root}/${stamp}"
  printf '%s\n' "${root}/${stamp}"
}
```

- [ ] **Step 6: 写本地调度入口骨架**

```bash
#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

main() {
  mapfile -t changed_files < <(git diff --name-only HEAD)
  mode=$(determine_verification_mode "${changed_files[@]}")
  run_dir=$(create_run_dir)
  printf 'mode=%s\nrun_dir=%s\n' "${mode}" "${run_dir}"
}

main "$@"
```

- [ ] **Step 7: 运行测试确认通过**

Run: `bash tests/verification_trigger_rules.sh && bash tests/verification_artifact_dir_layout.sh`
Expected: PASS with no output

- [ ] **Step 8: 提交**

```bash
git add dev/verification/common.sh dev/verification/run.sh tests/verification_trigger_rules.sh tests/verification_artifact_dir_layout.sh
git commit -m "test: cover verification trigger rules"
```

### Task 2: 接入本地测试执行、变更快照和场景映射

**Files:**
- Modify: `dev/verification/common.sh`
- Modify: `dev/verification/run.sh`
- Create: `tests/verification_scenario_mapping.sh`
- Create: `tests/verification_run_writes_changed_files.sh`

- [ ] **Step 1: 写场景映射失败测试**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# shellcheck disable=SC1091
source "${REPO_ROOT}/dev/verification/common.sh"

assert_scenarios() {
  local expected=$1
  shift
  local actual
  actual=$(printf '%s\n' "$(resolve_remote_scenarios "$@")" | paste -sd, -)
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'expected scenarios %s, got %s\n' "${expected}" "${actual}" >&2
    exit 1
  fi
}

assert_scenarios "fresh_install_vless,reconfigure_existing_install,runtime_smoke" install.sh
assert_scenarios "fresh_install_vless,reconfigure_existing_install,runtime_smoke,uninstall_and_reinstall" install.sh tests/uninstall_purge_removes_runtime_artifacts.sh
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash tests/verification_scenario_mapping.sh`
Expected: FAIL with `resolve_remote_scenarios: command not found`

- [ ] **Step 3: 写变更快照失败测试**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/git" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "diff" && "${2:-}" == "--name-only" ]]; then
  printf 'install.sh\nREADME.md\n'
  exit 0
fi
printf 'unexpected git call: %s\n' "$*" >&2
exit 1
EOF
chmod +x "${TMP_DIR}/git"

PATH="${TMP_DIR}:${PATH}" VERIFY_SKIP_LOCAL_TESTS=1 VERIFY_SKIP_REMOTE=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" > "${TMP_DIR}/stdout.txt"

run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout.txt")
grep -Fqx 'install.sh' "${run_dir}/changed-files.txt"
grep -Fqx 'README.md' "${run_dir}/changed-files.txt"
```

- [ ] **Step 4: 运行测试确认失败**

Run: `bash tests/verification_run_writes_changed_files.sh`
Expected: FAIL because `changed-files.txt` is not created yet

- [ ] **Step 5: 扩展公共决策函数**

```bash
resolve_remote_scenarios() {
  local needs_reinstall=0
  local file

  printf '%s\n' fresh_install_vless reconfigure_existing_install runtime_smoke

  for file in "$@"; do
    case "${file}" in
      *uninstall*|*takeover*|*reinstall*|*incomplete*|*residual*|*legacy*)
        needs_reinstall=1
        ;;
    esac
  done

  if [[ "${needs_reinstall}" == "1" ]]; then
    printf '%s\n' uninstall_and_reinstall
  fi
}
```

- [ ] **Step 6: 扩展调度脚本，写入变更文件和场景快照**

```bash
run_local_tests() {
  if [[ "${VERIFY_SKIP_LOCAL_TESTS:-0}" == "1" ]]; then
    return 0
  fi

  for test_file in tests/*.sh; do
    bash "${test_file}"
  done
}

main() {
  mapfile -t changed_files < <(git diff --name-only HEAD)
  mode=$(determine_verification_mode "${changed_files[@]}")
  run_dir=$(create_run_dir)
  printf '%s\n' "${changed_files[@]}" > "${run_dir}/changed-files.txt"
  printf 'mode=%s\nrun_dir=%s\n' "${mode}" "${run_dir}"
  run_local_tests

  if [[ "${mode}" == "remote" ]]; then
    resolve_remote_scenarios "${changed_files[@]}" > "${run_dir}/scenarios.txt"
  fi
}
```

- [ ] **Step 7: 运行测试确认通过**

Run: `bash tests/verification_scenario_mapping.sh && bash tests/verification_run_writes_changed_files.sh`
Expected: PASS with no output

- [ ] **Step 8: 提交**

```bash
git add dev/verification/common.sh dev/verification/run.sh tests/verification_scenario_mapping.sh tests/verification_run_writes_changed_files.sh
git commit -m "feat: snapshot verification inputs"
```

### Task 3: 落地 SSH 前置检查、远程锁和失败即停

**Files:**
- Modify: `dev/verification/common.sh`
- Modify: `dev/verification/run.sh`
- Create: `dev/verification/remote/entrypoint.sh`
- Create: `tests/verification_requires_remote_env.sh`
- Create: `tests/verification_stops_on_remote_failure.sh`

- [ ] **Step 1: 写远程环境变量失败测试**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if VERIFY_SKIP_LOCAL_TESTS=1 bash "${REPO_ROOT}/dev/verification/run.sh" --changed-file install.sh > /tmp/verification.out 2>/tmp/verification.err; then
  printf 'expected remote verification to fail without host configuration\n' >&2
  exit 1
fi

grep -Fq 'VERIFY_REMOTE_HOST is required' /tmp/verification.err
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash tests/verification_requires_remote_env.sh`
Expected: FAIL because `run.sh` does not validate remote env yet

- [ ] **Step 3: 写远程失败即停测试**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/ssh" <<'EOF'
#!/usr/bin/env bash
printf 'simulated remote failure\n' >&2
exit 23
EOF
chmod +x "${TMP_DIR}/ssh"

if PATH="${TMP_DIR}:${PATH}" VERIFY_REMOTE_HOST=test.example VERIFY_REMOTE_USER=root VERIFY_SKIP_LOCAL_TESTS=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" --changed-file install.sh > "${TMP_DIR}/stdout.txt" 2> "${TMP_DIR}/stderr.txt"; then
  printf 'expected dispatcher to fail on remote error\n' >&2
  exit 1
fi

grep -Fq 'simulated remote failure' "${TMP_DIR}/stderr.txt"
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout.txt")
[[ -f "${run_dir}/remote.stderr.log" ]]
```

- [ ] **Step 4: 运行测试确认失败**

Run: `bash tests/verification_stops_on_remote_failure.sh`
Expected: FAIL because `run.sh` does not call `ssh` or persist remote stderr yet

- [ ] **Step 5: 增加远程配置和 SSH 包装函数**

```bash
require_remote_env() {
  : "${VERIFY_REMOTE_HOST:?VERIFY_REMOTE_HOST is required}"
  : "${VERIFY_REMOTE_USER:?VERIFY_REMOTE_USER is required}"
}

run_remote_entrypoint() {
  local run_dir=$1
  ssh "${VERIFY_REMOTE_USER}@${VERIFY_REMOTE_HOST}" 'bash -s' < "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" \
    > "${run_dir}/remote.stdout.log" \
    2> "${run_dir}/remote.stderr.log"
}
```

- [ ] **Step 6: 写远程入口最小实现，包含占用锁**

```bash
#!/usr/bin/env bash

set -euo pipefail

LOCK_DIR=/tmp/sing-box-vps-verification.lock
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  printf 'verification host is busy\n' >&2
  exit 32
fi

cleanup() {
  rmdir "${LOCK_DIR}"
}
trap cleanup EXIT

hostname
```

- [ ] **Step 7: 接入远程执行并保持失败即停**

```bash
if [[ "${mode}" == "remote" ]]; then
  require_remote_env
  resolve_remote_scenarios "${changed_files[@]}" > "${run_dir}/scenarios.txt"
  run_remote_entrypoint "${run_dir}"
fi
```

- [ ] **Step 8: 运行测试确认通过**

Run: `bash tests/verification_requires_remote_env.sh && bash tests/verification_stops_on_remote_failure.sh`
Expected: PASS with no output

- [ ] **Step 9: 提交**

```bash
git add dev/verification/common.sh dev/verification/run.sh dev/verification/remote/entrypoint.sh tests/verification_requires_remote_env.sh tests/verification_stops_on_remote_failure.sh
git commit -m "feat: add remote verification gate"
```

### Task 4: 实现远程运行态冒烟场景和产物拉回

**Files:**
- Modify: `dev/verification/remote/entrypoint.sh`
- Create: `dev/verification/remote/scenarios/runtime_smoke.sh`
- Modify: `dev/verification/run.sh`
- Create: `tests/verification_runtime_smoke_artifacts.sh`

- [ ] **Step 1: 写运行态产物失败测试**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/ssh" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
REMOTE_HOST=test-vps
SCENARIO=runtime_smoke
OUT
exit 0
EOF
chmod +x "${TMP_DIR}/ssh"

PATH="${TMP_DIR}:${PATH}" VERIFY_REMOTE_HOST=test.example VERIFY_REMOTE_USER=root VERIFY_SKIP_LOCAL_TESTS=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" --changed-file install.sh > "${TMP_DIR}/stdout.txt"

run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout.txt")
grep -Fq 'runtime_smoke' "${run_dir}/scenarios.txt"
grep -Fq 'REMOTE_HOST=test-vps' "${run_dir}/remote.stdout.log"
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash tests/verification_runtime_smoke_artifacts.sh`
Expected: FAIL because remote execution does not pass scenario context through the entrypoint yet

- [ ] **Step 3: 写运行态场景脚本**

```bash
#!/usr/bin/env bash

set -euo pipefail

printf 'SCENARIO=runtime_smoke\n'
printf 'SERVICE_ACTIVE=%s\n' "$(systemctl is-active sing-box)"
systemctl status sing-box --no-pager || true
journalctl -u sing-box -n 100 --no-pager || true
sing-box check -c /root/sing-box-vps/config.json
ss -lntp || true
```

- [ ] **Step 4: 扩展远程入口，按场景分发**

```bash
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

for scenario in "$@"; do
  case "${scenario}" in
    runtime_smoke)
      bash "${SCRIPT_DIR}/scenarios/runtime_smoke.sh"
      ;;
    *)
      printf 'unknown scenario: %s\n' "${scenario}" >&2
      exit 2
      ;;
  esac
done
```

- [ ] **Step 5: 调整本地 SSH 调用，显式传入场景参数**

```bash
mapfile -t scenarios < "${run_dir}/scenarios.txt"
ssh "${VERIFY_REMOTE_USER}@${VERIFY_REMOTE_HOST}" 'bash -s -- '"${scenarios[*]}" < "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" \
  > "${run_dir}/remote.stdout.log" \
  2> "${run_dir}/remote.stderr.log"
```

- [ ] **Step 6: 运行测试确认通过**

Run: `bash tests/verification_runtime_smoke_artifacts.sh`
Expected: PASS with no output

- [ ] **Step 7: 提交**

```bash
git add dev/verification/remote/entrypoint.sh dev/verification/remote/scenarios/runtime_smoke.sh dev/verification/run.sh tests/verification_runtime_smoke_artifacts.sh
git commit -m "feat: add runtime smoke verification"
```

### Task 5: 实现首次安装、重配置和卸载重装场景

**Files:**
- Create: `dev/verification/remote/scenarios/fresh_install_vless.sh`
- Create: `dev/verification/remote/scenarios/reconfigure_existing_install.sh`
- Create: `dev/verification/remote/scenarios/uninstall_and_reinstall.sh`
- Modify: `dev/verification/remote/entrypoint.sh`
- Create: `tests/verification_remote_scenario_dispatch.sh`

- [ ] **Step 1: 写场景分发失败测试**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if bash "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" fresh_install_vless > /tmp/verification.out 2>/tmp/verification.err; then
  printf 'expected dispatch to fail before scenario exists\n' >&2
  exit 1
fi

grep -Eq 'No such file|unknown scenario' /tmp/verification.err
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash tests/verification_remote_scenario_dispatch.sh`
Expected: FAIL because the new scenario scripts do not exist yet

- [ ] **Step 3: 写首次安装场景**

```bash
#!/usr/bin/env bash

set -euo pipefail

printf 'SCENARIO=fresh_install_vless\n'
bash /root/Clouds/sing-box-vps/install.sh <<'EOF'

1

EOF
test -f /root/sing-box-vps/config.json
systemctl is-active --quiet sing-box
sing-box check -c /root/sing-box-vps/config.json
```

- [ ] **Step 4: 写重配置场景**

```bash
#!/usr/bin/env bash

set -euo pipefail

printf 'SCENARIO=reconfigure_existing_install\n'
before_port=$(jq -r '.inbounds[0].listen_port // empty' /root/sing-box-vps/config.json)
bash /usr/local/bin/sbv <<'EOF'
3
1
8443
0
EOF
after_port=$(jq -r '.inbounds[0].listen_port // empty' /root/sing-box-vps/config.json)
[[ -n "${before_port}" && "${before_port}" != "${after_port}" ]]
systemctl is-active --quiet sing-box
```

- [ ] **Step 5: 写卸载重装场景**

```bash
#!/usr/bin/env bash

set -euo pipefail

printf 'SCENARIO=uninstall_and_reinstall\n'
bash /root/Clouds/sing-box-vps/uninstall.sh --yes || bash /root/Clouds/sing-box-vps/install.sh --internal-uninstall-purge --yes
test ! -e /root/sing-box-vps/config.json
bash /root/Clouds/sing-box-vps/install.sh <<'EOF'

1

EOF
systemctl is-active --quiet sing-box
```

- [ ] **Step 6: 扩展远程分发**

```bash
case "${scenario}" in
  fresh_install_vless)
    bash "${SCRIPT_DIR}/scenarios/fresh_install_vless.sh"
    ;;
  reconfigure_existing_install)
    bash "${SCRIPT_DIR}/scenarios/reconfigure_existing_install.sh"
    ;;
  uninstall_and_reinstall)
    bash "${SCRIPT_DIR}/scenarios/uninstall_and_reinstall.sh"
    ;;
  runtime_smoke)
    bash "${SCRIPT_DIR}/scenarios/runtime_smoke.sh"
    ;;
esac
```

- [ ] **Step 7: 运行测试确认通过**

Run: `bash tests/verification_remote_scenario_dispatch.sh`
Expected: PASS with no output

- [ ] **Step 8: 提交**

```bash
git add dev/verification/remote/entrypoint.sh dev/verification/remote/scenarios/fresh_install_vless.sh dev/verification/remote/scenarios/reconfigure_existing_install.sh dev/verification/remote/scenarios/uninstall_and_reinstall.sh tests/verification_remote_scenario_dispatch.sh
git commit -m "feat: add remote lifecycle scenarios"
```

### Task 6: 收尾接入、使用说明和端到端验证

**Files:**
- Modify: `README.md`
- Modify: `dev/.gitignore`
- Modify: `docs/superpowers/specs/2026-04-22-remote-validation-workflow-design.md`
- Modify: `dev/verification/run.sh`
- Create: `tests/verification_tests_only_stays_local.sh`

- [ ] **Step 1: 写 tests-only 仍留在本地的回归测试**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

output=$(VERIFY_SKIP_LOCAL_TESTS=1 VERIFY_SKIP_REMOTE=1 bash "${REPO_ROOT}/dev/verification/run.sh" --changed-file tests/install_hy2_protocol_creates_state.sh)

grep -Fq 'mode=local' <<<"${output}"
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash tests/verification_tests_only_stays_local.sh`
Expected: FAIL if `--changed-file` override is not supported yet

- [ ] **Step 3: 增强调度入口和忽略规则**

```bash
if [[ "${1:-}" == "--changed-file" ]]; then
  shift
  changed_files=("$@")
else
  mapfile -t changed_files < <(git diff --name-only HEAD)
fi

if [[ "${VERIFY_SKIP_REMOTE:-0}" == "1" ]]; then
  printf 'remote execution skipped by VERIFY_SKIP_REMOTE\n' >> "${run_dir}/summary.log"
  exit 0
fi
```

- [ ] **Step 4: 更新 README 和忽略规则**

```bash
dev/verification-runs/
```

```markdown
## 开发验证工作流

配置 `VERIFY_REMOTE_HOST` 与 `VERIFY_REMOTE_USER` 后运行：

```bash
bash dev/verification/run.sh
```

核心脚本改动会自动触发远程验证；仅修改 `tests/`、`docs/`、`README.md` 不会占用测试机。
```

- [ ] **Step 5: 运行端到端验证**

Run: `bash tests/verification_tests_only_stays_local.sh && bash tests/verification_trigger_rules.sh && bash tests/verification_scenario_mapping.sh && bash tests/verification_requires_remote_env.sh && bash tests/verification_runtime_smoke_artifacts.sh`
Expected: PASS with no output

- [ ] **Step 6: 提交**

```bash
git add README.md dev/.gitignore docs/superpowers/specs/2026-04-22-remote-validation-workflow-design.md dev/verification/run.sh tests/verification_tests_only_stays_local.sh
git commit -m "docs: document verification workflow"
```

## Self-Review

- Spec coverage:
  - 触发规则由 Task 1、Task 2、Task 6 覆盖。
  - 本地测试先于远程执行、失败即停由 Task 2、Task 3 覆盖。
  - 远程锁、主机校验和 SSH 前置条件由 Task 3 覆盖。
  - `runtime_smoke`、`fresh_install_vless`、`reconfigure_existing_install`、`uninstall_and_reinstall` 四个场景分别由 Task 4、Task 5 覆盖。
  - 产物归档由 Task 1、Task 2、Task 4 覆盖。
  - README 接入说明和忽略规则由 Task 6 覆盖。
- Placeholder scan: 已避免 `TODO`、`适当处理`、`类似 Task N` 这类空泛步骤；每个代码步骤都给出明确片段和命令。
- Type consistency:
  - 本地入口统一使用 `determine_verification_mode`、`resolve_remote_scenarios`、`create_run_dir`、`run_local_tests`、`require_remote_env`、`run_remote_entrypoint`。
  - 远程场景名称统一为 `fresh_install_vless`、`reconfigure_existing_install`、`uninstall_and_reinstall`、`runtime_smoke`。
