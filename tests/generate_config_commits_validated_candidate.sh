#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"
CHECK_LOG="${TMP_DIR}/check.log"
CHECK_FAIL_FILE="${TMP_DIR}/check.fail"
export CHECK_LOG CHECK_FAIL_FILE

sed \
  -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  -e "s|readonly SINGBOX_BIN_PATH=\"/usr/local/bin/sing-box\"|readonly SINGBOX_BIN_PATH=\"${TMP_DIR}/bin/sing-box\"|" \
  -e "s|readonly SINGBOX_SERVICE_FILE=\"/etc/systemd/system/sing-box.service\"|readonly SINGBOX_SERVICE_FILE=\"${TMP_DIR}/sing-box.service\"|" \
  -e 's|main "\$@"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/bin" "${TMP_DIR}/project" "${TMP_DIR}/mktemp"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash
printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  version)
    printf 'sing-box version 1.14.0\n'
    ;;
  check)
    [[ "${2:-}" == "-c" && -f "${3:-}" ]]
    printf '%s\n' "${3}" >> "${CHECK_LOG}"
    [[ ! -e "${CHECK_FAIL_FILE}" ]]
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "${TMP_DIR}/bin/sing-box"

export PATH="${TMP_DIR}/bin:${PATH}"
export TMPDIR="${TMP_DIR}/mktemp"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

ensure_warp_routing_assets() { :; }
load_warp_route_settings() { :; }
refresh_warp_route_assets() {
  SB_WARP_CUSTOM_DOMAINS_JSON='[]'
  SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON='[]'
  SB_WARP_LOCAL_RULE_SETS_JSON='[]'
  SB_WARP_REMOTE_RULE_SETS_JSON='[]'
  SB_WARP_RULE_SET_TAGS_JSON='[]'
}
ensure_stack_mode_state_loaded() { :; }
instance_outbound_requires_warp() { return 1; }
list_effective_protocols() { printf 'mixed\n'; }
load_protocol_state() { :; }
build_inbound_for_protocol() {
  if [[ "${MUTATE_DURING_BUILD:-n}" == "y" ]]; then
    printf 'must roll back\n' > "${SB_PROJECT_DIR}/builder-mutated.state"
  fi
  printf '%s\n' '{"type":"mixed","tag":"mixed-in","listen":"127.0.0.1","listen_port":1080}'
  if [[ "${GRAPH_FAILURE:-}" == "duplicate" ]]; then
    printf '%s\n' '{"type":"mixed","tag":"mixed-in","listen":"127.0.0.1","listen_port":1081}'
  elif [[ "${GRAPH_FAILURE:-}" == "listener" ]]; then
    printf '%s\n' '{"type":"mixed","tag":"private-listener-tag","listen":"0.0.0.0","listen_port":1080}'
  fi
}
build_protocol_route_rules() {
  if [[ "${GRAPH_FAILURE:-}" == "reference" ]]; then
    printf '%s\n' '[{"inbound":"missing-private-tag","action":"route","outbound":"direct"}]'
  else
    printf '%s\n' '[]'
  fi
}
build_certificate_provider_for_protocol() {
  [[ "${PROVIDER_FAIL:-n}" != "y" ]]
}

SB_ADVANCED_ROUTE="n"
SB_ENABLE_WARP="n"
SB_WARP_ROUTE_MODE="selective"
SB_OUTBOUND_STACK_MODE="prefer_ipv4"

printf '%s\n' '{"old":true}' > "${SINGBOX_CONFIG_FILE}"
generate_config >/dev/null

if ! jq -e '.inbounds[0].tag == "mixed-in"' "${SINGBOX_CONFIG_FILE}" >/dev/null; then
  printf 'expected validated candidate to replace the live config\n' >&2
  exit 1
fi
if [[ "$(cat "${SINGBOX_CONFIG_FILE}.bak")" != '{"old":true}' ]]; then
  printf 'expected persistent backup to contain the previous live config\n' >&2
  exit 1
fi
if [[ "$(stat -c '%a' "${SINGBOX_CONFIG_FILE}")" != "600" || "$(stat -c '%a' "${SINGBOX_CONFIG_FILE}.bak")" != "600" ]]; then
  printf 'expected live config and backup permissions to be 600\n' >&2
  exit 1
fi
checked_candidate=$(tail -n1 "${CHECK_LOG}")
if [[ "${checked_candidate}" == "${SINGBOX_CONFIG_FILE}" || "${checked_candidate}" != "${SINGBOX_CONFIG_DIR}"/.config.json.candidate.* ]]; then
  printf 'expected sing-box check to validate a same-directory candidate, got %s\n' "${checked_candidate}" >&2
  exit 1
fi

# A normal protocol candidate must fail before resource preparation when a
# live root namespace is outside the generator's ownership model.
unknown_root_config=$(cat "${SINGBOX_CONFIG_FILE}")
unknown_root_backup=$(cat "${SINGBOX_CONFIG_FILE}.bak")
jq '.experimental = {must_preserve:true}' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
unknown_root_input=$(cat "${SINGBOX_CONFIG_FILE}")
if generate_config_candidate >"${TMP_DIR}/unknown-root.out" 2>"${TMP_DIR}/unknown-root.err"; then
  printf 'expected unknown top-level namespace to abort normal candidate generation\n' >&2
  exit 1
fi
[[ "$(cat "${SINGBOX_CONFIG_FILE}")" == "${unknown_root_input}" ]]
[[ "$(cat "${SINGBOX_CONFIG_FILE}.bak")" == "${unknown_root_backup}" ]]
grep -Fq '未建模的顶层或投影字段' "${TMP_DIR}/unknown-root.out"
printf '%s\n' "${unknown_root_config}" > "${SINGBOX_CONFIG_FILE}"

assert_projection_rejected() {
  local label=$1
  local input backup candidate_input
  input=$(cat "${SINGBOX_CONFIG_FILE}")
  backup=$(cat "${SINGBOX_CONFIG_FILE}.bak")
  case "${label}" in
    dns)
      jq '.dns.servers += [{type:"udp",tag:"unowned-dns",server:"1.1.1.1"}]' \
        "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next" ;;
    route)
      jq '.route.default_domain_resolver = "unowned-dns"' \
        "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next" ;;
    certificate)
      jq '.certificate_providers = [{type:"acme",tag:"unowned-cert",domain:["unowned.example"]}]' \
        "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next" ;;
    *) return 1 ;;
  esac
  mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
  candidate_input=$(cat "${SINGBOX_CONFIG_FILE}")
  if generate_config_candidate >"${TMP_DIR}/${label}-projection.out" \
    2>"${TMP_DIR}/${label}-projection.err"; then
    printf 'expected %s projection drift to abort candidate generation\n' "${label}" >&2
    exit 1
  fi
  [[ "$(cat "${SINGBOX_CONFIG_FILE}")" == "${candidate_input}" ]]
  [[ "$(cat "${SINGBOX_CONFIG_FILE}.bak")" == "${backup}" ]]
  grep -Fq '未建模的顶层或投影字段' "${TMP_DIR}/${label}-projection.out"
  printf '%s\n' "${input}" > "${SINGBOX_CONFIG_FILE}"
}

assert_projection_rejected dns
assert_projection_rejected route
assert_projection_rejected certificate

# Exercise the production jq assembly rather than only the helper contract:
# an auto-routed managed TUN must add the loop guard to the published route,
# while an explicit unsafe live setting must abort before publication.
managed_component_render_json_definition=$(declare -f managed_component_render_json)
validate_live_inbound_inventory_definition=$(declare -f validate_live_inbound_inventory)
managed_component_render_json() {
  jq -cn '{inbounds:[{type:"tun",tag:"tun-auto",interface_name:"tun-sbv",address:["172.19.0.1/30"],auto_route:true,strict_route:true}],endpoints:[],outbounds:[],route_rules:[]}'
}
validate_live_inbound_inventory() { :; }
generate_config >/dev/null
jq -e '.route.auto_detect_interface == true and any(.inbounds[]; .tag == "tun-auto" and .auto_route == true)' \
  "${SINGBOX_CONFIG_FILE}" >/dev/null
jq '.route.auto_detect_interface = false | del(.route.default_interface)' \
  "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
tun_config_conflict_input=$(cat "${SINGBOX_CONFIG_FILE}")
if generate_config >"${TMP_DIR}/tun-route.out" 2>"${TMP_DIR}/tun-route.err"; then
  printf 'expected explicit unsafe TUN loop guard to abort generation\n' >&2
  exit 1
fi
grep -Fq 'tun_auto_route_loop_guard_conflict' "${TMP_DIR}/tun-route.err"
[[ "$(cat "${SINGBOX_CONFIG_FILE}")" == "${tun_config_conflict_input}" ]]
jq -e '.route.auto_detect_interface == false and (.route.default_interface? == null)' \
  "${SINGBOX_CONFIG_FILE}" >/dev/null
jq '.route.default_interface = "eth0"' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
generate_config >/dev/null
jq -e '.route.auto_detect_interface == false and .route.default_interface == "eth0"' \
  "${SINGBOX_CONFIG_FILE}" >/dev/null
eval "${managed_component_render_json_definition}"
unset managed_component_render_json_definition
eval "${validate_live_inbound_inventory_definition}"
unset validate_live_inbound_inventory_definition

printf '%s\n' '{"keep":"check-failure"}' > "${SINGBOX_CONFIG_FILE}"
rm -f "${SINGBOX_CONFIG_FILE}.bak"
touch "${CHECK_FAIL_FILE}"
MUTATE_DURING_BUILD="y"
if generate_config >/dev/null 2>&1; then
  printf 'expected candidate validation failure to abort generation\n' >&2
  exit 1
fi
MUTATE_DURING_BUILD="n"
rm -f "${CHECK_FAIL_FILE}"
if [[ "$(cat "${SINGBOX_CONFIG_FILE}")" != '{"keep":"check-failure"}' || -e "${SINGBOX_CONFIG_FILE}.bak" ]]; then
  printf 'expected validation failure to preserve live config without publishing a backup\n' >&2
  exit 1
fi
if [[ -e "${SB_PROJECT_DIR}/builder-mutated.state" ]]; then
  printf 'expected failed generation to restore builder-mutated managed state\n' >&2
  exit 1
fi

# The mock core accepts these candidates. The real graph preflight must reject
# them before check/backup/publication and restore all builder side effects.
for GRAPH_FAILURE in duplicate reference listener; do
  printf '%s\n' '{"keep":"graph-failure"}' > "${SINGBOX_CONFIG_FILE}"
  printf '%s\n' '{"keep":"previous-backup"}' > "${SINGBOX_CONFIG_FILE}.bak"
  checked_before=$(wc -l < "${CHECK_LOG}")
  MUTATE_DURING_BUILD="y"
  if generate_config >"${TMP_DIR}/graph.out" 2>"${TMP_DIR}/graph.err"; then
    printf 'expected graph failure to abort generation: %s\n' "${GRAPH_FAILURE}" >&2
    exit 1
  fi
  MUTATE_DURING_BUILD="n"
  [[ "$(<"${SINGBOX_CONFIG_FILE}")" == '{"keep":"graph-failure"}' ]]
  [[ "$(<"${SINGBOX_CONFIG_FILE}.bak")" == '{"keep":"previous-backup"}' ]]
  [[ ! -e "${SB_PROJECT_DIR}/builder-mutated.state" ]]
  [[ "$(wc -l < "${CHECK_LOG}")" == "${checked_before}" ]]
  if [[ "${GRAPH_FAILURE}" == listener ]]; then
    grep -Fq 'listener_resources:' "${TMP_DIR}/graph.err"
    ! grep -Fq 'private-listener-tag' "${TMP_DIR}/graph.err"
  else
    grep -Fq 'component_graph:' "${TMP_DIR}/graph.err"
  fi
  if grep -Fq 'missing-private-tag' "${TMP_DIR}/graph.err"; then
    printf 'graph error leaked a user-controlled tag\n' >&2
    exit 1
  fi
done
unset GRAPH_FAILURE

printf '%s\n' '{"keep":"provider-failure"}' > "${SINGBOX_CONFIG_FILE}"
PROVIDER_FAIL="y"
if generate_config >/dev/null 2>&1; then
  printf 'expected certificate provider builder failure to abort generation\n' >&2
  exit 1
fi
PROVIDER_FAIL="n"
if [[ "$(cat "${SINGBOX_CONFIG_FILE}")" != '{"keep":"provider-failure"}' ]]; then
  printf 'expected provider failure to preserve the live config\n' >&2
  exit 1
fi

mv "${SINGBOX_BIN_PATH}" "${SINGBOX_BIN_PATH}.missing"
if generate_config >/dev/null 2>&1; then
  printf 'expected generation without a sing-box binary to fail closed\n' >&2
  exit 1
fi
mv "${SINGBOX_BIN_PATH}.missing" "${SINGBOX_BIN_PATH}"

if find "${TMP_DIR}/mktemp" "${SINGBOX_CONFIG_DIR}" -maxdepth 1 -type f \
  \( -name '.config.json.candidate.*' -o -name '.config.json.backup.*' \) | grep -q .; then
  printf 'expected all generation candidates to be cleaned up\n' >&2
  exit 1
fi
