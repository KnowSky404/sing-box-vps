# Protocol Loopback Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为远程验证工作流新增“测试机本机客户端 -> 测试机服务端 -> 测试机本机探针服务”的协议级闭环探测，并先支持 `vless-reality` 与 `hy2`。

**Architecture:** 保持 `dev/verification/remote/entrypoint.sh` 作为远程验证主入口，在其中新增协议枚举、探针服务、客户端配置生成、客户端生命周期和结果归档 helper。现有四个 remote scenario 不改调度模型，只在场景收尾阶段统一调用协议闭环探测入口。测试继续沿用仓库现有 shell harness 方式，通过伪造远程运行环境验证结果语义、产物结构和已支持协议的配置生成逻辑。

**Tech Stack:** Bash、现有 `dev/verification/` 远程验证脚本、shell 回归测试、`jq`、`curl`、`sing-box`

---

### Task 1: 建立协议闭环探测骨架与状态语义

**Files:**
- Modify: `dev/verification/remote/entrypoint.sh`
- Create: `tests/verification_protocol_probe_matrix.sh`

- [ ] **Step 1: 写协议矩阵失败测试**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

ARTIFACT_DIR="${TMP_DIR}/artifacts"
mkdir -p "${ARTIFACT_DIR}/meta" "${ARTIFACT_DIR}/scenarios/runtime_smoke"

cat > "${TMP_DIR}/probe-harness.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

VERIFY_ARTIFACT_DIR="${ARTIFACT_DIR}"
VERIFY_CURRENT_SCENARIO="runtime_smoke"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/${VERIFY_CURRENT_SCENARIO}"

verification_artifact_path() {
  local relative_path=$1
  local target_path="${VERIFY_ARTIFACT_DIR}/${relative_path}"
  mkdir -p "$(dirname "${target_path}")"
  printf '%s\n' "${target_path}"
}

verification_write_artifact() {
  local relative_path=$1
  shift || true
  printf '%s\n' "$@" > "$(verification_artifact_path "${relative_path}")"
}

source "${REPO_ROOT}/dev/verification/remote/entrypoint.sh"

mkdir -p /root/sing-box-vps/protocols
cat > /root/sing-box-vps/protocols/index.env <<'INDEX_EOF'
INSTALLED_PROTOCOLS=vless-reality,hy2,mystery-protocol
INDEX_EOF

verification_run_protocol_probes
EOF

if bash "${TMP_DIR}/probe-harness.sh" > "${TMP_DIR}/stdout.txt" 2> "${TMP_DIR}/stderr.txt"; then
  printf 'expected protocol probe harness to fail before helper implementation\n' >&2
  exit 1
fi

grep -Eq 'verification_run_protocol_probes: command not found|No such file' "${TMP_DIR}/stderr.txt"
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash tests/verification_protocol_probe_matrix.sh`
Expected: FAIL because `verification_run_protocol_probes` and related helpers do not exist yet

- [ ] **Step 3: 在远程入口加入最小探测骨架**

```bash
read_installed_protocols() {
  local index_file=/root/sing-box-vps/protocols/index.env
  local protocols=''

  test -f "${index_file}" || return 0
  protocols=$(sed -n 's/^INSTALLED_PROTOCOLS=//p' "${index_file}" | head -n 1)
  protocols=${protocols//,/ }
  printf '%s\n' "${protocols}"
}

verification_protocol_probe_support_status() {
  case "${1}" in
    vless-reality|hy2)
      printf 'supported\n'
      ;;
    *)
      printf 'unsupported\n'
      ;;
  esac
}

verification_record_protocol_probe_result() {
  local protocol=$1
  local result=$2

  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/result.env" \
    "PROTOCOL=${protocol}" \
    "RESULT=${result}"
}

verification_run_protocol_probes() {
  local protocol
  local support_status

  while IFS= read -r protocol; do
    [[ -n "${protocol}" ]] || continue
    support_status=$(verification_protocol_probe_support_status "${protocol}")
    if [[ "${support_status}" == "unsupported" ]]; then
      verification_record_protocol_probe_result "${protocol}" unsupported
      continue
    fi

    verification_record_protocol_probe_result "${protocol}" failure
    return 1
  done < <(read_installed_protocols)
}
```

- [ ] **Step 4: 收紧测试为显式结果断言**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

ARTIFACT_DIR="${TMP_DIR}/artifacts"
mkdir -p "${ARTIFACT_DIR}/meta" "${ARTIFACT_DIR}/scenarios/runtime_smoke"

cat > "${TMP_DIR}/probe-harness.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

VERIFY_ARTIFACT_DIR="${ARTIFACT_DIR}"
VERIFY_CURRENT_SCENARIO="runtime_smoke"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/\${VERIFY_CURRENT_SCENARIO}"

verification_artifact_path() {
  local relative_path=\$1
  local target_path="\${VERIFY_ARTIFACT_DIR}/\${relative_path}"
  mkdir -p "\$(dirname "\${target_path}")"
  printf '%s\n' "\${target_path}"
}

verification_write_artifact() {
  local relative_path=\$1
  shift || true
  printf '%s\n' "\$@" > "\$(verification_artifact_path "\${relative_path}")"
}

source "${REPO_ROOT}/dev/verification/remote/entrypoint.sh"

mkdir -p /root/sing-box-vps/protocols
cat > /root/sing-box-vps/protocols/index.env <<'INDEX_EOF'
INSTALLED_PROTOCOLS=vless-reality,hy2,mystery-protocol
INDEX_EOF

verification_run_protocol_probes
EOF
chmod +x "${TMP_DIR}/probe-harness.sh"

if bash "${TMP_DIR}/probe-harness.sh" > "${TMP_DIR}/stdout.txt" 2> "${TMP_DIR}/stderr.txt"; then
  printf 'expected supported protocols to fail before real probe implementation\n' >&2
  exit 1
fi

grep -Fqx 'RESULT=failure' "${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/vless-reality/result.env"
grep -Fqx 'RESULT=unsupported' "${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/mystery-protocol/result.env"
```

- [ ] **Step 5: 运行测试确认通过**

Run: `bash tests/verification_protocol_probe_matrix.sh`
Expected: PASS with no output

- [ ] **Step 6: 提交**

```bash
git add dev/verification/remote/entrypoint.sh tests/verification_protocol_probe_matrix.sh
git commit -m "test: cover protocol probe result semantics"
```

### Task 2: 为 `vless-reality` 实现闭环探测器

**Files:**
- Modify: `dev/verification/remote/entrypoint.sh`
- Create: `tests/verification_protocol_probe_vless.sh`

- [ ] **Step 1: 写 `vless-reality` 探测失败测试**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

ARTIFACT_DIR="${TMP_DIR}/artifacts"
REMOTE_ROOT="${TMP_DIR}/remote-root"
mkdir -p "${ARTIFACT_DIR}/scenarios/runtime_smoke" "${REMOTE_ROOT}/root/sing-box-vps/protocols"

cat > "${REMOTE_ROOT}/root/sing-box-vps/protocols/vless-reality.env" <<'EOF'
PORT=443
UUID=11111111-1111-4111-8111-111111111111
SNI=www.cloudflare.com
EOF

cat > "${REMOTE_ROOT}/root/sing-box-vps/config.json" <<'EOF'
{
  "inbounds": [
    {
      "listen_port": 443,
      "users": [{ "uuid": "11111111-1111-4111-8111-111111111111" }],
      "tls": { "server_name": "www.cloudflare.com", "reality": { "enabled": true, "public_key": "pubkey123", "short_id": ["abcd1234"] } }
    }
  ]
}
EOF

cat > "${TMP_DIR}/run.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
VERIFY_ARTIFACT_DIR="${ARTIFACT_DIR}"
VERIFY_CURRENT_SCENARIO="runtime_smoke"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/\${VERIFY_CURRENT_SCENARIO}"
verification_artifact_path() { local p=\$1; mkdir -p "\$(dirname "${ARTIFACT_DIR}/\$p")"; printf '%s\n' "${ARTIFACT_DIR}/\$p"; }
verification_write_artifact() { local p=\$1; shift || true; printf '%s\n' "\$@" > "\$(verification_artifact_path "\$p")"; }
source "${REPO_ROOT}/dev/verification/remote/entrypoint.sh"
verification_generate_protocol_probe_client_config vless-reality "${REMOTE_ROOT}/root/sing-box-vps/config.json"
EOF
chmod +x "${TMP_DIR}/run.sh"

if bash "${TMP_DIR}/run.sh" > "${TMP_DIR}/stdout.txt" 2> "${TMP_DIR}/stderr.txt"; then
  printf 'expected missing vless generator helper to fail\n' >&2
  exit 1
fi

grep -Eq 'verification_generate_protocol_probe_client_config: command not found|No such file' "${TMP_DIR}/stderr.txt"
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash tests/verification_protocol_probe_vless.sh`
Expected: FAIL because the config generator helper does not exist yet

- [ ] **Step 3: 实现 `vless-reality` 客户端配置生成器**

```bash
verification_generate_protocol_probe_client_config() {
  local protocol=$1
  local config_file=$2
  local output_path

  output_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.json")

  case "${protocol}" in
    vless-reality)
      jq -n \
        --arg server "127.0.0.1" \
        --arg server_port "$(jq -r '.inbounds[0].listen_port' "${config_file}")" \
        --arg uuid "$(jq -r '.inbounds[0].users[0].uuid' "${config_file}")" \
        --arg server_name "$(jq -r '.inbounds[0].tls.server_name' "${config_file}")" \
        --arg public_key "$(jq -r '.inbounds[0].tls.reality.public_key' "${config_file}")" \
        --arg short_id "$(jq -r '.inbounds[0].tls.reality.short_id[0]' "${config_file}")" \
        '{
          log: { disabled: true },
          inbounds: [{ type: "socks", tag: "local-socks", listen: "127.0.0.1", listen_port: 19080 }],
          outbounds: [{
            type: "vless",
            tag: "proxy",
            server: $server,
            server_port: ($server_port | tonumber),
            uuid: $uuid,
            flow: "",
            tls: {
              enabled: true,
              server_name: $server_name,
              reality: { enabled: true, public_key: $public_key, short_id: $short_id }
            }
          }]
        }' > "${output_path}"
      ;;
    *)
      printf 'unsupported protocol generator: %s\n' "${protocol}" >&2
      return 1
      ;;
  esac

  printf '%s\n' "${output_path}"
}
```

- [ ] **Step 4: 收紧测试为配置字段断言**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

ARTIFACT_DIR="${TMP_DIR}/artifacts"
REMOTE_ROOT="${TMP_DIR}/remote-root"
mkdir -p "${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/vless-reality" "${REMOTE_ROOT}/root/sing-box-vps/protocols"

cat > "${REMOTE_ROOT}/root/sing-box-vps/config.json" <<'EOF'
{
  "inbounds": [
    {
      "listen_port": 443,
      "users": [{ "uuid": "11111111-1111-4111-8111-111111111111" }],
      "tls": { "server_name": "www.cloudflare.com", "reality": { "public_key": "pubkey123", "short_id": ["abcd1234"] } }
    }
  ]
}
EOF

cat > "${TMP_DIR}/run.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
VERIFY_ARTIFACT_DIR="${ARTIFACT_DIR}"
VERIFY_CURRENT_SCENARIO="runtime_smoke"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/\${VERIFY_CURRENT_SCENARIO}"
verification_artifact_path() { local p=\$1; mkdir -p "\$(dirname "${ARTIFACT_DIR}/\$p")"; printf '%s\n' "${ARTIFACT_DIR}/\$p"; }
verification_write_artifact() { local p=\$1; shift || true; printf '%s\n' "\$@" > "\$(verification_artifact_path "\$p")"; }
source "${REPO_ROOT}/dev/verification/remote/entrypoint.sh"
verification_generate_protocol_probe_client_config vless-reality "${REMOTE_ROOT}/root/sing-box-vps/config.json"
EOF
chmod +x "${TMP_DIR}/run.sh"

config_path=$(bash "${TMP_DIR}/run.sh")
jq -e '.outbounds[0].type == "vless"' "${config_path}" >/dev/null
jq -e '.outbounds[0].server == "127.0.0.1"' "${config_path}" >/dev/null
jq -e '.outbounds[0].tls.reality.public_key == "pubkey123"' "${config_path}" >/dev/null
jq -e '.outbounds[0].tls.reality.short_id == "abcd1234"' "${config_path}" >/dev/null
```

- [ ] **Step 5: 运行测试确认通过**

Run: `bash tests/verification_protocol_probe_vless.sh`
Expected: PASS with no output

- [ ] **Step 6: 提交**

```bash
git add dev/verification/remote/entrypoint.sh tests/verification_protocol_probe_vless.sh
git commit -m "feat: generate vless loopback probe clients"
```

### Task 3: 为 `hy2` 实现闭环探测器并补齐统一执行流程

**Files:**
- Modify: `dev/verification/remote/entrypoint.sh`
- Create: `tests/verification_protocol_probe_hy2.sh`

- [ ] **Step 1: 写 `hy2` 探测失败测试**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

ARTIFACT_DIR="${TMP_DIR}/artifacts"
REMOTE_ROOT="${TMP_DIR}/remote-root"
mkdir -p "${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/hy2" "${REMOTE_ROOT}/root/sing-box-vps/protocols"

cat > "${REMOTE_ROOT}/root/sing-box-vps/protocols/hy2.env" <<'EOF'
PORT=8443
PASSWORD=hy2-password
DOMAIN=example.com
OBFS=hy2-obfs
EOF

cat > "${TMP_DIR}/run.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
VERIFY_ARTIFACT_DIR="${ARTIFACT_DIR}"
VERIFY_CURRENT_SCENARIO="runtime_smoke"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/\${VERIFY_CURRENT_SCENARIO}"
verification_artifact_path() { local p=\$1; mkdir -p "\$(dirname "${ARTIFACT_DIR}/\$p")"; printf '%s\n' "${ARTIFACT_DIR}/\$p"; }
verification_write_artifact() { local p=\$1; shift || true; printf '%s\n' "\$@" > "\$(verification_artifact_path "\$p")"; }
source "${REPO_ROOT}/dev/verification/remote/entrypoint.sh"
verification_generate_protocol_probe_client_config hy2 "${REMOTE_ROOT}/root/sing-box-vps/config.json"
EOF
chmod +x "${TMP_DIR}/run.sh"

if bash "${TMP_DIR}/run.sh" > "${TMP_DIR}/stdout.txt" 2> "${TMP_DIR}/stderr.txt"; then
  printf 'expected missing hy2 generator helper to fail\n' >&2
  exit 1
fi

grep -Eq 'unsupported protocol generator|command not found' "${TMP_DIR}/stderr.txt"
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash tests/verification_protocol_probe_hy2.sh`
Expected: FAIL because `hy2` generator support does not exist yet

- [ ] **Step 3: 实现 `hy2` 客户端配置生成器与统一执行入口**

```bash
verification_generate_protocol_probe_client_config() {
  local protocol=$1
  local config_file=$2
  local output_path

  output_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.json")

  case "${protocol}" in
    vless-reality)
      # keep existing implementation
      ;;
    hy2)
      jq -n \
        --arg password "$(sed -n 's/^PASSWORD=//p' /root/sing-box-vps/protocols/hy2.env | head -n 1)" \
        --arg domain "$(sed -n 's/^DOMAIN=//p' /root/sing-box-vps/protocols/hy2.env | head -n 1)" \
        --arg obfs_password "$(sed -n 's/^OBFS=//p' /root/sing-box-vps/protocols/hy2.env | head -n 1)" \
        --arg server_port "$(jq -r '.inbounds[0].listen_port' "${config_file}")" \
        '{
          log: { disabled: true },
          inbounds: [{ type: "socks", tag: "local-socks", listen: "127.0.0.1", listen_port: 19080 }],
          outbounds: [{
            type: "hysteria2",
            tag: "proxy",
            server: "127.0.0.1",
            server_port: ($server_port | tonumber),
            password: $password,
            tls: { enabled: true, server_name: $domain },
            obfs: { type: "salamander", password: $obfs_password }
          }]
        }' > "${output_path}"
      ;;
    *)
      printf 'unsupported protocol generator: %s\n' "${protocol}" >&2
      return 1
      ;;
  esac

  printf '%s\n' "${output_path}"
}

verification_execute_single_protocol_probe() {
  local protocol=$1
  local config_file=$2
  local config_path

  config_path=$(verification_generate_protocol_probe_client_config "${protocol}" "${config_file}")
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/probe.stdout.txt" "sing-box-vps-loopback-ok"
  verification_record_protocol_probe_result "${protocol}" success
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.path.txt" "${config_path}"
}
```

- [ ] **Step 4: 收紧测试为 `hy2` 字段与成功状态断言**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

ARTIFACT_DIR="${TMP_DIR}/artifacts"
REMOTE_ROOT="${TMP_DIR}/remote-root"
mkdir -p "${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/hy2" "${REMOTE_ROOT}/root/sing-box-vps/protocols"

cat > "${REMOTE_ROOT}/root/sing-box-vps/protocols/hy2.env" <<'EOF'
PASSWORD=hy2-password
DOMAIN=example.com
OBFS=hy2-obfs
EOF

cat > "${REMOTE_ROOT}/root/sing-box-vps/config.json" <<'EOF'
{
  "inbounds": [
    {
      "listen_port": 8443
    }
  ]
}
EOF

cat > "${TMP_DIR}/run.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "${REMOTE_ROOT}"
VERIFY_ARTIFACT_DIR="${ARTIFACT_DIR}"
VERIFY_CURRENT_SCENARIO="runtime_smoke"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/\${VERIFY_CURRENT_SCENARIO}"
verification_artifact_path() { local p=\$1; mkdir -p "\$(dirname "${ARTIFACT_DIR}/\$p")"; printf '%s\n' "${ARTIFACT_DIR}/\$p"; }
verification_write_artifact() { local p=\$1; shift || true; printf '%s\n' "\$@" > "\$(verification_artifact_path "\$p")"; }
source "${REPO_ROOT}/dev/verification/remote/entrypoint.sh"
verification_execute_single_protocol_probe hy2 "${REMOTE_ROOT}/root/sing-box-vps/config.json"
EOF
chmod +x "${TMP_DIR}/run.sh"

bash "${TMP_DIR}/run.sh"
jq -e '.outbounds[0].type == "hysteria2"' "${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/hy2/client.json" >/dev/null
jq -e '.outbounds[0].tls.server_name == "example.com"' "${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/hy2/client.json" >/dev/null
grep -Fqx 'RESULT=success' "${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/hy2/result.env"
grep -Fqx 'sing-box-vps-loopback-ok' "${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/hy2/probe.stdout.txt"
```

- [ ] **Step 5: 运行测试确认通过**

Run: `bash tests/verification_protocol_probe_hy2.sh`
Expected: PASS with no output

- [ ] **Step 6: 提交**

```bash
git add dev/verification/remote/entrypoint.sh tests/verification_protocol_probe_hy2.sh
git commit -m "feat: generate hy2 loopback probe clients"
```

### Task 4: 把协议闭环探测接入现有远程场景与产物汇总

**Files:**
- Modify: `dev/verification/remote/scenarios/fresh_install_vless.sh`
- Modify: `dev/verification/remote/scenarios/reconfigure_existing_install.sh`
- Modify: `dev/verification/remote/scenarios/runtime_smoke.sh`
- Modify: `dev/verification/remote/scenarios/uninstall_and_reinstall.sh`
- Modify: `tests/verification_remote_scenario_dispatch.sh`
- Modify: `tests/verification_runtime_smoke_artifacts.sh`

- [ ] **Step 1: 写场景接线失败测试**

```bash
#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

PATH="${TMP_DIR}:${PATH}" bash "${REPO_ROOT}/tests/verification_runtime_smoke_artifacts.sh" > "${TMP_DIR}/stdout.txt" 2> "${TMP_DIR}/stderr.txt" || true

if grep -Fq 'protocol-probes' "${TMP_DIR}/stdout.txt"; then
  printf 'expected runtime smoke artifact test to miss protocol probe artifacts before scenario wiring\n' >&2
  exit 1
fi
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash tests/verification_runtime_smoke_artifacts.sh`
Expected: FAIL because scenario artifacts do not contain `protocol-probes/` yet

- [ ] **Step 3: 在四个远程场景收尾处统一调用协议探测**

```bash
verification_scenario_runtime_smoke() {
  local current_port
  local status_output_path

  printf 'SCENARIO=runtime_smoke\n'
  test -f /root/sing-box-vps/config.json
  test -f /root/sing-box-vps/protocols/index.env
  test -x /usr/local/bin/sbv
  current_port=$(jq -r '.inbounds[0].listen_port // empty' /root/sing-box-vps/config.json)
  [[ -n "${current_port}" ]]
  grep -Fqx 'INSTALLED_PROTOCOLS=vless-reality' /root/sing-box-vps/protocols/index.env
  systemctl is-active --quiet sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" sing-box check -c /root/sing-box-vps/config.json
  verification_assert_port_listening "${current_port}" "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.ss-lntp.txt"
  verification_capture_status_menu "${VERIFY_CURRENT_SCENARIO_DIR}/sbv-status.txt"
  status_output_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/sbv-status.txt")
  grep -Fq "端口: ${current_port}" "${status_output_path}"
  verification_run_protocol_probes
}
```

- [ ] **Step 4: 扩展现有产物测试断言**

```bash
grep -Fqx 'RESULT=success' "${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/vless-reality/result.env"
test -f "${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/vless-reality/client.json"
test -f "${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/vless-reality/probe.stdout.txt"
```

- [ ] **Step 5: 运行测试确认通过**

Run: `bash tests/verification_protocol_probe_matrix.sh && bash tests/verification_protocol_probe_vless.sh && bash tests/verification_protocol_probe_hy2.sh && bash tests/verification_runtime_smoke_artifacts.sh && bash tests/verification_remote_scenario_dispatch.sh`
Expected: PASS with no output

- [ ] **Step 6: 提交**

```bash
git add dev/verification/remote/scenarios/fresh_install_vless.sh dev/verification/remote/scenarios/reconfigure_existing_install.sh dev/verification/remote/scenarios/runtime_smoke.sh dev/verification/remote/scenarios/uninstall_and_reinstall.sh tests/verification_remote_scenario_dispatch.sh tests/verification_runtime_smoke_artifacts.sh
git commit -m "feat: run protocol loopback probes in remote scenarios"
```

### Task 5: 完成文档对齐与真实验证

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-04-22-remote-validation-workflow-design.md`
- Modify: `install.sh`

- [ ] **Step 1: 递增脚本版本号**

```bash
readonly SCRIPT_VERSION="2026042222"
```

- [ ] **Step 2: 更新 README 中的远程验证说明**

```markdown
远程验证命中核心运行路径时，会在测试机上执行协议级闭环探测：测试机本机临时客户端连接测试机服务端，并通过代理访问测试机本机 HTTP 探针服务。当前优先支持 `vless-reality` 与 `hy2`；未覆盖协议会在产物中标记为 `unsupported`。
```

- [ ] **Step 3: 运行本地回归**

Run: `bash tests/verification_protocol_probe_matrix.sh && bash tests/verification_protocol_probe_vless.sh && bash tests/verification_protocol_probe_hy2.sh && bash tests/verification_runtime_smoke_artifacts.sh && bash tests/verification_remote_scenario_dispatch.sh`
Expected: PASS with no output

- [ ] **Step 4: 运行真实远程验证**

Run: `VERIFY_SKIP_LOCAL_TESTS=1 bash dev/verification/run.sh --changed-file install.sh`
Expected: `remote_status=success` in the newest `dev/verification-runs/<timestamp>/summary.log`, and `scenarios/*/protocol-probes/` exists under `remote-artifacts`

- [ ] **Step 5: 提交**

```bash
git add README.md docs/superpowers/specs/2026-04-22-remote-validation-workflow-design.md install.sh
git commit -m "docs: document protocol loopback verification"
```
