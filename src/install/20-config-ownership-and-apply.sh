
managed_component_live_config_root_fields_supported() {
  local config_file=${1:-}
  [[ -f "${config_file}" && ! -L "${config_file}" ]] || return 1
  # The normal server generator owns only these root namespaces.  Reject any
  # additional namespace before a rebuild so an operator's service, cache,
  # HTTP-client or other unmodelled settings cannot be silently discarded by
  # the projection below.  Route rule-sets are checked separately because
  # they live below the generator-owned route namespace.
  jq -e '
    if type != "object" then
      false
    else
      . as $root |
      (["log","dns","endpoints","inbounds","outbounds","route","certificate_providers","http_clients","services","network_namespaces"]) as $owned |
      if ($owned | any(.[]; . as $key | ($root | has($key)))) then
        (($root | keys) - $owned | length == 0)
      else
        true
      end
    end
  ' "${config_file}" >/dev/null 2>&1
}

managed_component_live_route_rule_sets_match_state() {
  local config_file=${1:-} state=${2:-} allow_legacy_download_detour=${3:-false} policy_sets
  [[ -f "${config_file}" && ! -L "${config_file}" && -n "${state}" ]] || return 1
  [[ "${allow_legacy_download_detour}" == true || "${allow_legacy_download_detour}" == false ]] || return 1
  managed_component_state_validate_json "${state}" || return 1
  policy_sets=$(routing_policy_owned_rule_sets_json "" "${state}") || return 1
  jq -e --argjson state "${state}" --argjson policy_sets "${policy_sets}" \
    --argjson allow_legacy_download_detour "${allow_legacy_download_detour}" '
    def safe_string:
      type == "string" and length <= 4096 and
      (any(explode[]; . < 32 or . == 127) | not);
    def warp_tag($tag):
      ($tag | startswith("warp-local-") or startswith("warp-remote-"));
    def policy_owned: . as $set | any($policy_sets[]; . == $set);
    def legacy_download_detour($set):
      $allow_legacy_download_detour and
      ($set.type == "remote") and
      ($set | has("download_detour")) and
      ((($set.tag // "") == "") or
        (($set.tag | safe_string and length > 0) and
          (($set.tag | startswith("warp-") | not) or ($set.tag | startswith("warp-remote-"))) and
          (any($state.components[]?;
            .role == "rule_set" and .enabled == true and .tag == $set.tag) | not)));
    type == "object" and
    ((has("route") | not) or (.route | type == "object")) and
    (.route // {}) as $route |
    ($route | ((has("rule_set") | not) or (.rule_set | type == "array"))) and
    ($route.rule_set // []) as $sets |
    ($sets | type == "array" and length <= 128) and
    ([ $sets[] | select((legacy_download_detour(.) | not) or ((.tag // "") != "")) | .tag ] | unique | length) ==
      ([ $sets[] | select((legacy_download_detour(.) | not) or ((.tag // "") != "")) ] | length) and
    all($sets[];
      . as $set |
      type == "object" and
      ($set.type | type == "string" and IN("inline","local","remote")) and
      (if legacy_download_detour($set) then
         ((($set.tag // "") == "") or ($set.tag | safe_string and length > 0))
       else
         ($set.tag | safe_string and length > 0)
       end) and
      (if legacy_download_detour($set) then
         true
       elif ($set | policy_owned) then
         true
       elif warp_tag($set.tag) then
         ((($set.tag | startswith("warp-local-")) and $set.type == "local") or
          (($set.tag | startswith("warp-remote-")) and $set.type == "remote"))
       else
         any($state.components[]?;
           .role == "rule_set" and .enabled == true and
           .type == $set.type and .tag == $set.tag and
           ((.config + {type:.type,tag:.tag}) == $set))
       end)) and
    ([$state.components[]? |
      select(.role == "rule_set" and .enabled == true)] | length) ==
    ([$sets[] | select((warp_tag(.tag // "") | not) and (legacy_download_detour(.) | not) and (policy_owned | not))] | length)
  ' "${config_file}" >/dev/null 2>&1
}

managed_component_live_route_rule_sets_supported() {
  local config_file=${1:-} prior_state_file=${2:-} state snapshot_dir
  [[ -f "${config_file}" && ! -L "${config_file}" ]] || return 1
  if [[ -n "${prior_state_file}" ]]; then
    snapshot_dir=${prior_state_file%/project/components.json}
    [[ "${prior_state_file}" == "${snapshot_dir}/project/components.json" ]] || return 1
    managed_state_snapshot_is_valid "${snapshot_dir}" || return 1
    if [[ -f "${prior_state_file}" && ! -L "${prior_state_file}" &&
          -r "${prior_state_file}" ]]; then
      state=$(jq -cS '.' "${prior_state_file}") || return 1
      managed_component_state_validate_json "${state}" || return 1
    elif [[ ! -e "${prior_state_file}" ]]; then
      state=$(managed_component_state_default_json) || return 1
    else
      return 1
    fi
  else
    state=$(managed_component_state_json) || return 1
  fi
  managed_component_live_route_rule_sets_match_state "${config_file}" "${state}"
}

managed_component_live_services_supported() {
  local config_file=${1:-} state service_types
  [[ -f "${config_file}" && ! -L "${config_file}" ]] || return 1
  state=$(managed_component_state_json) || return 1
  service_types=$(component_registry_static_json | jq -c '[.[] | select(.role == "service") | .type]') || return 1
  jq -e --argjson state "${state}" --argjson service_types "${service_types}" '
    def safe_string:
      type == "string" and length <= 4096 and
      (any(explode[]; . < 32 or . == 127) | not);
    if has("services") then
      (.services) as $services |
      ($services | type == "array" and length <= 128 and
        ([.[]?.tag] | unique | length) == ([.[]?.tag] | length) and
        all(.[]?;
          . as $service |
          type == "object" and
          (($service.type | type == "string") and
           (($service_types | index($service.type)) != null)) and
          ($service.tag | safe_string and length > 0) and
          any($state.components[]?;
            .role == "service" and .type == ($service.type // "") and
            .tag == ($service.tag // "") and .enabled == true and
            ((.config + {type:.type,tag:.tag}) == $service))) and
        ([ $state.components[]? |
           select(.role == "service" and .enabled == true) ] |
          length == ($services | length)))
    else
      ([ $state.components[]? |
         select(.role == "service" and .enabled == true) ] |
        length == 0)
    end
  ' "${config_file}" >/dev/null 2>&1
}

managed_component_live_config_projection_supported() {
  local config_file=${1:-} prior_state_file=${2:-} state
  [[ -f "${config_file}" && ! -L "${config_file}" ]] || return 1
  managed_component_live_config_root_fields_supported "${config_file}" || return 1
  managed_component_live_route_rule_sets_supported "${config_file}" "${prior_state_file}" || return 1
  state=$(managed_component_state_json) || return 1
  jq -e '
    if has("dns") then
      (.dns | type == "object" and
        ((keys - ["servers","strategy"]) | length == 0) and
        (.servers | type == "array" and length == 1 and
          .[0] == {type:"local",tag:"local-dns"}) and
        (.strategy | type == "string" and
          IN("ipv4_only","ipv6_only","prefer_ipv4","prefer_ipv6")))
    else true end
  ' "${config_file}" >/dev/null 2>&1 || return 1
  managed_component_live_services_supported "${config_file}" || return 1
  jq -e --argjson state "${state}" '
    if has("route") then
      (.route | type == "object" and
        ((keys - ["rule_set","rules","final","auto_detect_interface","default_interface","default_http_client"]) | length == 0) and
        ((has("default_http_client") | not) or
          (.default_http_client as $client |
            ($client | type == "string" and
              (any(explode[]; . < 32 or . == 127) | not)) and
            (($client == "") or
              any($state.components[]?;
                .role == "http_client" and .type == "shared" and
                .tag == $client and .enabled == true)))))
    else true end
  ' "${config_file}" >/dev/null 2>&1 || return 1
  jq -e --argjson state "${state}" '
    if has("http_clients") then
      (.http_clients) as $client_objects |
      ($client_objects | type == "array" and length <= 128 and
        ([.[]?.tag] | unique | length) == length and
        all(.[]?;
          . as $client |
          type == "object" and
          (.tag | type == "string" and length > 0 and
            (any(explode[]; . < 32 or . == 127) | not)) and
          any($state.components[]?;
            .role == "http_client" and .type == "shared" and
            .tag == ($client.tag // "") and .enabled == true and
            ((.config + {tag:.tag}) == $client))) and
        ([ $state.components[]? |
           select(.role == "http_client" and .type == "shared" and .enabled == true) ] |
          length == ($client_objects | length)))
    else
      ([ $state.components[]? |
         select(.role == "http_client" and .type == "shared" and .enabled == true) ] |
        length == 0)
    end
  ' "${config_file}" >/dev/null 2>&1 || return 1
  jq -e --argjson state "${state}" '
    if has("certificate_providers") then
      .certificate_providers as $provider_objects |
      if ($provider_objects | type) != "array" then
        false
      elif (any($provider_objects[]; type != "object" or
        .type != "acme" or (.tag | type != "string" or length == 0))) then
        false
      else
        ($provider_objects | map(.tag) | unique) as $providers |
        ([.inbounds[]?.tls? | .certificate_provider? |
          select(type == "string")] | unique) as $references |
        (($providers | length) == ($provider_objects | length)) and
        (all($provider_objects[]; . as $provider |
          (($references | index($provider.tag)) != null or
           any($state.components[]?;
             .role == "certificate_provider" and .type == "acme" and
             .tag == $provider.tag and .enabled == true and
             ((.config + {type:.type,tag:.tag}) == $provider)))) and
         all($references[]; . as $tag | ($providers | index($tag)) != null))
      end
    else true end
  ' "${config_file}" >/dev/null 2>&1 || return 1
  jq -e --argjson state "${state}" '
    if has("network_namespaces") then
      (.network_namespaces | type == "array" and length <= 128 and
        ([.[]?.tag] | unique | length) == length and
        all(.[]?;
          . as $namespace |
          type == "object" and
          (.type | type == "string" and IN("default","unshare")) and
          (.tag | type == "string" and length > 0 and
            (any(explode[]; . < 32 or . == 127) | not)) and
          (if .type == "default" then
             ((keys - ["type","tag","path"]) | length == 0) and
             (.path | type == "string" and length > 0 and startswith("/") and
               (any(explode[]; . < 32 or . == 127) | not))
           else
             ((keys - ["type","tag"]) | length == 0)
           end) and
          any($state.components[]?;
            .role == "network_namespace" and .type == ($namespace.type // "") and
            .tag == ($namespace.tag // "") and .enabled == true and
            ((.config + {type:.type,tag:.tag}) == $namespace))))
    else true end
  ' "${config_file}" >/dev/null 2>&1 || return 1
}

# Exclude operator-owned components from the ownership comparison. They remain
# in the actual candidate and are checked by the core and graph validators.
coexisting_component_projection() {
  local config_file=$1 state=$2 registry policy_sets
  registry=$(component_registry_static_json) || return 1
  policy_sets=$(routing_policy_owned_rule_sets_json "" "${state}") || return 1
  jq --argjson state "${state}" --argjson registry "${registry}" --argjson policy_sets "${policy_sets}" '
    def known($role): . as $record |
      any($registry[]; .role == $role and .type == $record.type);
    def owns($role): . as $record |
      any($state.components[]?; .role == $role and .tag == $record.tag);
    if has("inbounds") then .inbounds |= map(select(
      (.type | IN("direct","tun","redirect","tproxy","cloudflared") | not) or owns("inbound"))) else . end |
    if has("outbounds") then .outbounds |= map(select(
      (.tag | IN("direct","block","warp-ep")) or owns("outbound") or (known("outbound") | not))) else . end |
    if has("endpoints") then .endpoints |= map(select(.tag == "warp-ep" or owns("endpoint") or (known("endpoint") | not))) else . end |
    if has("services") then .services |= map(select(owns("service") or (known("service") | not))) else . end |
    if has("network_namespaces") then .network_namespaces |= map(select(owns("network_namespace") or (known("network_namespace") | not))) else . end |
    if has("certificate_providers") then .certificate_providers |= map(select(
      (.tag | IN("hy2-cert-provider","anytls-cert-provider")) or owns("certificate_provider") or (known("certificate_provider") | not))) else . end |
    if .route.default_http_client? != null and
       ((.route.default_http_client as $client | any($state.components[]?; .role == "http_client" and .tag == $client)) | not) and
       (.route.default_http_client as $client | [.http_clients[]? | select(.tag == $client)] | length == 1) then
      del(.route.default_http_client) else . end |
    if has("http_clients") then .http_clients |= map(select(owns("http_client") or has("type"))) else . end |
    if .route.rule_set? != null then .route.rule_set |= map(select(
      ((.tag // "") | startswith("warp-local-") or startswith("warp-remote-")) or owns("rule_set") or
      (. as $set | any($policy_sets[]; . == $set)))) else . end
  ' "${config_file}"
}

managed_component_state_matches_live_config() (
  local config_file=${1:-} state_file=${2:-} allow_legacy=${3:-false} state projected
  [[ -f "${config_file}" && ! -L "${config_file}" ]] || return 1
  if [[ -n "${state_file}" ]]; then
    managed_state_snapshot_is_valid "${state_file%/project/components.json}" || return 1
    if [[ -f "${state_file}" && ! -L "${state_file}" ]]; then state=$(cat "${state_file}") || return 1
    elif [[ ! -e "${state_file}" ]]; then state=$(managed_component_state_default_json) || return 1
    else return 1; fi
  else state=$(managed_component_state_json) || return 1; fi
  managed_component_state_validate_json "${state}" || return 1
  umask 077
  projected=$(storage_mktemp) || return 1
  trap 'rm -f -- "${projected}"' EXIT
  coexisting_component_projection "${config_file}" "${state}" > "${projected}" || return 1
  managed_component_owned_projection_matches "${projected}" "${state_file}" "${allow_legacy}"
)

# Three-way merge: generated baseline vs live config vs new generated config.
# Tag-keyed records have explicit ownership; all other operator content stays
# in the live tree. A changed owned value is a conflict unless it already
# matches the new state. Never resolve a conflict by overwriting operator work.
merge_generated_config_with_live() {
  local generated=$1 live=$2 baseline=$3 merge_input
  [[ -f "${live}" && ! -L "${live}" && ! -L "${baseline}" ]] || return 1
  if [[ -e "${baseline}" ]]; then
    [[ -f "${baseline}" && "$(stat -c %a "${baseline}")" == 600 ]] || return 1
    jq -e 'type == "object" and (.inbounds | type == "array")' "${baseline}" >/dev/null || return 1
  else
    baseline=${generated}
  fi
  for merge_input in "${generated}" "${live}" "${baseline}"; do
    jq -e '
      all([.inbounds,.outbounds,.endpoints,.services,.http_clients,.certificate_providers,.network_namespaces][];
        . == null or (type == "array" and ([.[]?.tag // empty] | length) == ([.[]?.tag // empty] | unique | length)))
    ' "${merge_input}" >/dev/null || {
      printf '[ERROR] component_graph: duplicate tag; 配置未发布。\n' >&2
      return 1
    }
  done
  jq --slurpfile generated "${generated}" --slurpfile baseline "${baseline}" \
    --argjson bootstrap "$([[ "${baseline}" == "${generated}" ]] && printf true || printf false)" '
    def tagged: type == "array" and all(.[]; type == "object" and (.tag | type == "string" and length > 0));
    def collision: error("managed_config_conflict");
    def auth_users:
      if type == "array" then map(if type == "object" then
        del(.name,.flow) | if has("uuid") then .alterId=(.alterId // 0) else . end
        else . end) else . end;
    def bootstrap_security_options_match($model; $existing):
      if ($model | type) == "object" and ($existing | type) == "object" then
        all($model | keys[]; . as $key |
          if $key == "insecure" then $model[$key] == ($existing[$key] // false)
          else ($existing | has($key)) and
            bootstrap_security_options_match($model[$key]; $existing[$key]) end)
      else $model == $existing end;
    def bootstrap_sensitive_matches($model; $existing):
      if ($model | type) == "object" and ($existing | type) == "object" then
        all($model | keys[]; . as $key |
          if $key == "listen" then $model[$key] == ($existing[$key] // "127.0.0.1")
          elif $key == "listen_port" then $model[$key] == $existing[$key]
          elif $key == "users" then ($model[$key] | auth_users) == ($existing[$key] | auth_users)
          elif $key == "strict_mode" then $model[$key] == ($existing[$key] // false)
          elif $key == "wildcard_sni" then $model[$key] == ($existing[$key] // "off")
          elif ($key | IN("tls","transport","detour","network","udp_over_tcp") or
              test("(^|_)(server|address|port|ports)($|_)")) then
            bootstrap_security_options_match($model[$key]; $existing[$key])
          elif ($key | IN("username","uuid","psk","auth","auth_str","authentication","obfs","short_id") or
              test("(^|_)(password|passwords|passwd|passphrase|secret|token|key)($|_)")) then
            $model[$key] == $existing[$key]
          else bootstrap_sensitive_matches($model[$key]; $existing[$key]) end)
      elif ($model | type) == "array" and ($existing | type) == "array" then
        ($model | length) == ($existing | length) and
        all(range(0; $model | length); . as $index |
          bootstrap_sensitive_matches($model[$index]; $existing[$index]))
      else true end;
    def seed_defaults($model; $existing):
      if ($model | type) == "object" and ($existing | type) == "object" then
        reduce ($model | keys[]) as $key ({};
          if $existing | has($key) then
            if $key == "users" and ($model[$key] | type) == "array" and
               ($existing[$key] | type) == "array" and
               ($model[$key] | auth_users) == ($existing[$key] | auth_users)
            then .[$key] = $existing[$key]
            else .[$key] = seed_defaults($model[$key]; $existing[$key]) end
          else . end)
      else $model end;
    def merge($base; $live; $next):
      if $live == $base or $live == $next then $next
      elif $next == $base then $live
      elif ($base | type) == "object" and ($live | type) == "object" and ($next | type) == "object" then
        reduce (($base + $live + $next) | keys[]) as $key ({};
          if ($base | has($key)) then
            if ($next | has($key) | not) then
              if ($live | has($key)) then
                if ($base[$key] | tagged) and ($live[$key] | tagged) then
                  merge($base[$key]; $live[$key]; []) as $remaining |
                  if ($remaining | length) > 0 then .[$key] = $remaining else . end
                elif $live[$key] != $base[$key] then collision else . end
              else . end
            elif ($live | has($key) | not) then
              if $next[$key] == $base[$key] then . else collision end
            else .[$key] = merge($base[$key]; $live[$key]; $next[$key]) end
          elif ($live | has($key)) and ($next | has($key)) then
            if $live[$key] == $next[$key] then .[$key] = $live[$key]
            elif ($live[$key] | tagged) and ($next[$key] | tagged) then
              .[$key] = merge([]; $live[$key]; $next[$key])
            else collision end
          elif ($next | has($key)) then .[$key] = $next[$key]
          else .[$key] = $live[$key] end)
      elif ($base | tagged) and ($live | tagged) and ($next | tagged) then
        def keyed: map({key:.tag,value:.}) | from_entries;
        merge(($base|keyed); ($live|keyed); ($next|keyed)) as $merged |
        reduce ($live + $next)[] as $record ({seen:[],records:[]};
          if (.seen | index($record.tag)) != null then . else
            .seen += [$record.tag] | .records += [$merged[$record.tag] // empty] end) | .records
      elif ($base | type) == "array" and ($live | type) == "array" and ($next | type) == "array" and
           all(($base + $live + $next)[]; type == "object" and (has("action") or has("outbound"))) then
        # Non-tagged arrays are ordered. Retain custom entries in place and
        # replace/remove exact baseline entries; append only new generated
        # entries. Pure generated lists took the first branch above.
        def rule_key:
          if (.inbound | type) == "string" and
             ((.action == "sniff" and (keys | sort) == ["action","inbound"]) or
              (.action == "route" and (keys | sort) == ["action","inbound","outbound"])) then
            ["inbound-rule",.inbound,.action] | tojson
          else tojson end;
        def keyed_rules: map({key:rule_key,value:.}) | from_entries;
        if any([$base,$live,$next][];
          (map(rule_key) | unique | length) != length) then collision else
          merge(($base|keyed_rules); ($live|keyed_rules); ($next|keyed_rules)) as $merged |
          reduce ($live + $next)[] as $rule ({seen:[],rules:[]};
            ($rule | rule_key) as $key |
            if (.seen | index($key)) != null then . else
              .seen += [$key] | .rules += [$merged[$key] // empty] end) | .rules
        end
      else collision end;
    $generated[0] as $next |
    # Missing rules mean no rules. An omitted final uses the first outbound,
    # not the stale state final; make that existing fallback explicit.
    (if $bootstrap and ($next.route | type)=="object" then
      .route=(.route // {}) | .route.rules=(.route.rules // []) |
      if (.route.final // "")=="" and (.outbounds[0].tag | type)=="string" and
         (.outbounds[0].tag | length)>0 then .route.final=.outbounds[0].tag else . end
    else . end) as $live |
    (if $bootstrap then
      # Existing state cannot silently recreate an operator-deleted listener.
      # New listeners must establish the old baseline before changing state.
      if any($next.inbounds[]?; .tag as $tag |
        any($live.inbounds[]?; .tag==$tag) | not) then collision else . end |
      # Legacy installs have no baseline. Adopt only matching generated tags,
      # seeding generated defaults only where live fields exist. Live option
      # drift stays an operator override; sensitive drift is rejected first.
      # Credential-equivalent user metadata may normalize to generated form.
      # Never adopt other changed live options as proof that stale state owns it.
      reduce ["inbounds","outbounds","endpoints","services","http_clients","certificate_providers","network_namespaces"][] as $field (seed_defaults($next; $live);
        if $live | has($field) then
          .[$field] = [$next[$field][]? as $record | $live[$field][]? | select(.tag == $record.tag) |
          if (.type // "shared") == ($record.type // "shared") and bootstrap_sensitive_matches($record; .)
          then seed_defaults($record; .) else collision end]
        else del(.[$field]) end) |
      if $live | has("dns") then
        # A legacy DNS tag does not prove ownership of its live settings.
        # Seed generated defaults so custom same-tag servers remain live.
        if $live.dns | has("servers") then
          .dns.servers = [$next.dns.servers[]? as $server |
            $live.dns.servers[]? | select(.tag == $server.tag) | $server]
        else del(.dns.servers) end
      else del(.dns) end |
      # Keep generated routing policy as the old baseline. A live deletion
      # must never turn a stale permission rule into an apparently new rule.
      if $next | has("route") then .route=$next.route else del(.route) end |
      with_entries(select(.key as $key | $live | has($key)))
    else $baseline[0] end) as $base |
    merge($base; $live; $next)
  ' "${live}"
}

managed_component_owned_projection_matches() {
  local config_file=${1:-} state_file=${2:-} allow_legacy_download_detour=${3:-false} state registry endpoint_types outbound_types
  local certificate_provider_types http_client_types service_types namespace_types snapshot_dir
  [[ -f "${config_file}" && ! -L "${config_file}" ]] || return 1
  [[ "${allow_legacy_download_detour}" == true || "${allow_legacy_download_detour}" == false ]] || return 1
  if [[ -n "${state_file}" ]]; then
    snapshot_dir=${state_file%/project/components.json}
    [[ "${state_file}" == "${snapshot_dir}/project/components.json" ]] || return 1
    managed_state_snapshot_is_valid "${snapshot_dir}" || return 1
    if [[ -f "${state_file}" && ! -L "${state_file}" && -r "${state_file}" ]]; then
      state=$(jq -cS '.' "${state_file}") || return 1
      managed_component_state_validate_json "${state}" || return 1
    elif [[ ! -e "${state_file}" ]]; then
      state=$(managed_component_state_default_json) || return 1
    else
      return 1
    fi
  else
    state=$(managed_component_state_json) || return 1
  fi
  managed_component_live_route_rule_sets_match_state \
    "${config_file}" "${state}" "${allow_legacy_download_detour}" || return 1
  registry=$(component_registry_static_json) || return 1
  endpoint_types=$(jq -c '[.[] | select(.role == "endpoint") | .type]' <<< "${registry}") || return 1
  outbound_types=$(jq -c '[.[] | select(.role == "outbound") | .type]' <<< "${registry}") || return 1
  certificate_provider_types=$(jq -c '[.[] | select(.role == "certificate_provider") | .type]' <<< "${registry}") || return 1
  http_client_types=$(jq -c '[.[] | select(.role == "http_client") | .type]' <<< "${registry}") || return 1
  service_types=$(jq -c '[.[] | select(.role == "service") | .type]' <<< "${registry}") || return 1
  namespace_types=$(jq -c '[.[] | select(.role == "network_namespace") | .type]' <<< "${registry}") || return 1
  jq -e --argjson state "${state}" --argjson endpoint_types "${endpoint_types}" \
    --argjson outbound_types "${outbound_types}" \
    --argjson certificate_provider_types "${certificate_provider_types}" \
    --argjson http_client_types "${http_client_types}" \
    --argjson service_types "${service_types}" \
    --argjson namespace_types "${namespace_types}" '
    def safe_string:
      type == "string" and length <= 4096 and
      (any(explode[]; . < 32 or . == 127) | not);
    def managed($role; $type; $tag):
      any($state.components[]; .role == $role and .type == $type and .tag == $tag and .enabled == true);
    (all(.inbounds[]?;
      if (.type | IN("direct","tun","redirect","tproxy","cloudflared")) then
        managed("inbound"; .type; (.tag // ""))
      else true end)) and
    (all(.endpoints[]?;
      .type as $endpoint_type |
      if ((.tag // "") == "warp-ep") then
        true
      elif (($endpoint_types | index($endpoint_type // "")) != null) then
        managed("endpoint"; ($endpoint_type // ""); (.tag // ""))
      else
        false
      end)) and
    (all(.certificate_providers[]?;
      . as $provider |
      if (($provider.tag // "") | IN("hy2-cert-provider","anytls-cert-provider")) then
        ($provider.type // "") == "acme"
      elif (($certificate_provider_types | index($provider.type // "")) == null) then
        false
      else
        ([ $state.components[]? |
          select(.role == "certificate_provider" and .type == "acme" and
            .tag == ($provider.tag // "") and .enabled == true) ] | length) as $managed_count |
        ($managed_count == 0 or
          any($state.components[]?;
            .role == "certificate_provider" and .type == "acme" and
            .tag == ($provider.tag // "") and .enabled == true and
            ((.config + {type:.type,tag:.tag}) == $provider)))
      end)) and
    (all(.network_namespaces[]?;
      . as $namespace |
      ($namespace_types | index($namespace.type // "")) != null and
      managed("network_namespace"; ($namespace.type // ""); ($namespace.tag // "")) and
      any($state.components[]?;
        .role == "network_namespace" and .type == ($namespace.type // "") and
        .tag == ($namespace.tag // "") and .enabled == true and
        ((.config + {type:.type,tag:.tag}) == $namespace)))) and
    (if has("services") then
       (.services) as $services |
       ($services | type == "array" and length <= 128 and
         ([.[]?.tag] | unique | length) == ([.[]?.tag] | length) and
         all(.[]?;
           . as $service |
           type == "object" and
           (($service.type | type == "string") and
            (($service_types | index($service.type)) != null)) and
           ($service.tag | safe_string and length > 0) and
           managed("service"; ($service.type // ""); ($service.tag // "")) and
           any($state.components[]?;
             .role == "service" and .type == ($service.type // "") and
             .tag == ($service.tag // "") and .enabled == true and
             ((.config + {type:.type,tag:.tag}) == $service))) and
         ([ $state.components[]? |
            select(.role == "service" and .enabled == true) ] |
           length == ($services | length)))
     else
       ([ $state.components[]? |
          select(.role == "service" and .enabled == true) ] |
         length == 0)
     end) and
    ((if has("route") then
        (.route | type == "object" and
          ((has("default_http_client") | not) or
            (.default_http_client as $client |
              ($client | safe_string) and
              (($client == "") or managed("http_client"; "shared"; $client)))))
      else true end)) and
    ((if has("http_clients") then
        (.http_clients | type == "array" and length <= 128 and
          ([.[]?.tag] | unique | length) == ([.[]?.tag] | length) and
          all(.[]?;
            . as $client |
            ($client | type == "object" and
              (.tag | safe_string and length > 0)) and
            (($http_client_types | index("shared")) != null) and
            managed("http_client"; "shared"; ($client.tag // "")) and
            any($state.components[]?;
              .role == "http_client" and .type == "shared" and
              .tag == ($client.tag // "") and .enabled == true and
              ((.config + {tag:.tag}) == $client))))
      else
        ([ $state.components[]? |
           select(.role == "http_client" and .type == "shared" and .enabled == true) ] |
          length == 0)
      end)) and
    # Proxy protocol adapters generate client outbounds only for exports; the
    # server configuration registered custom outbounds are component-owned.
    # Keep the two built-in safety owners out of the state contract.
    (all(.outbounds[]?;
      . as $outbound |
      if (($outbound.tag // "") == "warp-ep") then
        true
      elif (($outbound_types | index($outbound.type // "")) != null) and
         ((($outbound.type == "direct" and ($outbound.tag // "") == "direct") or
           ($outbound.type == "block" and ($outbound.tag // "") == "block")) | not) then
        managed("outbound"; ($outbound.type // ""); ($outbound.tag // ""))
      elif (($outbound.tag // "") == "direct" or ($outbound.tag // "") == "block") then
        (($outbound.type // "") == ($outbound.tag // ""))
      elif (($outbound_types | index($outbound.type // "")) == null) then
        false
      else true end))
  ' "${config_file}" >/dev/null 2>&1
}

managed_component_state_core_features_supported() {
  local state=${1:-} minimum core_version has_http_client_reference
  [[ -n "${state}" ]] || return 1
  managed_component_state_validate_json "${state}" || return 1
  has_http_client_reference=$(jq -r '
    any(.components[]?;
      .enabled == true and .role == "rule_set" and .type == "remote" and
      (.config | has("http_client")))
  ' <<< "${state}") || return 1
  [[ "${has_http_client_reference}" == true ]] || return 0
  minimum=$(component_registry_field route-rule-set-remote features | \
    jq -er '.http_client_reference_minimum_core | strings') || return 1
  core_version=$(detect_installed_singbox_version 2>/dev/null) || return 1
  [[ "${core_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  singbox_version_at_least "${core_version}" "${minimum}"
}

managed_component_unowned_tag_collision() {
  local role=$1 tag=$2 state=$3 config_file=$4
  [[ -f "${config_file}" && ! -L "${config_file}" ]] || return 1
  jq -c --arg role "${role}" --arg tag "${tag}" --slurpfile live "${config_file}" '
    def namespace:
      if IN("inbound","outbound","endpoint") then "component" else . end;
    if ($live | length) != 1 or ($live[0] | type) != "object" then error("invalid_config")
    elif any(.components[]; .tag==$tag and (.role|namespace)==($role|namespace)) then false
    else $live[0] |
      (if ($role|namespace)=="component" then [.inbounds[]?,.outbounds[]?,.endpoints[]?]
       elif $role=="certificate_provider" then [.certificate_providers[]?]
       elif $role=="http_client" then [.http_clients[]?]
       elif $role=="service" then [.services[]?]
       elif $role=="network_namespace" then [.network_namespaces[]?]
       elif $role=="rule_set" then [.route.rule_set[]?]
       else error("invalid_namespace") end) |
      any(.[]; if (.tag|type)=="array" then (.tag|index($tag))!=null else .tag==$tag end)
    end
  ' <<< "${state}" 2>/dev/null
}

managed_component_network_namespaces_accessible() {
  local state=${1:-} paths path
  paths=$(jq -r '.components[] | select(.enabled == true and .role == "network_namespace" and .type == "default") | .config.path' <<< "${state}") || return 1
  [[ -n "${paths}" ]] || return 0
  if ! command -v nsenter >/dev/null 2>&1 || ! command -v timeout >/dev/null 2>&1; then
    printf '[ERROR] network_namespace_unavailable: namespace 预检工具不可用；配置未发布。\n' >&2
    return 1
  fi
  while IFS= read -r path; do
    # Reject FIFOs/devices before opening an operator-supplied path. A valid
    # namespace handle (including /proc/PID/ns/net) is a regular nsfs file.
    if [[ ! -f "${path}" ]] || ! timeout 5 nsenter --net="${path}" -- /bin/true >/dev/null 2>&1; then
      printf '[ERROR] network_namespace_unavailable: namespace 不存在或无法访问；配置未发布。\n' >&2
      return 1
    fi
  done <<< "${paths}"
}

managed_component_state_apply() {
  local operation=${1:-} expected=${2:-} input=${3:-} target_id=${4:-} allow_public=${5:-n}
  local state current_revision record candidate snapshot service_restarted=false state_changed=true
  local role type tag result_record old_config old_listener_plan new_listener_plan
  local old_redirect_policy_plan='[]' new_redirect_policy_plan='[]' redirect_policy_journal=''
  local old_tproxy_policy_plan='[]' new_tproxy_policy_plan='[]' tproxy_policy_journal=''
  local takeover_records takeover_status result_count=0
  local firewall_journal=""
  local firewall_summary='{"status":"not_attempted","backends":[],"diagnostics":[]}'
  local redirect_policy_summary='{"status":"not_configured","resources":[],"operator_managed":[]}'
  local tproxy_policy_summary='{"status":"not_configured","resources":[],"operator_managed":[]}'
  local result_id candidate_revision lock_dir="${SB_COMPONENT_TRANSACTION_DIR}" before_active=false owner_pid owner_start=""
  local inventory_state_file=""
  MANAGED_COMPONENT_LAST_ERROR=""
  MANAGED_COMPONENT_LAST_RESULT=""
  result_record='{}'
  [[ ${EUID} -eq 0 ]] || { MANAGED_COMPONENT_LAST_ERROR=root_required; return 1; }
  [[ ! -L "${SB_PROJECT_DIR}" ]] || { MANAGED_COMPONENT_LAST_ERROR=component_write_failed; return 1; }
  mkdir -p "${SB_PROJECT_DIR}" || { MANAGED_COMPONENT_LAST_ERROR=component_write_failed; return 1; }
  acquire_managed_write_lock || { MANAGED_COMPONENT_LAST_ERROR=component_write_busy; return 1; }
  if [[ -e "${SB_PROJECT_DIR}.instance-write.lock" || -L "${SB_PROJECT_DIR}.instance-write.lock" ]]; then
    MANAGED_COMPONENT_LAST_ERROR=instance_transaction_pending
    return 1
  fi
  state=$(managed_component_state_json) || { MANAGED_COMPONENT_LAST_ERROR=state_invalid; return 1; }
  current_revision=$(jq -r '.revision | tostring' <<< "${state}") || { MANAGED_COMPONENT_LAST_ERROR=state_invalid; return 1; }
  [[ "${expected}" == "${current_revision}" ]] || { MANAGED_COMPONENT_LAST_ERROR=revision_mismatch; return 1; }
  [[ ! -e "${lock_dir}" && ! -L "${lock_dir}" ]] || {
    MANAGED_COMPONENT_LAST_ERROR=component_transaction_pending
    return 1
  }
  owner_pid=${BASHPID:-$$}
  owner_start=$(awk '{print $22}' "/proc/${owner_pid}/stat") || {
    MANAGED_COMPONENT_LAST_ERROR=component_transaction_begin_failed
    return 1
  }
  [[ "${owner_start}" =~ ^[0-9]+$ ]] || {
    MANAGED_COMPONENT_LAST_ERROR=component_transaction_begin_failed
    return 1
  }
  if [[ -f "${SINGBOX_SERVICE_FILE}" ]] && systemctl is-active sing-box >/dev/null 2>&1; then
    before_active=true
  fi
  case "${operation}" in
    create|replace)
      record=$(managed_component_normalize_input_file "${input}") || { MANAGED_COMPONENT_LAST_ERROR=record_invalid; return 1; }
      result_record="${record}"
      tag=$(jq -r '.tag' <<< "${record}") || { MANAGED_COMPONENT_LAST_ERROR=record_invalid; return 1; }
      if [[ -f "${SINGBOX_CONFIG_FILE}" ]]; then
        local incoming_role collision
        incoming_role=$(jq -r '.role' <<< "${record}") || { MANAGED_COMPONENT_LAST_ERROR=record_invalid; return 1; }
        collision=$(managed_component_unowned_tag_collision "${incoming_role}" "${tag}" "${state}" "${SINGBOX_CONFIG_FILE}") || {
          MANAGED_COMPONENT_LAST_ERROR=component_live_untrusted; return 1;
        }
        if [[ "${collision}" == true ]]; then
          MANAGED_COMPONENT_LAST_ERROR=component_conflict
          return 1
        fi
      fi
      if managed_component_requires_public_confirmation "${record}" && [[ "${allow_public}" != y ]]; then
        MANAGED_COMPONENT_LAST_ERROR=public_confirmation_required
        return 1
      fi
      candidate=$(managed_component_state_candidate "${state}" "${operation}" "${record}") || {
        MANAGED_COMPONENT_LAST_ERROR=component_conflict; return 1;
      }
      ;;
    delete)
      managed_component_state_id_valid "${target_id}" || { MANAGED_COMPONENT_LAST_ERROR=invalid_id; return 1; }
      candidate=$(managed_component_state_candidate "${state}" delete "" "${target_id}") || {
        MANAGED_COMPONENT_LAST_ERROR=component_referenced_or_missing; return 1;
      }
      ;;
    rebuild)
      [[ -z "${input}${target_id}" && "${allow_public}" == n ]] || {
        MANAGED_COMPONENT_LAST_ERROR=invalid_operation; return 1;
      }
      candidate="${state}"
      state_changed=false
      ;;
    takeover)
      [[ -z "${input}${target_id}" ]] || {
        MANAGED_COMPONENT_LAST_ERROR=invalid_operation; return 1;
      }
      takeover_records=$(managed_component_live_takeover_records_json "${state}") || {
        takeover_status=$?
        case "${takeover_status}" in
          2) MANAGED_COMPONENT_LAST_ERROR=component_live_missing ;;
          3) MANAGED_COMPONENT_LAST_ERROR=component_live_missing ;;
          4) MANAGED_COMPONENT_LAST_ERROR=component_live_untrusted ;;
          *) MANAGED_COMPONENT_LAST_ERROR=component_takeover_failed ;;
        esac
        return 1
      }
      if jq -e 'any(.[];
          (.role == "inbound" and
           (.type == "tun" or .type == "cloudflared" or
            ((.config.listen // "127.0.0.1") as $listen |
             ($listen != "127.0.0.1" and $listen != "::1" and $listen != "localhost")))) or
          (.role == "endpoint" and .type == "openvpn-server") or
          (.role == "service" and .type == "resolved" and
           ((.config.listen // "") as $listen |
            (($listen | type) != "string" or
             ($listen != "" and $listen != "localhost" and $listen != "::1" and
              (($listen | startswith("127.")) | not))))))' <<< "${takeover_records}" >/dev/null 2>&1 &&
         [[ "${allow_public}" != y ]]; then
        MANAGED_COMPONENT_LAST_ERROR=public_confirmation_required
        return 1
      fi
      candidate=$(managed_component_state_takeover_candidate "${state}" "${takeover_records}") || {
        MANAGED_COMPONENT_LAST_ERROR=component_takeover_conflict; return 1;
      }
      if [[ "${candidate}" == "${state}" ]]; then
        state_changed=false
      fi
      result_record='{}'
      ;;
    *) MANAGED_COMPONENT_LAST_ERROR=invalid_operation; return 1 ;;
  esac

  if ! managed_component_state_core_features_supported "${candidate}"; then
    MANAGED_COMPONENT_LAST_ERROR=component_feature_unsupported
    return 1
  fi
  local namespace_build_status=0
  managed_component_namespace_runtime_safe "${candidate}" || namespace_build_status=$?
  if [[ "${namespace_build_status}" != 0 ]]; then
    if [[ "${namespace_build_status}" == 3 ]]; then
      MANAGED_COMPONENT_LAST_ERROR=namespace_runtime_build_not_assessed
    else
      MANAGED_COMPONENT_LAST_ERROR=namespace_runtime_unsafe_build
    fi
    return 1
  fi
  # check accepts unresolved namespace paths. Verify only the enabled candidate
  # before journaling/publishing so an inaccessible path cannot stop the core.
  # A delete may still remove an unavailable namespace from the candidate.
  if ! managed_component_network_namespaces_accessible "${candidate}"; then
    MANAGED_COMPONENT_LAST_ERROR=network_namespace_unavailable
    return 1
  fi
  old_redirect_policy_plan=$(managed_component_redirect_host_policy_plan_json "${state}") || {
    MANAGED_COMPONENT_LAST_ERROR=host_policy_state_invalid; return 1;
  }
  new_redirect_policy_plan=$(managed_component_redirect_host_policy_plan_json "${candidate}") || {
    MANAGED_COMPONENT_LAST_ERROR=host_policy_state_invalid; return 1;
  }
  if [[ "${old_redirect_policy_plan}" != "${new_redirect_policy_plan}" ||
        "${old_redirect_policy_plan}" != '[]' ]]; then
    if [[ "${old_redirect_policy_plan}" != "${new_redirect_policy_plan}" &&
          "${before_active}" != true && "${old_redirect_policy_plan}" == '[]' &&
          "${new_redirect_policy_plan}" != '[]' ]]; then
      MANAGED_COMPONENT_LAST_ERROR=host_policy_requires_active_service
      return 1
    fi
    if ! managed_component_redirect_policy_preflight \
      "${old_redirect_policy_plan}" "${new_redirect_policy_plan}"; then
      MANAGED_COMPONENT_LAST_ERROR=host_policy_preflight_failed
      return 1
    fi
  fi
  old_tproxy_policy_plan=$(managed_component_tproxy_host_policy_plan_json "${state}") || {
    MANAGED_COMPONENT_LAST_ERROR=tproxy_host_policy_state_invalid; return 1;
  }
  new_tproxy_policy_plan=$(managed_component_tproxy_host_policy_plan_json "${candidate}") || {
    MANAGED_COMPONENT_LAST_ERROR=tproxy_host_policy_state_invalid; return 1;
  }
  if [[ "${old_tproxy_policy_plan}" != "${new_tproxy_policy_plan}" ||
        "${old_tproxy_policy_plan}" != '[]' ]]; then
    if [[ "${old_tproxy_policy_plan}" != "${new_tproxy_policy_plan}" &&
          "${before_active}" != true && "${old_tproxy_policy_plan}" == '[]' &&
          "${new_tproxy_policy_plan}" != '[]' ]]; then
      MANAGED_COMPONENT_LAST_ERROR=tproxy_host_policy_requires_active_service
      return 1
    fi
    if ! managed_component_tproxy_policy_preflight \
      "${old_tproxy_policy_plan}" "${new_tproxy_policy_plan}"; then
      MANAGED_COMPONENT_LAST_ERROR=tproxy_host_policy_preflight_failed
      return 1
    fi
  fi
  if ! managed_component_transaction_begin "${lock_dir}" "${operation}" "${expected}" \
    "${before_active}" "${owner_pid}" "${owner_start}"; then
    MANAGED_COMPONENT_LAST_ERROR=component_transaction_begin_failed
    return 1
  fi
  snapshot="${lock_dir}/snapshot"
  if ! create_managed_state_snapshot "${snapshot}" >/dev/null; then
    if ! rm -rf -- "${lock_dir}"; then
      MANAGED_COMPONENT_LAST_ERROR=component_cleanup_failed
    else
      MANAGED_COMPONENT_LAST_ERROR=snapshot_failed
    fi
    return 1
  fi
  # Capture old global settings before either the baseline or component state
  # changes; fresh Agent shells otherwise still contain default route flags.
  if ! load_config_generation_settings "${SINGBOX_CONFIG_FILE}"; then
    managed_component_abort_component_transaction "${lock_dir}" "${snapshot}" "现有全局配置设置无法读取" || :
    MANAGED_COMPONENT_LAST_ERROR=config_check_failed
    return 1
  fi
  if [[ ! -e "${SB_PROJECT_DIR}/managed-config.generated.json" && -f "${SINGBOX_CONFIG_FILE}" ]]; then
    if ! ensure_existing_generated_config_baseline; then
      managed_component_abort_component_transaction "${lock_dir}" "${snapshot}" "旧组件生成基线无法建立" || :
      MANAGED_COMPONENT_LAST_ERROR=component_transaction_write_failed
      return 1
    fi
  fi
  candidate_revision=$(jq -r '.revision' <<< "${candidate}") || {
    managed_component_abort_component_transaction "${lock_dir}" "${snapshot}" "高级组件事务 revision 读取失败" || :
    MANAGED_COMPONENT_LAST_ERROR=component_transaction_write_failed
    return 1
  }
  if ! managed_component_transaction_checkpoint "${lock_dir}" snapshot ||
     ! managed_component_transaction_set_revision "${lock_dir}" "${candidate_revision}" ||
     ! managed_component_transaction_checkpoint "${lock_dir}" publish; then
    managed_component_abort_component_transaction "${lock_dir}" "${snapshot}" "高级组件事务日志写入失败" || :
    MANAGED_COMPONENT_LAST_ERROR=component_transaction_write_failed
    return 1
  fi
  old_config="${snapshot}/project/config.json"
  [[ -f "${old_config}" && ! -L "${old_config}" ]] || old_config=""
  if [[ "${state_changed}" == true ]]; then
    if ! managed_component_write_state "${candidate}"; then
      managed_component_abort_component_transaction "${lock_dir}" "${snapshot}" "高级组件状态写入失败" || :
      MANAGED_COMPONENT_LAST_ERROR=state_write_failed
      return 1
    fi
  fi
  if [[ "${operation}" != takeover ]]; then
    inventory_state_file="${snapshot}/project/components.json"
  fi

  if ! generate_config "${inventory_state_file}" ||
     [[ ! -f "${SINGBOX_CONFIG_FILE}" || -L "${SINGBOX_CONFIG_FILE}" ]]; then
    managed_component_abort_component_transaction "${lock_dir}" "${snapshot}" "高级组件配置生成或校验失败" || :
    MANAGED_COMPONENT_LAST_ERROR=config_check_failed
    return 1
  fi
  if [[ "${operation}" == takeover ]] &&
     ! managed_component_takeover_preserves_live_config "${old_config}" "${SINGBOX_CONFIG_FILE}"; then
    managed_component_abort_component_transaction "${lock_dir}" "${snapshot}" "高级组件接管会丢失现有配置对象或路由规则" || :
    MANAGED_COMPONENT_LAST_ERROR=config_check_failed
    return 1
  fi

  # Fixed listeners owned by advanced components use the same firewall
  # ownership ledger as structured protocol instances.  Keep the journal in
  # the state snapshot so a file/config rollback and external resource
  # compensation share one bounded recovery material set.
  new_listener_plan=$(managed_listener_plan "${SINGBOX_CONFIG_FILE}") || {
    managed_component_abort_component_transaction "${lock_dir}" "${snapshot}" "高级组件监听资源预检失败" || :
    MANAGED_COMPONENT_LAST_ERROR=config_check_failed
    return 1
  }
  if [[ -n "${old_config}" ]]; then
    old_listener_plan=$(managed_listener_plan "${old_config}") || {
      managed_component_abort_component_transaction "${lock_dir}" "${snapshot}" "高级组件旧监听资源预检失败" || :
      MANAGED_COMPONENT_LAST_ERROR=config_check_failed
      return 1
    }
  else
    old_listener_plan='[]'
  fi
  if [[ "${old_redirect_policy_plan}" != "${new_redirect_policy_plan}" ]]; then
    redirect_policy_journal="${snapshot}/component-redirect-policy.json"
    if ! managed_component_redirect_policy_journal_write "${redirect_policy_journal}" \
      "${old_redirect_policy_plan}" "${new_redirect_policy_plan}"; then
      managed_component_abort_component_transaction "${lock_dir}" "${snapshot}" "Redirect 主机策略事务日志准备失败" || :
      MANAGED_COMPONENT_LAST_ERROR=host_policy_journal_failed
      return 1
    fi
  fi
  if [[ "${old_tproxy_policy_plan}" != "${new_tproxy_policy_plan}" ]]; then
    tproxy_policy_journal="${snapshot}/component-tproxy-policy.json"
    if ! managed_component_tproxy_policy_journal_write "${tproxy_policy_journal}" \
      "${old_tproxy_policy_plan}" "${new_tproxy_policy_plan}"; then
      managed_component_abort_component_transaction "${lock_dir}" "${snapshot}" "TProxy 主机策略事务日志准备失败" || :
      MANAGED_COMPONENT_LAST_ERROR=tproxy_host_policy_journal_failed
      return 1
    fi
  fi
  if ! managed_component_transaction_set_firewall_expected \
       "${lock_dir}" "$([[ "${old_listener_plan}" != "${new_listener_plan}" ]] && printf true || printf false)" ||
     ! managed_component_transaction_set_redirect_policy_expected \
       "${lock_dir}" "$([[ "${old_redirect_policy_plan}" != "${new_redirect_policy_plan}" ]] && printf true || printf false)" ||
     ! managed_component_transaction_set_tproxy_policy_expected \
       "${lock_dir}" "$([[ "${old_tproxy_policy_plan}" != "${new_tproxy_policy_plan}" ]] && printf true || printf false)" ||
     ! managed_component_transaction_checkpoint "${lock_dir}" resources; then
    managed_component_abort_component_transaction "${lock_dir}" "${snapshot}" "高级组件事务资源阶段记录失败" || :
    MANAGED_COMPONENT_LAST_ERROR=component_transaction_write_failed
    return 1
  fi
  if [[ "${old_listener_plan}" != "${new_listener_plan}" ]]; then
    firewall_journal="${snapshot}/component-firewall.json"
    if ! instance_firewall_prepare "${old_config}" "${SINGBOX_CONFIG_FILE}" "${firewall_journal}"; then
      firewall_summary=$(instance_transaction_firewall_summary "${firewall_journal}")
      managed_component_abort_component_transaction "${lock_dir}" "${snapshot}" "高级组件防火墙资源预检失败" || :
      MANAGED_COMPONENT_LAST_ERROR=firewall_prepare_failed
      return 1
    fi
    firewall_summary=$(instance_transaction_firewall_summary "${firewall_journal}")
    if ! instance_firewall_apply "${firewall_journal}"; then
      firewall_summary=$(instance_transaction_firewall_summary "${firewall_journal}")
      if ! instance_firewall_rollback "${firewall_journal}"; then
        MANAGED_COMPONENT_LAST_ERROR=firewall_rollback_failed
        if restore_managed_state_snapshot "${snapshot}"; then
          printf '[ERROR] 高级组件防火墙应用失败且外部资源回滚不确定；文件状态已恢复，事务快照保留在 %s。\n' \
            "${snapshot}" >&2
        else
          printf '[ERROR] 高级组件防火墙应用失败且自动回滚失败；事务快照保留在 %s。\n' \
            "${snapshot}" >&2
        fi
        return 1
      fi
      firewall_summary=$(instance_transaction_firewall_summary "${firewall_journal}")
      managed_component_abort_component_transaction "${lock_dir}" "${snapshot}" "高级组件防火墙资源应用失败" || :
      MANAGED_COMPONENT_LAST_ERROR=firewall_apply_failed
      return 1
    fi
    firewall_summary=$(instance_transaction_firewall_summary "${firewall_journal}")
  fi
  if ! managed_component_transaction_checkpoint "${lock_dir}" service; then
    if [[ -n "${firewall_journal}" ]] && ! instance_firewall_rollback "${firewall_journal}"; then
      MANAGED_COMPONENT_LAST_ERROR=firewall_rollback_failed
      if restore_managed_state_snapshot "${snapshot}"; then
        printf '[ERROR] 高级组件事务服务阶段记录失败且防火墙回滚不确定；文件状态已恢复，事务目录保留在 %s。\n' \
          "${lock_dir}" >&2
      else
        printf '[ERROR] 高级组件事务服务阶段记录失败且自动回滚失败；事务目录保留在 %s。\n' \
          "${lock_dir}" >&2
      fi
      return 1
    fi
    managed_component_abort_component_transaction "${lock_dir}" "${snapshot}" "高级组件事务服务阶段记录失败" || :
    MANAGED_COMPONENT_LAST_ERROR=component_transaction_write_failed
    return 1
  fi
  if [[ "${before_active}" == true ]]; then
    if ! run_with_progress "重启 sing-box（ACME 签发或 DNS 验证可能需要较长时间）" systemctl restart sing-box >/dev/null ||
       [[ "$(systemctl is-active sing-box 2>/dev/null || true)" != active ]]; then
      if [[ -n "${firewall_journal}" ]]; then
        if ! instance_firewall_rollback "${firewall_journal}"; then
          MANAGED_COMPONENT_LAST_ERROR=firewall_rollback_failed
          if restore_managed_state_snapshot "${snapshot}"; then
            printf '[ERROR] 高级组件服务重启失败且防火墙回滚不确定；文件状态已恢复，事务快照保留在 %s。\n' \
              "${snapshot}" >&2
          else
            printf '[ERROR] 高级组件服务重启失败且自动回滚失败；事务快照保留在 %s。\n' \
              "${snapshot}" >&2
          fi
          return 1
        fi
        firewall_summary=$(instance_transaction_firewall_summary "${firewall_journal}")
      fi
      managed_component_abort_component_transaction "${lock_dir}" "${snapshot}" "高级组件服务重启失败" y || :
      MANAGED_COMPONENT_LAST_ERROR=service_restart_failed
      return 1
    fi
    service_restarted=true
  fi
  if [[ "${service_restarted}" == true ]] &&
     jq -e 'any(.inbounds[]?; .type == "tun") or
       any(.outbounds[]?; .type == "bridge") or
       any(.endpoints[]?;
         (
           ((.type == "wireguard" or .type == "openconnect" or
             .type == "openvpn-client" or .type == "openvpn-server") and
            .system == true and ((.name // "") | length > 0)) or
           (.type == "tailscale" and .system_interface == true and
            ((.system_interface_name // "") | length > 0))
         ))' \
       "${SINGBOX_CONFIG_FILE}" >/dev/null 2>&1; then
    if ! managed_component_transparent_runtime_healthy_with_retry "${SINGBOX_CONFIG_FILE}"; then
      if [[ -n "${firewall_journal}" ]]; then
        if ! instance_firewall_rollback "${firewall_journal}"; then
          MANAGED_COMPONENT_LAST_ERROR=firewall_rollback_failed
          if restore_managed_state_snapshot "${snapshot}"; then
            printf '[ERROR] 高级组件透明运行资源检查失败且防火墙回滚不确定；文件状态已恢复，事务快照保留在 %s。\n' \
              "${snapshot}" >&2
          else
            printf '[ERROR] 高级组件透明运行资源检查失败且自动回滚失败；事务快照保留在 %s。\n' \
              "${snapshot}" >&2
          fi
          return 1
        fi
        firewall_summary=$(instance_transaction_firewall_summary "${firewall_journal}")
      fi
      managed_component_abort_component_transaction "${lock_dir}" "${snapshot}" \
        "高级组件透明运行资源检查失败" y || :
      MANAGED_COMPONENT_LAST_ERROR=transparent_resource_check_failed
      return 1
    fi
  fi
  if [[ "${old_redirect_policy_plan}" != "${new_redirect_policy_plan}" ]]; then
    if ! managed_component_redirect_policy_apply_journal "${redirect_policy_journal}"; then
      managed_component_abort_transaction_with_resources "${lock_dir}" \
        "高级组件 Redirect 主机策略应用失败" || return 1
      MANAGED_COMPONENT_LAST_ERROR=host_policy_apply_failed
      return 1
    fi
  fi
  if [[ "${old_tproxy_policy_plan}" != "${new_tproxy_policy_plan}" ]]; then
    if ! managed_component_tproxy_policy_apply_journal "${tproxy_policy_journal}"; then
      managed_component_abort_transaction_with_resources "${lock_dir}" \
        "高级组件 TProxy 主机策略应用失败" || return 1
      MANAGED_COMPONENT_LAST_ERROR=tproxy_host_policy_apply_failed
      return 1
    fi
  fi
  redirect_policy_summary=$(managed_component_redirect_policy_diagnose_json "${candidate}") || {
    managed_component_abort_transaction_with_resources "${lock_dir}" \
      "高级组件 Redirect 主机策略 postcheck 失败" || return 1
    MANAGED_COMPONENT_LAST_ERROR=host_policy_postcheck_failed
    return 1
  }
  if [[ "${new_redirect_policy_plan}" != '[]' ]] &&
     ! jq -e '.status == "available"' <<< "${redirect_policy_summary}" >/dev/null 2>&1; then
    managed_component_abort_transaction_with_resources "${lock_dir}" \
      "高级组件 Redirect 主机策略 postcheck 缺少受管规则" || return 1
    MANAGED_COMPONENT_LAST_ERROR=host_policy_postcheck_failed
    return 1
  fi
  tproxy_policy_summary=$(managed_component_tproxy_policy_diagnose_json "${candidate}") || {
    managed_component_abort_transaction_with_resources "${lock_dir}" \
      "高级组件 TProxy 主机策略 postcheck 失败" || return 1
    MANAGED_COMPONENT_LAST_ERROR=tproxy_host_policy_postcheck_failed
    return 1
  }
  if [[ "${new_tproxy_policy_plan}" != '[]' ]] &&
     ! jq -e '.status == "available"' <<< "${tproxy_policy_summary}" >/dev/null 2>&1; then
    managed_component_abort_transaction_with_resources "${lock_dir}" \
      "高级组件 TProxy 主机策略 postcheck 缺少受管规则" || return 1
    MANAGED_COMPONENT_LAST_ERROR=tproxy_host_policy_postcheck_failed
    return 1
  fi
  if [[ -n "${firewall_journal}" ]]; then
    if ! instance_firewall_commit "${firewall_journal}"; then
      firewall_summary=$(instance_transaction_firewall_summary "${firewall_journal}")
      if ! instance_firewall_rollback "${firewall_journal}"; then
        MANAGED_COMPONENT_LAST_ERROR=firewall_rollback_failed
        if restore_managed_state_snapshot "${snapshot}"; then
          printf '[ERROR] 高级组件防火墙提交失败且外部资源回滚不确定；文件状态已恢复，事务快照保留在 %s。\n' \
            "${snapshot}" >&2
        else
          printf '[ERROR] 高级组件防火墙提交失败且自动回滚失败；事务快照保留在 %s。\n' \
            "${snapshot}" >&2
        fi
        return 1
      fi
      firewall_summary=$(instance_transaction_firewall_summary "${firewall_journal}")
      managed_component_abort_component_transaction "${lock_dir}" "${snapshot}" "高级组件防火墙资源提交失败" y || :
      MANAGED_COMPONENT_LAST_ERROR=firewall_commit_failed
      return 1
    fi
    firewall_summary=$(instance_transaction_firewall_summary "${firewall_journal}")
  fi
  if ! managed_component_transaction_checkpoint "${lock_dir}" committed; then
    if [[ -n "${firewall_journal}" ]] && ! instance_firewall_rollback "${firewall_journal}"; then
      MANAGED_COMPONENT_LAST_ERROR=firewall_rollback_failed
      if restore_managed_state_snapshot "${snapshot}"; then
        printf '[ERROR] 高级组件事务提交记录失败且防火墙回滚不确定；文件状态已恢复，事务目录保留在 %s。\n' \
          "${lock_dir}" >&2
      else
        printf '[ERROR] 高级组件事务提交记录失败且自动回滚失败；事务目录保留在 %s。\n' \
          "${lock_dir}" >&2
      fi
      return 1
    fi
    managed_component_abort_component_transaction "${lock_dir}" "${snapshot}" "高级组件事务提交记录失败" y || :
    MANAGED_COMPONENT_LAST_ERROR=component_transaction_write_failed
    return 1
  fi
  if ! rm -rf -- "${lock_dir}"; then
    MANAGED_COMPONENT_LAST_ERROR=component_cleanup_failed
    return 1
  fi
  role=$(jq -r '.role // empty' <<< "${result_record}")
  type=$(jq -r '.type // empty' <<< "${result_record}")
  tag=$(jq -r '.tag // empty' <<< "${result_record}")
  if [[ "${operation}" == delete ]]; then
    role=$(jq -r --arg id "${target_id}" '.components[] | select(.id == $id) | .role' <<< "${state}")
    type=$(jq -r --arg id "${target_id}" '.components[] | select(.id == $id) | .type' <<< "${state}")
    tag=$(jq -r --arg id "${target_id}" '.components[] | select(.id == $id) | .tag' <<< "${state}")
  fi
  result_id="${target_id}"
  if [[ -z "${result_id}" ]]; then
    result_id=$(jq -r '.id // empty' <<< "${result_record}")
  fi
  result_count=$(jq -r '.components | length' <<< "${candidate}") || result_count=0
  MANAGED_COMPONENT_LAST_RESULT=$(jq -cn --arg operation "${operation}" --arg revision "$(jq -r '.revision' <<< "${candidate}")" \
    --arg id "${result_id}" --arg role "${role}" --arg type "${type}" --arg tag "${tag}" \
    --argjson count "${result_count}" \
    --argjson service_restarted "${service_restarted}" \
    --argjson firewall "${firewall_summary}" \
    --argjson redirect_policy "${redirect_policy_summary}" \
    --argjson tproxy_policy "${tproxy_policy_summary}" \
    '{action:"component-apply",operation:$operation,revision:($revision|tonumber),
      id:(if $id == "" then null else $id end),
      role:(if $role == "" then null else $role end),
      type:(if $type == "" then null else $type end),
      tag:(if $tag == "" then null else $tag end),
      config_check:"passed",service_restarted:$service_restarted,firewall:$firewall,
      redirect_host_policy:$redirect_policy,tproxy_host_policy:$tproxy_policy} +
      (if $operation == "takeover" then {count:$count} else {} end)')
  return 0
}
