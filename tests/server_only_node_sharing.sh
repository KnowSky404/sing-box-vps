#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"

# Removed exports cannot create a file, rotate retained exports or acquire a
# write lock, even when the caller invokes the old command directly.
export_dir="${SB_PROJECT_DIR}/client"
mkdir -p "${export_dir}"
printf 'retained-export\n' > "${export_dir}/sing-box-client.json"
printf 'retained-backup\n' > "${export_dir}/sing-box-client.json.bak"
before=$(find "${SB_PROJECT_DIR}" -type f -exec sha256sum {} + | sort)
acquire_managed_write_lock() { printf 'unexpected lock acquisition\n' >&2; return 97; }
if response=$(agent_dispatch export-client --json); then
  printf 'removed client-config command succeeded\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "unknown_command" and .command == "export-client"' \
  <<< "${response}" >/dev/null
[[ "$(find "${SB_PROJECT_DIR}" -type f -exec sha256sum {} + | sort)" == "${before}" ]]
[[ ! -e "${SB_PROJECT_DIR}.instance-write.lock" ]]
rm -r -- "${export_dir}"
if agent_dispatch export-client --json > "${TMP_DIR}/absent.json"; then exit 1; fi
[[ ! -e "${export_dir}" ]]

capabilities=$(agent_capabilities_json)
jq -e '
  (.commands | has("export-client") | not) and
  (.features.connection_material | has("bare_core_client_export") | not) and
  .features.connection_material.links and .features.connection_material.ansi_qr and
  all(.protocol_registry[]; (has("client_export") | not) and
    (.features | has("client_export") | not))
' <<< "${capabilities}" >/dev/null
[[ "$(agent_print_help)" != *export-client* ]]
menu=$(show_node_info_action_menu <<'INPUT'
0
INPUT
)
[[ "${menu}" != *客户端配置* && "${menu}" == *SubMan* && "${menu}" == *二维码* ]]
for removed in build_singbox_client_config export_singbox_client_config agent_export_client_json \
  write_client_config_export validate_client_config_json client_export_file_path \
  list_exportable_client_protocols collect_client_export_warnings_json; do
  if declare -F "${removed}" >/dev/null; then
    printf 'removed full client export helper still present: %s\n' "${removed}" >&2
    exit 1
  fi
done
# Node serializers remain available to SubMan, share links and isolated probes.
for retained in build_client_outbound_json_for_protocol build_vless_plain_links_json \
  build_vmess_links_json build_subman_node_payload agent_collect_nodes_json; do
  declare -F "${retained}" >/dev/null
done
printf 'Server-only node sharing checks passed\n'
