
managed_component_redirect_host_policy_validate_record() {
  local record=${1:-}
  [[ -n "${record}" ]] || return 1
  jq -e '
    if has("host_policy") and .type == "redirect" then
      . as $record | .host_policy as $policy |
      ($record.role == "inbound" and $record.type == "redirect" and
       ($record.enabled | type == "boolean") and
       $record.config.listen == "0.0.0.0" and
       ($record.config.listen_port | type == "number" and . == floor and . >= 1 and . <= 65535)) and
      ($policy | type == "object" and
        ((keys - ["ingress_interface","destination_ports","management_ports"]) | length == 0) and
        (.ingress_interface | type == "string" and length >= 1 and length <= 15 and
          test("^[A-Za-z0-9_.:-]+$")) and
        (.destination_ports | type == "array" and length >= 1 and length <= 15 and
          all(.[]; type == "number" and . == floor and . >= 1 and . <= 65535) and
          (unique | length) == length) and
        (.management_ports | type == "array" and length >= 1 and length <= 15 and
          all(.[]; type == "number" and . == floor and . >= 1 and . <= 65535) and
          (unique | length) == length and (index(22) != null)) and
        (($policy.destination_ports | index($record.config.listen_port)) == null) and
        all(.destination_ports[]; . as $port | ($policy.management_ports | index($port)) == null))
    else true end
  ' <<< "${record}" >/dev/null 2>&1
}

managed_component_tproxy_host_policy_validate_record() {
  local record=${1:-}
  [[ -n "${record}" ]] || return 1
  jq -e '
    if has("host_policy") and .type == "tproxy" then
      . as $record | .host_policy as $policy |
      ($record.role == "inbound" and $record.type == "tproxy" and
       ($record.enabled | type == "boolean") and
       $record.config.listen == "0.0.0.0" and
       ($record.config.listen_port | type == "number" and . == floor and . >= 1 and . <= 65535) and
       ($record.config.network | type == "array" and length >= 1 and length <= 2 and
         all(.[]; type == "string" and IN("tcp","udp")) and
         (unique | length) == length)) and
      ($policy | type == "object" and
        ((keys - ["ingress_interface","destination_ports","management_ports"]) | length == 0) and
        (.ingress_interface | type == "string" and length >= 1 and length <= 15 and
          test("^[A-Za-z0-9_.:-]+$")) and
        (.destination_ports | type == "array" and length >= 1 and length <= 15 and
          all(.[]; type == "number" and . == floor and . >= 1 and . <= 65535) and
          (unique | length) == length) and
        (.management_ports | type == "array" and length >= 1 and length <= 15 and
          all(.[]; type == "number" and . == floor and . >= 1 and . <= 65535) and
          (unique | length) == length and (index(22) != null)) and
        (($policy.destination_ports | index($record.config.listen_port)) == null) and
        all(.destination_ports[]; . as $port | ($policy.management_ports | index($port)) == null))
    else true end
  ' <<< "${record}" >/dev/null 2>&1
}

managed_component_state_validate_record() {
  local record=${1:-} role type tag registry_id config route_rules
  [[ -n "${record}" ]] || return 1
  jq -s -e '
    if length != 1 then false
    else .[0] |
      type == "object" and
      ((keys - ["id","role","type","tag","enabled","route_rules","config","host_policy"]) | length == 0) and
      (.id | type == "string") and (.role | type == "string") and
      (.type | type == "string") and (.tag | type == "string")
    end
  ' <<< "${record}" >/dev/null 2>&1 || return 1
  role=$(jq -r '.role // empty' <<< "${record}") || return 1
  type=$(jq -r '.type // empty' <<< "${record}") || return 1
  tag=$(jq -r '.tag // empty' <<< "${record}") || return 1
  registry_id=$(component_registry_resolve_id "${role}" "${type}") || return 1
  managed_component_state_id_valid "$(jq -r '.id // empty' <<< "${record}")" || return 1
  managed_component_tag_valid "${tag}" || return 1
  jq -e '.role | IN("inbound","endpoint","outbound","certificate_provider","http_client","service","network_namespace","rule_set")' \
    <<< "${record}" >/dev/null 2>&1 || return 1
  jq -e '.enabled | type == "boolean"' <<< "${record}" >/dev/null 2>&1 || return 1
  jq -e '.config | type == "object" and (has("type") | not) and (has("tag") | not)' \
    <<< "${record}" >/dev/null 2>&1 || return 1
  managed_component_redirect_host_policy_validate_record "${record}" || return 1
  managed_component_tproxy_host_policy_validate_record "${record}" || return 1
  if jq -e 'has("host_policy") and (.type | IN("redirect","tproxy") | not)' \
    <<< "${record}" >/dev/null 2>&1; then
    return 1
  fi
  route_rules=$(jq -c '.route_rules // []' <<< "${record}") || return 1
  managed_component_route_rules_validate_json "${route_rules}" || return 1
  config=$(jq -c '.config' <<< "${record}") || return 1

  if [[ ("${role}" == network_namespace || "${role}" == service || "${role}" == rule_set) &&
        "${route_rules}" != '[]' ]]; then
    return 1
  fi
  if [[ "${role}" == rule_set && "${tag}" == warp-* ]]; then
    return 1
  fi
  if [[ "${role}" == certificate_provider &&
        ("${tag}" == hy2-cert-provider || "${tag}" == anytls-cert-provider) ]]; then
    return 1
  fi

  # Reject the two built-in outbound owners.  Custom direct/block records are
  # supported, while replacing the safety defaults requires a future explicit
  # migration rather than creating duplicate tags in the generated graph.
  if [[ "${role}" == outbound && ("${tag}" == direct || "${tag}" == block) ]]; then
    return 1
  fi

  case "${role}:${type}" in
    inbound:direct)
      managed_component_direct_config_validate_json "${config}" || return 1
      ;;
    inbound:redirect)
      managed_component_redirect_config_validate_json "${config}" || return 1
      ;;
    inbound:tproxy)
      managed_component_tproxy_config_validate_json "${config}" || return 1
      ;;
    inbound:tun)
      managed_component_tun_config_validate_json "${config}" || return 1
      ;;
    inbound:cloudflared)
      managed_component_cloudflared_config_validate_json "${config}" || return 1
      ;;
    certificate_provider:acme)
      managed_component_certificate_provider_config_validate_json "${config}" || return 1
      ;;
    http_client:shared)
      managed_component_http_client_config_validate_json "${config}" || return 1
      ;;
    network_namespace:default|network_namespace:unshare)
      managed_component_network_namespace_config_validate_json "${type}" "${config}" || return 1
      ;;
    service:resolved)
      managed_component_resolved_service_config_validate_json "${config}" || return 1
      ;;
    rule_set:inline)
      managed_component_rule_set_inline_config_validate_json "${config}" || return 1
      ;;
    rule_set:local)
      managed_component_rule_set_local_config_validate_json "${config}" || return 1
      ;;
    rule_set:remote)
      managed_component_rule_set_remote_config_validate_json "${config}" || return 1
      ;;
    endpoint:wireguard)
      managed_component_wireguard_config_validate_json "${config}" || return 1
      ;;
    endpoint:tailscale)
      managed_component_tailscale_config_validate_json "${config}" || return 1
      ;;
    endpoint:openconnect)
      managed_component_openconnect_config_validate_json "${config}" || return 1
      ;;
    endpoint:openvpn-client)
      managed_component_openvpn_client_config_validate_json "${config}" || return 1
      ;;
    endpoint:openvpn-server)
      managed_component_openvpn_server_config_validate_json "${config}" || return 1
      ;;
    outbound:selector|outbound:urltest)
      managed_component_group_config_validate_json "${type}" "${config}" || return 1
      ;;
    outbound:ssh)
      managed_component_ssh_config_validate_json "${config}" || return 1
      ;;
    outbound:tor)
      managed_component_tor_config_validate_json "${config}" || return 1
      ;;
    outbound:socks)
      managed_component_socks_config_validate_json "${config}" || return 1
      ;;
    outbound:http)
      managed_component_http_config_validate_json "${config}" || return 1
      ;;
    outbound:shadowsocks)
      managed_component_shadowsocks_config_validate_json "${config}" || return 1
      ;;
    outbound:anytls)
      managed_component_anytls_config_validate_json "${config}" || return 1
      ;;
    outbound:snell)
      managed_component_snell_config_validate_json "${config}" || return 1
      ;;
    outbound:hysteria2)
      managed_component_hysteria2_config_validate_json "${config}" || return 1
      ;;
    outbound:hysteria)
      managed_component_hysteria_config_validate_json "${config}" || return 1
      ;;
    outbound:tuic)
      managed_component_tuic_config_validate_json "${config}" || return 1
      ;;
    outbound:naive)
      managed_component_naive_config_validate_json "${config}" || return 1
      ;;
    outbound:shadowtls)
      managed_component_shadowtls_config_validate_json "${config}" || return 1
      ;;
    outbound:vless|outbound:vmess|outbound:trojan)
      managed_component_v2ray_outbound_config_validate_json "${type}" "${config}" || return 1
      ;;
    outbound:direct)
      managed_component_direct_outbound_config_validate_json "${config}" || return 1
      ;;
    outbound:block)
      managed_component_block_outbound_config_validate_json "${config}" || return 1
      ;;
    outbound:bridge)
      managed_component_bridge_outbound_config_validate_json "${config}" || return 1
      ;;
    *) return 1 ;;
  esac
  [[ -n "${registry_id}" ]]
}

managed_component_state_validate_json() {
  local state=${1:-} record
  [[ -n "${state}" ]] || return 1
  jq -s -e --argjson schema "${SB_COMPONENT_STATE_SCHEMA_VERSION}" '
    if length != 1 then false
    else .[0] |
      type == "object" and
      ((keys - ["schema_version","revision","components"]) | length == 0) and
      .schema_version == $schema and
      (.revision | type == "number" and . == floor and . >= 0 and . <= 9007199254740991) and
      (.components | type == "array" and length <= 128) and
      (([.components[]?.id] | unique | length) == (.components | length)) and
      (([.components[]?.tag] | unique | length) == (.components | length)) and
      all(.components[]; type == "object" and
        (.id | type == "string") and (.role | type == "string") and
        (.type | type == "string") and (.tag | type == "string") and
        (.enabled | type == "boolean") and (.config | type == "object") and
        ((.route_rules // []) | type == "array"))
    end
  ' <<< "${state}" >/dev/null 2>&1 || return 1
  while IFS= read -r record; do
    [[ -n "${record}" ]] || continue
    managed_component_state_validate_record "${record}" || return 1
  done < <(jq -c '.components[]' <<< "${state}")
}

managed_component_state_json() (
  local snapshot result
  if [[ ! -e "${SB_COMPONENT_STATE_FILE}" ]]; then
    managed_component_state_default_json
    return 0
  fi
  [[ -f "${SB_COMPONENT_STATE_FILE}" && ! -L "${SB_COMPONENT_STATE_FILE}" && -r "${SB_COMPONENT_STATE_FILE}" ]] || return 1
  snapshot=$(mktemp /tmp/sbv-components.XXXXXX) || return 1
  trap 'rm -f -- "${snapshot}"' EXIT
  head -c 4194305 -- "${SB_COMPONENT_STATE_FILE}" > "${snapshot}" || return 1
  [[ "$(wc -c < "${snapshot}")" -le 4194304 ]] || return 1
  result=$(jq -cS '.' "${snapshot}") || return 1
  managed_component_state_validate_json "${result}" || return 1
  printf '%s\n' "${result}"
)

managed_component_normalize_input_file() (
  local input=${1:-} snapshot result
  [[ -f "${input}" && ! -L "${input}" && -r "${input}" ]] || return 1
  snapshot=$(mktemp /tmp/sbv-component-record.XXXXXX) || return 1
  trap 'rm -f -- "${snapshot}"' EXIT
  head -c 1048577 -- "${input}" > "${snapshot}" || return 1
  [[ "$(wc -c < "${snapshot}")" -le 1048576 ]] || return 1
  result=$(jq -cS '
    if type != "object" then error("record") else . as $r |
      if ($r | has("config")) and
         ((($r | keys) - ["id","role","type","tag","enabled","route_rules","config","host_policy"]) | length > 0)
      then error("unknown_record_field") else
      {
        id: $r.id,
        role: $r.role,
        type: $r.type,
        tag: $r.tag,
        enabled: (if ($r | has("enabled")) then $r.enabled else true end),
        route_rules: ($r.route_rules // []),
        config: (if ($r | has("config")) then $r.config
                 else $r | del(.id,.role,.type,.tag,.enabled,.route_rules,.host_policy) end)
      } + (if $r | has("host_policy") then {host_policy:$r.host_policy} else {} end)
      end
    end' "${snapshot}") || return 1
  managed_component_state_validate_record "${result}" || return 1
  printf '%s\n' "${result}"
)

managed_component_render_json() {
  local state=${1:-}
  [[ -n "${state}" ]] || state=$(managed_component_state_json) || return 1
  managed_component_state_validate_json "${state}" || return 1
  jq -c '
    def enabled: select(.enabled == true);
    .components as $components |
    {
      inbounds: [$components[] | enabled | select(.role == "inbound") |
        .config + {type:.type, tag:.tag}],
      endpoints: [$components[] | enabled | select(.role == "endpoint") |
        .config + {type:.type, tag:.tag}],
      outbounds: [$components[] | enabled | select(.role == "outbound") |
        .config + {type:.type, tag:.tag}],
      certificate_providers: [$components[] | enabled | select(.role == "certificate_provider") |
        .config + {type:.type, tag:.tag}],
      http_clients: [$components[] | enabled | select(.role == "http_client") |
        .config + {tag:.tag}],
      services: [$components[] | enabled | select(.role == "service") |
        .config + {type:.type, tag:.tag}],
      network_namespaces: [$components[] | enabled | select(.role == "network_namespace") |
        .config + {type:.type, tag:.tag}],
      rule_sets: [$components[] | enabled | select(.role == "rule_set") |
        .config + {type:.type, tag:.tag}],
      route_rules: [$components[] | enabled | (.route_rules // [])[]]
  }' <<< "${state}"
}

managed_component_redirect_host_policy_plan_for_record() {
  local record=${1:-} component_id interface_name listen_port destination_ports management_ports
  local digest policy_id chain marker
  managed_component_redirect_host_policy_validate_record "${record}" || return 1
  jq -e 'has("host_policy")' <<< "${record}" >/dev/null 2>&1 || return 2
  component_id=$(jq -r '.id' <<< "${record}") || return 1
  interface_name=$(jq -r '.host_policy.ingress_interface' <<< "${record}") || return 1
  listen_port=$(jq -r '.config.listen_port' <<< "${record}") || return 1
  destination_ports=$(jq -r '.host_policy.destination_ports | sort | map(tostring) | join(",")' <<< "${record}") || return 1
  management_ports=$(jq -r '.host_policy.management_ports | sort | map(tostring) | join(",")' <<< "${record}") || return 1
  digest=$(printf '%s\0' "${component_id}" "${interface_name}" "${destination_ports}" \
    "${management_ports}" "${listen_port}" | sha256sum | awk '{print $1}') || return 1
  [[ "${digest}" =~ ^[[:xdigit:]]{64}$ ]] || return 1
  policy_id=${digest:0:20}
  chain="${MANAGED_REDIRECT_POLICY_CHAIN_PREFIX}${policy_id}"
  marker="${MANAGED_REDIRECT_POLICY_COMMENT_PREFIX}${policy_id}"
  jq -cn --arg id "${component_id}" --arg tag "$(jq -r '.tag' <<< "${record}")" \
    --arg interface "${interface_name}" --arg chain "${chain}" --arg marker "${marker}" \
    --argjson listen_port "${listen_port}" \
    --argjson destination_ports "$(jq -c '.host_policy.destination_ports | sort' <<< "${record}")" \
    --argjson management_ports "$(jq -c '.host_policy.management_ports | sort' <<< "${record}")" \
    '{id:$id,tag:$tag,chain:$chain,marker:$marker,interface:$interface,
      destination_ports:$destination_ports,management_ports:$management_ports,
      listen_port:$listen_port,family:"ipv4",transport:"tcp"}'
}

managed_component_redirect_host_policy_plan_json() {
  local state=${1:-} record plan
  local plans=()
  managed_component_state_validate_json "${state}" || return 1
  while IFS= read -r record; do
    [[ -n "${record}" ]] || continue
    jq -e 'has("host_policy") and .enabled == true and .type == "redirect"' \
      <<< "${record}" >/dev/null 2>&1 || continue
    plan=$(managed_component_redirect_host_policy_plan_for_record "${record}") || return 1
    plans+=("${plan}")
  done < <(jq -c '.components[]' <<< "${state}")
  if ((${#plans[@]} == 0)); then
    printf '[]\n'
  else
    printf '%s\n' "${plans[@]}" | jq -sc 'sort_by(.id)'
  fi
}

managed_component_redirect_host_policy_plan_validate_json() {
  local plans=${1:-}
  [[ -n "${plans}" ]] || return 1
  jq -s -e '
    length == 1 and
    (.[0] | type == "array" and length <= 128 and
      all(.[]; . as $plan |
        ($plan | type == "object" and
          ((keys - ["id","tag","chain","marker","interface","destination_ports","management_ports","listen_port","family","transport"]) | length == 0) and
          (.id | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")) and
          (.tag | type == "string" and length > 0 and length <= 128) and
          (.chain | type == "string" and test("^SBVR_[a-f0-9]{20}$")) and
          (.marker | type == "string" and test("^sbv-redirect-[a-f0-9]{20}$")) and
          (.interface | type == "string" and length >= 1 and length <= 15 and test("^[A-Za-z0-9_.:-]+$")) and
          (.destination_ports | type == "array" and length >= 1 and length <= 15 and
            all(.[]; type == "number" and . == floor and . >= 1 and . <= 65535) and
            (unique | length) == length) and
          (.management_ports | type == "array" and length >= 1 and length <= 15 and
            all(.[]; type == "number" and . == floor and . >= 1 and . <= 65535) and
            (unique | length) == length) and
          (.listen_port | type == "number" and . == floor and . >= 1 and . <= 65535) and
          .family == "ipv4" and .transport == "tcp" and
          (.chain | ltrimstr("SBVR_")) == (.marker | ltrimstr("sbv-redirect-"))) and
        all($plan.destination_ports[]; . as $port | ($plan.management_ports | index($port)) == null) and
        ($plan.destination_ports | index($plan.listen_port)) == null
      ) and
      ([.[].chain] | unique | length) == length and
      ([.[].id] | unique | length) == length)
  ' <<< "${plans}" >/dev/null 2>&1
}

managed_component_redirect_policy_plan_has_chain() {
  local plans=${1:-} chain=${2:-}
  jq -e --arg chain "${chain}" 'any(.[]; .chain == $chain)' <<< "${plans}" >/dev/null 2>&1
}

# Return one of absent/present/partial/conflict/unavailable.  Inspection uses
# the complete nat table and exact `-C` probes; it never infers ownership from
# a rule's port alone.
managed_component_redirect_policy_probe() {
  local plan=${1:-} rules chain chain_output interface_name destination_ports listen_port marker
  local chain_count rule_count reference_count marker_count rule_status=1 jump_status=1 status
  managed_component_redirect_host_policy_plan_validate_json "[$plan]" || { printf 'conflict\n'; return 0; }
  command -v iptables >/dev/null 2>&1 || { printf 'unavailable\n'; return 0; }
  chain=$(jq -r '.chain' <<< "${plan}") || return 1
  interface_name=$(jq -r '.interface' <<< "${plan}") || return 1
  destination_ports=$(jq -r '.destination_ports | sort | map(tostring) | join(",")' <<< "${plan}") || return 1
  listen_port=$(jq -r '.listen_port' <<< "${plan}") || return 1
  marker=$(jq -r '.marker' <<< "${plan}") || return 1
  rules=$(iptables -t nat -S 2>/dev/null) || { printf 'unavailable\n'; return 0; }
  chain_count=$(awk -v chain="${chain}" '$1 == "-N" && $2 == chain { count++ } END { print count+0 }' <<< "${rules}") || return 1
  marker_count=$(awk -v marker="${marker}" 'index($0, marker) { count++ } END { print count+0 }' <<< "${rules}") || return 1
  reference_count=$(awk -v chain="${chain}" '$1 == "-A" && $2 != chain && $NF == chain { count++ } END { print count+0 }' <<< "${rules}") || return 1
  if [[ "${chain_count}" == 0 ]]; then
    if [[ "${marker_count}" == 0 && "${reference_count}" == 0 ]]; then
      printf 'absent\n'
    else
      printf 'conflict\n'
    fi
    return 0
  fi
  [[ "${chain_count}" == 1 ]] || { printf 'conflict\n'; return 0; }
  chain_output=$(iptables -t nat -S "${chain}" 2>/dev/null) || { printf 'unavailable\n'; return 0; }
  rule_count=$(awk '$1 == "-A" { count++ } END { print count+0 }' <<< "${chain_output}") || return 1
  if iptables -t nat -C "${chain}" -i "${interface_name}" -p tcp -m multiport \
    --dports "${destination_ports}" -j REDIRECT --to-ports "${listen_port}" >/dev/null 2>&1; then
    rule_status=0
  else
    status=$?
    [[ "${status}" == 1 ]] || { printf 'unavailable\n'; return 0; }
  fi
  if iptables -t nat -C PREROUTING -m comment --comment "${marker}" -j "${chain}" >/dev/null 2>&1; then
    jump_status=0
  else
    status=$?
    [[ "${status}" == 1 ]] || { printf 'unavailable\n'; return 0; }
  fi
  if [[ "${marker_count}" == 1 && "${reference_count}" == 1 && "${rule_count}" == 1 &&
        "${rule_status}" == 0 && "${jump_status}" == 0 ]]; then
    printf 'present\n'
  elif [[ "${marker_count}" == 0 && "${reference_count}" == 0 &&
          ( "${rule_count}" == 0 || ( "${rule_count}" == 1 && "${rule_status}" == 0 ) ) ]]; then
    printf 'partial\n'
  else
    printf 'conflict\n'
  fi
}

managed_component_redirect_policy_ensure_plan() {
  local plan=${1:-} allow_partial=${2:-false} status chain interface_name destination_ports listen_port marker
  managed_component_redirect_host_policy_plan_validate_json "[$plan]" || return 1
  status=$(managed_component_redirect_policy_probe "${plan}") || return 1
  case "${status}" in
    present) return 0 ;;
    absent) ;;
    partial)
      [[ "${allow_partial}" == true ]] || return 1
      ;;
    *) return 1 ;;
  esac
  chain=$(jq -r '.chain' <<< "${plan}") || return 1
  interface_name=$(jq -r '.interface' <<< "${plan}") || return 1
  destination_ports=$(jq -r '.destination_ports | sort | map(tostring) | join(",")' <<< "${plan}") || return 1
  listen_port=$(jq -r '.listen_port' <<< "${plan}") || return 1
  marker=$(jq -r '.marker' <<< "${plan}") || return 1
  if [[ "${status}" == absent ]]; then
    iptables -t nat -N "${chain}" || return 1
  fi
  if ! iptables -t nat -C "${chain}" -i "${interface_name}" -p tcp -m multiport \
    --dports "${destination_ports}" -j REDIRECT --to-ports "${listen_port}" >/dev/null 2>&1; then
    iptables -t nat -A "${chain}" -i "${interface_name}" -p tcp -m multiport \
      --dports "${destination_ports}" -j REDIRECT --to-ports "${listen_port}" || return 1
  fi
  if ! iptables -t nat -C PREROUTING -m comment --comment "${marker}" -j "${chain}" >/dev/null 2>&1; then
    iptables -t nat -A PREROUTING -m comment --comment "${marker}" -j "${chain}" || return 1
  fi
  [[ "$(managed_component_redirect_policy_probe "${plan}")" == present ]]
}

managed_component_redirect_policy_remove_plan() {
  local plan=${1:-} allow_partial=${2:-false} status chain marker
  managed_component_redirect_host_policy_plan_validate_json "[$plan]" || return 1
  status=$(managed_component_redirect_policy_probe "${plan}") || return 1
  [[ "${status}" == absent ]] && return 0
  [[ "${status}" == present || ( "${status}" == partial && "${allow_partial}" == true ) ]] || return 1
  chain=$(jq -r '.chain' <<< "${plan}") || return 1
  marker=$(jq -r '.marker' <<< "${plan}") || return 1
  if [[ "${status}" == present ]]; then
    iptables -t nat -D PREROUTING -m comment --comment "${marker}" -j "${chain}" || return 1
  fi
  iptables -t nat -F "${chain}" || return 1
  iptables -t nat -X "${chain}" || return 1
  [[ "$(managed_component_redirect_policy_probe "${plan}")" == absent ]]
}

managed_component_redirect_policy_precedence_json() {
  local plan=${1:-} marker rules preceding status
  managed_component_redirect_host_policy_plan_validate_json "[${plan}]" || return 1
  marker=$(jq -r '.marker' <<< "${plan}") || return 1
  if ! command -v iptables >/dev/null 2>&1 ||
     ! rules=$(iptables -t nat -S PREROUTING 2>/dev/null); then
    jq -cn '{status:"unavailable",preceding_rule_count:null}'
    return 0
  fi
  preceding=$(awk -v marker="${marker}" '
    $1 == "-A" && $2 == "PREROUTING" {
      if (index($0, marker)) { found=1; exit }
      count++
    }
    END { if (!found) exit 1; print count+0 }
  ' <<< "${rules}") || {
    jq -cn '{status:"unavailable",preceding_rule_count:null}'
    return 0
  }
  if [[ "${preceding}" == 0 ]]; then
    status=unshadowed_in_observed_order
  else
    status=not_assessed_earlier_rules_present
  fi
  jq -cn --arg status "${status}" --argjson count "${preceding}" \
    '{status:$status,preceding_rule_count:$count}'
}

managed_component_redirect_policy_preflight() {
  local before=${1:-} after=${2:-} plan status interface_name
  managed_component_redirect_host_policy_plan_validate_json "${before}" || return 1
  managed_component_redirect_host_policy_plan_validate_json "${after}" || return 1
  if ((${#after} > 2)); then
    command -v iptables >/dev/null 2>&1 || return 1
    iptables -t nat -S >/dev/null 2>&1 || return 1
  fi
  while IFS= read -r plan; do
    [[ -n "${plan}" ]] || continue
    status=$(managed_component_redirect_policy_probe "${plan}") || return 1
    [[ "${status}" == present ]] || return 1
  done < <(jq -c '.[]' <<< "${before}")
  while IFS= read -r plan; do
    [[ -n "${plan}" ]] || continue
    if managed_component_redirect_policy_plan_has_chain "${before}" "$(jq -r '.chain' <<< "${plan}")"; then
      continue
    fi
    status=$(managed_component_redirect_policy_probe "${plan}") || return 1
    [[ "${status}" == absent ]] || return 1
    interface_name=$(jq -r '.interface' <<< "${plan}") || return 1
    command -v ip >/dev/null 2>&1 || return 1
    ip link show dev "${interface_name}" >/dev/null 2>&1 || return 1
  done < <(jq -c '.[]' <<< "${after}")
}

managed_component_redirect_policy_journal_path_valid() {
  local journal_file=${1:-}
  [[ "${journal_file}" == "${SB_COMPONENT_TRANSACTION_DIR}/snapshot/component-redirect-policy.json" &&
     -d "${SB_COMPONENT_TRANSACTION_DIR}/snapshot" &&
     ! -L "${SB_COMPONENT_TRANSACTION_DIR}" && ! -L "${SB_COMPONENT_TRANSACTION_DIR}/snapshot" ]] || return 1
}

managed_component_redirect_policy_journal_validate() {
  local journal_file=${1:-} before after
  managed_component_redirect_policy_journal_path_valid "${journal_file}" || return 1
  [[ -f "${journal_file}" && ! -L "${journal_file}" && -r "${journal_file}" ]] || return 1
  [[ "$(stat -c '%a' "${journal_file}")" == 600 ]] || return 1
  if ! jq -ce '
    type == "object" and ((keys - ["schema_version","status","before","after"]) | length == 0) and
    .schema_version == 1 and (.status | IN("prepared","applying","applied","rolling_back","rolled_back")) and
    (.before | type == "array") and (.after | type == "array") and
    true
  ' "${journal_file}" >/dev/null 2>&1; then
    return 1
  fi
  before=$(jq -c '.before' "${journal_file}") || return 1
  after=$(jq -c '.after' "${journal_file}") || return 1
  managed_component_redirect_host_policy_plan_validate_json "${before}" || return 1
  managed_component_redirect_host_policy_plan_validate_json "${after}"
}

managed_component_redirect_policy_journal_write() {
  local journal_file=${1:-} before=${2:-} after=${3:-} candidate payload
  managed_component_redirect_policy_journal_path_valid "${journal_file}" || return 1
  [[ ! -e "${journal_file}" && ! -L "${journal_file}" ]] || return 1
  managed_component_redirect_host_policy_plan_validate_json "${before}" || return 1
  managed_component_redirect_host_policy_plan_validate_json "${after}" || return 1
  payload=$(jq -cn --argjson before "${before}" --argjson after "${after}" \
    '{schema_version:1,status:"prepared",before:$before,after:$after}') || return 1
  candidate=$(mktemp "${journal_file%/*}/.component-redirect-policy.XXXXXX") || return 1
  if ! printf '%s\n' "${payload}" > "${candidate}" || ! chmod 600 "${candidate}" ||
     ! mv -f -- "${candidate}" "${journal_file}"; then
    rm -f -- "${candidate}"
    return 1
  fi
  managed_component_redirect_policy_journal_validate "${journal_file}"
}

managed_component_redirect_policy_journal_set_status() {
  local journal_file=${1:-} status=${2:-} candidate
  managed_component_redirect_policy_journal_validate "${journal_file}" || return 1
  [[ "${status}" =~ ^(prepared|applying|applied|rolling_back|rolled_back)$ ]] || return 1
  candidate=$(mktemp "${journal_file%/*}/.component-redirect-policy.XXXXXX") || return 1
  if ! jq --arg status "${status}" '.status=$status' "${journal_file}" > "${candidate}" ||
     ! chmod 600 "${candidate}" || ! mv -f -- "${candidate}" "${journal_file}"; then
    rm -f -- "${candidate}"
    return 1
  fi
  managed_component_redirect_policy_journal_validate "${journal_file}"
}

managed_component_redirect_policy_apply_journal() {
  local journal_file=${1:-} before after plan
  managed_component_redirect_policy_journal_validate "${journal_file}" || return 1
  before=$(jq -c '.before' "${journal_file}") || return 1
  after=$(jq -c '.after' "${journal_file}") || return 1
  managed_component_redirect_policy_journal_set_status "${journal_file}" applying || return 1
  while IFS= read -r plan; do
    [[ -n "${plan}" ]] || continue
    managed_component_redirect_policy_ensure_plan "${plan}" false || return 1
  done < <(jq -c '.[]' <<< "${after}")
  while IFS= read -r plan; do
    [[ -n "${plan}" ]] || continue
    if ! managed_component_redirect_policy_plan_has_chain "${after}" "$(jq -r '.chain' <<< "${plan}")"; then
      managed_component_redirect_policy_remove_plan "${plan}" || return 1
    fi
  done < <(jq -c '.[]' <<< "${before}")
  managed_component_redirect_policy_journal_set_status "${journal_file}" applied
}

managed_component_redirect_policy_remove_delta() {
  local journal_file=${1:-} status before after plan
  managed_component_redirect_policy_journal_validate "${journal_file}" || return 1
  status=$(jq -r '.status' "${journal_file}") || return 1
  [[ "${status}" == prepared || "${status}" == rolled_back ]] && return 0
  managed_component_redirect_policy_journal_set_status "${journal_file}" rolling_back || return 1
  before=$(jq -c '.before' "${journal_file}") || return 1
  after=$(jq -c '.after' "${journal_file}") || return 1
  while IFS= read -r plan; do
    [[ -n "${plan}" ]] || continue
    if ! managed_component_redirect_policy_plan_has_chain "${before}" "$(jq -r '.chain' <<< "${plan}")"; then
      managed_component_redirect_policy_remove_plan "${plan}" true || return 1
    fi
  done < <(jq -c '.[]' <<< "${after}")
}

managed_component_redirect_policy_restore_before() {
  local journal_file=${1:-} status before plan
  managed_component_redirect_policy_journal_validate "${journal_file}" || return 1
  status=$(jq -r '.status' "${journal_file}") || return 1
  [[ "${status}" == prepared || "${status}" == rolled_back ]] && return 0
  before=$(jq -c '.before' "${journal_file}") || return 1
  while IFS= read -r plan; do
    [[ -n "${plan}" ]] || continue
    managed_component_redirect_policy_ensure_plan "${plan}" true || return 1
  done < <(jq -c '.[]' <<< "${before}")
  managed_component_redirect_policy_journal_set_status "${journal_file}" rolled_back
}

managed_component_redirect_policy_diagnose_json() {
  local state=${1:-} plans plan status precedence row resources_json
  local resources=() operators='[]' overall=available
  plans=$(managed_component_redirect_host_policy_plan_json "${state}") || return 1
  managed_component_redirect_host_policy_plan_validate_json "${plans}" || return 1
  while IFS= read -r plan; do
    [[ -n "${plan}" ]] || continue
    status=$(managed_component_redirect_policy_probe "${plan}") || return 1
    precedence=$(managed_component_redirect_policy_precedence_json "${plan}") || return 1
    [[ "${status}" == present ]] || overall=unavailable
    row=$(jq -cn --argjson plan "${plan}" --arg status "${status}" \
      --argjson precedence "${precedence}" \
      '$plan + {resource_scope:"installer_owned_ipv4_tcp_prerouting",status:$status,
        precedence:$precedence.status,preceding_rule_count:$precedence.preceding_rule_count}') || return 1
    resources+=("${row}")
  done < <(jq -c '.[]' <<< "${plans}")
  if ((${#resources[@]} > 0)); then
    resources_json=$(printf '%s\n' "${resources[@]}" | jq -sc '.') || return 1
  else
    resources_json='[]'
    [[ "${overall}" == available ]] && overall=not_configured
  fi
  operators=$(jq -c '[.components[] | select(.enabled == true and .role == "inbound" and .type == "tproxy" and (has("host_policy") | not)) |
    {id,tag,type,resource_scope:"operator_policy_required",status:"not_managed"}]' <<< "${state}") || return 1
  jq -cn --arg status "${overall}" --argjson resources "${resources_json}" --argjson operators "${operators}" \
    '{status:$status,managed_backend:"iptables",managed_family:"ipv4",managed_transport:"tcp",
      ordering:"append_after_existing_prerouting_rules",
      resources:$resources,operator_managed:$operators,
      limitations:["only explicit Redirect IPv4/TCP policies are installer-owned","TProxy policies are reported separately","management ports are protected by exact destination-port allowlists","earlier PREROUTING rules may change effective precedence; effectiveness is not assessed when such rules exist"]}'
}

managed_component_redirect_policy_uninstall() {
  local plans=${1:-} plan status nat_rules
  managed_component_redirect_host_policy_plan_validate_json "${plans}" || return 1
  if [[ "${plans}" == '[]' ]] && command -v iptables >/dev/null 2>&1 &&
     nat_rules=$(iptables -t nat -S 2>/dev/null); then
    if grep -E 'SBVR_[a-f0-9]{20}|sbv-redirect-[a-f0-9]{20}' <<< "${nat_rules}" >/dev/null; then
      printf '[ERROR] 检测到缺少 state 所属记录的 Redirect 受管链；拒绝卸载以避免遗留或误删主机规则。\n' >&2
      return 1
    fi
  fi
  while IFS= read -r plan; do
    [[ -n "${plan}" ]] || continue
    status=$(managed_component_redirect_policy_probe "${plan}") || return 1
    case "${status}" in
      absent|present|partial) ;;
      *) return 1 ;;
    esac
  done < <(jq -c '.[]' <<< "${plans}")
  while IFS= read -r plan; do
    [[ -n "${plan}" ]] || continue
    managed_component_redirect_policy_remove_plan "${plan}" true || return 1
  done < <(jq -c '.[]' <<< "${plans}")
}
