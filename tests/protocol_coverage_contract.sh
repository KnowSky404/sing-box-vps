#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${TESTS_DIR}/.." && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

COVERAGE_DOC="${REPO_ROOT}/docs/superpowers/specs/2026-09-06-protocol-coverage.md"
README_DOC="${REPO_ROOT}/README.md"

assert_coverage_row() {
  local row_id=$1
  grep -Fq "| ${row_id} |" "${COVERAGE_DOC}" || {
    printf 'coverage matrix is missing row: %s\n' "${row_id}" >&2
    exit 1
  }
}

# Keep the prose matrix tied to the installer's current release metadata. This
# prevents a later protocol increment from silently leaving an old worktree
# version at the top of the audit document.
grep -Fq '审阅日期：2026-09-22' "${COVERAGE_DOC}"
grep -Fq "当前支持上限：\`v${SB_SUPPORT_MAX_VERSION}\`" "${COVERAGE_DOC}"
grep -Fq "当前交付工作区已提升为 \`SCRIPT_VERSION=${SCRIPT_VERSION}\`" "${COVERAGE_DOC}"
grep -Fq "脚本版本：\`${SCRIPT_VERSION}\`" "${README_DOC}"
grep -Fq "sing-box 适配版本：\`${SB_SUPPORT_MAX_VERSION}\`" "${README_DOC}"

# The matrix is intentionally split by role. Assert every required family and
# auxiliary role appears in the appropriate table instead of relying on a
# single supported=true aggregate.
for row_id in \
  direct-inbound mixed 'vless-reality（旧预设）' 'vless-plain（普通预设）' socks http shadowsocks vmess \
  trojan naive-inbound hysteria shadowtls vless tuic hysteria2 anytls snell \
  tun redirect tproxy cloudflared; do
  assert_coverage_row "${row_id}"
done
for row_id in \
  direct-outbound bridge block socks http shadowsocks vmess trojan hysteria \
  vless shadowtls tuic hysteria2 anytls snell tor ssh selector urltest naive; do
  assert_coverage_row "${row_id}"
done
for row_id in wireguard-endpoint tailscale openconnect openvpn-client openvpn-server; do
  assert_coverage_row "${row_id}"
done
for row_id in route-rule-set-inline route-rule-set-local route-rule-set-remote; do
  assert_coverage_row "${row_id}"
done
for row_id in \
  certificate-provider-acme http-client-shared resolved-service \
  network-namespace-default network-namespace-unshare; do
  assert_coverage_row "${row_id}"
done

matrix_header='| ID | 官方 type / 角色 | 版本、构建和平台条件 | TCP/UDP/主要约束 | upstream | available（官方 ARM64 包） | implemented；D/T/E/R | 导出 / 分享 / SubMan | validated |'
[[ "$(grep -Fc "${matrix_header}" "${COVERAGE_DOC}")" -ge 3 ]]

protocol_registry=$(protocol_registry_json)
component_registry=$(component_registry_static_json)
capabilities=$(agent_capabilities_json)

jq -e '
  length == 15 and
  ([.[].state_id] | unique | length) == 15 and
  all(.[];
    .core_supported == true and
    .implemented == true and
    .available == null and
    .validated.status == "not_assessed" and
    (.lifecycle | .deploy == true and .takeover == true and .edit == true and .remove == true) and
    (.handlers | length) > 0
  ) and
  ([.[].state_id] | sort) ==
    ["anytls","http","hy2","hysteria","mixed","naive","shadowsocks","shadowtls","snell","socks","trojan","tuic","vless-plain","vless-reality","vmess"]
' <<< "${protocol_registry}" >/dev/null

jq -e '
  length == 38 and
  ([.[].state_id] | unique | length) == 38 and
  all(.[];
    .implemented == true and
    .available == null and
    .validated.status == "not_assessed" and
    (.lifecycle | .create == true and .replace == true and .delete == true and
      .rebuild == true and .export == true and .takeover == true and .recover == true)
  ) and
  ([.[] | [.role,.type]] | unique | length) == 38 and
  any(.[]; .role == "inbound" and .type == "tproxy") and
  any(.[]; .role == "endpoint" and .type == "wireguard") and
  any(.[]; .role == "outbound" and .type == "vless") and
  any(.[]; .role == "rule_set" and .type == "remote")
' <<< "${component_registry}" >/dev/null

# Agent capabilities must expose the same two registries, including the
# implementation/availability/validation dimensions used by the matrix.
jq -e --argjson protocols "${protocol_registry}" --argjson components "${component_registry}" '
  .managed_registry.schema_version == 1 and
  ([.managed_registry.entries[].registry_kind] | sort | unique) == ["component","protocol"] and
  ([.managed_registry.entries[] | [.registry_kind,.state_id]] | unique | length) ==
    (.managed_registry.entries | length) and
  ([.protocol_registry[].state_id] | sort) == ($protocols | map(.state_id) | sort) and
  ([.managed_registry.entries[] | select(.registry_kind == "component") | .state_id] | sort) ==
    ($components | map(.state_id) | sort)
' <<< "${capabilities}" >/dev/null

# The current README must describe the newly component-owned TProxy policy;
# the operator-managed boundary applies only when host_policy is absent.
grep -Fq '可选 TProxy `host_policy` 仅拥有显式 ingress interface 与目标端口的 IPv4/TCP+UDP' "${README_DOC}"
grep -Fq '未配置 `host_policy` 的 TProxy/Redirect 仍归操作员管理' "${README_DOC}"
grep -Fq '2026-09-22 TProxy `host_policy` 验收' "${README_DOC}"

printf '%s\n' 'protocol coverage matrix contract passed'
