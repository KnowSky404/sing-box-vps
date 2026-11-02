#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

CLIENT_RULE_CORE=${SINGBOX_BINARY_114:-$(command -v sing-box)}
[[ -x "${CLIENT_RULE_CORE}" ]] || { printf 'client policy checks require a real sing-box core\n' >&2; exit 1; }
CLIENT_RULE_CORE=$(readlink -f -- "${CLIENT_RULE_CORE}")
CLIENT_RULE_CORE_VERSION=$("${CLIENT_RULE_CORE}" version | awk 'NR == 1 {print $3}')
[[ "${CLIENT_RULE_CORE_VERSION}" == 1.14.* ]] || { printf 'client policy checks require a 1.14.x core\n' >&2; exit 1; }

setup_menu_test_env 120
ln -s "${CLIENT_RULE_CORE}" "${TMP_DIR}/bin/sing-box"
source_testable_install
SB_VERSION="${CLIENT_RULE_CORE_VERSION}"

get_public_ip() { printf '203.0.113.10\n'; }
mkdir -p "${SB_PROTOCOL_STATE_DIR}"
printf 'INSTALLED_PROTOCOLS=anytls\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
cat > "${SB_PROTOCOL_STATE_DIR}/anytls.env" <<'EOF_STATE'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=client-rules-test
PORT=9443
DOMAIN=anytls.example.invalid
PASSWORD=client-rules-dummy-password
USER_NAME=client-rules-user
TLS_MODE=manual
ACME_MODE=http
ACME_EMAIL=
ACME_DOMAIN=
DNS_PROVIDER=cloudflare
CF_API_TOKEN=
CERT_PATH=/unused/client-rules.crt
KEY_PATH=/unused/client-rules.key
EOF_STATE
load_protocol_state anytls

base_policy=$(routing_policy_read_json)
jq -e '.client == {lan_direct:true,cn_direct:true,adblock:false}' <<< "${base_policy}" >/dev/null
baseline=$(build_singbox_client_config)
baseline_outbounds=$(jq -cS '.outbounds' <<< "${baseline}")
baseline_link=$(agent_link_json_for_current_protocol 203.0.113.10)

assert_rule_set_references() {
  local config=$1
  jq -e '
    [.route.rule_set[]?.tag] as $defined |
    ([.route.rules[]?, .dns.rules[]?] |
     [.. | objects | .rule_set? // empty |
      if type == "array" then .[] else . end] | unique) as $used |
    (($used - $defined) | length) == 0 and
    (($defined - $used) | length) == 0
  ' <<< "${config}" >/dev/null
}

# All three switches act independently; application nodes and credentials stay
# exactly the same while the complete exported config passes the real core.
matrix_count=0
for lan_direct in false true; do
  for cn_direct in false true; do
    for adblock_enabled in false true; do
      policy=$(jq -c \
        --argjson lan "${lan_direct}" --argjson cn "${cn_direct}" \
        --argjson ads "${adblock_enabled}" \
        '.client={lan_direct:$lan,cn_direct:$cn,adblock:$ads} |
         .server.adblock=($ads|not) |
         .adblock.url="" | .adblock.domains=["ads.example.invalid"] |
         .adblock.allow=["allowed.ads.example.invalid"]' <<< "${base_policy}")
      config=$(build_singbox_client_config "${policy}")
      jq -e --argjson lan "${lan_direct}" --argjson cn "${cn_direct}" --argjson ads "${adblock_enabled}" '
        (.route.rules | any(.ip_is_private? == true and .outbound? == "direct")) == $lan and
        (.route.rules | any(.rule_set? == "geosite-cn" and .outbound? == "direct")) == $cn and
        (.route.rule_set | any(.tag == "geoip-cn")) == $cn and
        (.dns.rules | any(.rule_set? == "geosite-cn" and .server? == "cn-dns")) == $cn and
        (.route.rules | any(.action == "reject")) == $ads and
        (.dns.rules | map(select(.action == "reject"))) ==
          (.route.rules | map(select(.action == "reject"))) and
        (.route.rules | any(.protocol? == "dns" and .action == "hijack-dns")) and
        .route.default_domain_resolver == "cn-dns" and .dns.final == "remote-dns" and
        .route.final == "proxy"
      ' <<< "${config}" >/dev/null
      [[ "$(jq -cS '.outbounds' <<< "${config}")" == "${baseline_outbounds}" ]]
      assert_rule_set_references "${config}"
      validate_client_config_json "${config}"
      if [[ "${adblock_enabled}" == true ]]; then
        # A whitelist narrows reject matching rather than forcing an outbound
        # before the client can choose its normal CN/default route.
        jq -e '
          [.route.rules[] | select(.action == "reject") |
           .. | objects | select(.invert? == true) |
           .domain_suffix? // empty | .[]?] |
          index("allowed.ads.example.invalid") != null
        ' <<< "${config}" >/dev/null
      fi
      matrix_count=$((matrix_count + 1))
    done
  done
done

# Remote ad sources use the client proxy for downloads; inline sources must not
# inherit remote-only HTTP settings or server-local filesystem paths.
remote_policy=$(jq -c '.client.adblock=true' <<< "${base_policy}")
remote_config=$(build_singbox_client_config "${remote_policy}")
jq -e '
  .route.rule_set | all(.[];
    if .type == "remote" then .http_client.detour == "proxy"
    else (.http_client? == null) end) and
  all(.[]; .type != "local")
' <<< "${remote_config}" >/dev/null
assert_rule_set_references "${remote_config}"
validate_client_config_json "${remote_config}"

# Legacy client rendering must also use the client proxy, without adding a
# legacy detour field to the unchanged CN-only default template.
legacy_remote_config=$(
  detect_installed_singbox_version() { printf '1.13.18\n'; }
  SB_VERSION=1.13.18
  build_singbox_client_config "${remote_policy}"
)
jq -e '
  .route.rule_set | any(.type == "remote" and (.tag | startswith("sbv-adblock")) and
    .download_detour == "proxy" and (.http_client? == null))
' <<< "${legacy_remote_config}" >/dev/null

# Interactive and Agent exports read the same effective policy. Policy edits do
# not change ordinary node links, and malformed policy cannot publish over an
# existing export or its backup.
CLIENT_RULE_EFFECTIVE_POLICY=$(jq -c '.client={lan_direct:false,cn_direct:false,adblock:false}' <<< "${base_policy}")
routing_policy_read_json() { printf '%s\n' "${CLIENT_RULE_EFFECTIVE_POLICY}"; }
export_singbox_client_config > "${TMP_DIR}/interactive-export.txt"
export_path=$(client_export_file_path)
interactive_config=$(cat "${export_path}")
agent_result=$(agent_export_client_json)
jq -e '.config.route.rule_set == [] and .config.dns.rules == []' <<< "${agent_result}" >/dev/null
[[ "$(jq -cS '.route' <<< "${interactive_config}")" == "$(jq -cS '.config.route' <<< "${agent_result}")" ]]
[[ "$(agent_link_json_for_current_protocol 203.0.113.10)" == "${baseline_link}" ]]

cp "${export_path}" "${TMP_DIR}/before-export.json"
cp "${export_path}.bak" "${TMP_DIR}/before-backup.json"
CLIENT_RULE_EFFECTIVE_POLICY=$(jq -c '.client.lan_direct="invalid"' <<< "${CLIENT_RULE_EFFECTIVE_POLICY}")
if export_singbox_client_config > "${TMP_DIR}/invalid-export.txt" 2> "${TMP_DIR}/invalid-export.stderr"; then
  printf 'invalid effective policy unexpectedly exported\n' >&2
  exit 1
fi
if agent_export_client_json > "${TMP_DIR}/invalid-agent.json" 2> "${TMP_DIR}/invalid-agent.stderr"; then
  printf 'invalid effective policy unexpectedly passed Agent export\n' >&2
  exit 1
fi
if build_singbox_client_config "${CLIENT_RULE_EFFECTIVE_POLICY}" > "${TMP_DIR}/invalid-candidate.json"; then
  printf 'invalid candidate policy unexpectedly generated a client config\n' >&2
  exit 1
fi
[[ ! -s "${TMP_DIR}/invalid-candidate.json" ]]
cmp "${TMP_DIR}/before-export.json" "${export_path}"
cmp "${TMP_DIR}/before-backup.json" "${export_path}.bak"

printf 'Client routing policy checks passed: combinations=%s core=%s\n' "${matrix_count}" "${CLIENT_RULE_CORE_VERSION}"
