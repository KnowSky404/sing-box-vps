#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
AGENT_DOCS=(
  "${REPO_ROOT}/README.md"
  "${REPO_ROOT}/docs/agents/llms.txt"
  "${REPO_ROOT}/docs/agents/sing-box-vps-agent-runbook.md"
  "${REPO_ROOT}/skills/sing-box-vps-operator/SKILL.md"
)

for doc in "${AGENT_DOCS[@]}"; do
  grep -Fq 'sbv agent capabilities --json' "${doc}"
  grep -Fq 'sbv agent upgrade-check --json 1.14.0' "${doc}"
  grep -Fq 'sbv agent upgrade --json 1.14.0 --yes' "${doc}"
  grep -Fq '/root/sing-box-vps-backups/' "${doc}"
done

UPGRADE_DOC="${REPO_ROOT}/docs/agents/sing-box-1.13-to-1.14-upgrade-test.md"
for feature in \
  'VLESS + REALITY' \
  'Mixed HTTP/SOCKS' \
  'Hysteria2' \
  'NaiveProxy' \
  'AnyTLS' \
  'REALITY 多实例' \
  'REALITY QoS' \
  'Warp' \
  '入站/出站栈' \
  'BBR' \
  '媒体检测' \
  '接管/修复' \
  '客户端导出' \
  'SubMan 同步' \
  '服务 start/stop/restart' \
  'sing-box 升级' \
  '卸载'; do
  grep -Fq "${feature}" "${UPGRADE_DOC}"
done

grep -Fq 'target_binary_validation.performed=false' "${UPGRADE_DOC}"
grep -Fq 'blockers=[]' "${UPGRADE_DOC}"
grep -Fq 'error=rollback_failed' "${UPGRADE_DOC}"
grep -Fq 'manual_intervention_required=true' "${UPGRADE_DOC}"
grep -Fq 'inline `tls.acme`' "${UPGRADE_DOC}"
grep -Fq '`download_detour`' "${UPGRADE_DOC}"

LLMS_DOC="${REPO_ROOT}/docs/agents/llms.txt"
grep -Fq 'transaction.result_persisted=true' "${LLMS_DOC}"
grep -Fq 'transaction.status=not_attempted' "${LLMS_DOC}"
grep -Fq 'transaction.reason=already_installed' "${LLMS_DOC}"

printf '%s\n' 'agent documentation capability coverage passed'
