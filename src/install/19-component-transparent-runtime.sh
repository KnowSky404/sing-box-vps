
# An auto-routed TUN must have an explicit host-route loop guard.  The
# generator can safely add auto_detect_interface when the existing route does
# not choose another interface, but it must not silently override an operator's
# explicit unsafe setting.  This is a config-level guard only; it does not
# claim to manage the host's complete policy-routing or firewall state.
managed_component_tun_route_options_json() {
  local components=${1:-} route='{}'
  [[ -n "${components}" ]] || return 1
  jq -e 'type == "object" and (.inbounds | type == "array")' <<< "${components}" >/dev/null 2>&1 || return 1
  if ! jq -e 'any(.inbounds[]?; .type == "tun" and .auto_route == true)' <<< "${components}" >/dev/null 2>&1; then
    printf '{}\n'
    return 0
  fi
  if [[ -e "${SINGBOX_CONFIG_FILE}" ]]; then
    [[ -f "${SINGBOX_CONFIG_FILE}" && ! -L "${SINGBOX_CONFIG_FILE}" && -r "${SINGBOX_CONFIG_FILE}" ]] || return 1
    route=$(jq -c 'if has("route") then .route else {} end' "${SINGBOX_CONFIG_FILE}") || return 1
    jq -e 'type == "object" and
      ((has("auto_detect_interface") | not) or (.auto_detect_interface | type == "boolean")) and
      ((has("default_interface") | not) or (.default_interface | type == "string"))' \
      <<< "${route}" >/dev/null 2>&1 || return 1
    if jq -e '.auto_detect_interface == false and
      ((.default_interface // "") == "")' <<< "${route}" >/dev/null 2>&1; then
      printf '[ERROR] component_route: tun_auto_route_loop_guard_conflict; 请启用 route.auto_detect_interface 或设置 route.default_interface。\n' >&2
      return 1
    fi
    if jq -e 'has("auto_detect_interface") or
      (has("default_interface") and ((.default_interface // "") | length > 0))' \
      <<< "${route}" >/dev/null 2>&1; then
      jq -c 'with_entries(select(.key == "auto_detect_interface" or
        (.key == "default_interface" and ((.value // "") | length > 0))))' <<< "${route}"
      return 0
    fi
  fi
  printf '%s\n' '{"auto_detect_interface":true}'
}

# Inspect resources which are created by a running transparent inbound.  The
# sing-box process owns TUN interfaces, iproute2 rules/routes and auto-redirect
# nftables state; the installer must not try to infer ownership from arbitrary
# host rules or delete an operator's policy.  Redirect/TProxy listeners still
# need an operator-owned PREROUTING policy, so those resources are explicitly
# reported as not assessed rather than being mistaken for a complete data
# plane.  This function is read-only and bounded: it is used by diagnose and
# never mutates the network namespace.
managed_component_transparent_resources_json() (
  local config_file=${1:-${SINGBOX_CONFIG_FILE:-}} service_state=${2:-unknown}
  local snapshot records='[]' resources='[]' status=not_assessed reason=service_inactive
  local tun_count=0 bridge_count=0 system_endpoint_count=0 record tag type interface_name auto_route auto_redirect
  local table_index rule_index link_status route_status rule_status nft_status
  local bridge_name bound_interface bridge_interface_name bridge_port bridge_index
  local bridge_table bridge_rule bridge_octet bridge_configured_table bridge_configured_rule
  local system_interface_name system_addresses system_mtu system_address_count system_reason_prefix
  local expected_address expected_addr expected_prefix actual_mtu
  local interface_status address_status mtu_status
  local link_file address_file rule_file route_file nft_file output_size
  [[ -f "${config_file}" && ! -L "${config_file}" && -r "${config_file}" ]] || return 1
  snapshot=$(storage_mktemp -d "${SB_DATA_ROOT}/tmp/sbv-transparent-resources.XXXXXX") || return 1
  trap 'rm -rf -- "${snapshot}"' EXIT INT TERM HUP
  head -c 4194305 -- "${config_file}" > "${snapshot}/config.json" || return 1
  [[ "$(wc -c < "${snapshot}/config.json")" -le 4194304 ]] || return 1
  records=$(jq -c '
    [
      (.inbounds[]? | select(.type == "tun" or .type == "redirect" or .type == "tproxy") |
        {tag:(.tag // ""),type:.type,interface_name:(.interface_name // "tun0"),
         auto_route:(.auto_route // false),auto_redirect:(.auto_redirect // false),
         table_index:(.iproute2_table_index // null),rule_index:(.iproute2_rule_index // null),
         bridge_name:(.bridge_name // "bridge"),bound_interface:(.interface // ""),
         listen:(.listen // ""),listen_port:(.listen_port // 0),system_interface:false,
         addresses:[],mtu:null}),
      (.outbounds[]? | select(.type == "bridge") |
        {tag:(.tag // ""),type:.type,interface_name:(.interface_name // "tun0"),
         auto_route:(.auto_route // false),auto_redirect:(.auto_redirect // false),
         table_index:(.iproute2_table_index // null),rule_index:(.iproute2_rule_index // null),
         bridge_name:(.bridge_name // "bridge"),bound_interface:(.interface // ""),
         listen:(.listen // ""),listen_port:(.listen_port // 0),system_interface:false,
         addresses:[],mtu:null}),
      (.endpoints[]? |
        select((.type == "openvpn-client" or .type == "openvpn-server") and .system == true) |
        {tag:(.tag // ""),type:.type,interface_name:(.name // ""),
         auto_route:false,auto_redirect:false,table_index:null,rule_index:null,
         bridge_name:"",bound_interface:"",listen:(.listen // ""),listen_port:(.listen_port // 0),
         system_interface:true,
         addresses:(if ((.address? // null) | type) == "array" then
                      [.address[] | select(type == "string" and length > 0)]
                    elif ((.address? // null) | type) == "string" and (.address | length > 0) then
                      [.address]
                    else [] end),
         mtu:(if ((.mtu? // null) | type) == "number" and (.mtu // 0) > 0 then .mtu else 1500 end)})
      ,(.endpoints[]? |
        select(
          ((.type == "wireguard" or .type == "openconnect") and .system == true) or
          (.type == "tailscale" and .system_interface == true)
        ) |
        {tag:(.tag // ""),type:.type,
         interface_name:(if .type == "tailscale" then (.system_interface_name // "") else (.name // "") end),
         auto_route:false,auto_redirect:false,table_index:null,rule_index:null,
         bridge_name:"",bound_interface:"",listen:(.listen // ""),listen_port:(.listen_port // 0),
         system_interface:true,
         addresses:(if ((.address? // null) | type) == "array" then
                      [.address[] | select(type == "string" and length > 0)]
                    elif ((.address? // null) | type) == "string" and (.address | length > 0) then
                      [.address]
                    else [] end),
         mtu:(if .type == "wireguard" then
                (if ((.mtu? // null) | type) == "number" and (.mtu // 0) > 0 then .mtu else 1408 end)
              elif .type == "tailscale" then
                (if ((.system_interface_mtu? // null) | type) == "number" and (.system_interface_mtu // 0) > 0 then .system_interface_mtu else 0 end)
              else
                (if ((.mtu? // null) | type) == "number" and (.mtu // 0) > 0 then .mtu else 0 end)
              end)})
    ]
  ' "${snapshot}/config.json") || return 1
  tun_count=$(jq -r '[.[] | select(.type == "tun")] | length' <<< "${records}") || return 1
  bridge_count=$(jq -r '[.[] | select(.type == "bridge")] | length' <<< "${records}") || return 1
  system_endpoint_count=$(jq -r '[.[] | select(.system_interface == true)] | length' <<< "${records}") || return 1
  if [[ "${service_state}" != active ]]; then
    jq -cn --arg status "${status}" --arg reason "${reason}" --argjson resources "${records}" \
      '{status:$status,reason:$reason,service_active:false,resources:($resources | map({tag,type,listen,listen_port,interface_name:(if .system_interface then .interface_name else null end),resource_scope:(if .type == "tun" or .type == "bridge" or .system_interface then "core_owned" elif .type == "redirect" or .type == "tproxy" then "host_policy_reported_separately" else "operator_policy_required" end),status:"not_assessed",reason:"service_inactive"})),limitations:["Redirect policy ownership is reported separately under redirect_host_policy","TProxy policy ownership is reported separately under tproxy_host_policy; inbounds without an enabled policy remain operator-managed","TUN/bridge/system endpoint interfaces are core-owned resources and require a running core"]}'
    return 0
  fi
  if (( tun_count == 0 && bridge_count == 0 && system_endpoint_count == 0 )) && ! jq -e 'any(.[]; .type == "redirect" or .type == "tproxy")' <<< "${records}" >/dev/null 2>&1; then
    jq -cn '{status:"available",reason:null,service_active:true,resources:[],limitations:[]}'
    return 0
  fi
  if (( tun_count == 0 && bridge_count == 0 && system_endpoint_count == 0 )); then
    jq -cn --argjson resources "${records}" \
      '{status:"not_assessed",reason:"host_policy_not_observed_here",service_active:true,
        resources:($resources | map({tag,type,listen,listen_port,
          resource_scope:(if .type == "redirect" or .type == "tproxy" then "host_policy_reported_separately" else "operator_policy_required" end),
          status:"not_assessed",reason:"host_policy_not_observed_here"})),
        limitations:["Redirect policy ownership is reported separately under redirect_host_policy","TProxy policy ownership is reported separately under tproxy_host_policy; inbounds without an enabled policy remain operator-managed"]}'
    return 0
  fi
  status=available
  reason=''
  link_file="${snapshot}/link.json"
  if ! command -v ip >/dev/null 2>&1; then
    status=unavailable
    reason=iproute2_missing
  elif (( tun_count > 0 || bridge_count > 0 )); then
    rule_file="${snapshot}/rule.json"
    route_file="${snapshot}/route.json"
    if ! ip -j rule show > "${rule_file}" 2>"${snapshot}/rule.stderr"; then
      status=unavailable
      reason=iproute2_rule_probe_failed
    elif [[ "$(wc -c < "${rule_file}")" -gt 1048576 ]]; then
      status=unavailable
      reason=iproute2_rule_probe_oversized
    elif ! jq -e 'type == "array"' "${rule_file}" >/dev/null 2>&1; then
      status=unavailable
      reason=iproute2_rule_probe_invalid
    elif ! ip -j route show table all > "${route_file}" 2>"${snapshot}/route.stderr"; then
      status=unavailable
      reason=iproute2_route_probe_failed
    elif [[ "$(wc -c < "${route_file}")" -gt 1048576 ]]; then
      status=unavailable
      reason=iproute2_route_probe_oversized
    elif ! jq -e 'type == "array"' "${route_file}" >/dev/null 2>&1; then
      status=unavailable
      reason=iproute2_route_probe_invalid
    fi
  fi
  if (( tun_count > 0 || bridge_count > 0 )) && [[ "${status}" == available ]]; then
    if command -v nft >/dev/null 2>&1; then
      nft_file="${snapshot}/nft.json"
      if nft -j list ruleset > "${nft_file}" 2>"${snapshot}/nft.stderr"; then
        output_size=$(wc -c < "${nft_file}") || output_size=0
        if (( output_size > 2097152 )); then
          nft_status=oversized
        elif jq -e 'type == "object"' "${nft_file}" >/dev/null 2>&1; then
          nft_status=observed
        else
          nft_status=invalid
        fi
      else
        nft_status=probe_failed
      fi
    else
      nft_status=missing
    fi
  else
    nft_status=not_required
  fi
  while IFS= read -r record; do
    [[ -n "${record}" ]] || continue
    tag=$(jq -r '.tag' <<< "${record}") || return 1
    type=$(jq -r '.type' <<< "${record}") || return 1
    if jq -e '.system_interface == true' <<< "${record}" >/dev/null 2>&1; then
      system_interface_name=$(jq -r '.interface_name // ""' <<< "${record}") || return 1
      system_addresses=$(jq -c '.addresses // []' <<< "${record}") || return 1
      system_mtu=$(jq -r '.mtu // 1500' <<< "${record}") || return 1
      case "${type}" in
        wireguard) system_reason_prefix=wireguard_system ;;
        tailscale) system_reason_prefix=tailscale_system ;;
        openconnect) system_reason_prefix=openconnect_system ;;
        openvpn-client|openvpn-server) system_reason_prefix=openvpn_system ;;
        *) system_reason_prefix=system_endpoint ;;
      esac
      address_file="${snapshot}/addr.json"
      interface_status=not_assessed
      address_status=not_assessed
      mtu_status=not_assessed
      if [[ "${system_mtu}" == 0 ]]; then
        mtu_status=not_required
      fi
      if [[ -z "${system_interface_name}" ]]; then
        if [[ "${status}" == available ]]; then
          status=not_assessed
          reason=${system_reason_prefix}_interface_name_unset
        fi
      elif [[ ! "${system_interface_name}" =~ ^[A-Za-z0-9_.-]{1,15}$ ]]; then
        if [[ "${status}" == available ]]; then
          status=not_assessed
          reason=${system_reason_prefix}_interface_name_invalid
        fi
      elif [[ "${status}" == unavailable ]]; then
        interface_status=not_probed
        address_status=not_probed
        mtu_status=not_probed
      else
        interface_status=missing
        if [[ "${system_mtu}" != 0 ]]; then
          mtu_status=missing
        fi
        if ip -j link show dev "${system_interface_name}" > "${link_file}" 2>"${snapshot}/link.stderr"; then
          if [[ "$(wc -c < "${link_file}")" -le 1048576 ]] &&
             jq -e 'type == "array"' "${link_file}" >/dev/null 2>&1 &&
             jq -e --arg name "${system_interface_name}" 'any(.[]; .ifname == $name)' "${link_file}" >/dev/null 2>&1; then
            interface_status=present
            actual_mtu=$(jq -r --arg name "${system_interface_name}" \
              '[.[] | select(.ifname == $name) | .mtu][0] // empty' "${link_file}") || return 1
            if [[ -n "${actual_mtu}" && "${actual_mtu}" == "${system_mtu}" ]]; then
              mtu_status=present
            fi
          fi
        fi
        system_address_count=$(jq -r 'length' <<< "${system_addresses}") || return 1
        if (( system_address_count == 0 )); then
          address_status=not_required
        elif [[ "${interface_status}" == present ]]; then
          address_status=present
          if ! ip -j addr show dev "${system_interface_name}" > "${address_file}" 2>"${snapshot}/addr.stderr" ||
             [[ ! -f "${address_file}" ]] ||
             [[ "$(wc -c < "${address_file}")" -gt 1048576 ]] ||
             ! jq -e 'type == "array"' "${address_file}" >/dev/null 2>&1; then
            address_status=missing
          else
            while IFS= read -r expected_address; do
              [[ -n "${expected_address}" ]] || continue
              if [[ "${expected_address}" != */* ]]; then
                address_status=missing
                break
              fi
              expected_addr=${expected_address%/*}
              expected_prefix=${expected_address##*/}
              if ! jq -e --arg addr "${expected_addr}" --arg prefix "${expected_prefix}" \
                'any(.[]?.addr_info[]?; (.local // "") == $addr and (((.prefixlen // "") | tostring) == $prefix))' \
                "${address_file}" >/dev/null 2>&1; then
                address_status=missing
                break
              fi
            done < <(jq -r '.[]' <<< "${system_addresses}")
          fi
        else
          address_status=not_probed
        fi
      fi
      record=$(jq -c --argjson item "${record}" --arg link "${interface_status}" \
        --arg addresses "${address_status}" --arg mtu "${mtu_status}" \
        '{tag:$item.tag,type:$item.type,interface_name:$item.interface_name,system_interface:true,
          expected_addresses:$item.addresses,expected_mtu:$item.mtu,resource_scope:"core_owned",
          interface:{status:$link},interface_addresses:{status:$addresses},mtu:{status:$mtu}}' \
        <<< "${record}") || return 1
      if [[ "${status}" != unavailable && -n "${system_interface_name}" &&
            "${system_interface_name}" =~ ^[A-Za-z0-9_.-]{1,15}$ &&
            ( "${interface_status}" != present ||
              ( "${mtu_status}" != present && "${mtu_status}" != not_required ) ||
              ( "${address_status}" != present && "${address_status}" != not_required ) ) ]]; then
        status=unavailable
        reason=${system_reason_prefix}_runtime_resources_missing
      fi
      resources=$(jq -c --argjson item "${record}" '. + [$item]' <<< "${resources}") || return 1
      continue
    fi
    if [[ "${type}" == bridge ]]; then
      bridge_name=$(jq -r '.bridge_name // "bridge"' <<< "${record}") || return 1
      [[ "${bridge_name}" =~ ^[A-Za-z0-9_.-]{1,15}$ ]] || return 1
      bound_interface=$(jq -r '.bound_interface // ""' <<< "${record}") || return 1
      bridge_interface_name=''
      bridge_port=''
      if [[ "${status}" == available ]]; then
        bridge_interface_name=$(jq -r --arg base "${bridge_name}" '
          [.[] | (.dev // "") | tostring |
            select(. == $base or (startswith($base) and
              (.[($base | length):] | test("^[0-9]+$"))))] |
          unique | if length == 1 then .[0] else "" end
        ' "${route_file}") || return 1
        bridge_port=$(jq -r --arg interface "${bridge_interface_name}" '
          [.[] | select((.dev // "") == $interface and
            ((.dst // "") | test("^192\\.0\\.2\\.[0-9]{1,3}$")) and
            (((.table // "main") | tostring) == "main")) | .dst] |
          unique | if length == 1 then .[0] else "" end
        ' "${route_file}") || return 1
      fi
      bridge_index=-1
      if [[ "${bridge_port}" =~ ^192\.0\.2\.([0-9]+)$ ]]; then
        bridge_octet=$((10#${BASH_REMATCH[1]}))
        if (( bridge_octet >= 1 && bridge_octet <= 254 )); then
          bridge_index=$((bridge_octet - 1))
        fi
      fi
      bridge_configured_table=$(jq -r 'if ((.table_index | type) == "number") then .table_index | tostring else "0" end' <<< "${record}") || return 1
      bridge_configured_rule=$(jq -r 'if ((.rule_index | type) == "number") then .rule_index | tostring else "0" end' <<< "${record}") || return 1
      [[ "${bridge_configured_table}" =~ ^[0-9]+$ && "${bridge_configured_rule}" =~ ^[0-9]+$ ]] || return 1
      (( bridge_configured_table <= 2147483647 && bridge_configured_rule <= 2147483647 )) || return 1
      bridge_table=0
      if [[ -n "${bound_interface}" ]]; then
        if (( bridge_configured_table > 0 )); then
          bridge_table=${bridge_configured_table}
        elif (( bridge_index >= 0 )); then
          bridge_table=$((2200 + bridge_index))
        else
          bridge_table=-1
        fi
      fi
      if (( bridge_configured_rule > 0 )); then
        bridge_rule=${bridge_configured_rule}
      else
        bridge_rule=100
      fi
      link_status=missing
      if [[ "${status}" == available && "${bridge_interface_name}" =~ ^[A-Za-z0-9_.-]{1,15}$ ]] &&
         ip -j link show dev "${bridge_interface_name}" > "${link_file}" 2>"${snapshot}/link.stderr"; then
        if [[ "$(wc -c < "${link_file}")" -le 1048576 ]] && jq -e 'type == "array"' "${link_file}" >/dev/null 2>&1 &&
           jq -e --arg name "${bridge_interface_name}" 'any(.[]; .ifname == $name)' "${link_file}" >/dev/null 2>&1; then
          link_status=present
        fi
      elif [[ "${status}" != available ]]; then
        link_status=not_probed
      fi
      route_status=missing
      rule_status=missing
      if [[ "${status}" != available ]]; then
        route_status=not_probed
        rule_status=not_probed
      elif [[ "${bridge_interface_name}" =~ ^[A-Za-z0-9_.-]{1,15}$ &&
            "${bridge_port}" =~ ^192\.0\.2\.[0-9]{1,3}$ && "${bridge_table}" != -1 ]]; then
        if jq -e --arg dst "${bridge_port}" --arg interface "${bridge_interface_name}" \
          'any(.[]; (.dst // "") == $dst and (.dev // "") == $interface and
            (((.table // "main") | tostring) == "main"))' "${route_file}" >/dev/null 2>&1; then
          route_status=present
        fi
        if jq -e --argjson priority "${bridge_rule}" --arg interface "${bridge_interface_name}" \
          --arg table "$(if (( bridge_table == 0 )); then printf main; else printf '%s' "${bridge_table}"; fi)" \
          --argjson to_priority "$((bridge_rule + 1))" --arg dst "${bridge_port}" \
          'any(.[]; (.priority == $priority) and (.iif // "") == $interface and
            (((.table // "main") | tostring) == $table)) and
           any(.[]; (.priority == $to_priority) and (.dst // "") == $dst and
            (((.table // "main") | tostring) == "main"))' "${rule_file}" >/dev/null 2>&1; then
          rule_status=present
        fi
        if (( bridge_table > 0 )) && ! jq -e --arg table "${bridge_table}" --arg interface "${bound_interface}" \
          'any(.[]; (((.table // "main") | tostring) == $table) and
            (((.dst // "") == "default" and (.dev // "") == $interface) or
             ((.type // "") == "blackhole" and (.dst // "") == "default")))' \
          "${route_file}" >/dev/null 2>&1; then
          route_status=missing
        fi
      fi
      record=$(jq -c --argjson item "${record}" --arg scope core_owned --arg iface "${bridge_interface_name}" \
        --arg port "${bridge_port}" --arg table "${bridge_table}" --arg rule "${bridge_rule}" \
        --arg link "${link_status}" --arg route "${route_status}" --arg rule_status "${rule_status}" \
        --arg nft "${nft_status}" \
        '{tag:$item.tag,type:$item.type,bridge_name:$item.bridge_name,bound_interface:$item.bound_interface,
          interface_name:$iface,bridge_port:$port,route_table:($table|tonumber),rule_priority:($rule|tonumber),
          resource_scope:$scope,interface:{status:$link},policy_routing:{status:$route},rule:{status:$rule_status},
          bridge_netfilter:{status:(if $nft == "observed" then "observed" else "not_assessed" end),ownership:"core_dynamic"}}' \
        <<< "${record}") || return 1
      if [[ "${status}" == available &&
            ( "${link_status}" != present || "${route_status}" != present || "${rule_status}" != present ) ]]; then
        status=unavailable
        reason=bridge_runtime_resources_missing
      fi
      resources=$(jq -c --argjson item "${record}" '. + [$item]' <<< "${resources}") || return 1
      continue
    fi
    if [[ "${type}" != tun ]]; then
      resources=$(jq -c --argjson item "${record}" '. + [($item | {
        tag,type,listen,listen_port,
        resource_scope:(if .type == "redirect" or .type == "tproxy" then "host_policy_reported_separately" else "operator_policy_required" end),
        status:"not_assessed",reason:"host_policy_not_observed_here"})]' <<< "${resources}") || return 1
      [[ "${status}" == available ]] && { status=not_assessed; reason=host_policy_not_observed_here; }
      continue
    fi
    interface_name=$(jq -r '.interface_name' <<< "${record}") || return 1
    [[ "${interface_name}" =~ ^[A-Za-z0-9_.-]{1,15}$ ]] || return 1
    auto_route=$(jq -r '.auto_route' <<< "${record}") || return 1
    auto_redirect=$(jq -r '.auto_redirect' <<< "${record}") || return 1
    table_index=$(jq -r 'if ((.table_index | type) == "number" and .table_index > 0) then .table_index elif ((.table_index | type) == "array" and ((.table_index[0] // 0) > 0)) then .table_index[0] else 2022 end' <<< "${record}") || return 1
    rule_index=$(jq -r 'if ((.rule_index | type) == "number" and .rule_index > 0) then .rule_index elif ((.rule_index | type) == "array" and ((.rule_index[0] // 0) > 0)) then .rule_index[0] else 9000 end' <<< "${record}") || return 1
    link_status=missing
    if [[ "${status}" == available ]] && ip -j link show dev "${interface_name}" > "${link_file}" 2>"${snapshot}/link.stderr"; then
      if [[ "$(wc -c < "${link_file}")" -le 1048576 ]] && jq -e 'type == "array"' "${link_file}" >/dev/null 2>&1; then
        if jq -e --arg name "${interface_name}" 'any(.[]; .ifname == $name)' "${link_file}" >/dev/null 2>&1; then
          link_status=present
        else
          link_status=missing
        fi
      else
        link_status=invalid
      fi
    elif [[ "${status}" != available ]]; then
      link_status=not_probed
    fi
    route_status=not_required
    rule_status=not_required
    if [[ "${auto_route}" == true ]]; then
      if [[ "${status}" == available ]]; then
        if jq -e --argjson priority "${rule_index}" --arg table "${table_index}" \
          'any(.[]; (.priority == $priority) and ((.table // "") | tostring) == $table)' "${rule_file}" >/dev/null 2>&1; then
          rule_status=present
        else
          rule_status=missing
        fi
        if jq -e --arg table "${table_index}" --arg name "${interface_name}" \
          'any(.[]; ((.table // "main") | tostring) == $table and (.dev // "") == $name)' "${route_file}" >/dev/null 2>&1; then
          route_status=present
        else
          route_status=missing
        fi
      else
        route_status=not_probed
        rule_status=not_probed
      fi
    fi
    record=$(jq -c --argjson item "${record}" --arg scope core_owned --arg link "${link_status}" \
      --arg route "${route_status}" --arg rule "${rule_status}" --arg nft "${nft_status}" \
      '{tag:$item.tag,type:$item.type,interface_name:$item.interface_name,auto_route:$item.auto_route,
        auto_redirect:$item.auto_redirect,resource_scope:$scope,
        interface:{status:$link},policy_routing:{status:$route},rule:{status:$rule},
        auto_redirect_rules:{status:(if $item.auto_redirect then $nft else "not_required" end),ownership:"core_dynamic"}}' \
      <<< "${record}") || return 1
    if [[ "${link_status}" != present || ( "${auto_route}" == true && ("${route_status}" != present || "${rule_status}" != present)) ]]; then
      status=unavailable
      reason=tun_runtime_resources_missing
    elif [[ "${auto_redirect}" == true && "${nft_status}" != observed ]]; then
      status=not_assessed
      reason=auto_redirect_rules_not_observed
    fi
    resources=$(jq -c --argjson item "${record}" '. + [$item]' <<< "${resources}") || return 1
  done < <(jq -c '.[]' <<< "${records}")
  jq -cn --arg status "${status}" --arg reason "${reason}" --argjson resources "${resources}" \
    '{status:$status,reason:(if $reason == "" then null else $reason end),service_active:true,resources:$resources,
      limitations:["Redirect policy ownership is reported separately under redirect_host_policy","TProxy policy ownership is reported separately under tproxy_host_policy; inbounds without an enabled policy remain operator-managed","bridge forwarding/NAT policy is core-dynamic and observation only","system endpoint interfaces, addresses and MTU are observed but routes and packet payload are not claimed","reported core-owned state is observation only"]}'
)

managed_component_transparent_runtime_healthy() {
  local config_file=${1:-} report

  [[ -f "${config_file}" && ! -L "${config_file}" && -r "${config_file}" ]] || return 1
  report=$(managed_component_transparent_resources_json "${config_file}" active) || return 1
  jq -e '
    type == "object" and
    .service_active == true and
    (.resources | type == "array" and length > 0) and
    any(.resources[];
      .type == "tun" or .type == "bridge" or
      (.system_interface == true and (.interface_name // "") != "")) and
    (all(.resources[] | select(.type == "tun");
      .interface.status == "present" and
      ((.auto_route != true) or
       (.policy_routing.status == "present" and .rule.status == "present")) and
      ((.auto_redirect != true) or .auto_redirect_rules.status == "observed")))
    and
    (all(.resources[] | select(.type == "bridge");
      .interface.status == "present" and
      .policy_routing.status == "present" and .rule.status == "present"))
    and
    (all(.resources[] | select(.system_interface == true and (.interface_name // "") != "");
      .interface.status == "present" and
      (.interface_addresses.status == "present" or .interface_addresses.status == "not_required") and
      (.mtu.status == "present" or .mtu.status == "not_required")))
  ' <<< "${report}" >/dev/null 2>&1
}

# A core restart can report active before it has finished publishing a
# dynamically allocated TUN/rule/route set.  Keep the transaction fail-closed,
# but give those core-owned resources a short bounded convergence window.
managed_component_transparent_runtime_healthy_with_retry() {
  local config_file=${1:-} attempt=0
  while (( attempt < 10 )); do
    if managed_component_transparent_runtime_healthy "${config_file}"; then
      return 0
    fi
    ((attempt += 1))
    (( attempt < 10 )) && sleep 0.2
  done
  return 1
}

managed_component_state_candidate() {
  local state=${1:-} operation=${2:-} record=${3:-} target_id=${4:-}
  local candidate
  managed_component_state_validate_json "${state}" || return 1
  if [[ "${operation}" == create || "${operation}" == replace ]]; then
    managed_component_state_validate_record "${record}" || return 1
  fi
  if ! candidate=$(jq -c --arg operation "${operation}" --arg target "${target_id}" \
    --argjson record "${record:-null}" '
      . as $state |
      def ref_values:
        if type == "string" then [.] elif type == "array" then
          map(select(type == "string"))
        else [] end;
      def component_references:
        . as $component |
        ($component.config // {}) as $config |
        ([(($component.route_rules // [])[]? | .. | objects | to_entries[] |
            select(.key | IN("inbound", "outbound", "rule_set")) | .value)] +
         [
           $config.detour?,
           $config.netns?,
           $config.tls.certificate_provider?,
           $config.realm.http_client?,
           $config.control_dialer.detour?,
           $config.control_dialer.netns?,
           $config.tunnel_dialer.detour?,
           $config.tunnel_dialer.netns?,
           (if $component.role == "certificate_provider" or
                  $component.role == "rule_set" then $config.http_client? else empty end),
           (if $component.role == "outbound" and
                  ($component.type == "selector" or $component.type == "urltest") then
              $config.outbounds?, $config.default?
            else empty end)
         ]) |
        map(ref_values) | add // [] | unique;
      if $operation == "create" then
        if any($state.components[]; .id == $record.id or .tag == $record.tag) then error("duplicate")
        else $state | .components += [$record] | .revision = (.revision + 1) end
      elif $operation == "replace" then
        ([$state.components[] | select(.id == $record.id)] | first) as $existing |
        if $existing == null then error("missing")
        elif any($state.components[]; .id != $record.id and .tag == $record.tag) then
          error("duplicate")
        elif ($existing.tag != $record.tag and
              any($state.components[] |
                  if .id == $record.id then $record else . end;
                  component_references | index($existing.tag) != null)) then
          error("referenced")
        else
          $state | .components |= map(if .id == $record.id then $record else . end) |
          .revision = (.revision + 1)
        end
      elif $operation == "delete" then
        ([$state.components[] | select(.id == $target)] | first) as $existing |
        if $existing == null then error("missing")
        elif any($state.components[] | select(.id != $target);
                 component_references | index($existing.tag) != null) then error("referenced")
        else $state | .components |= map(select(.id != $target)) | .revision = (.revision + 1) end
      else error("operation") end
    ' <<< "${state}" 2>/dev/null); then
    return 1
  fi
  managed_component_state_validate_json "${candidate}" || return 1
  printf '%s\n' "${candidate}"
}

managed_component_takeover_id() {
  local role=${1:-} type=${2:-} tag=${3:-} safe_tag digest candidate
  [[ -n "${role}" && -n "${type}" && -n "${tag}" ]] || return 1
  if [[ "${tag}" =~ ^[a-z0-9][a-z0-9_-]{0,47}$ ]]; then
    safe_tag=${tag}
    candidate="${role}-${type}-${safe_tag}"
  else
    digest=$(printf '%s:%s:%s' "${role}" "${type}" "${tag}" | sha256sum | awk '{print substr($1,1,16)}') || return 1
    candidate="${role}-${type}-${digest}"
  fi
  [[ ${#candidate} -le 64 ]] || candidate="${role}-${type}-$(printf '%s' "${candidate}" | sha256sum | awk '{print substr($1,1,16)}')"
  managed_component_state_id_valid "${candidate}" || return 1
  printf '%s' "${candidate}"
}

managed_component_live_takeover_records_json() (
  local state=${1:-} registry inbound_types endpoint_types outbound_types certificate_provider_types http_client_types service_types namespace_types rule_set_types
  local source_objects object role type tag id config route_rules record
  local config_snapshot
  local records=() existing_id
  [[ -n "${state}" ]] || return 1
  [[ -f "${SINGBOX_CONFIG_FILE}" && ! -L "${SINGBOX_CONFIG_FILE}" && -r "${SINGBOX_CONFIG_FILE}" ]] || return 2
  config_snapshot=$(storage_mktemp "${SB_DATA_ROOT}/tmp/sbv-component-live.XXXXXX") || return 1
  trap 'rm -f -- "${config_snapshot}"' EXIT
  head -c 4194305 -- "${SINGBOX_CONFIG_FILE}" > "${config_snapshot}" || return 4
  [[ "$(wc -c < "${config_snapshot}")" -le 4194304 ]] || return 4
  managed_component_state_validate_json "${state}" || return 1
  registry=$(component_registry_static_json) || return 1
  inbound_types=$(jq -c '[.[] | select(.role == "inbound") | .type]' <<< "${registry}") || return 1
  endpoint_types=$(jq -c '[.[] | select(.role == "endpoint") | .type]' <<< "${registry}") || return 1
  outbound_types=$(jq -c '[.[] | select(.role == "outbound") | .type]' <<< "${registry}") || return 1
  certificate_provider_types=$(jq -c '[.[] | select(.role == "certificate_provider") | .type]' <<< "${registry}") || return 1
  http_client_types=$(jq -c '[.[] | select(.role == "http_client") | .type]' <<< "${registry}") || return 1
  service_types=$(jq -c '[.[] | select(.role == "service") | .type]' <<< "${registry}") || return 1
  namespace_types=$(jq -c '[.[] | select(.role == "network_namespace") | .type]' <<< "${registry}") || return 1
  rule_set_types=$(jq -c '[.[] | select(.role == "rule_set") | .type]' <<< "${registry}") || return 1
  source_objects=$(jq -c --argjson inbound_types "${inbound_types}" --argjson endpoint_types "${endpoint_types}" \
    --argjson outbound_types "${outbound_types}" \
    --argjson certificate_provider_types "${certificate_provider_types}" \
    --argjson http_client_types "${http_client_types}" \
    --argjson service_types "${service_types}" \
    --argjson namespace_types "${namespace_types}" \
    --argjson rule_set_types "${rule_set_types}" '
    def safe_tag:
      type == "string" and length > 0 and length <= 4096 and
      (any(explode[]; . < 32 or . == 127) | not);
    if type != "object" then error("invalid_document") else
      if any(.outbounds[]?;
             . as $outbound |
             ($outbound.tag // "") != "warp-ep" and
             (($outbound_types | index($outbound.type // "")) == null)) then
        error("unknown_outbound_type")
      elif any(.outbounds[]?;
               (.tag // "") != "warp-ep" and
               (((.tag // "") == "direct" and (.type // "") != "direct") or
                ((.tag // "") == "block" and (.type // "") != "block"))) then
        error("reserved_outbound_tag")
      elif any(.certificate_providers[]?;
               . as $provider |
               ((($provider.tag // "") | IN("hy2-cert-provider","anytls-cert-provider")) and
                (($provider.type // "") != "acme")) or
               ((($provider.tag // "") | IN("hy2-cert-provider","anytls-cert-provider") | not) and
                (($certificate_provider_types | index($provider.type // "")) == null))) then
        error("unknown_certificate_provider_type")
      elif any(.network_namespaces[]?;
               . as $namespace |
               ($namespace_types | index($namespace.type // "")) == null) then
        error("unknown_network_namespace_type")
      elif (has("services") and (.services | type != "array")) then
        error("invalid_service")
      elif (has("services") and (.services | length > 128)) then
        error("invalid_service")
      elif any(.services[]?;
               type != "object" or
               (. as $service | ($service_types | index($service.type // "")) == null) or
               (.tag | type != "string" or length == 0)) then
        error("invalid_service")
      elif ([.services[]?.tag] | unique | length) != ([.services[]?.tag] | length) then
        error("duplicate_service_tag")
      elif (has("http_clients") and (.http_clients | type != "array")) then
        error("invalid_http_client")
      elif (has("http_clients") and (.http_clients | length > 128)) then
        error("invalid_http_client")
      elif any(.http_clients[]?; type == "object" and has("type")) then
        error("invalid_http_client")
      elif any(.http_clients[]?;
               type != "object" or
               (.tag | type != "string" or length == 0) or
               (($http_client_types | index("shared")) == null)) then
        error("invalid_http_client")
      elif ([.http_clients[]?.tag] | unique | length) != ([.http_clients[]?.tag] | length) then
        error("duplicate_http_client_tag")
      elif (has("route") and (.route | type != "object")) then
        error("invalid_rule_set")
      elif (has("route") and (.route | has("rule_set")) and
            (.route.rule_set | type != "array")) then
        error("invalid_rule_set")
      elif ((.route.rule_set // []) | type != "array" or length > 128) then
        error("invalid_rule_set")
      elif any((.route.rule_set // [])[];
               type != "object" or
               (.tag | safe_tag | not) or
               (.type | type != "string" or ($rule_set_types | index(.)) == null)) then
        error("invalid_rule_set")
      elif any((.route.rule_set // [])[];
               (((.tag | startswith("warp-local-")) and .type != "local") or
                ((.tag | startswith("warp-remote-")) and .type != "remote"))) then
        error("invalid_rule_set")
      elif ([.route.rule_set[]?.tag] | unique | length) != ([.route.rule_set[]?.tag] | length) then
        error("duplicate_rule_set_tag")
      else
      ([.inbounds // [] | .[] | select(.type as $type | $inbound_types | index($type) != null) |
        {role:"inbound",object:.}] +
       [.endpoints // [] | .[] |
        select((.tag // "") != "warp-ep") |
        select(.type as $type | $endpoint_types | index($type) != null) |
        {role:"endpoint",object:.}] +
       [.outbounds // [] | .[] |
        if ((((.tag // "") == "warp-ep") or
             (.type == "direct" and (.tag // "") == "direct") or
             (.type == "block" and (.tag // "") == "block")) | not) then
          {role:"outbound",object:.}
        else empty end] +
       [.certificate_providers // [] | .[] |
        select((.tag // "") | IN("hy2-cert-provider","anytls-cert-provider") | not) |
        select(.type as $type | $certificate_provider_types | index($type) != null) |
        {role:"certificate_provider",object:.}] +
       [.http_clients // [] | .[] |
        {role:"http_client",object:(. + {type:"shared"})}] +
       [.services // [] | .[] |
        {role:"service",object:.}] +
       [.network_namespaces // [] | .[] |
        select(.type as $type | $namespace_types | index($type) != null) |
        {role:"network_namespace",object:.}] +
       [(.route.rule_set // [])[] |
        select((((.tag // "") | startswith("warp-local-")) or
                ((.tag // "") | startswith("warp-remote-"))) | not) |
        {role:"rule_set",object:.}])[]
      end
    end
  ' "${config_snapshot}" 2>/dev/null) || return 4
  while IFS= read -r object; do
    [[ -n "${object}" ]] || continue
    role=$(jq -r '.role' <<< "${object}") || return 4
    type=$(jq -r '.object.type // empty' <<< "${object}") || return 4
    tag=$(jq -r '.object.tag // empty' <<< "${object}") || return 4
    managed_component_tag_valid "${tag}" || return 4
    existing_id=$(jq -r --arg role "${role}" --arg type "${type}" --arg tag "${tag}" \
      '.components[] | select(.role == $role and .type == $type and .tag == $tag) | .id' <<< "${state}" | head -n1) || return 1
    if [[ -n "${existing_id}" ]]; then
      id=${existing_id}
    else
      id=$(managed_component_takeover_id "${role}" "${type}" "${tag}") || return 4
    fi
    config=$(jq -c '.object | del(.type,.tag)' <<< "${object}") || return 4
    if [[ "${role}" == outbound ]]; then
      route_rules=$(jq -c --arg tag "${tag}" '[.route.rules[]? |
        select((.outbound == $tag) or ((.outbound | type) == "array" and ((.outbound | index($tag)) != null)))]' \
        "${config_snapshot}") || return 4
    elif [[ "${role}" == http_client || "${role}" == service || "${role}" == rule_set ]]; then
      route_rules='[]'
    else
      route_rules=$(jq -c --arg tag "${tag}" '[.route.rules[]? |
        select((.inbound == $tag) or ((.inbound | type) == "array" and ((.inbound | index($tag)) != null)))]' \
      "${config_snapshot}") || return 4
    fi
    record=$(jq -cn --arg id "${id}" --arg role "${role}" --arg type "${type}" --arg tag "${tag}" \
      --argjson config "${config}" --argjson route_rules "${route_rules}" \
      '{id:$id,role:$role,type:$type,tag:$tag,enabled:true,route_rules:$route_rules,config:$config}') || return 4
    managed_component_state_validate_record "${record}" || return 4
    records+=("${record}")
  done <<< "${source_objects}"
  ((${#records[@]} > 0)) || return 3
  printf '%s\n' "${records[@]}" | jq -scS '.'
)

managed_component_state_takeover_candidate() {
  local state=${1:-} records=${2:-} candidate
  managed_component_state_validate_json "${state}" || return 1
  jq -e 'type == "array" and length > 0 and all(.[]; type == "object")' <<< "${records}" >/dev/null 2>&1 || return 1
  if ! candidate=$(jq -cS --argjson records "${records}" '
    . as $state |
    reduce $records[] as $record (.;
      if any(.components[]; .role == $record.role and .type == $record.type and .tag == $record.tag) then
        .components |= map(if .role == $record.role and .type == $record.type and .tag == $record.tag
                           then ($record | .id = .id) else . end)
      elif any(.components[]; .id == $record.id or .tag == $record.tag) then
        error("component_conflict")
      else
        .components += [$record]
      end) |
    if .components == $state.components then . else .revision = (.revision + 1) end
  ' <<< "${state}" 2>/dev/null); then
    return 1
  fi
  managed_component_state_validate_json "${candidate}" || return 1
  printf '%s\n' "${candidate}"
}

managed_component_takeover_preserves_live_config() {
  local old_config=${1:-} new_config=${2:-} registry inbound_types endpoint_types
  [[ -f "${old_config}" && ! -L "${old_config}" && -f "${new_config}" && ! -L "${new_config}" ]] || return 1
  [[ "$(wc -c < "${old_config}")" -le 4194304 && "$(wc -c < "${new_config}")" -le 4194304 ]] || return 1
  registry=$(component_registry_static_json) || return 1
  inbound_types=$(jq -c '[.[] | select(.role == "inbound") | .type]' <<< "${registry}") || return 1
  endpoint_types=$(jq -c '[.[] | select(.role == "endpoint") | .type]' <<< "${registry}") || return 1
  jq -se --argjson inbound_types "${inbound_types}" --argjson endpoint_types "${endpoint_types}" '
    def preserves($new; $old):
      (($new | type) == ($old | type)) and
      (if ($new | type) == "object" or ($new | type) == "array" then
         ($new | contains($old))
       else
         $new == $old
       end);
    def root_object_arrays:
      ["inbounds","endpoints","outbounds","certificate_providers","http_clients","services","network_namespaces"];
    def root_fields_preserved($old; $new):
      ($old | keys) as $keys |
      ($keys | all(.[]; . as $key |
        if (root_object_arrays | index($key)) != null then true
        elif ($new | has($key)) then preserves($new[$key]; $old[$key])
        else false end));
    def objects($root):
      ([($root.inbounds // [])[]? | {role:"inbound",object:.}] +
       [($root.endpoints // [])[]? | {role:"endpoint",object:.}] +
       [($root.outbounds // [])[]? | {role:"outbound",object:.}] +
       [($root.certificate_providers // [])[]? | {role:"certificate_provider",object:.}] +
       [($root.http_clients // [])[]? | {role:"http_client",object:.}] +
       [($root.services // [])[]? | {role:"service",object:.}] +
       [($root.network_namespaces // [])[]? | {role:"network_namespace",object:.}]);
    .[0] as $old |
    .[1] as $new |
    objects($old) as $old_objects |
    objects($new) as $new_objects |
    root_fields_preserved($old; $new) as $root_ok |
    ($old_objects | map(
      . as $item |
      {
        supported:(
          if $item.role == "inbound" then
            ($inbound_types | index($item.object.type // "")) != null
          elif $item.role == "endpoint" then
            ($endpoint_types | index($item.object.type // "")) != null
          else true end),
        preserved:any($new_objects[];
          .role == $item.role and
          (.object.type // "") == ($item.object.type // "") and
          (.object.tag // "") == ($item.object.tag // "") and
          (.object | contains($item.object)))
      }
    ) | all(.[]; .supported and .preserved)) as $objects_ok |
    ($old.route.rules // []) as $old_rules |
    ($new.route.rules // []) as $new_rules |
    ($old_rules | all(.[]; . as $rule | any($new_rules[]; . == $rule))) as $rules_ok |
    ($root_ok and $objects_ok and $rules_ok)
  ' <(jq -cS . "${old_config}") <(jq -cS . "${new_config}") >/dev/null 2>&1
}

managed_component_requires_public_confirmation() {
  local record=${1:-}
  jq -e '
    if .enabled != true then false
    elif .role == "inbound" then
      (.type == "tun" or .type == "cloudflared" or has("host_policy") or
       (((.config.listen // "") != "127.0.0.1") and
        ((.config.listen // "") != "::1") and
       ((.config.listen // "") != "localhost")))
    elif .role == "endpoint" and .type == "openvpn-server" then true
    elif .role == "service" and .type == "resolved" then
      (.config.listen // "") as $listen |
      (($listen | type) != "string" or
       ($listen != "" and $listen != "localhost" and $listen != "::1" and
        (($listen | startswith("127.")) | not)))
    else false end
  ' <<< "${record}" >/dev/null 2>&1
}

managed_component_write_state() (
  local state=${1:-} candidate backup
  managed_component_state_validate_json "${state}" || return 1
  [[ ! -L "${SB_PROJECT_DIR}" && ! -L "${SB_COMPONENT_STATE_FILE}" &&
     ! -L "${SB_COMPONENT_STATE_FILE}.bak" ]] || return 1
  mkdir -p "${SB_PROJECT_DIR}" || return 1
  candidate=$(storage_mktemp "${SB_PROJECT_DIR}/.components.json.candidate.XXXXXX") || return 1
  trap 'rm -f -- "${candidate}" "${backup:-}"' EXIT
  printf '%s\n' "${state}" > "${candidate}" || return 1
  chmod 600 "${candidate}" || return 1
  if [[ -f "${SB_COMPONENT_STATE_FILE}" ]]; then
    backup=$(storage_mktemp "${SB_PROJECT_DIR}/.components.json.backup.XXXXXX") || return 1
    cp -p "${SB_COMPONENT_STATE_FILE}" "${backup}" || return 1
    chmod 600 "${backup}" || return 1
    mv -f "${backup}" "${SB_COMPONENT_STATE_FILE}.bak" || return 1
    backup=""
  fi
  mv -f "${candidate}" "${SB_COMPONENT_STATE_FILE}" || return 1
  trap - EXIT
)

managed_component_inventory_json() {
  local state registry component_records component component_id role type base environment
  local instance_environments='[]' instance_environment_rows=()
  state=$(managed_component_state_json) || return 1
  registry=$(component_registry_json) || return 1
  component_records=$(jq -c '.components[]' <<< "${state}") || return 1
  while IFS= read -r component; do
    [[ -n "${component}" ]] || continue
    component_id=$(jq -r '.id' <<< "${component}") || return 1
    role=$(jq -r '.role' <<< "${component}") || return 1
    type=$(jq -r '.type' <<< "${component}") || return 1
    base=$(jq -ce --arg role "${role}" --arg type "${type}" \
      'first(.[] | select(.role == $role and .type == $type) | .environment) // empty' \
      <<< "${registry}") || return 1
    environment=$(managed_component_instance_environment_json "${component}" "${base}") || return 1
    instance_environment_rows+=("$(jq -cn --arg id "${component_id}" --argjson environment "${environment}" \
      '{id:$id,environment:$environment}')")
  done <<< "${component_records}"
  if ((${#instance_environment_rows[@]} > 0)); then
    instance_environments=$(printf '%s\n' "${instance_environment_rows[@]}" | jq -sc '.') || return 1
  fi
  jq -cn --argjson state "${state}" --argjson registry "${registry}" \
    --argjson instance_environments "${instance_environments}" '
    {
      schema: "1",
      action: "component-list",
      revision: $state.revision,
      components: [ $state.components[] |
        . as $component |
        ($registry[] | select(.role == $component.role and .type == $component.type)) as $entry |
        {id:$component.id, role:$component.role, type:$component.type, tag:$component.tag,
         enabled:$component.enabled, registry_id:$entry.state_id,
         display_name:$entry.display_name, availability:$entry.availability,
         environment:$entry.environment,
         instance_environment:(first($instance_environments[] |
           select(.id == $component.id) | .environment) // $entry.environment),
         minimum_project_core:$entry.minimum_project_core,
         config_keys:($component.config | keys), route_rule_count:(($component.route_rules // []) | length),
         host_policy:(if ($component | has("host_policy")) then
           {backend:"iptables",family:"ipv4",transport:"tcp",ingress_interface:$component.host_policy.ingress_interface,
            destination_ports:$component.host_policy.destination_ports,management_ports:$component.host_policy.management_ports}
           else null end)} |
        if (.role == "outbound" and .type == "ssh") then
          . + {host_key_verification:(
            if (($component.config.host_key? // null) |
                if type == "array" then length > 0
                elif type == "string" then length > 0
                else false end)
            then "pinned" else "unverified" end)}
        elif (.role == "outbound" and .type == "tor") then
          . + {runtime_mode:(
            if (($component.config.executable_path? // null) |
                if type == "string" then length > 0 else false end)
            then "external" else "embedded_unverified" end)}
        elif (.role == "outbound" and (.type == "selector" or .type == "urltest")) then
          . + {member_count:(($component.config.outbounds // []) | length)}
        else . end
      ],
      supported: $registry
    }'
}

managed_component_diagnose_json() {
  local state inventory config_status graph_status listener_status core_status redirect_host_policy tproxy_host_policy
  local config_present=false service_state=unknown firewall_status=not_configured firewall_rules=0
  local instance_pending=false component_pending=false component_transaction_phase=none ledger
  local transparent_resources='{"status":"not_assessed","reason":"config_missing","service_active":false,"resources":[],"limitations":[]}'

  state=$(managed_component_state_json) || return 1
  inventory=$(managed_component_inventory_json) || return 1
  redirect_host_policy=$(managed_component_redirect_policy_diagnose_json "${state}") || \
    redirect_host_policy='{"status":"unavailable","resources":[],"operator_managed":[]}'
  tproxy_host_policy=$(managed_component_tproxy_policy_diagnose_json "${state}") || \
    tproxy_host_policy='{"status":"unavailable","resources":[],"operator_managed":[]}'

  if [[ ! -e "${SINGBOX_CONFIG_FILE}" ]]; then
    config_status=missing
    graph_status=not_run
    listener_status=not_run
    core_status=not_run
  elif [[ -f "${SINGBOX_CONFIG_FILE}" && ! -L "${SINGBOX_CONFIG_FILE}" && -r "${SINGBOX_CONFIG_FILE}" ]]; then
    config_present=true
    config_status=present
    if validate_managed_component_graph "${SINGBOX_CONFIG_FILE}" >/dev/null 2>&1; then
      graph_status=passed
    else
      graph_status=failed
    fi
    if validate_managed_listener_resources "${SINGBOX_CONFIG_FILE}" >/dev/null 2>&1; then
      listener_status=passed
    else
      listener_status=failed
    fi
    if [[ -x "${SINGBOX_BIN_PATH}" ]]; then
      if "${SINGBOX_BIN_PATH}" check -c "${SINGBOX_CONFIG_FILE}" >/dev/null 2>&1; then
        core_status=passed
      else
        core_status=failed
      fi
    else
      core_status=unavailable
    fi
  else
    config_status=untrusted
    graph_status=not_run
    listener_status=not_run
    core_status=not_run
  fi

  if command -v systemctl >/dev/null 2>&1; then
    service_state=$(systemctl is-active sing-box 2>/dev/null || printf 'unknown')
  fi
  if [[ "${config_present}" == true ]]; then
    transparent_resources=$(managed_component_transparent_resources_json "${SINGBOX_CONFIG_FILE}" "${service_state}") || \
      transparent_resources='{"status":"unavailable","reason":"resource_probe_failed","service_active":false,"resources":[],"limitations":[]}'
  fi
  if [[ -e "${INSTANCE_FIREWALL_LEDGER_FILE}" ]]; then
    if ledger=$(instance_firewall_read_ledger); then
      firewall_status=available
      firewall_rules=$(jq -r '.rules | length' <<< "${ledger}") || firewall_rules=0
    else
      firewall_status=unavailable
    fi
  fi
  [[ -e "${SB_PROJECT_DIR}.instance-write.lock" ]] && instance_pending=true
  if [[ -e "${SB_COMPONENT_TRANSACTION_DIR}" ]]; then
    component_pending=true
    if [[ -f "${SB_COMPONENT_TRANSACTION_DIR}/transaction.json" &&
          ! -L "${SB_COMPONENT_TRANSACTION_DIR}/transaction.json" ]] &&
       component_transaction_phase=$(jq -r '.phase // "untrusted"' \
         "${SB_COMPONENT_TRANSACTION_DIR}/transaction.json"); then
      :
    else
      component_transaction_phase=untrusted
    fi
  fi

  jq -cn --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" --arg revision "$(jq -r '.revision' <<< "${state}")" \
    --arg config_status "${config_status}" --arg graph_status "${graph_status}" \
    --arg listener_status "${listener_status}" --arg core_status "${core_status}" \
    --arg service_state "${service_state:-unknown}" --arg firewall_status "${firewall_status}" \
    --argjson config_present "${config_present}" --argjson component_count "$(jq -r '.components | length' <<< "${state}")" \
    --argjson firewall_rules "${firewall_rules}" --argjson instance_pending "${instance_pending}" \
    --argjson component_pending "${component_pending}" --arg component_phase "${component_transaction_phase}" \
    --argjson inventory "${inventory}" --argjson transparent_resources "${transparent_resources}" \
    --argjson redirect_host_policy "${redirect_host_policy}" \
    --argjson tproxy_host_policy "${tproxy_host_policy}" \
    '{schema:$schema,action:"component-diagnose",
      state:{revision:($revision|tonumber),component_count:$component_count,valid:true},
      config:{status:$config_status,present:$config_present,graph:$graph_status,listener_resources:$listener_status,core_check:$core_status},
      service:{active_state:$service_state},
      firewall:{ledger_status:$firewall_status,managed_rule_count:$firewall_rules},
      transactions:{instance_write_pending:$instance_pending,component_write_pending:$component_pending,
        component_write_phase:$component_phase},
      transparent_resources:$transparent_resources,
      redirect_host_policy:$redirect_host_policy,
      tproxy_host_policy:$tproxy_host_policy,
      components:$inventory.components,supported:$inventory.supported}'
}

managed_component_export_json() {
  local component_id=${1:-} expected_revision=${2:-} state revision record
  managed_component_state_id_valid "${component_id}" || return 1
  state=$(managed_component_state_json) || return 1
  revision=$(jq -r '.revision | tostring' <<< "${state}") || return 1
  if [[ -n "${expected_revision}" && "${expected_revision}" != "${revision}" ]]; then
    return 2
  fi
  record=$(jq -c --arg id "${component_id}" '.components[] | select(.id == $id)' <<< "${state}") || return 1
  [[ -n "${record}" ]] || return 3
  jq -cn --arg revision "${revision}" --argjson component "${record}" \
    '{action:"component-export",revision:($revision|tonumber),sensitive:true,component:$component}'
}
