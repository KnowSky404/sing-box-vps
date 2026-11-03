# Supplemental policy is read as JSON data, never sourced or evaluated.
routing_policy_file_path() {
  printf '%s\n' "${SB_ROUTING_POLICY_FILE:-${SB_PROJECT_DIR}/routing-policy.json}"
}

routing_policy_legacy_validate_json() {
  local policy=${1:-}
  [[ -n "${policy}" && "${#policy}" -le 262144 ]] || return 1
  jq -e '
    def exact($names): type == "object" and (keys | sort) == ($names | sort);
    def safe: type == "string" and (any(explode[]; . < 32 or . == 127) | not);
    def slug: safe and test("^[a-z0-9][a-z0-9_-]{0,63}$");
    def domain: safe and length <= 253 and
      test("^(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$");
    def url: safe and length <= 2048 and
      test("^https://[A-Za-z0-9][A-Za-z0-9.-]*(?::[0-9]{1,5})?(?:/[^[:space:]#]*)?$");
    def path: safe and length <= 4096 and startswith("/") and . != "/" and
      (test("(^|/)\\.\\.?(/|$)") | not);
    def action: IN("direct","warp","reject");
    def interval: safe and test("^[1-9][0-9]{0,7}[smhd]$");
    exact(["schema_version","server","client","adblock"]) and .schema_version == 1 and
    (.server | exact(["private_network_block","adblock","warp_ai","warp_streaming","rules","rule_sets"]) and
      ([.private_network_block,.adblock,.warp_ai,.warp_streaming] | all(.[]; type == "boolean")) and
      (.rules | type == "array" and length <= 128 and
        (map(.id) | unique | length) == length and all(.[];
          exact(["id","kind","value","action","enabled"]) and
          (.id | slug) and (.enabled | type == "boolean") and (.action | action) and
          (.kind | IN("domain","domain_suffix","ip_cidr")) and
          (if .kind == "ip_cidr" then
             (.value | safe and length <= 64 and
               test("^(?:[0-9]{1,3}(?:\\.[0-9]{1,3}){3}/[0-9]{1,2}|[A-Fa-f0-9:]+/[0-9]{1,3})$"))
           else (.value | domain) end))) and
      (.rule_sets | type == "array" and length <= 64 and
        (map(.tag) | unique | length) == length and all(.[];
          (.tag | slug) and (.enabled | type == "boolean") and (.action | action) and
          (.format | IN("binary","source")) and (.update_interval | interval) and
          (if .type == "remote" then
             exact(["tag","type","format","url","action","enabled","update_interval"]) and (.url | url)
           elif .type == "local" then
             exact(["tag","type","format","path","action","enabled","update_interval"]) and (.path | path)
           else false end)))) and
    (.client | exact(["lan_direct","cn_direct","adblock"]) and all(.[]; type == "boolean")) and
    (.adblock | exact(["url","domains","allow"]) and
      (.url == "" or (.url | url)) and
      (.domains | type == "array" and length <= 256 and all(.[]; domain) and (unique | length) == length) and
      (.allow | type == "array" and length <= 256 and all(.[]; domain) and (unique | length) == length)) and
    (if .server.adblock or .client.adblock then (.adblock.url != "" or (.adblock.domains | length) > 0) else true end)
  ' <<< "${policy}" >/dev/null 2>&1
}

# Current policy is server-only. Schema 1 is accepted only to preserve an
# existing installation until its owner explicitly applies the network draft.
routing_policy_validate_json() {
  local policy=${1:-} legacy
  [[ -n "${policy}" && "${#policy}" -le 262144 ]] || return 1
  if jq -e '.schema_version == 1' <<< "${policy}" >/dev/null 2>&1; then
    routing_policy_legacy_validate_json "${policy}"
    return $?
  fi
  jq -e '
    type == "object" and (keys | sort) == ["schema_version","server"] and .schema_version == 2 and
    (.server | type == "object" and
      (keys | sort) == ["block_cn","rule_sets","rules","warp_ai","warp_streaming"] and
      ([.block_cn,.warp_ai,.warp_streaming] | all(.[]; type == "boolean")))
  ' <<< "${policy}" >/dev/null 2>&1 || return 1
  # Reuse the bounded matcher/source validator without exposing legacy fields
  # in persisted current policy or in the user interface.
  legacy=$(jq -c '{schema_version:1,
    server:(.server | del(.block_cn) | . + {private_network_block:false,adblock:false}),
    client:{lan_direct:false,cn_direct:false,adblock:false},adblock:{url:"",domains:[],allow:[]}}' <<< "${policy}") || return 1
  routing_policy_legacy_validate_json "${legacy}"
}

routing_policy_current_json() {
  local policy=${1:-}
  routing_policy_validate_json "${policy}" || return 1
  jq -c 'if .schema_version == 2 then . else
    {schema_version:2,server:{block_cn:false,warp_ai:.server.warp_ai,warp_streaming:.server.warp_streaming,
      rules:.server.rules,rule_sets:.server.rule_sets}} end' <<< "${policy}"
}

routing_policy_read_json() {
  local file=${1:-} policy
  [[ -n "${file}" ]] || file=$(routing_policy_file_path) || return 1
  command -v jq >/dev/null 2>&1 || return 1
  if [[ -e "${file}" || -L "${file}" ]]; then
    [[ -f "${file}" && ! -L "${file}" && "$(wc -c < "${file}")" -le 262144 ]] || return 1
    policy=$(jq -ces 'if length == 1 then .[0] else error("policy_document_count") end' "${file}") || return 1
    routing_policy_validate_json "${policy}" || return 1
    printf '%s\n' "${policy}"
    return 0
  fi
  printf '%s\n' '{"schema_version":2,"server":{"block_cn":false,"warp_ai":true,"warp_streaming":true,"rules":[],"rule_sets":[]}}'
}

routing_policy_prepare_install_defaults() {
  local file policy
  file=$(routing_policy_file_path) || return 1
  SB_OUTBOUND_POLICY=default
  if [[ ! -e "${file}" && ! -L "${file}" && ! -e "${SINGBOX_CONFIG_FILE}" && ! -L "${SINGBOX_CONFIG_FILE}" ]]; then
    # Fresh-install prompts run before the dependency installer prepares jq.
    SB_ADVANCED_ROUTE=n
    SB_ENABLE_WARP=n
    SB_WARP_ROUTE_MODE=selective
    return 0
  fi
  policy=$(routing_policy_read_json) || return 1
  SB_ADVANCED_ROUTE=$(jq -r 'if .server.private_network_block then "y" else "n" end' <<< "${policy}") || return 1
  if [[ -f "${SINGBOX_CONFIG_FILE}" ]]; then
    if config_has_warp_enabled "${SINGBOX_CONFIG_FILE}"; then SB_ENABLE_WARP=y; else SB_ENABLE_WARP=n; fi
    load_warp_route_settings || return 1
  else
    SB_ENABLE_WARP=n
    SB_WARP_ROUTE_MODE=selective
  fi
}

routing_policy_requires_warp() {
  local policy=${1:-}
  if [[ -z "${policy}" ]]; then
    policy=$(routing_policy_read_json) || return 1
  fi
  routing_policy_validate_json "${policy}" || return 1
  jq -e 'any((.server.rules + .server.rule_sets)[]; .enabled and .action == "warp")' <<< "${policy}" >/dev/null
}

routing_policy_legacy_adblock_json() {
  local policy=${1:-} use_http_client=n
  routing_policy_validate_json "${policy}" || return 1
  if singbox_config_supports_1_14; then use_http_client=y; fi
  jq -cn --argjson policy "${policy}"  --arg modern "${use_http_client}" '
    if $policy.schema_version == 1 and $policy.server.adblock then
      ([if $policy.adblock.url != "" then
          {type:"remote",tag:"sbv-adblock-remote",format:(if ($policy.adblock.url | test("\\.json(?:\\?.*)?$")) then "source" else "binary" end),
           url:$policy.adblock.url,update_interval:"1d"} +
          (if $modern == "y" then {http_client:{detour:"direct"}} else {download_detour:"direct"} end)
        else empty end,
        if ($policy.adblock.domains | length) > 0 then
          {type:"inline",tag:"sbv-adblock-inline",rules:[{domain_suffix:$policy.adblock.domains}]}
        else empty end]) as $sets |
      {rule_sets:$sets,rules:[
        (if ($policy.adblock.allow | length) > 0 then
           {type:"logical",mode:"and",rules:[{rule_set:($sets | map(.tag))},{domain_suffix:$policy.adblock.allow,invert:true}]}
         else {rule_set:($sets | map(.tag))} end) + {action:"reject"}]}
    else {rule_sets:[],rules:[]} end'
}

routing_policy_render_server_json() {
  local policy=${1:-} tags=${2:-'[]'} adblock use_http_client=n path
  routing_policy_validate_json "${policy}" || return 1
  jq -e 'type == "array" and all(.[]; type == "string" and length > 0) and (unique | length) == length' <<< "${tags}" >/dev/null || return 1
  while IFS= read -r path; do
    [[ ! -L "${path}" ]] || return 1
  done < <(jq -r '.server.rule_sets[] | select(.enabled and .type == "local") | .path' <<< "${policy}")
  adblock=$(routing_policy_legacy_adblock_json "${policy}") || return 1
  if singbox_config_supports_1_14; then use_http_client=y; fi
  jq -cn --argjson policy "${policy}" --argjson tags "${tags}" --argjson ads "${adblock}" --arg modern "${use_http_client}" '
    def action($value): if $value == "reject" then {action:"reject"} else
      {action:"route",outbound:(if $value == "warp" then "warp-ep" else "direct" end)} end;
    ([$policy.server.rule_sets[] | select(.enabled) |
      {type:.type,tag:("sbv-rule-" + .tag),format:.format} +
      (if .type == "local" then {path:.path} else
         {url:.url,update_interval:.update_interval} +
         (if $modern == "y" then {http_client:{detour:"direct"}} else {download_detour:"direct"} end) end)]) as $sets |
    {inbound:$tags,action:"resolve",server:"local-dns"} as $resolve |
    (if $policy.server.block_cn then
      ["geosite-cn","geoip-cn"] | map(. as $tag |
        {type:"remote",tag:("sbv-block-" + $tag),format:"binary",
         url:("https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/" +
           (if $tag == "geosite-cn" then "geosite" else "geoip" end) + "/cn.srs"),update_interval:"1d"} +
        (if $modern == "y" then {http_client:{detour:"direct"}} else {download_detour:"direct"} end))
     else [] end) as $cn_sets |
    ((if $policy.server.private_network_block then
        [$resolve,
         {ip_is_private:true,action:"reject",inbound:$tags}]
      elif $policy.server.adblock and $policy.adblock.url != "" then
        # Remote content may include IP matchers, even if its name suggests
        # domains. Resolve at this filtering stage before matching its set.
        [$resolve]
      else [] end) +
      (if $policy.server.block_cn then
         [{inbound:$tags,rule_set:["sbv-block-geosite-cn"],action:"reject"},$resolve,
          {inbound:$tags,rule_set:["sbv-block-geoip-cn"],action:"reject"}]
       else [] end) +
      [$ads.rules[] | if .type == "logical" then
         .rules = [{inbound:$tags}] + .rules
       else . + {inbound:$tags} end]) as $protection |
    ([$policy.server.rules[] | select(.enabled) | {inbound:$tags} + {(.kind):[.value]} + action(.action)] +
      [$policy.server.rule_sets[] | select(.enabled) | {inbound:$tags,rule_set:["sbv-rule-" + .tag]} + action(.action)] |
      # Keep earlier domain decisions ahead of DNS. Local/remote sets are
      # opaque and can change content, so every set action needs resolved IPs.
      reduce .[] as $rule
        ({resolved:any($protection[]; .action == "resolve"),rules:[]};
         if (.resolved | not) and ($rule | has("ip_cidr") or has("rule_set")) then
           .resolved = true | .rules += [$resolve,$rule]
         else .rules += [$rule] end) | .rules) as $custom |
    if ($tags | length) == 0 then {rule_sets:[],protection_rules:[],custom_rules:[],rules:[]} else
      {rule_sets:($ads.rule_sets + $cn_sets + $sets),protection_rules:$protection,custom_rules:$custom,rules:($protection + $custom)} end'
}

routing_policy_owned_rule_sets_json() {
  local policy=${1:-} component_state=${2:-} current='[]' baseline='[]' component_tags rendered
  local baseline_file="${SB_PROJECT_DIR}/managed-config.generated.json"
  if [[ -z "${policy}" ]]; then policy=$(routing_policy_read_json) || return 1; fi
  if [[ -z "${component_state}" ]]; then component_state=$(managed_component_state_json) || return 1; fi
  component_tags=$(jq -c '[.components[]? | select(.role == "rule_set") | .tag]' <<< "${component_state}") || return 1
  rendered=$(routing_policy_render_server_json "${policy}" '["ownership-projection"]') || return 1
  current=$(jq -c '.rule_sets' <<< "${rendered}") || return 1
  # Existing component names remain valid even if they predate this namespace.
  # A new policy declaration may not take over any registered component tag.
  jq -e --argjson tags "${component_tags}" 'all(.[]; .tag as $tag | $tags | index($tag) == null)' \
    <<< "${current}" >/dev/null || return 1
  if [[ -e "${baseline_file}" || -L "${baseline_file}" ]]; then
    [[ -f "${baseline_file}" && ! -L "${baseline_file}" && "$(stat -c %a "${baseline_file}")" == 600 ]] || return 1
    baseline=$(jq -ce --argjson component_tags "${component_tags}" '[.route.rule_set[]? |
      select((.tag // "") | test("^sbv-(block-(geosite|geoip)-cn|adblock-(inline|remote)|rule-[a-z0-9][a-z0-9_-]{0,63})$")) |
      select(.tag as $tag | $component_tags | index($tag) == null)]' "${baseline_file}") || return 1
  fi
  jq -cn --argjson current "${current}" --argjson baseline "${baseline}" '$current + $baseline | unique'
}

routing_policy_warp_rules_json() {
  local policy=${1:-} tags=${2:-'[]'}
  routing_policy_validate_json "${policy}" || return 1
  jq -cn --argjson policy "${policy}" --argjson tags "${tags}" \
    --arg enabled "${SB_ENABLE_WARP:-n}" --arg mode "${SB_WARP_ROUTE_MODE:-selective}" \
    --argjson ai_domains "${WARP_AI_ROUTE_DOMAINS_JSON}" --argjson ai_suffixes "${WARP_AI_ROUTE_DOMAIN_SUFFIXES_JSON}" \
    --argjson media_domains "${WARP_STREAM_ROUTE_DOMAINS_JSON}" --argjson media_suffixes "${WARP_STREAM_ROUTE_DOMAIN_SUFFIXES_JSON}" \
    --argjson custom_domains "${SB_WARP_CUSTOM_DOMAINS_JSON:-[]}" --argjson custom_suffixes "${SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON:-[]}" \
    --argjson warp_sets "${SB_WARP_RULE_SET_TAGS_JSON:-[]}" '
    if $enabled == "y" and $mode == "selective" and ($tags | length) > 0 then
      (if ($custom_domains | length) > 0 or ($custom_suffixes | length) > 0 then
         [{inbound:$tags,domain:$custom_domains,domain_suffix:$custom_suffixes,action:"route",outbound:"warp-ep"}]
       else [] end) +
      (if ($warp_sets | length) > 0 then
         [{inbound:$tags,rule_set:$warp_sets,action:"route",outbound:"warp-ep"}]
       else [] end) +
      (if $policy.server.warp_ai then
         [{inbound:$tags,domain:$ai_domains,domain_suffix:$ai_suffixes,action:"route",outbound:"warp-ep"}]
       else [] end) +
      (if $policy.server.warp_streaming then
         [{inbound:$tags,domain:$media_domains,domain_suffix:$media_suffixes,action:"route",outbound:"warp-ep"}]
       else [] end)
    else [] end'
}

# A state record proves only the exact binding it declares. A same-tag route
# with another outbound policy remains operator content, even in simple form.
routing_policy_nodes_inventory_json() {
  local nodes=$1
  jq -ce '
    select(type == "array" and all(.[];
      (.tag | type == "string" and length > 0) and (.policy | IN("default","direct","warp"))) and
      (map(.tag) | unique | length) == length) |
    {tags:(map(.tag) | sort),bindings:[.[] | . as $node |
      {inbound:$node.tag,action:"sniff"},
      (if $node.policy == "default" then empty else
         {inbound:$node.tag,action:"route",outbound:(if $node.policy == "warp" then "warp-ep" else "direct" end)} end)]}
  ' <<< "${nodes}"
}

routing_policy_store_inventory_json() {
  local protocol=$1 store=$2 nodes
  [[ -f "${store}" && ! -L "${store}" ]] || return 1
  nodes=$(jq -ce --arg protocol "${protocol}" '.instances | select(type == "array") |
    map({tag:(if $protocol == "shadowtls" then .detour.tag else .tag end),policy:(.outbound_policy // "default")})' "${store}") || return 1
  routing_policy_nodes_inventory_json "${nodes}"
}

# Virtual legacy imports derive policy from live rules; only a persisted store
# (or its transaction snapshot) proves state authority. Otherwise fixed rules
# need an exact prior generated record, excluding component-owned declarations.
routing_policy_old_store_inventory_json() {
  local protocol=$1 store=$2 inventory proof snapshot marker baseline component_rules='[]' baseline_rules='[]'
  inventory=$(routing_policy_store_inventory_json "${protocol}" "${store}") || return 1
  if jq -e 'all(.bindings[]; .action != "route")' <<< "${inventory}" >/dev/null; then
    printf '%s\n' "${inventory}"
    return 0
  fi
  proof=$(plain_proxy_structured_store_file "${protocol}") || return 1
  if plain_proxy_structured_state_active "${protocol}" &&
     jq -es 'length==2 and .[0]==.[1]' "${store}" "${proof}" >/dev/null; then
    printf '%s\n' "${inventory}"
    return 0
  fi
  snapshot="${SB_PROJECT_DIR}.instance-write.lock/snapshot"
  proof="${snapshot}/project/protocols/instances/${protocol}.json"
  marker="${snapshot}/project/protocols/${protocol}.env"
  if managed_state_snapshot_is_valid "${snapshot}" && plain_proxy_structured_marker_is_valid "${marker}" &&
     [[ -f "${proof}" && ! -L "${proof}" && "$(stat -c %a "${proof}")" == 600 ]] &&
     validate_structured_instance_store "${protocol}" "${proof}" &&
     jq -es 'length==2 and .[0]==.[1]' "${store}" "${proof}" >/dev/null; then
    printf '%s\n' "${inventory}"
    return 0
  fi
  baseline="${SB_PROJECT_DIR}/managed-config.generated.json"
  if [[ -e "${baseline}" || -L "${baseline}" ]]; then
    [[ -f "${baseline}" && ! -L "${baseline}" && "$(stat -c %a "${baseline}")" == 600 ]] || return 1
    baseline_rules=$(jq -c '.route.rules // []' "${baseline}") || return 1
  fi
  component_rules=$(managed_component_render_json | jq -c '.route_rules') || return 1
  jq -c --argjson baseline "${baseline_rules}" --argjson components "${component_rules}" '
    .bindings |= map(. as $rule | select(.action == "sniff" or
      (($baseline | index($rule)) != null and ($components | index($rule)) == null)))
  ' <<< "${inventory}"
}

# Read only registered protocol state. Never infer ownership from an inbound
# type or a user-selected tag prefix; another same-protocol listener is manual.
routing_policy_registered_inventory_json() (
  local skip=${1:-} protocol schema state_file snapshot ids instance_id tag
  local protocols='' nodes='[]' fragment policy
  protocols=$(list_installed_protocols_read_only) || return 1
  while IFS= read -r protocol; do
    [[ -n "${protocol}" && "${protocol}" != "${skip}" ]] || continue
    schema=$(protocol_instance_state_schema "${protocol}") || return 1
    case "${protocol}:${schema}" in
      vless-reality:2)
        ids=$(list_vless_reality_managed_instance_ids) || return 1
        load_vless_reality_protocol_state || return 1
        fragment='[]'
        while IFS= read -r instance_id; do
          [[ -n "${instance_id}" ]] || continue
          load_vless_reality_instance_state "${instance_id}" || return 1
          tag=$(vless_reality_inbound_tag_for_instance "${instance_id}") || return 1
          policy=${SB_OUTBOUND_POLICY:-default}
          fragment=$(jq -cn --argjson nodes "${fragment}" --arg tag "${tag}" --arg policy "${policy}" \
            '$nodes + [{tag:$tag,policy:$policy}]') || return 1
        done <<< "${ids}"
        ;;
      *:2)
        state_file=$(plain_proxy_structured_store_file "${protocol}") || return 1
        snapshot=$(structured_instance_store_snapshot_json "${protocol}" "${state_file}") || return 1
        fragment=$(jq -c --arg protocol "${protocol}" '[.instances[] |
          {tag:(if $protocol == "shadowtls" then .detour.tag else .tag end),policy:.outbound_policy}]' <<< "${snapshot}") || return 1
        ;;
      vless-reality:1|mixed:1|hy2:1|anytls:1)
        tag=$(protocol_inbound_tag "${protocol}") || return 1
        fragment=$(jq -cn --arg tag "${tag}" '[{tag:$tag,policy:"default"}]') || return 1
        ;;
      *) return 1 ;;
    esac
    nodes=$(jq -cn --argjson nodes "${nodes}" --argjson more "${fragment}" '$nodes + $more') || return 1
  done <<< "${protocols}"
  routing_policy_nodes_inventory_json "${nodes}"
)

routing_policy_registered_tags_json() {
  local inventory
  inventory=$(routing_policy_registered_inventory_json "${1:-}") || return 1
  jq -c '.tags' <<< "${inventory}"
}

# The legacy producer below this boundary rewrites simple target bindings.
# Refuse unknown/duplicate records before it can prune them, and refuse missing
# declared bindings instead of recreating a foreign protocol's operator edit.
routing_policy_precheck_instance_candidate() (
  local protocol=$1 old_config=$2 old_store=$3 new_store=$4 file other old new policy tags rendered warp exceptions
  file=$(routing_policy_file_path) || return 1
  [[ -e "${file}" || -L "${file}" ]] || return 0
  policy=$(routing_policy_read_json) || return 1
  [[ -f "${old_config}" && ! -L "${old_config}" ]] || return 1
  other=$(routing_policy_registered_inventory_json "${protocol}") || return 1
  old=$(routing_policy_old_store_inventory_json "${protocol}" "${old_store}") || return 1
  new=$(routing_policy_store_inventory_json "${protocol}" "${new_store}") || return 1
  tags=$(jq -cn --argjson other "${other}" --argjson old "${old}" '$other.tags + $old.tags | unique') || return 1
  rendered=$(routing_policy_render_server_json "${policy}" "${tags}") || return 1
  routing_policy_projection_assets_load || return 1
  warp=$(routing_policy_warp_rules_json "${policy}" "${tags}") || return 1
  exceptions=$(routing_policy_baseline_protocol_rules_json) || return 1
  jq -e --argjson other "${other}" --argjson old "${old}" --argjson new "${new}" \
    --argjson tags "${tags}" --argjson rendered "${rendered}" --argjson warp "${warp}" --argjson exceptions "${exceptions}" '
    def simple_binding:
      (.inbound | type) == "string" and
      ((.action == "sniff" and (keys | sort) == ["action","inbound"]) or
       (.action == "route" and (.outbound | IN("direct","warp-ep")) and
        (keys | sort) == ["action","inbound","outbound"]));
    (.route.rules // []) as $rules |
    ($other.bindings + $old.bindings) as $known |
    ([$exceptions[] | . as $rule | select(($rules | index($rule)) != null)]) as $protocol_rules |
    ($rendered.rules + $warp) as $policy_rules |
    ([$tags[] | {inbound:.,action:"sniff"}] + $rendered.protection_rules +
      ([$known[] | select(.action == "route")] | sort_by(.inbound)) +
      $protocol_rules + $rendered.custom_rules + $warp) as $expected |
    ($known + $policy_rules + $protocol_rules) as $owned |
    ($old.tags + $new.tags | unique) as $affected |
    (($other.tags + $old.tags | unique | length) == ($other.tags + $old.tags | length)) and
    (($other.tags + $new.tags | unique | length) == ($other.tags + $new.tags | length)) and
    all($known[]; . as $rule | [$rules[] | select(. == $rule)] | length == 1) and
    all($policy_rules[]; . as $rule | [$rules[] | select(. == $rule)] | length == 1) and
    ([$rules[] | . as $rule | select(($owned | index($rule)) != null)] == $expected) and
    all($rules[] | select(simple_binding and (.inbound as $tag | $affected | index($tag) != null));
      . as $rule | ($old.bindings | index($rule)) != null)
  ' "${old_config}" >/dev/null || {
    printf '[ERROR] routing_policy_instance_projection_conflict: 入口绑定归属缺失、重复或包含未声明手工规则；配置未发布。\n' >&2
    return 1
  }
)

routing_policy_projection_assets_load() {
  # These readers update shell variables/private temporary files only.
  load_config_generation_settings "${SINGBOX_CONFIG_FILE}" || return 1
  build_custom_warp_domain_json || return 1
  build_local_warp_rule_sets_json || return 1
  build_remote_warp_rule_sets_json || return 1
  build_warp_rule_set_tags_json || return 1
}

routing_policy_baseline_protocol_rules_json() {
  local baseline="${SB_PROJECT_DIR}/managed-config.generated.json"
  if [[ ! -e "${baseline}" && ! -L "${baseline}" ]]; then printf '[]\n'; return 0; fi
  [[ -f "${baseline}" && ! -L "${baseline}" && "$(stat -c %a "${baseline}")" == 600 ]] || return 1
  jq -c '[.route.rules[]? | select(.action == "direct" and (keys | sort) == ["action","domain"])]' "${baseline}"
}

# Tag labels enumerate generated rules; they do not prove an arbitrary manual
# matcher is disjoint. Inversion negates all conditions, and logical children
# may match managed traffic regardless of an apparent outer inbound label.
routing_policy_rule_scope_jq() {
  cat <<'JQ'
    def routing_rule_action:
      (.action // "") | if . == "" then "route" else . end;
    def routing_rule_terminal:
      routing_rule_action | IN("route","direct","reject","hijack-dns","bypass");
    def routing_positive_inbound_tag($tags):
      .inbound as $in |
        if ($in | type) == "string" then ($tags | index($in)) != null
        elif ($in | type) == "array" then any($in[]; . as $tag | ($tags | index($tag)) != null)
        else false end;
    def routing_rule_tagged($tags):
      .invert != true and
      (if .type == "logical" then
         .mode == "and" and (.rules | type) == "array" and (.rules | length) > 0 and
         (.rules[0] | (keys == ["inbound"]) and routing_positive_inbound_tag($tags))
       else routing_positive_inbound_tag($tags) end);
    def routing_rule_may_overlap($tags):
      if ($tags | length) == 0 then false
      elif .invert == true then true
      elif .type == "logical" then
        if (.rules | type) != "array" or (.rules | length) == 0 then true
        elif .mode == "and" then all(.rules[]; routing_rule_may_overlap($tags))
        elif .mode == "or" then any(.rules[]; routing_rule_may_overlap($tags))
        else true end
      elif (.type // "default" | IN("", "default") | not) then true
      else .inbound as $in |
        if ($in | type) == "string" and ($in | length) > 0 then ($tags | index($in)) != null
        elif ($in | type) == "array" and ($in | length) > 0 and all($in[]; type == "string" and length > 0) then
          any($in[]; . as $tag | ($tags | index($tag)) != null)
        else true end
      end;
JQ
}

routing_policy_project_instance_candidate() (
  local protocol=${1:-} old_store=${2:-} new_store=${3:-} file policy candidate other old new old_tags new_tags old_bindings new_bindings
  local old_render new_render old_warp new_warp baseline_rules='[]'
  file=$(routing_policy_file_path) || return 1
  if [[ ! -e "${file}" && ! -L "${file}" ]]; then cat; return $?; fi
  [[ -f "${old_store}" && ! -L "${old_store}" && -f "${new_store}" && ! -L "${new_store}" ]] || return 1
  policy=$(routing_policy_read_json) || return 1
  candidate=$(cat) || return 1
  [[ "${#candidate}" -le 4194304 ]] || return 1
  other=$(routing_policy_registered_inventory_json "${protocol}") || return 1
  old=$(routing_policy_old_store_inventory_json "${protocol}" "${old_store}") || return 1
  new=$(routing_policy_store_inventory_json "${protocol}" "${new_store}") || return 1
  old_tags=$(jq -cn --argjson other "${other}" --argjson old "${old}" '$other.tags + $old.tags | unique') || return 1
  new_tags=$(jq -cn --argjson other "${other}" --argjson new "${new}" '$other.tags + $new.tags | unique') || return 1
  old_bindings=$(jq -cn --argjson other "${other}" --argjson old "${old}" '$other.bindings + $old.bindings') || return 1
  new_bindings=$(jq -cn --argjson other "${other}" --argjson new "${new}" '$other.bindings + $new.bindings') || return 1
  old_render=$(routing_policy_render_server_json "${policy}" "${old_tags}") || return 1
  new_render=$(routing_policy_render_server_json "${policy}" "${new_tags}") || return 1
  routing_policy_projection_assets_load || return 1
  old_warp=$(routing_policy_warp_rules_json "${policy}" "${old_tags}") || return 1
  new_warp=$(routing_policy_warp_rules_json "${policy}" "${new_tags}") || return 1
  baseline_rules=$(routing_policy_baseline_protocol_rules_json) || return 1
  jq --argjson old_tags "${old_tags}" --argjson new_tags "${new_tags}" \
    --argjson old_bindings "${old_bindings}" --argjson new_bindings "${new_bindings}" \
    --argjson old_render "${old_render}" --argjson new_render "${new_render}" \
    --argjson old_warp "${old_warp}" --argjson new_warp "${new_warp}" --argjson exceptions "${baseline_rules}" "$(routing_policy_rule_scope_jq)"'
    def conflict: error("routing_policy_instance_projection_conflict");
    def binding:
      . as $rule | ($old_bindings + $new_bindings | index($rule)) != null;
    def overlaps: routing_rule_may_overlap($old_tags + $new_tags);
    ($old_render.rules + $old_warp) as $old_policy_rules |
    def owned:
      . as $rule | binding or ($old_policy_rules | index($rule)) != null or ($exceptions | index($rule)) != null;
    def existing_owned:
      . as $rule |
      ($old_bindings | index($rule)) != null or
      ($old_policy_rules | index($rule)) != null or ($exceptions | index($rule)) != null;
    (.route.rules // []) as $rules |
    if all($old_policy_rules[]; . as $expected | [$rules[] | select(. == $expected)] | length == 1) | not then conflict else . end |
    ($rules | to_entries) as $entries |
    ([$entries[] | select(.value | existing_owned) | .key]) as $positions |
    ($positions | min // ($rules | length)) as $at |
    ($positions | max // -1) as $last |
    if ($positions | length) == 0 and
       any($entries[]; .key < $at and (.value | (owned | not) and routing_rule_terminal and overlaps)) then conflict else . end |
    if any($entries[]; .key < $last and (.value | (owned | not) and routing_rule_terminal and overlaps)) then conflict else . end |
    # Rebuilding one contiguous owned chain must not move an interleaved
    # operator rule across an existing owned anchor, even for another listener.
    if any($entries[]; .key > $at and .key < $last and (.value | owned | not)) then conflict else . end |
    ([$rules[] | select(.action == "route" and (. as $rule | $new_bindings | index($rule) != null))]) as $fixed |
    if ($fixed | map(.inbound) | unique | length) != ($fixed | length) then conflict else . end |
    ([$rules[] | select(. as $rule | ($exceptions | index($rule)) != null)]) as $protocol_rules |
    ([$new_tags[] | {inbound:.,action:"sniff"}] + $new_render.protection_rules +
      ($fixed | sort_by(.inbound)) + $protocol_rules + $new_render.custom_rules + $new_warp) as $next_rules |
    .route.rules = ([$rules[:$at][] | select(owned | not)] + $next_rules +
      [$rules[$at:][] | select(owned | not)]) |
    (.route.rule_set // []) as $sets |
    if all($old_render.rule_sets[]; . as $expected | [$sets[] | select(. == $expected)] | length == 1) | not then conflict else . end |
    ([$sets[] | select(. as $set | ($old_render.rule_sets | index($set)) == null)]) as $retained_sets |
    if any($retained_sets[]; .tag as $tag | any($new_render.rule_sets[]; .tag == $tag)) then conflict else . end |
    .route.rule_set = ($retained_sets + $new_render.rule_sets)
  ' <<< "${candidate}" || {
    printf '[ERROR] routing_policy_instance_projection_conflict: 节点变化无法保留现有规则归属和优先级；配置未发布。\n' >&2
    return 1
  }
)

# Ordered three-way merging appends previously unseen rules. Place only rules
# absent from BOTH the trusted baseline and original live config at the nearest
# existing generated anchor. Every original live rule keeps its relative order.
routing_policy_place_new_generated_rules() {
  local generated=$1 merged=$2 baseline=$3 live=$4 tags=$5
  if [[ ! -e "${baseline}" && ! -L "${baseline}" ]]; then cat -- "${merged}"; return $?; fi
  [[ -f "${baseline}" && ! -L "${baseline}" && "$(stat -c %a "${baseline}")" == 600 ]] || return 1
  jq --slurpfile generated "${generated}" --slurpfile baseline "${baseline}" --slurpfile live "${live}" \
    --argjson tags "${tags}" "$(routing_policy_rule_scope_jq)"'
    def conflict: error("routing_policy_order_conflict");
    def scoped: routing_rule_tagged($tags);
    def terminal: routing_rule_terminal;
    ($baseline[0].route.rules // []) as $prior |
    ($live[0].route.rules // []) as $original |
    [$generated[0].route.rules[]? | select(scoped)] as $expected |
    [$expected[] | . as $rule | select(($prior | index($rule)) == null and ($original | index($rule)) == null)] as $new |
    if ($new | length) == 0 then . else
      # A manual terminal rule for managed traffic is a conflict regardless of
      # its current position. Do not make it appear safe by inserting ahead.
      if any($original[]; . as $rule | ($prior | index($rule)) == null and terminal and
        routing_rule_may_overlap($tags)) then conflict else . end |
      (.route.rules // []) as $merged |
      if any($new[]; . as $rule | [$merged[] | select(. == $rule)] | length != 1) then conflict else . end |
      [$merged[] | . as $rule | select(($new | index($rule)) == null)] as $retained |
      if ([$retained[] | . as $rule | select(($expected | index($rule)) != null)]) !=
         ([$expected[] | . as $rule | select(($new | index($rule)) == null)]) then conflict else . end |
      .route.rules = (reduce range(0; $expected | length) as $i ($retained;
        $expected[$i] as $rule |
        if ($new | index($rule)) == null then . else
          . as $current |
          ([$expected[$i+1:][] | . as $next | $current | index($next) | select(. != null)][0]) as $next_at |
          (if $next_at != null then $next_at else
            ([$expected[:$i][] | . as $previous | $current | index($previous) | select(. != null)] | max // (($current | length) - 1)) + 1
           end) as $at |
          $current[:$at] + [$rule] + $current[$at:]
        end))
    end
  ' "${merged}" || {
    printf '[ERROR] routing_policy_order_conflict: 手工或组件规则与新增受管规则存在优先级冲突；配置未发布。\n' >&2
    return 1
  }
}

routing_policy_validate_merged_order() {
  local generated=${1:-} merged=${2:-} tags=${3:-'[]'}
  jq -e --slurpfile expected "${generated}" --argjson tags "${tags}" "$(routing_policy_rule_scope_jq)"'
    def scoped: routing_rule_tagged($tags);
    def terminal: routing_rule_terminal;
    def ad_match: (.rule_set // [] | if type == "string" then [.] else . end) as $sets |
      any($sets[]; startswith("sbv-adblock-") or startswith("sbv-block-")) or any(.rules[]?; ad_match);
    [$expected[0].route.rules[]? | select(scoped)] as $owned |
    def owned: . as $rule | ($owned | index($rule)) != null;
    [.route.rules[]? | select(owned)] == $owned and
    (.route.rules // [] | to_entries) as $entries |
    ([$entries[] | select(.value | owned and .action == "reject" and (.ip_is_private == true or ad_match)) | .key] | max // -1) as $last_filter |
    all($entries[] | select(.key < $last_filter);
      .value as $rule |
      (($rule | terminal) | not) or
      # Ownership preserves a rule; it cannot let a component route managed
      # traffic around protection. Rejection and DNS handling remain safe.
      (($rule | owned) and ($rule | routing_rule_action | IN("reject","hijack-dns"))) or
      (($rule | routing_rule_may_overlap($tags)) | not))
  ' "${merged}" >/dev/null 2>&1 || {
    printf '[ERROR] routing_policy_order_conflict: 手工或组件规则与受管节点的过滤优先级冲突；配置未发布。\n' >&2
    return 1
  }
}

# Typed mutations publish their own candidate instead of running generate_config.
# Advance the pure generated projection in the same instance transaction so a
# later global merge can distinguish the typed change from operator edits.
# Never seed this record from live configuration: it may contain manual fields.
routing_policy_sync_instance_baseline() (
  local protocol=${1:-} old_store=${2:-} new_store=${3:-} file candidate='' validation_candidate=''
  local baseline_file="${SB_PROJECT_DIR}/managed-config.generated.json"
  file=$(routing_policy_file_path) || return 1
  [[ -e "${file}" || -L "${file}" ]] || return 0
  [[ -e "${baseline_file}" || -L "${baseline_file}" ]] || return 0
  [[ -f "${baseline_file}" && ! -L "${baseline_file}" &&
     "$(stat -c %a "${baseline_file}")" == 600 ]] || return 1
  candidate=$(storage_mktemp "${SB_PROJECT_DIR}/.managed-config.generated.candidate.XXXXXX") || return 1
  trap '[[ -z "${candidate}" ]] || rm -f -- "${candidate}"; [[ -z "${validation_candidate}" ]] || rm -f -- "${validation_candidate}"' EXIT
  plain_proxy_instance_config_candidate "${protocol}" "${baseline_file}" "${old_store}" "${new_store}" \
    > "${candidate}" || return 1
  # Generated facts may legitimately refer to operator objects omitted from
  # this ownership record. Validate in the complete already-published context,
  # while persisting only the pure projection below.
  validation_candidate=$(storage_mktemp "${SB_PROJECT_DIR}/.managed-config.validation.candidate.XXXXXX") || return 1
  chmod 600 "${validation_candidate}" || return 1
  merge_generated_config_with_live "${candidate}" "${SINGBOX_CONFIG_FILE}" "${baseline_file}" \
    > "${validation_candidate}" || return 1
  jq -es 'length == 2 and .[0] == .[1]' "${validation_candidate}" "${SINGBOX_CONFIG_FILE}" >/dev/null || {
    printf '[ERROR] routing_policy_baseline_context_conflict: 生成基线与已校验运行配置的上下文不一致；基线未发布。\n' >&2
    return 1
  }
  validate_managed_component_graph "${validation_candidate}" || return 1
  validate_managed_listener_resources "${validation_candidate}" || return 1
  "${SINGBOX_BIN_PATH}" check -c "${validation_candidate}" >&2 || return 1
  chmod 600 "${candidate}" || return 1
  persist_file_backup "${baseline_file}" "${baseline_file}.bak" || return 1
  mv -f -- "${candidate}" "${baseline_file}" || return 1
  candidate=''
)
