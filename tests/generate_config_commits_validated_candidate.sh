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
for GRAPH_FAILURE in duplicate reference; do
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
  grep -Fq 'component_graph:' "${TMP_DIR}/graph.err"
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
