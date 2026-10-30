#!/usr/bin/env bash

set -euo pipefail

# Host-safe selection only. This module never executes tests or Docker commands.
# The explicit full manifest preserves the original install.sh regression set;
# additions below cover the dispatcher, docs and focused groups without treating
# every tests/*.sh file as a host executable.
verification_selection_repo_root() {
  if [[ -n "${REPO_ROOT:-}" ]]; then
    printf '%s\n' "${REPO_ROOT}"
  else
    (cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
  fi
}

verification_list_groups() {
  printf '%s\n' \
    docs version bootstrap menu self-update subman verification \
    protocol:vless protocol:vless-plain protocol:mixed protocol:hy2 \
    protocol:anytls protocol:socks protocol:http protocol:shadowsocks \
    protocol:trojan protocol:vmess protocol:hysteria protocol:tuic \
    protocol:snell protocol:shadowtls protocol:naive full
}

verification_full_test_manifest() {
  cat <<'EOF_TESTS'
tests/sbv_update_transactions.sh
tests/sbv_menu_reloads_updated_script.sh
tests/bootstrap_download.sh
tests/cli_update_commands.sh
tests/protocol_registry_contract.sh
tests/protocol_coverage_contract.sh
tests/protocol_instance_adapter.sh
tests/structured_instance_store.sh
tests/managed_listener_resources.sh
tests/listener_network_selection.sh
tests/firewall_listener_references.sh
tests/mixed_active_state.sh
tests/mixed_instance_lifecycle.sh
tests/mixed_instance_lifecycle_runtime.sh
tests/mixed_structured_takeover.sh
tests/instance_firewall_ledger.sh
tests/mixed_instance_menu.sh
tests/plain_proxy_structured_store.sh
tests/socks_instance_lifecycle.sh
tests/instance_rebuild_takeover.sh
tests/socks_instance_lifecycle_runtime.sh
tests/socks_instance_menu.sh
tests/socks_structured_takeover.sh
tests/socks_export_client.sh
tests/plain_proxy_share_links.sh
tests/plain_proxy_share_runtime.sh
tests/http_structured_instance_store.sh
tests/http_structured_takeover.sh
tests/http_instance_lifecycle.sh
tests/http_instance_menu.sh
tests/http_export_client.sh
tests/http_export_runtime.sh
tests/http_agent_contract.sh
tests/shadowsocks_structured_instance_store.sh
tests/shadowsocks_structured_takeover.sh
tests/shadowsocks_instance_lifecycle.sh
tests/shadowsocks_instance_menu.sh
tests/shadowsocks_export_client.sh
tests/shadowsocks_agent_share.sh
tests/shadowsocks_runtime.sh
tests/subman_shadowsocks_sync.sh
tests/v2ray_transport_contract.sh
tests/v2ray_transport_runtime.sh
tests/trojan_structured_instance_store.sh
tests/trojan_structured_takeover.sh
tests/trojan_instance_lifecycle.sh
tests/trojan_instance_menu.sh
tests/trojan_agent_share.sh
tests/trojan_export_runtime.sh
tests/subman_trojan_sync.sh
tests/vmess_structured_instance_store.sh
tests/vmess_structured_takeover.sh
tests/vmess_instance_lifecycle.sh
tests/vmess_agent_share.sh
tests/vmess_export_runtime.sh
tests/subman_vmess_sync.sh
tests/vless_plain_structured_instance_store.sh
tests/vless_plain_instance_lifecycle.sh
tests/vless_plain_agent_share.sh
tests/vless_plain_export_runtime.sh
tests/subman_vless_plain_sync.sh
tests/anytls_structured_instance_store.sh
tests/anytls_structured_takeover.sh
tests/anytls_instance_lifecycle.sh
tests/anytls_agent_share.sh
tests/anytls_export_runtime.sh
tests/snell_instance_lifecycle.sh
tests/tuic_instance_lifecycle.sh
tests/hysteria_instance_lifecycle.sh
tests/naive_instance_lifecycle.sh
tests/shadowtls_composite_export.sh
tests/managed_components_contract.sh
tests/managed_redirect_host_policy.sh
tests/managed_tproxy_host_policy.sh
tests/managed_openvpn_endpoint_runtime.sh
tests/managed_transparent_resources.sh
tests/managed_transparent_transaction.sh
tests/managed_component_availability.sh
tests/verification_ssh_outbound_contract.sh
tests/verification_socks_outbound_contract.sh
tests/verification_selector_outbound_contract.sh
tests/verification_urltest_outbound_contract.sh
tests/verification_shadowsocks_outbound_contract.sh
tests/verification_direct_block_outbound_contract.sh
tests/verification_vless_outbound_contract.sh
tests/verification_tor_outbound_contract.sh
tests/verification_shadowtls_outbound_contract.sh
tests/managed_component_graph.sh
tests/managed_component_graph_core_startup.sh
tests/live_inbound_inventory_guards.sh
tests/verification_protocol_probe_matrix.sh
tests/verification_protocol_probe_vless.sh
tests/verification_protocol_probe_hy2.sh
tests/verification_protocol_probe_anytls.sh
tests/verification_protocol_probe_http.sh
tests/verification_protocol_probe_shadowsocks.sh
tests/verification_protocol_probe_trojan.sh
tests/verification_protocol_probe_vmess.sh
tests/verification_protocol_probe_snell.sh
tests/verification_protocol_probe_naive.sh
tests/verification_protocol_probe_shadowtls.sh
tests/verification_protocol_probe_hysteria.sh
tests/verification_protocol_probe_tuic.sh
tests/verification_protocol_probe_udp.sh
tests/verification_protocol_probe_vless_plain.sh
tests/reality_sni_validation.sh
tests/generate_config_cleans_temp_files_on_failure.sh
tests/generate_config_commits_validated_candidate.sh
tests/managed_config_transactions.sh
tests/system_safety_guards.sh
tests/agent_upgrade_commands.sh
tests/agent_cli_multi_instance_status.sh
tests/agent_cli_ops_commands.sh
tests/agent_cli_outputs_machine_readable_node_info.sh
tests/agent_json_regression.sh
tests/export_client_config_1_14_compatibility.sh
tests/export_client_config_mixed_only.sh
tests/export_client_config_mixed_auth.sh
tests/export_client_config_mixed_runtime.sh
tests/export_client_config_validates_generated_config.sh
tests/agent_docs_cover_capabilities.sh
tests/version_metadata_is_consistent.sh
tests/vless_reality_instance_removal.sh
tests/install_takeover_rebuilds_protocol_state_from_config.sh
tests/install_takeover_rebuilds_vless_reality_instances.sh
tests/detect_existing_instance_auto_heals_managed_config_drift.sh
tests/update_keeps_existing_config.sh
tests/update_binary_path_initializes_system_info.sh
tests/update_rolls_back_binary_when_config_invalid.sh
tests/update_rolls_back_binary_when_restart_fails.sh
tests/uninstall_purge_removes_runtime_artifacts.sh
tests/subman_config_helpers.sh
tests/subman_payload_generation.sh
tests/subman_api_push.sh
tests/subman_sync_orchestration.sh
EOF_TESTS
}

verification_group_test_candidates() {
  local group=${1:-}
  local root pattern file
  local patterns=()
  root=$(verification_selection_repo_root) || return 1

  case "${group}" in
    docs)
      printf '%s\n' tests/wiki_documentation.sh tests/agent_docs_cover_capabilities.sh
      ;;
    version)
      printf '%s\n' tests/readme_mentions_current_versions.sh tests/version_metadata_is_consistent.sh
      ;;
    bootstrap)
      printf '%s\n' tests/bootstrap_download.sh
      ;;
    menu)
      patterns=('tests/*menu*.sh')
      ;;
    self-update)
      printf '%s\n' \
        tests/sbv_update_transactions.sh \
        tests/sbv_menu_reloads_updated_script.sh \
        tests/cli_update_commands.sh \
        tests/ensure_sbv_command_updates_stale_existing_script.sh \
        tests/initial_exit_installs_sbv_command.sh
      ;;
    subman)
      patterns=('tests/subman_*.sh')
      ;;
    verification)
      printf '%s\n' \
        tests/verification_artifact_dir_layout.sh \
        tests/verification_trigger_rules.sh \
        tests/verification_scenario_mapping.sh \
        tests/verification_requires_remote_env.sh \
        tests/verification_docker_image_build.sh \
        tests/verification_stops_on_remote_failure.sh \
        tests/verification_run_writes_changed_files.sh \
        tests/verification_tests_only_stays_local.sh \
        tests/verification_runtime_smoke_artifacts.sh \
        tests/verification_remote_scenario_dispatch.sh \
        tests/verification_planner.sh
      ;;
    protocol:hy2|protocol:hysteria2)
      patterns=('tests/*hy2*.sh')
      ;;
    protocol:vless|protocol:vless-reality)
      patterns=('tests/*vless*.sh' 'tests/*reality*.sh')
      ;;
    protocol:vless-plain)
      patterns=('tests/*vless_plain*.sh')
      ;;
    protocol:mixed|protocol:anytls|protocol:socks|protocol:http|protocol:shadowsocks|protocol:trojan|protocol:vmess|protocol:hysteria|protocol:tuic|protocol:snell|protocol:shadowtls|protocol:naive)
      pattern=${group#protocol:}
      patterns=("tests/*${pattern}*.sh")
      ;;
    full)
      verification_full_test_manifest
      for group in docs version bootstrap menu self-update subman verification; do
        verification_group_test_candidates "${group}" || return 1
      done
      ;;
    *)
      printf 'unknown verification group: %s\n' "${group:-<empty>}" >&2
      return 2
      ;;
  esac

  # Expand only our fixed, validated patterns. No caller input is evaluated.
  for pattern in "${patterns[@]}"; do
    while IFS= read -r file; do
      [[ -n "${file}" ]] || continue
      printf '%s\n' "${file#"${root}/"}"
    done < <(compgen -G "${root}/${pattern}" | LC_ALL=C sort)
  done
}

verification_group_tests() {
  local group=${1:-}
  local root candidates file count=0
  local seen=$'\n'
  root=$(verification_selection_repo_root) || return 1
  candidates=$(verification_group_test_candidates "${group}") || return "$?"

  while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    case "${file}" in
      tests/*_helper.sh|tests/hy2_instance_acme_runtime.sh) continue ;;
    esac
    case "${group}:${file}" in
      protocol:vless:tests/*vless_plain*|protocol:vless-reality:tests/*vless_plain*) continue ;;
    esac
    if [[ ! -f "${root}/${file}" ]]; then
      printf 'registered host test is missing: %s\n' "${file}" >&2
      return 2
    fi
    case "${seen}" in
      *$'\n'"${file}"$'\n'*) continue ;;
    esac
    printf '%s\n' "${file}"
    count=$((count + 1))
    seen+="${file}"$'\n'
  done <<< "${candidates}"
  if [[ "${count}" -eq 0 ]]; then
    printf 'no host tests available for group: %s\n' "${group}" >&2
    return 2
  fi
}

verification_list_scenarios() {
  printf '%s\n' \
    fresh_install_vless \
    reconfigure_existing_install \
    legacy_takeover_export \
    fresh_install_anytls \
    fresh_install_socks \
    fresh_install_http \
    fresh_install_shadowsocks \
    fresh_install_trojan \
    fresh_install_vmess \
    fresh_install_hysteria \
    fresh_install_vless_plain \
    multi_protocol_coexistence \
    upgrade_1_13_to_1_14 \
    upgrade_rollback_1_13_to_1_14 \
    uninstall_and_reinstall \
    runtime_smoke
}

verification_expand_scenarios() {
  local scenario root
  local baseline=''
  local requested_scenarios=("$@")
  root=$(verification_selection_repo_root) || return 1

  # Validate the entire request before emitting a partial executable plan.
  for scenario in "${requested_scenarios[@]}"; do
    case "${scenario}" in
      fresh_install_vless|reconfigure_existing_install|legacy_takeover_export|fresh_install_anytls|fresh_install_socks|fresh_install_http|fresh_install_shadowsocks|fresh_install_trojan|fresh_install_vmess|fresh_install_hysteria|fresh_install_vless_plain|multi_protocol_coexistence|upgrade_1_13_to_1_14|upgrade_rollback_1_13_to_1_14|uninstall_and_reinstall|runtime_smoke)
        if [[ ! -f "${root}/dev/verification/remote/scenarios/${scenario}.sh" ]]; then
          printf 'verification scenario file is missing: %s\n' "${scenario}" >&2
          return 2
        fi
        ;;
      *)
        printf 'unknown verification scenario: %s\n' "${scenario:-<empty>}" >&2
        return 2
        ;;
    esac
  done

  [[ "${#requested_scenarios[@]}" -gt 0 ]] || return 0
  for scenario in "${requested_scenarios[@]}"; do
    case "${scenario}" in
      runtime_smoke)
        # Always inspect the final configured state, after all mutations.
        continue
        ;;
      reconfigure_existing_install)
        # The scenario needs the default REALITY instance at its original port.
        # A previous reconfigure or a different fresh install invalidates it.
        if [[ "${baseline}" != fresh_vless ]]; then
          printf '%s\n' fresh_install_vless
        fi
        printf '%s\n' "${scenario}"
        baseline=reconfigured_vless
        ;;
      uninstall_and_reinstall)
        # A real prior VLESS UUID is needed for the credential-regeneration check.
        case "${baseline}" in
          fresh_vless|reconfigured_vless|legacy_vless|upgraded_vless) ;;
          *) printf '%s\n' fresh_install_vless ;;
        esac
        printf '%s\n' "${scenario}"
        baseline=fresh_vless
        ;;
      fresh_install_vless)
        printf '%s\n' "${scenario}"
        baseline=fresh_vless
        ;;
      legacy_takeover_export)
        printf '%s\n' "${scenario}"
        baseline=legacy_vless
        ;;
      upgrade_1_13_to_1_14|upgrade_rollback_1_13_to_1_14)
        # Both create their own VLESS REALITY installation on port 443.
        printf '%s\n' "${scenario}"
        baseline=upgraded_vless
        ;;
      *)
        printf '%s\n' "${scenario}"
        baseline=other_install
        ;;
    esac
  done

  # A smoke-only run starts in a fresh container and has no installed baseline.
  if [[ -z "${baseline}" ]]; then
    printf '%s\n' fresh_install_http
  fi
  printf '%s\n' runtime_smoke
}
