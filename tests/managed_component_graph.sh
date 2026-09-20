#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/sing-box-vps-component-graph.XXXXXX)
PWN_MARKER="${TEST_DIR}/pwned"
trap 'rm -rf -- "${TEST_DIR}"' EXIT

# Source the real implementation.  This is a unit preflight test; the
# generated fixtures are intentionally not claimed to be complete core configs.
source "${REPO_ROOT}/install.sh"

pass_count=0

write_case() {
  local name=$1
  local json=$2
  printf '%s\n' "${json}" > "${TEST_DIR}/${name}.json"
}

expect_valid_file() {
  local name=$1
  local file=$2
  local stdout_file="${TEST_DIR}/${name}.stdout"
  local stderr_file="${TEST_DIR}/${name}.stderr"
  local status=0
  validate_managed_component_graph "${file}" >"${stdout_file}" 2>"${stderr_file}" || status=$?
  if [[ ${status} -ne 0 || -s "${stdout_file}" || -s "${stderr_file}" ]]; then
    printf 'expected valid graph failed: %s (status=%s)\n' "${name}" "${status}" >&2
    sed -n '1,4p' "${stderr_file}" >&2
    return 1
  fi
  pass_count=$((pass_count + 1))
}

expect_valid() {
  local name=$1
  local json=$2
  write_case "${name}" "${json}"
  expect_valid_file "${name}" "${TEST_DIR}/${name}.json"
}

expect_invalid_file() {
  local name=$1
  local file=$2
  local reason=$3
  local stdout_file="${TEST_DIR}/${name}.stdout"
  local stderr_file="${TEST_DIR}/${name}.stderr"
  local status=0
  local expected="[ERROR] component_graph: ${reason}; 配置未发布。"
  validate_managed_component_graph "${file}" >"${stdout_file}" 2>"${stderr_file}" || status=$?
  if [[ ${status} -eq 0 || -s "${stdout_file}" ]]; then
    printf 'expected invalid graph accepted or wrote stdout: %s (status=%s)\n' "${name}" "${status}" >&2
    return 1
  fi
  if [[ $(<"${stderr_file}") != "${expected}" ]]; then
    printf 'unexpected sanitized error for %s\n' "${name}" >&2
    sed -n '1,4p' "${stderr_file}" >&2
    return 1
  fi
  # The validator must not expose jq diagnostics or echo fixture-controlled
  # strings which could be interpreted as shell syntax.
  if grep -Eq 'jq:|/tmp/|\$\(|`|Authorization|Bearer|password|token' "${stderr_file}"; then
    printf 'unsanitized graph error for %s\n' "${name}" >&2
    return 1
  fi
  pass_count=$((pass_count + 1))
}

expect_invalid() {
  local name=$1
  local json=$2
  local reason=$3
  write_case "${name}" "${json}"
  expect_invalid_file "${name}" "${TEST_DIR}/${name}.json" "${reason}"
}

# Empty graph, component roles, selector/urltest/default, and independent
# namespaces (the same tag is allowed in HTTP and outbound spaces).
expect_valid "roles-and-namespaces" '{
  "inbounds":[
    {"type":"mixed","tag":"in","detour":"in-target","tls":{"certificate_provider":"cert-shared"}},
    {"type":"mixed","tag":"in-target"}
  ],
  "outbounds":[
    {"type":"selector","tag":"sel","outbounds":["leaf"],"default":"leaf"},
    {"type":"urltest","tag":"ut","outbounds":["leaf"]},
    {"type":"direct","tag":"leaf"}
  ],
  "endpoints":[{"type":"openvpn-server","tag":"ep","detour":"in-target"}],
  "certificate_providers":[{"type":"acme","tag":"cert-shared","http_client":"shared"}],
  "http_clients":[{"tag":"shared","detour":"leaf"}],
  "route":{"final":"sel","default_http_client":"shared"}
}'
expect_valid "empty" '{}'

# Nested route and DNS rules, rule-set references, and DNS references use the
# intended fields rather than recursively treating arbitrary object keys as
# dependencies.
expect_valid "nested-route-dns-rules" '{
  "inbounds":[{"type":"mixed","tag":"in"}],
  "outbounds":[{"type":"direct","tag":"leaf"}],
  "route":{
    "final":"leaf",
    "rule_set":[{"tag":"rs","type":"local","rules":[{"outbound":"leaf"}]}],
    "rules":[{"inbound":["in"],"outbound":"leaf","rule_set":["rs"],"rules":[{"action":"route","outbound":"leaf"}]}]
  },
  "dns":{
    "servers":[{"tag":"dns-local","address":"127.0.0.1"}],
    "rules":[{"inbound":["in"],"outbound":"leaf","rule_set":["rs"],"server":"dns-local","rules":[{"outbound":"leaf"}]}]
  }
}'

# Named and inline providers/http clients, including the non-reference
# headers object and a legal direct-IP server with no resolver dependency.
expect_valid "provider-inline-http-and-headers" '{
  "inbounds":[
    {"type":"mixed","tag":"named","tls":{"certificate_provider":"cp"}},
    {"type":"mixed","tag":"inline","tls":{"certificate_provider":{"type":"acme","http_client":{"detour":"leaf"}}}}
  ],
  "outbounds":[{"type":"direct","tag":"leaf","server":"127.0.0.1"}],
  "certificate_providers":[{"type":"acme","tag":"cp","http_client":"hc"}],
  "http_clients":[{"tag":"hc","detour":"leaf","headers":{"outbound":"not-a-reference","rule_set":"not-a-reference"}}],
  "route":{"final":"leaf","default_http_client":"hc"}
}'

# Remote rule sets may reference only a named shared HTTP client. The graph
# must include that dependency so malformed references fail before publish.
expect_valid "remote-ruleset-http-client-reference" '{
  "outbounds":[{"type":"direct","tag":"leaf"}],
  "http_clients":[{"tag":"rules-http","detour":"leaf"}],
  "route":{"rule_set":[{"type":"remote","tag":"remote-rules","format":"source",
    "url":"https://rules.example.test/rules.json","http_client":"rules-http"}]}
}'

expect_valid "valid-domain-resolver-and-dns" '{
  "outbounds":[{"type":"direct","tag":"leaf","server":"example.test"}],
  "route":{"final":"leaf","default_domain_resolver":"dns1"},
  "dns":{"servers":[{"tag":"dns1","address":"127.0.0.1"}],"final":"dns1"}
}'

# A shell-looking tag must remain data and must not cause command execution.
special_tag="\$(touch ${PWN_MARKER});special"
special_json=$(jq -cn --arg tag "${special_tag}" \
  '{outbounds:[{type:"direct",tag:$tag}],route:{final:$tag}}')
expect_valid "special-tag-data" "${special_json}"
[[ ! -e "${PWN_MARKER}" ]]

# Shared selector DAG: the graph check must remain iterative and accept a
# large diamond-like set of shared dependencies without recursive traversal.
jq -n '
  {outbounds:
    ([range(0;80) as $i |
      {type:"selector", tag:("node-" + ($i|tostring)),
       outbounds:(if $i == 0 then ["leaf-a","leaf-b"] else
         [("node-" + (($i-1)|tostring)), (if ($i % 2) == 0 then "leaf-a" else "leaf-b" end)] end)}]
     + [{type:"direct",tag:"leaf-a"},{type:"direct",tag:"leaf-b"}]),
   route:{final:"node-79"}}
' > "${TEST_DIR}/large-shared-dag.json"
expect_valid_file "large-shared-dag" "${TEST_DIR}/large-shared-dag.json"

# Additional positive contracts: explicit DNS resolver edges must be checked
# without inventing a cycle, and historical positional tags remain valid in
# their own namespaces.
expect_valid "direct-domain-resolver-and-dns-detour" '{
  "outbounds":[
    {"type":"direct","tag":"proxy","server":"name.test","domain_resolver":"dns"},
    {"type":"direct","tag":"direct"}
  ],
  "dns":{"servers":[{"tag":"dns","type":"udp","server":"1.1.1.1","detour":"direct"}]},
  "route":{"final":"proxy"}
}'
expect_valid "same-http-and-outbound-tag" '{
  "outbounds":[{"type":"direct","tag":"shared"}],
  "http_clients":[{"tag":"shared","engine":"go"}],
  "route":{"final":"shared","default_http_client":"shared"}
}'
expect_valid "resolved-service-detour" '{
  "inbounds":[{"type":"mixed","tag":"resolved-detour"}],
  "services":[{"type":"resolved","tag":"resolved","listen":"127.0.0.53","listen_port":53,"detour":"resolved-detour"}],
  "outbounds":[{"type":"direct","tag":"direct"}],
  "route":{"final":"direct"}
}'
expect_valid "positional-dns-and-provider-tags" '{
  "inbounds":[{"type":"mixed","tag":"in","tls":{"certificate_provider":"0"}}],
  "outbounds":[{"type":"direct","tag":"direct"}],
  "certificate_providers":[{"type":"acme"}],
  "dns":{"servers":[{"type":"udp","server":"1.1.1.1"}],"final":"0"},
  "route":{"final":"direct","default_domain_resolver":"0"}
}'
expect_valid "dns-matcher-any" '{
  "dns":{"servers":[{"tag":"dns","type":"udp","server":"1.1.1.1"}],"rules":[{"outbound":"any"}]}
}'

# Missing references, malformed fields, invalid selector defaults, and
# dependency cycles must fail closed with fixed, redacted classifications.
expect_invalid "missing-domain-resolver" '{"outbounds":[{"type":"direct","tag":"leaf","server":"name.test","domain_resolver":"missing"}],"route":{"final":"leaf"}}' "unknown reference"
expect_invalid "missing-detour" '{"outbounds":[{"type":"direct","tag":"leaf","detour":"missing"}],"route":{"final":"leaf"}}' "unknown reference"
expect_invalid "selector-default-not-member" '{"outbounds":[{"type":"selector","tag":"sel","outbounds":["leaf"],"default":"missing"},{"type":"direct","tag":"leaf"}]}' "invalid field type"
expect_invalid "empty-urltest-members" '{"outbounds":[{"type":"urltest","tag":"ut","outbounds":[]}]}' "invalid field type"
expect_invalid "outbound-cycle" '{"outbounds":[{"type":"selector","tag":"a","outbounds":["b"]},{"type":"selector","tag":"b","outbounds":["a"]}]}' "dependency cycle"
expect_invalid "dns-ip-resolver-self-cycle" '{"dns":{"servers":[{"tag":"a","type":"udp","server":"1.1.1.1","domain_resolver":"a"}]}}' "dependency cycle"
expect_invalid "dns-resolver-cycle" '{"dns":{"servers":[{"tag":"a","type":"udp","server":"1.1.1.1","domain_resolver":"b"},{"tag":"b","type":"udp","server":"1.1.1.1","domain_resolver":"a"}]}}' "dependency cycle"
expect_invalid "missing-dns-final" '{"dns":{"servers":[{"tag":"dns","type":"udp","server":"1.1.1.1"}],"final":"missing"}}' "unknown reference"
expect_invalid "missing-route-final" '{"outbounds":[{"type":"direct","tag":"direct"}],"route":{"final":"missing"}}' "unknown reference"
expect_invalid "missing-dns-domain-resolver" '{"dns":{"servers":[{"tag":"dns","type":"udp","server":"name.test","domain_resolver":"missing"}]}}' "unknown reference"
expect_invalid "missing-realm-stun-resolver" '{"inbounds":[{"type":"hysteria2","tag":"hy","realm":{"stun_domain_resolver":"missing"}}]}' "unknown reference"
expect_invalid "missing-reality-handshake-detour" '{"inbounds":[{"type":"mixed","tag":"in","tls":{"reality":{"handshake":{"server":"name.test","detour":"missing"}}}}]}' "unknown reference"
expect_invalid "missing-inbound-reference" '{"route":{"rules":[{"inbound":"missing"}]}}' "unknown reference"
expect_invalid "missing-provider-reference" '{"inbounds":[{"type":"mixed","tag":"in","tls":{"certificate_provider":"missing"}}]}' "unknown reference"
expect_invalid "missing-http-reference" '{"route":{"default_http_client":"missing"}}' "unknown reference"
expect_invalid "missing-ruleset-http-client-reference" '{"route":{"rule_set":[{"type":"remote","tag":"remote-rules","format":"source","url":"https://rules.example.test/rules.json","http_client":"missing"}]}}' "unknown reference"
expect_invalid "missing-resolved-service-detour" '{"services":[{"type":"resolved","tag":"resolved","detour":"missing"}]}' "unknown reference"
expect_invalid "missing-ruleset-reference" '{"route":{"rules":[{"rule_set":"missing"}]}}' "unknown reference"
expect_invalid "wrong-role-inbound-detour" '{"inbounds":[{"type":"mixed","tag":"in","detour":"out"}],"outbounds":[{"type":"direct","tag":"out"}]}' "unknown reference"
expect_invalid "route-outbound-array" '{"outbounds":[{"type":"direct","tag":"direct"}],"route":{"rules":[{"outbound":["direct"]}]}}' "invalid field type"
expect_invalid "certificate-http-endpoint-cycle" '{
  "endpoints":[{"type":"openvpn-server","tag":"ep","tls":{"certificate_provider":"cp"}}],
  "certificate_providers":[{"type":"acme","tag":"cp","http_client":"hc"}],
  "http_clients":[{"tag":"hc","detour":"ep"}]
}' "dependency cycle"
expect_invalid "duplicate-component-tag" '{"inbounds":[{"type":"mixed","tag":"same"}],"outbounds":[{"type":"direct","tag":"same"}]}' "duplicate tag"
expect_invalid "duplicate-provider-tag" '{"certificate_providers":[{"type":"acme","tag":"cp"},{"type":"acme","tag":"cp"}]}' "duplicate tag"
expect_invalid "duplicate-http-tag" '{"http_clients":[{"tag":"hc"},{"tag":"hc"}]}' "duplicate tag"
expect_invalid "duplicate-dns-tag" '{"dns":{"servers":[{"tag":"dns","type":"udp","server":"1.1.1.1"},{"tag":"dns","type":"udp","server":"1.1.1.1"}]}}' "duplicate tag"
expect_invalid "duplicate-ruleset-tag" '{"route":{"rule_set":[{"tag":"rs","type":"local"},{"tag":"rs","type":"local"}]}}' "duplicate tag"
expect_invalid "empty-inline-provider" '{"inbounds":[{"type":"mixed","tag":"in","tls":{"certificate_provider":{}}}]}' "invalid field type"
expect_invalid "invalid-component-shape" '{"outbounds":[{"tag":"leaf"}]}' "invalid field type"
expect_invalid "invalid-array-shape" '{"outbounds":"not-an-array"}' "invalid field type"
expect_invalid "invalid-reference-type" '{"outbounds":[{"type":"direct","tag":"leaf","detour":42}]}' "invalid field type"

printf '{}\n{}\n' > "${TEST_DIR}/multiple-json.json"
expect_invalid_file "multiple-json" "${TEST_DIR}/multiple-json.json" "invalid config shape"
printf '{"outbounds":[' > "${TEST_DIR}/malformed-json.json"
expect_invalid_file "malformed-json" "${TEST_DIR}/malformed-json.json" "invalid config shape"

# Optional integration with real target cores.  These two fixtures are kept
# deliberately small and complete: one checks same-tag independent DNS and
# outbound namespaces, while the other checks selector, DNS detour, and
# inline route/DNS rules.  The graph preflight remains the assertion under
# test; core check is an additional compatibility gate when binaries are
# supplied by the verification harness.
jq -n '{
  log:{disabled:true},
  inbounds:[{type:"mixed",tag:"in",listen:"127.0.0.1",listen_port:1080}],
  outbounds:[{type:"direct",tag:"shared"}],
  dns:{servers:[{tag:"shared",type:"udp",server:"1.1.1.1"}],final:"shared"},
  route:{default_domain_resolver:"shared",final:"shared"}
}' > "${TEST_DIR}/core-namespaces.json"
expect_valid_file "core-namespaces" "${TEST_DIR}/core-namespaces.json"
jq -n '{
  log:{disabled:true},
  inbounds:[{type:"mixed",tag:"in",listen:"127.0.0.1",listen_port:1080}],
  outbounds:[
    {type:"selector",tag:"proxy",outbounds:["direct"],default:"direct"},
    {type:"direct",tag:"direct"}
  ],
  dns:{
    servers:[{tag:"dns",type:"udp",server:"1.1.1.1",detour:"direct"}],
    rules:[{inbound:["in"],server:"dns"}]
  },
  route:{
    rules:[{inbound:["in"],action:"route",outbound:"proxy"}],
    default_domain_resolver:"dns",final:"proxy"
  }
}' > "${TEST_DIR}/core-mixed-rules.json"
expect_valid_file "core-mixed-rules" "${TEST_DIR}/core-mixed-rules.json"

core_check() {
  local name=$1
  local file=$2
  local binary_var binary core_status
  for binary_var in SINGBOX_BINARY_113 SINGBOX_BINARY_114; do
    binary=${!binary_var:-}
    [[ -z "${binary}" ]] && continue
    [[ -x "${binary}" ]] || {
      printf '%s is not executable\n' "${binary_var}" >&2
      return 1
    }
    core_status=0
    "${binary}" check -c "${file}" >"${TEST_DIR}/${name}.${binary_var}.stdout" \
      2>"${TEST_DIR}/${name}.${binary_var}.stderr" || core_status=$?
    if [[ ${core_status} -ne 0 ]]; then
      printf 'real core rejected complete fixture %s (%s)\n' "${name}" "${binary_var}" >&2
      return 1
    fi
  done
}

core_check "core-namespaces" "${TEST_DIR}/core-namespaces.json"
core_check "core-mixed-rules" "${TEST_DIR}/core-mixed-rules.json"

printf 'managed component graph tests passed: %s\n' "${pass_count}"
