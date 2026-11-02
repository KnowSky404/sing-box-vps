
# Check and Enable BBR
enable_bbr() {
  local current_cc
  current_cc=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
  if [[ "${current_cc}" == "bbr" ]]; then
    log_success "BBR 拥塞控制已开启。"
  else
    log_warn "BBR 拥塞控制未开启，正在尝试开启..."
    set_sysctl_conf_value "net.core.default_qdisc" "fq" "/etc/sysctl.conf"
    set_sysctl_conf_value "net.ipv4.tcp_congestion_control" "bbr" "/etc/sysctl.conf"
    sysctl -p /etc/sysctl.conf
    log_success "BBR 开启成功。"
  fi
}

set_sysctl_conf_value() {
  local key=$1
  local value=$2
  local config_file=${3:-/etc/sysctl.conf}
  local escaped_key
  local escaped_value

  escaped_key=$(printf '%s' "${key}" | sed 's/[][\/.^$*]/\\&/g')
  escaped_value=$(printf '%s' "${value}" | sed 's/[\/&]/\\&/g')

  touch "${config_file}"
  if grep -qE "^[[:space:]]*${escaped_key}[[:space:]]*=" "${config_file}"; then
    sed -i -E "s|^[[:space:]]*${escaped_key}[[:space:]]*=.*|${key}=${escaped_value}|" "${config_file}"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${config_file}"
  fi
}

# Open firewall port
open_firewall_port() {
  local port=${1:-} networks transport status selected_transport=${3:-}
  local transports=()
  [[ "${port}" =~ ^[1-9][0-9]{0,4}$ && ${port} -le 65535 ]] || return 1
  networks=$(protocol_registry_field "${2:-${SB_PROTOCOL}}" listen_networks) || return 1
  IFS=, read -r -a transports <<< "${networks}"
  [[ ${#transports[@]} -gt 0 ]] || return 1
  for transport in "${transports[@]}"; do
    [[ "${transport}" == tcp || "${transport}" == udp ]] || return 1
  done
  # A committed listener plan may narrow a protocol's default networks. Keep
  # legacy two-argument calls, but never expand a selected instance network.
  # Validate before touching any backend, including explicitly empty input.
  if [[ $# -ge 3 ]]; then
    [[ "${selected_transport}" == tcp || "${selected_transport}" == udp ]] || return 1
    [[ ",${networks}," == *",${selected_transport},"* ]] || return 1
    transports=("${selected_transport}")
  fi
  log_info "正在尝试放行端口 ${port}..."
  for transport in "${transports[@]}"; do
    # UFW
    if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
      if ufw allow "${port}/${transport}" &>/dev/null; then :; else
        status=$?; printf '[ERROR] firewall_open: ufw_failed; external_state_may_be_partial\n' >&2; return "${status}"
      fi
    fi

    # Firewalld
    if command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null; then
      if firewall-cmd --permanent --add-port="${port}/${transport}" &>/dev/null &&
         firewall-cmd --reload &>/dev/null; then :; else
        status=$?; printf '[ERROR] firewall_open: firewalld_failed; external_state_may_be_partial\n' >&2; return "${status}"
      fi
    fi

    # Iptables
    if command -v iptables &>/dev/null; then
      if iptables -C INPUT -p "${transport}" --dport "${port}" -j ACCEPT &>/dev/null; then :; else
        status=$?
        if [[ ${status} -ne 1 ]]; then
          printf '[ERROR] firewall_open: iptables_inspection_failed; external_state_may_be_partial\n' >&2; return "${status}"
        fi
        if iptables -I INPUT -p "${transport}" --dport "${port}" -j ACCEPT &>/dev/null; then :; else
          status=$?; printf '[ERROR] firewall_open: iptables_insert_failed; external_state_may_be_partial\n' >&2; return "${status}"
        fi
      fi
      log_warn "裸 iptables 规则通常只对当前运行时生效；如需持久化，请确认系统已配置规则保存机制。"
    fi
  done
  log_success "端口 ${port} 防火墙配置尝试完成。"
}

# A listener plan concerns fixed listening sockets, not tunneled traffic. In
# particular Mixed reserves TCP here; its SOCKS UDP relays use dynamic sockets.
# It deliberately refuses unmodelled binding scopes instead of guessing that a
# resource is unused. Tags are owners in this projection, not new instance IDs.
canonical_listener_address() {
  local address=${1:-} left right part zeros result='' word
  local ipv4_tail ipv4_prefix octet ipv4_group_high ipv4_group_low
  local groups=() tail_groups=() octets=()
  # Normalize an IPv4 suffix before expanding the IPv6 groups.  The validator
  # accepts both compressed and full IPv4-embedded spellings; leaving the
  # dotted tail in place would make the hexadecimal parser treat it as an
  # arithmetic expression and reject a valid listener.
  if [[ "${address}" == *.* && "${address}" == *:* ]]; then
    ipv4_tail=${address##*:}
    ipv4_prefix=${address%:*}
    IFS=. read -r -a octets <<< "${ipv4_tail}"
    [[ ${#octets[@]} -eq 4 ]] || return 1
    for octet in "${octets[@]}"; do
      [[ "${octet}" =~ ^(0|[1-9][0-9]{0,2})$ ]] || return 1
      (( 10#${octet} <= 255 )) || return 1
    done
    printf -v ipv4_group_high '%x' \
      "$((10#${octets[0]} * 256 + 10#${octets[1]}))"
    printf -v ipv4_group_low '%x' \
      "$((10#${octets[2]} * 256 + 10#${octets[3]}))"
    address="${ipv4_prefix}:${ipv4_group_high}:${ipv4_group_low}"
  fi
  structured_instance_store_validate_address "${address}" || return 1
  if [[ "${address}" != *:* ]]; then printf '%s' "${address}"; return 0; fi
  if [[ "${address}" == *::* ]]; then
    left=${address%%::*}; right=${address#*::}
    [[ -z "${left}" ]] || IFS=: read -r -a groups <<< "${left}"
    [[ -z "${right}" ]] || IFS=: read -r -a tail_groups <<< "${right}"
    zeros=$((8 - ${#groups[@]} - ${#tail_groups[@]}))
    while (( zeros > 0 )); do groups+=(0); zeros=$((zeros - 1)); done
    if [[ ${#tail_groups[@]} -gt 0 ]]; then groups+=("${tail_groups[@]}"); fi
  else
    IFS=: read -r -a groups <<< "${address}"
  fi
  for part in "${groups[@]}"; do
    printf -v word '%04x' "$((16#${part}))"
    result+="${result:+:}${word}"
  done
  if [[ "${result}" == 0000:0000:0000:0000:0000:ffff:* ]]; then
    printf '%d.%d.%d.%d' "$((16#${groups[6]} >> 8))" "$((16#${groups[6]} & 255))" \
      "$((16#${groups[7]} >> 8))" "$((16#${groups[7]} & 255))"
  else
    printf '%s' "${result}"
  fi
}

managed_listener_plan_json() {
  local registry components projected addresses address canonical normalized='[]' result
  registry=$(protocol_registry_static_json) || return 1
  components=$(component_registry_static_json) || return 1
  # Parse once, project only non-secret resource fields, and capture all output
  # before emission. Input is bounded by the file wrapper or the typed store.
  if ! projected=$(jq -cs --argjson registry "${registry}" --argjson components "${components}" '
    def require($ok): if $ok then . else error("invalid_listener") end;
    # Only an explicitly modelled adapter may select its fixed listeners.
    # NetworkList accepts a string or list; absent/null/[] mean defaults.
    # This is independent of traffic_networks (e.g. SOCKS UDP over TCP).
    def networks($inbound; $entry):
      if ($entry.advanced // false) then
        if ($inbound.type == "tun" or $inbound.type == "cloudflared") then []
        else
          (if $inbound.type == "redirect" then ["tcp"]
           elif ($inbound.type == "direct" or $inbound.type == "tproxy") then
             ($inbound.network // ["tcp", "udp"] |
               if type == "string" then [.] elif type == "array" then . else error("invalid_listener") end)
           else error("invalid_listener") end) as $defaults |
          require(($defaults | length) > 0 and all($defaults[]; . == "tcp" or . == "udp")) |
          require(($defaults | unique | length) == ($defaults | length)) |
          $defaults
        end
      else
        $entry.listen_networks |
        require(type == "array" and length > 0) |
        require(all(.[]; . == "tcp" or . == "udp")) |
        require((unique | length) == length) | . as $defaults |
        if ($inbound | has("network")) then
          require($entry.features.listen_network_selection == true) |
          ($inbound.network | if . == null then []
            elif type == "string" then [.] elif type == "array" then .
            else error("invalid_listener") end) as $requested |
          require(all($requested[]; . == "tcp" or . == "udp")) |
          require(($requested | unique | length) == ($requested | length)) |
          require(all($requested[]; . as $network | $defaults | index($network) != null)) |
          if ($requested | length) == 0 then $defaults
          else [$defaults[] | . as $network | select($requested | index($network) != null)] end
        elif $entry.features.listen_transport_projection == true then
          (($inbound.transport.type // "none")) as $transport |
          if $transport == "quic" then ["udp"]
          elif $transport == "none" or $transport == "http" or $transport == "ws" or $transport == "grpc" then ["tcp"]
          else error("invalid_listener") end
        else $defaults end
      end;
    require(length == 1) | .[0] | require(type == "object") |
    require((.inbounds | type) == "array") |
    require((has("endpoints") | not) or (.endpoints | type) == "array") |
    require(all((.endpoints // [])[]; . as $endpoint |
      any($components[]; .role == "endpoint" and .type == $endpoint.type))) |
    require(all((.endpoints // [])[]; ((.listen_port // 0) | type == "number" and . == floor and . >= 0 and . <= 65535))) |
    require((has("services") | not) or (.services | type) == "array") |
    require(all((.services // [])[]; . as $service |
      type == "object" and
      any($components[]; .role == "service" and .type == $service.type) and
      (.tag | type == "string" and length > 0 and (test("[\u0000-\u001f\u007f]") | not)) and
      (.type == "resolved") and
      ((has("listen") | not) or
        (.listen | type == "string" and length > 0 and (test("[\u0000-\u0020\u007f]") | not))) and
      ((.listen_port // 0) | type == "number" and . == floor and . >= 0 and . <= 65535))) |
    . as $root | .inbounds | require(length <= 256) |
    require(all(.[]; type == "object" and
      (.tag | type == "string" and length > 0 and (test("[\u0000-\u001f\u007f]") | not)) and
      (.type | type == "string") and
      ((has("listen") | not) or (.listen | type == "string" and length > 0 and (test("[\u0000-\u0020\u007f]") | not))) and
      (if (.type == "tun" or .type == "cloudflared") then
         ((.listen_port // 0) == 0)
       else
         (.listen_port | type == "number" and . == floor and . >= 1 and . <= 65535)
       end) and
      ((.netns // "") == "") and ((.bind_interface // "") == "") and ((.reuse_addr // false) == false))) |
    require((map(.tag) | unique | length) == length) |
    (map(. as $inbound |
      ([$registry[] | select(
        if $inbound.type == "vless" then
          .state_id == (if $inbound.tls.reality? != null then "vless-reality" else "vless-plain" end)
        else .type == $inbound.type end
      ) | . + {advanced:false}] +
       [$components[] | select(.role == "inbound" and .type == $inbound.type) | . + {advanced:true}]) |
      require(length == 1) | .[0] as $entry |
      networks($inbound; $entry)[] |
      {owner:$inbound.tag, role:"inbound", protocol:($entry.state_id // $entry.type), address:($inbound.listen // "127.0.0.1"),
       transport:., port:$inbound.listen_port})
      ) +
      [($root.endpoints // [])[] | select((.listen_port // 0) > 0) |
       {owner:.tag, role:"endpoint", protocol:(.type + "-endpoint"), address:(.listen // "0.0.0.0"),
        transport:(if .type == "openvpn-server" then (.network // "udp") else "udp" end),
        port:.listen_port}] +
      [($root.services // [])[] | . as $service |
       {owner:$service.tag, role:"service", protocol:("resolved-service"),
        address:(if (($service.listen // "") == "") then "127.0.0.53" else $service.listen end),
        transport:"tcp",
        port:(if (($service.listen_port // 0) == 0) then 53 else $service.listen_port end)},
       {owner:$service.tag, role:"service", protocol:("resolved-service"),
        address:(if (($service.listen // "") == "") then "127.0.0.53" else $service.listen end),
        transport:"udp",
        port:(if (($service.listen_port // 0) == 0) then 53 else $service.listen_port end)}]
  ' 2>/dev/null); then
    printf '[ERROR] listener_resources: unmodelled_or_invalid_listener\n' >&2
    return 1
  fi
  addresses=$(jq -r '[.[].address] | unique[]' <<< "${projected}") || return 1
  while IFS= read -r address; do
    [[ -n "${address}" ]] || continue
    canonical=$(canonical_listener_address "${address}") || {
      printf '[ERROR] listener_resources: invalid_address\n' >&2; return 1;
    }
    normalized=$(jq -c --arg original "${address}" --arg canonical "${canonical}" \
      '. + [{original:$original,canonical:$canonical}]' <<< "${normalized}") || return 1
  done <<< "${addresses}"
  result=$(jq -c --argjson normalized "${normalized}" '
    map(. as $item | ($normalized[] | select(.original == $item.address) | .canonical) as $address |
      .address=$address | .family=(if $address | contains(":") then "ipv6" else "ipv4" end) |
      .dual_stack=($address == "0000:0000:0000:0000:0000:0000:0000:0000"))
  ' <<< "${projected}") || return 1
  printf '%s\n' "${result}"
}

managed_listener_plan() (
  umask 077
  local file=${1:-} snapshot result
  [[ -f "${file}" && ! -L "${file}" && -r "${file}" ]] || {
    printf '[ERROR] listener_resources: unreadable_config\n' >&2; return 1;
  }
  # No credentials in argv, no unbounded reads and no reread after validation.
  snapshot=$(mktemp /tmp/sbv-listener-plan.XXXXXX) || return 1
  trap 'if ! rm -f -- "${snapshot}"; then printf "[ERROR] listener_resources: cleanup_failed\n" >&2; fi' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  head -c 4194305 -- "${file}" > "${snapshot}" || return 1
  if [[ $(wc -c < "${snapshot}") -gt 4194304 ]]; then
    printf '[ERROR] listener_resources: oversized_config\n' >&2; return 1
  fi
  result=$(managed_listener_plan_json < "${snapshot}") || return $?
  rm -f -- "${snapshot}" || return $?
  trap - EXIT INT TERM HUP
  printf '%s\n' "${result}"
)

validate_listener_plan_json() {
  if ! jq -e '
    def overlap($a; $b):
      $a.dual_stack or $b.dual_stack or
      ($a.family == $b.family and ($a.address == $b.address or
        ($a.family == "ipv4" and ($a.address == "0.0.0.0" or $b.address == "0.0.0.0"))));
    . as $items | all(range(0; length); . as $i |
      all(range($i+1; $items|length); . as $j |
        ($items[$i].transport != $items[$j].transport or
         $items[$i].port != $items[$j].port or (overlap($items[$i]; $items[$j]) | not))))
  ' >/dev/null 2>&1; then
    printf '[ERROR] listener_resources: listener_conflict\n' >&2
    return 1
  fi
}

validate_managed_listener_resources() {
  local plan
  plan=$(managed_listener_plan "${1:-}") || return $?
  validate_listener_plan_json <<< "${plan}"
}

# Close only fixed-port transports with no remaining owner. Legacy rules are
# broad (all addresses/families), so any remaining address retains the rule.
# This reference guard does not establish ownership of pre-existing user rules.
# Missing live config is allowed only by the explicit all-protocol removal path.
# Close firewall port (reverse of open_firewall_port)
singbox_service_confirmed_stopped() {
  local active_state
  active_state=$(systemctl show sing-box --property=ActiveState --value 2>/dev/null) || {
    printf '[ERROR] firewall_cleanup: service_state_unavailable; rules_unchanged\n' >&2; return 1;
  }
  [[ "${active_state}" == inactive ]] || {
    printf '[ERROR] firewall_cleanup: service_not_stopped; rules_unchanged\n' >&2; return 1;
  }
}

close_firewall_port() {
  local port=${1:-} mode=${2:-remaining} plan old_plan transports transport status
  [[ "${port}" =~ ^[1-9][0-9]{0,4}$ && ${port} -le 65535 ]] || return 1
  if [[ "${mode}" == all_removed && ! -e "${SINGBOX_CONFIG_FILE}" && ! -L "${SINGBOX_CONFIG_FILE}" &&
        ! -e "${SB_PROTOCOL_INDEX_FILE}" && ! -L "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    singbox_service_confirmed_stopped || return $?
    plan='[]'
  elif [[ "${mode}" == remaining ]]; then
    plan=$(managed_listener_plan "${SINGBOX_CONFIG_FILE}") || {
      printf '[ERROR] firewall_cleanup: inventory_unavailable; rules_unchanged\n' >&2
      return 1
    }
  else
    printf '[ERROR] firewall_cleanup: invalid_removal_state; rules_unchanged\n' >&2
    return 1
  fi
  old_plan=$(managed_listener_plan "${SINGBOX_CONFIG_FILE}.bak") || {
    printf '[ERROR] firewall_cleanup: previous_inventory_unavailable; rules_unchanged\n' >&2
    return 1
  }
  transports=$(jq -r --argjson port "${port}" --argjson old "${old_plan}" '
    . as $owners | [$old[] | select(.port == $port) | .transport] | unique[] | . as $transport |
    select(any($owners[]; .port == $port and .transport == $transport) | not)
  ' <<< "${plan}") || return 1
  [[ -n "${transports}" ]] || {
    log_info "端口 ${port} 仍有实例引用，保留防火墙规则。"
    return 0
  }
  log_info "正在尝试关闭端口 ${port}..."
  while IFS= read -r transport; do
    if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
      if ufw delete allow "${port}/${transport}" &>/dev/null; then :; else
        status=$?; printf '[ERROR] firewall_cleanup: ufw_failed; external_state_may_be_partial\n' >&2; return "${status}"
      fi
    fi
    if command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null; then
      if firewall-cmd --permanent --remove-port="${port}/${transport}" &>/dev/null &&
         firewall-cmd --reload &>/dev/null; then :; else
        status=$?; printf '[ERROR] firewall_cleanup: firewalld_failed; external_state_may_be_partial\n' >&2; return "${status}"
      fi
    fi
    if command -v iptables &>/dev/null; then
      if iptables -C INPUT -p "${transport}" --dport "${port}" -j ACCEPT &>/dev/null; then
        if iptables -D INPUT -p "${transport}" --dport "${port}" -j ACCEPT &>/dev/null; then :; else
          status=$?; printf '[ERROR] firewall_cleanup: iptables_delete_failed; external_state_may_be_partial\n' >&2; return "${status}"
        fi
      else
        status=$?
        if [[ ${status} -ne 1 ]]; then
          printf '[ERROR] firewall_cleanup: iptables_inspection_failed; external_state_may_be_partial\n' >&2
          return "${status}"
        fi
      fi
    fi
  done <<< "${transports}"
  log_info "端口 ${port} 防火墙规则清理尝试完成。"
}

# Instance firewall transactions deliberately use a separate ownership ledger
# from the legacy coarse port helpers above.  These functions are a narrow
# transaction primitive for callers which already have a committed old/new
# listener plan.  They never infer ownership from a port alone: a rule is
# either positively observed before it is recorded, or it is created by this
# transaction with a deterministic marker.
readonly INSTANCE_FIREWALL_SCHEMA_VERSION="1"
readonly INSTANCE_FIREWALL_LEDGER_FILE="${SB_PROJECT_DIR}/managed-firewall.json"

instance_firewall_journal_path_valid() {
  local journal_file=${1:-} journal_dir
  [[ -n "${journal_file}" && "${journal_file}" != */ && "${journal_file}" != "${SB_PROJECT_DIR}"/* ]] || return 1
  [[ "${journal_file}" != *$'\n'* && "${journal_file}" != *$'\r'* ]] || return 1
  journal_dir=$(dirname -- "${journal_file}") || return 1
  [[ -d "${journal_dir}" && ! -L "${journal_dir}" ]] || return 1
  [[ ! -e "${journal_file}" || ! -L "${journal_file}" ]] || return 1
}

instance_firewall_write_json_atomic() {
  local destination=$1 payload=$2 destination_dir candidate
  destination_dir=$(dirname -- "${destination}") || return 1
  [[ -d "${destination_dir}" && ! -L "${destination_dir}" ]] || return 1
  [[ ! -e "${destination}" || ! -L "${destination}" ]] || return 1
  jq -e . >/dev/null 2>&1 <<< "${payload}" || return 1
  candidate=$(mktemp "${destination_dir}/.$(basename -- "${destination}").candidate.XXXXXX") || return 1
  if ! printf '%s\n' "${payload}" > "${candidate}" ||
     ! chmod 600 "${candidate}" ||
     ! mv -f -- "${candidate}" "${destination}"; then
    rm -f -- "${candidate}"
    return 1
  fi
}

instance_firewall_empty_ledger() {
  printf '{"schema_version":%s,"rules":[]}\n' "${INSTANCE_FIREWALL_SCHEMA_VERSION}"
}

instance_firewall_ledger_validate() {
  jq -ce --argjson version "${INSTANCE_FIREWALL_SCHEMA_VERSION}" '
    def clean_string:
      type == "string" and length > 0 and (test("[\u0000-\u001f\u007f]") | not);
    def ref_valid:
      . as $instance |
      type == "object" and
      (.owner | clean_string) and
      (.protocol | clean_string) and
      (.address | clean_string) and
      (.transport | type == "string" and test("^(tcp|udp)$")) and
      (.port | type == "number" and . == floor and . >= 1 and . <= 65535);
    def rule_valid:
      type == "object" and
      (.backend | type == "string" and test("^(ufw|firewalld|iptables|ip6tables)$")) and
      (.family | type == "string" and test("^(any|ipv4|ipv6)$")) and
      (.address | clean_string) and
      (.transport | type == "string" and test("^(tcp|udp)$")) and
      (.port | type == "number" and . == floor and . >= 1 and . <= 65535) and
      (.comment | clean_string) and
      (.refs | type == "array" and length <= 4096 and all(.[]; ref_valid));
    def ledger_valid:
      type == "object" and .schema_version == $version and
      (.rules | type == "array" and length <= 4096 and all(.[]; rule_valid)) and
      (([.rules[] | [.backend,.family,.address,.transport,.port] | @json] | unique | length) == (.rules | length));
    select(type == "object" and ledger_valid)
  '
}

instance_firewall_read_ledger() {
  local ledger_file=${INSTANCE_FIREWALL_LEDGER_FILE}
  if [[ ! -e "${ledger_file}" ]]; then
    instance_firewall_empty_ledger
    return 0
  fi
  [[ -f "${ledger_file}" && ! -L "${ledger_file}" && -r "${ledger_file}" ]] || return 1
  [[ "$(stat -c '%a' "${ledger_file}")" == 600 ]] || return 1
  instance_firewall_ledger_validate < "${ledger_file}"
}

managed_firewall_owners_json() (
  trap - EXIT ERR RETURN DEBUG
  local explicit=${1:-'[]'} tags protocols protocol state_file store_file instance_id tag instance_ids component_tags
  tags=$(jq -ce 'select(type=="array" and all(.[]; type=="string" and length>0)) |
    map({role:"inbound",tag:.}) | unique' <<< "${explicit}") || return 1
  component_tags=$(managed_component_state_json | jq -ce '[.components[] |
    select(.enabled==true and (.role | IN("inbound","endpoint","service"))) | {role,tag}]') || return 1
  tags=$(jq -c --argjson components "${component_tags}" '. + $components' <<< "${tags}") || return 1
  protocols=$(list_indexed_protocols_raw) || return 1
  while IFS= read -r protocol; do
    [[ -n "${protocol}" ]] || continue
    state_file=$(protocol_state_file "${protocol}") || return 1
    [[ -f "${state_file}" && ! -L "${state_file}" ]] || continue
    if [[ "${protocol}" == vless-reality ]]; then
      load_vless_reality_protocol_state || return 1
      instance_ids=$(list_vless_reality_instance_ids) || return 1
      if [[ -n "${instance_ids}" ]]; then
        while IFS= read -r instance_id; do
          load_vless_reality_instance_state "${instance_id}" || return 1
          tag=$(vless_reality_inbound_tag_for_instance "${instance_id}") || return 1
          tags=$(jq -c --arg tag "${tag}" '. + [{role:"inbound",tag:$tag}]' <<< "${tags}") || return 1
        done <<< "${instance_ids}"
        continue
      fi
    else
      store_file=$(plain_proxy_structured_store_file "${protocol}") || return 1
      if [[ -e "${store_file}" || -L "${store_file}" ]]; then
        [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
        [[ "$(protocol_instance_state_schema "${protocol}")" == 2 ]] || return 1
        component_tags=$(jq -ce '.instances | select(type=="array") | [.[] | .tag, (.detour.tag? // empty)] |
          select(all(.[]; type=="string" and length>0)) | map({role:"inbound",tag:.})' "${store_file}") || return 1
        tags=$(jq -c --argjson instances "${component_tags}" '. + $instances' <<< "${tags}") || return 1
        continue
      fi
    fi
    tag=$(protocol_registry_field "${protocol}" default_tag) || return 1
    tags=$(jq -c --arg tag "${tag}" '. + [{role:"inbound",tag:$tag}]' <<< "${tags}") || return 1
  done <<< "${protocols}"
  jq -c 'unique' <<< "${tags}"
)

filter_owned_firewall_plan_json() {
  local plan=$1 explicit=${2:-'[]'} tags
  tags=$(managed_firewall_owners_json "${explicit}") || return 1
  jq -c --argjson owners "${tags}" 'map(select(. as $listener |
    any($owners[]; .role == $listener.role and .tag == $listener.owner)))' <<< "${plan}"
}

instance_firewall_plan_file() {
  local config_file=${1:-} explicit=${2:-'[]'} plan
  [[ -f "${config_file}" && ! -L "${config_file}" && -r "${config_file}" ]] || return 1
  plan=$(managed_listener_plan "${config_file}") || return 1
  filter_owned_firewall_plan_json "${plan}" "${explicit}"
}

open_scoped_protocol_ports() (
  trap - EXIT ERR RETURN DEBUG
  local journal="" status=0 keep_journal=n prepared=n reason
  umask 077
  trap 'if [[ -n "${journal}" && "${keep_journal}" != y ]]; then rm -f -- "${journal}"; fi' EXIT
  firewall_reconcile_interrupt() {
    local code=$1
    trap - INT TERM HUP
    if [[ "${prepared}" != y ]]; then
      printf '[WARN] firewall_reconcile: interrupted_before_apply; rules_unchanged\n' >&2
    elif ! instance_firewall_rollback "${journal}"; then
      keep_journal=y
      printf '[ERROR] firewall_reconcile: interrupted; rollback_failed; firewall_may_be_partial; journal=%s\n' "${journal}" >&2
    else
      printf '[WARN] firewall_reconcile: interrupted; firewall_rolled_back\n' >&2
    fi
    exit "${code}"
  }
  trap 'firewall_reconcile_interrupt 130' INT
  trap 'firewall_reconcile_interrupt 143' TERM
  trap 'firewall_reconcile_interrupt 129' HUP
  journal=$(mktemp "${SB_PROJECT_DIR}.firewall-reconcile.XXXXXX") || return 1
  if instance_firewall_prepare "" "${SINGBOX_CONFIG_FILE}" "${journal}"; then
    prepared=y
  else
    status=$?
    if reason=$(jq -r '[.diagnostics[]?.code] | unique | join(",")' "${journal}" 2>/dev/null); then :; else reason=unavailable; fi
    printf '[ERROR] firewall_reconcile: prepare_failed; rules_unchanged; reason=%s\n' "${reason:-unavailable}" >&2
    return "${status}"
  fi
  if instance_firewall_apply "${journal}" && instance_firewall_commit "${journal}"; then
    return 0
  else
    status=$?
    if ! instance_firewall_rollback "${journal}"; then
      keep_journal=y
      printf '[ERROR] firewall_reconcile: rollback_failed; firewall_may_be_partial; journal=%s\n' "${journal}" >&2
    else
      printf '[ERROR] firewall_reconcile: apply_or_commit_failed; firewall_rolled_back\n' >&2
    fi
  fi
  return "${status}"
)

instance_firewall_targets_json() {
  local plan_json=${1:-}
  jq -ce '
    def loopback:
      (.family == "ipv4" and (.address | test("^127\\."))) or
      (.family == "ipv6" and .address == "0000:0000:0000:0000:0000:0000:0000:0001");
    def physical:
      if .dual_stack then
        [{family:"ipv4",address:"0.0.0.0"},{family:"ipv6",address:"::"}]
      else [{family:.family,address:.address}]
      end;
    [ .[] as $listener |
      ($listener | physical[]) as $physical |
      {owner:$listener.owner,protocol:$listener.protocol,address:$physical.address,
       family:$physical.family,transport:$listener.transport,port:$listener.port} |
      select(loopback | not)
    ] | unique_by([.owner,.protocol,.address,.family,.transport,.port])
  ' <<< "${plan_json}"
}

instance_firewall_backend_state() {
  local backend=${1:-} status
  case "${backend}" in
    ufw)
      command -v ufw >/dev/null 2>&1 || return 2
      LC_ALL=C ufw status >/dev/null 2>&1 || return 3
      LC_ALL=C ufw status 2>/dev/null | grep -Fq 'Status: active' || return 2
      ;;
    firewalld)
      command -v firewall-cmd >/dev/null 2>&1 || return 2
      firewall-cmd --state >/dev/null 2>&1 || {
        status=$?
        [[ ${status} -eq 1 ]] && return 2
        return "${status}"
      }
      ;;
    iptables|ip6tables)
      command -v "${backend}" >/dev/null 2>&1 || return 2
      ;;
    *) return 1 ;;
  esac
  return 0
}

instance_firewall_rule_comment() {
  local backend=$1 family=$2 transport=$3 port=$4 address=$5
  local digest
  digest=$(printf '%s\0' "${backend}" "${family}" "${transport}" "${port}" "${address}" | sha256sum | awk '{print $1}') || return 1
  [[ "${digest}" =~ ^[[:xdigit:]]{64}$ ]] || return 1
  printf 'sbv-instance-%s' "${digest:0:24}"
}

instance_firewall_ufw_status_match() {
  local family=$1 address=$2 transport=$3 port=$4 comment=${5:-} require_marker=${6:-0}
  local line rule_text line_comment rule prefix first second target canonical_target target_family target_matched=0
  rule="${port}/${transport}"
  while IFS= read -r line; do
    # Comments are opaque data, never action/port/family tokens. Preserve
    # them separately only for the exact ownership comparison below.
    rule_text=${line%%' # '*}
    line_comment=''
    [[ "${line}" != *' # '* ]] || line_comment=${line#*' # '}
    [[ "${rule_text}" != *' ALLOW OUT '* ]] || continue
    if [[ "${rule_text}" == *' ALLOW IN '* ]]; then
      prefix=${rule_text%% ALLOW IN *}
    elif [[ "${rule_text}" == *' ALLOW '* ]]; then
      prefix=${rule_text%% ALLOW *}
    else
      continue
    fi
    [[ "${prefix}" =~ (^|[[:space:]])${rule}([[:space:]]|$) ]] || continue
    target=''
    if [[ "${prefix}" == *' on '* ]]; then
      target=${prefix##* on }
      target=${target%% *}
    else
      read -r first second _ <<< "${prefix}"
      [[ "${first}" == "${rule}" || "${first}" == "${rule}"\ * ]] || target=${first}
    fi
    target=${target#\[}
    target=${target%\]}
    target=${target%/32}
    target=${target%/128}
    if [[ -z "${target}" || "${target}" == Anywhere ]]; then
      [[ "${family}" == ipv4 && "${rule_text}" != *'(v6)'* ||
         "${family}" == ipv6 && "${rule_text}" == *'(v6)'* ]] || continue
    elif [[ "${target}" == "Anywhere (v6)" ]]; then
      [[ "${family}" == ipv6 ]] || continue
    else
      canonical_target=$(canonical_listener_address "${target}") || return 3
      target_family=ipv4
      [[ "${canonical_target}" == *:* ]] && target_family=ipv6
      [[ "${target_family}" == "${family}" && "${canonical_target}" == "${address}" ]] || continue
    fi
    target_matched=1
    if [[ "${require_marker}" == 0 ]]; then
      return 0
    fi
    # UFW's delete operation ignores comments, so ownership requires the
    # complete comment field to match exactly.  A substring is not evidence
    # of ownership (for example, an external suffix/prefix marker).
    [[ -n "${line_comment}" && "${line_comment}" == "${comment}" ]] && return 0
  done
  [[ "${require_marker}" == 1 && ${target_matched} -eq 1 ]] && return 4
  return 1
}

instance_firewall_rule_query() {
  local backend=$1 family=$2 transport=$3 port=$4 address=$5 comment=${6:-} require_marker=${7:-0} status
  case "${backend}" in
    ufw)
      [[ "${family}" == ipv4 || "${family}" == ipv6 ]] || return 3
      [[ -n "${comment}" || "${require_marker}" == 0 ]] || return 3
      LC_ALL=C ufw status 2>/dev/null | instance_firewall_ufw_status_match \
        "${family}" "${address}" "${transport}" "${port}" "${comment}" "${require_marker}"
      status=$?
      [[ ${status} -eq 0 || ${status} -eq 1 || ${status} -eq 4 ]] || return "${status}"
      return "${status}"
      ;;
    firewalld)
      local runtime_status permanent_status
      firewall-cmd --query-port="${port}/${transport}" >/dev/null 2>&1
      runtime_status=$?
      [[ ${runtime_status} -eq 0 || ${runtime_status} -eq 1 ]] || return "${runtime_status}"
      firewall-cmd --permanent --query-port="${port}/${transport}" >/dev/null 2>&1
      permanent_status=$?
      [[ ${permanent_status} -eq 0 || ${permanent_status} -eq 1 ]] || return "${permanent_status}"
      [[ ${runtime_status} -eq 0 && ${permanent_status} -eq 0 ]] && return 0
      return 1
      ;;
    iptables|ip6tables)
      local binary="${backend}" destination_args=()
      [[ "${family}" == ipv4 && "${backend}" == iptables ||
         "${family}" == ipv6 && "${backend}" == ip6tables ]] || return 3
      if [[ "${address}" != 0.0.0.0 && "${address}" != :: ]]; then
        destination_args=(-d "${address}")
      fi
      "${binary}" -C INPUT -p "${transport}" ${destination_args[@]+"${destination_args[@]}"} --dport "${port}" \
        -m comment --comment "${comment}" -j ACCEPT >/dev/null 2>&1
      status=$?
      [[ ${status} -eq 0 || ${status} -eq 1 ]] || return "${status}"
      return "${status}"
      ;;
    *) return 1 ;;
  esac
}

instance_firewall_rule_command() {
  local action=$1 backend=$2 family=$3 transport=$4 port=$5 address=$6 comment=$7
  local operation binary=''
  case "${action}" in create) operation=-I ;; delete) operation=-D ;; *) return 1 ;; esac
  case "${backend}" in
    iptables) binary=iptables; [[ "${family}" == ipv4 ]] || return 1 ;;
    ip6tables) binary=ip6tables; [[ "${family}" == ipv6 ]] || return 1 ;;
    ufw)
      [[ "${family}" == ipv4 || "${family}" == ipv6 ]] || return 1
      local ufw_address
      if [[ "${family}" == ipv6 ]]; then
        ufw_address=${address}
        [[ "${ufw_address}" == :: ]] && ufw_address=::/0
      else
        ufw_address=${address}
        [[ "${ufw_address}" == 0.0.0.0 ]] && ufw_address=0.0.0.0/0
      fi
      if [[ "${action}" == create ]]; then
        ufw allow in proto "${transport}" to "${ufw_address}" port "${port}" comment "${comment}"
      else
        ufw delete allow in proto "${transport}" to "${ufw_address}" port "${port}" comment "${comment}"
      fi
      return $?
      ;;
    firewalld)
      # firewalld has independent runtime/permanent rule sets and no portable
      # ownership marker for a plain port rule.  Never mutate either set here:
      # callers must provision both zones explicitly and then re-run prepare.
      return 1
      ;;
    *) return 1 ;;
  esac
  local destination_args=()
  if [[ "${address}" != 0.0.0.0 && "${address}" != :: ]]; then
    destination_args=(-d "${address}")
  fi
  "${binary}" "${operation}" INPUT -p "${transport}" ${destination_args[@]+"${destination_args[@]}"} --dport "${port}" \
    -m comment --comment "${comment}" -j ACCEPT
}

instance_firewall_targets_for_rule() {
  local targets=$1 backend=$2 family=$3 address=$4 transport=$5 port=$6
  jq -c --arg backend "${backend}" --arg family "${family}" --arg address "${address}" \
    --arg transport "${transport}" --argjson port "${port}" '
    map(select(.family == $family and .address == $address and .transport == $transport and .port == $port)) |
    map({owner,protocol,address,transport,port})
  ' <<< "${targets}"
}

instance_firewall_refs_for_rule() {
  local targets=$1 backend=$2 family=$3 address=$4 transport=$5 port=$6
  if [[ "${backend}" == firewalld ]]; then
    jq -c --arg transport "${transport}" --argjson port "${port}" \
      'map(select(.transport == $transport and .port == $port)) | map({owner,protocol,address,transport,port})' <<< "${targets}"
  else
    instance_firewall_targets_for_rule "${targets}" "${backend}" "${family}" "${address}" "${transport}" "${port}"
  fi
}

instance_firewall_journal_write() {
  local journal_file=$1 payload=$2
  instance_firewall_journal_path_valid "${journal_file}" || return 1
  instance_firewall_write_json_atomic "${journal_file}" "${payload}"
}

instance_firewall_journal_update() {
  local journal_file=$1 filter=$2
  local current updated
  [[ -f "${journal_file}" && ! -L "${journal_file}" ]] || return 1
  current=$(jq -ce . "${journal_file}") || return 1
  updated=$(jq -ce "${filter}" <<< "${current}") || return 1
  instance_firewall_write_json_atomic "${journal_file}" "${updated}"
}

instance_firewall_journal_validate() {
  local journal_file=${1:-}
  [[ -f "${journal_file}" && ! -L "${journal_file}" && -r "${journal_file}" ]] || return 1
  [[ "$(stat -c '%a' "${journal_file}")" == 600 ]] || return 1
  jq -ce --argjson version "${INSTANCE_FIREWALL_SCHEMA_VERSION}" '
    def clean_string:
      type == "string" and length > 0 and (test("[\u0000-\u001f\u007f]") | not);
    def ref_valid:
      type == "object" and
      (.owner | clean_string) and (.protocol | clean_string) and
      (.address | clean_string) and
      (.transport | type == "string" and test("^(tcp|udp)$")) and
      (.port | type == "number" and . == floor and . >= 1 and . <= 65535);
    def rule_valid:
      type == "object" and
      (.backend | type == "string" and test("^(ufw|firewalld|iptables|ip6tables)$")) and
      (.family | type == "string" and test("^(any|ipv4|ipv6)$")) and
      (.address | clean_string) and
      (.transport | type == "string" and test("^(tcp|udp)$")) and
      (.port | type == "number" and . == floor and . >= 1 and . <= 65535) and
      (.comment | clean_string) and
      (.refs | type == "array" and length <= 4096 and all(.[]; ref_valid));
    def ledger_valid:
      type == "object" and .schema_version == $version and
      (.rules | type == "array" and length <= 4096 and all(.[]; rule_valid)) and
      (([.rules[] | [.backend,.family,.address,.transport,.port] | @json] | unique | length) == (.rules | length));
    def operation_valid:
      type == "object" and
      (.id | clean_string) and
      (.backend | type == "string" and test("^(ufw|firewalld|iptables|ip6tables)$")) and
      (.family | type == "string" and test("^(any|ipv4|ipv6)$")) and
      (.address | clean_string) and
      (.transport | type == "string" and test("^(tcp|udp)$")) and
      (.port | type == "number" and . == floor and . >= 1 and . <= 65535) and
      (.comment | clean_string) and
      (.action | type == "string" and test("^(create|delete|preserve|unavailable)$")) and
      (.ownership | type == "string" and test("^(owned|preexisting|unowned)$")) and
      ((.action != "create" and .action != "delete") or .ownership == "owned") and
      (.action != "unavailable" or .ownership == "unowned") and
      (.refs_before | type == "array" and length <= 4096 and all(.[]; ref_valid)) and
      (.refs_after | type == "array" and length <= 4096 and all(.[]; ref_valid)) and
      (.state | type == "string" and test("^(planned|intent|applied|preserved|unavailable)$")) and
      (.rollback_state | type == "string" and test("^(none|intent|applied|already_compensated|uncertain)$"));
    def backend_status_valid:
      type == "object" and
      (.backend | type == "string" and test("^(ufw|firewalld|iptables|ip6tables)$")) and
      (.state | type == "string" and test("^(available|unavailable|external-managed)$"));
    def diagnostic_valid:
      type == "object" and (.code | clean_string) and
      (.severity | type == "string" and test("^(warning|error)$"));
    . as $journal |
    select(
      ($journal.schema_version == $version) and
      ($journal.status | type == "string" and test("^(prepared|applying|applied|committed|apply_failed|rolling_back|rolled_back|rollback_failed|rollback_uncertain)$")) and
      ($journal.before_ledger_exists | type == "boolean") and
      ($journal.before_ledger | ledger_valid) and
      ($journal.after_ledger | ledger_valid) and
      ($journal.operations | type == "array" and length <= 4096 and all(.[]; operation_valid) and ([.[] | .id] | unique | length) == length) and
      ($journal.backend_statuses | type == "array" and length <= 4 and all(.[]; backend_status_valid) and ([.[] | .backend] | unique | length) == length) and
      ($journal.diagnostics | type == "array" and length <= 4096 and all(.[]; diagnostic_valid))
    )
  ' "${journal_file}"
}

instance_firewall_prepare_failure() {
  local journal_file=$1 code=$2 result_status=${3:-1}
  local payload
  payload=$(jq -cn --argjson version "${INSTANCE_FIREWALL_SCHEMA_VERSION}" --arg code "${code}" \
    '{schema_version:$version,status:"prepare_failed",error_code:$code,before_ledger_exists:false,before_ledger:{schema_version:$version,rules:[]},after_ledger:{schema_version:$version,rules:[]},operations:[],diagnostics:[{code:$code,severity:"error"}]}') || return 1
  instance_firewall_journal_write "${journal_file}" "${payload}" || return 1
  return "${result_status}"
}

instance_firewall_prepare() {
  local old_config=${1:-} new_config=${2:-} journal_file=${3:-} explicit_tags=${4:-'[]'}
  local old_plan new_plan old_targets new_targets before_ledger
  local backend state backend_statuses='[]' diagnostics='[]' candidates selected_frontend=raw
  local ufw_state firewalld_state
  local operations='[]' after_rules='[]' candidate_json candidate_count index
  local rule_backend rule_family rule_address rule_transport rule_port comment
  local local_rule_family local_rule_address
  local refs_before refs_after ledger_rule query_status action ownership
  local journal_payload processed_key existing_key already_processed before_ledger_exists=false
  local processed_keys=()

  instance_firewall_journal_path_valid "${journal_file}" || return 1
  if [[ -n "${old_config}" && -e "${old_config}" ]]; then
    old_plan=$(instance_firewall_plan_file "${old_config}" "${explicit_tags}") || {
      instance_firewall_prepare_failure "${journal_file}" invalid_old_plan || :; return 1;
    }
  else
    old_plan='[]'
  fi
  new_plan=$(instance_firewall_plan_file "${new_config}" "${explicit_tags}") || {
    instance_firewall_prepare_failure "${journal_file}" invalid_new_plan || :; return 1;
  }
  old_targets=$(instance_firewall_targets_json "${old_plan}") || {
    instance_firewall_prepare_failure "${journal_file}" invalid_old_targets || :; return 1;
  }
  new_targets=$(instance_firewall_targets_json "${new_plan}") || {
    instance_firewall_prepare_failure "${journal_file}" invalid_new_targets || :; return 1
  }
  before_ledger=$(instance_firewall_read_ledger) || {
    instance_firewall_prepare_failure "${journal_file}" invalid_ledger || :; return 1;
  }
  [[ -e "${INSTANCE_FIREWALL_LEDGER_FILE}" ]] && before_ledger_exists=true
  candidates=$(jq -cn --argjson old "${old_targets}" --argjson new "${new_targets}" --argjson ledger "${before_ledger}" '
    def families: ["ipv4","ipv6"];
    def candidate($x):
      if $x.family == "ipv4" then
        [{family:"ipv4",address:(if $x.address == "0.0.0.0" then "0.0.0.0" else $x.address end),transport:$x.transport,port:$x.port}]
      else [{family:"ipv6",address:(if $x.address == "::" then "::" else $x.address end),transport:$x.transport,port:$x.port}]
      end;
    ([ $old[], $new[] ] | map(candidate(.)) | (add // [])) as $physical |
    ([$physical[]] + [$ledger.rules[] | {family:.family,address:.address,transport:.transport,port:.port}]) |
    unique_by([.family,.address,.transport,.port])
  ') || {
    instance_firewall_prepare_failure "${journal_file}" invalid_candidates || :; return 1;
  }
  for backend in ufw firewalld iptables ip6tables; do
    if instance_firewall_backend_state "${backend}"; then
      backend_statuses=$(jq -c --arg backend "${backend}" '. + [{backend:$backend,state:"available"}]' <<< "${backend_statuses}") || return 1
    else
      state=$?
      if [[ ${state} -eq 2 ]]; then
        backend_statuses=$(jq -c --arg backend "${backend}" '. + [{backend:$backend,state:"unavailable"}]' <<< "${backend_statuses}") || return 1
        diagnostics=$(jq -c --arg backend "${backend}" '. + [{code:"backend_unavailable",backend:$backend,severity:"warning"}]' <<< "${diagnostics}") || return 1
      else
        instance_firewall_prepare_failure "${journal_file}" backend_inspection_failed || :; return 1
      fi
    fi
  done
  ufw_state=$(jq -r '.[] | select(.backend == "ufw") | .state' <<< "${backend_statuses}") || return 1
  firewalld_state=$(jq -r '.[] | select(.backend == "firewalld") | .state' <<< "${backend_statuses}") || return 1
  if [[ "${ufw_state}" == available && "${firewalld_state}" == available ]]; then
    instance_firewall_prepare_failure "${journal_file}" backend_conflict || :; return 1
  elif [[ "${ufw_state}" == available ]]; then
    selected_frontend=ufw
  elif [[ "${firewalld_state}" == available ]]; then
    selected_frontend=firewalld
  fi
  if [[ "${selected_frontend}" != raw ]]; then
    backend_statuses=$(jq -c --arg frontend "${selected_frontend}" '
      map(if (.backend == "iptables" or .backend == "ip6tables")
          then .state = "external-managed" else . end)
    ' <<< "${backend_statuses}") || return 1
    diagnostics=$(jq -c --arg frontend "${selected_frontend}" '
      . + [{code:"backend_external_managed",frontend:$frontend,backend:"iptables",severity:"warning"},
           {code:"backend_external_managed",frontend:$frontend,backend:"ip6tables",severity:"warning"}]
    ' <<< "${diagnostics}") || return 1
  fi

  candidate_count=$(jq -r 'length' <<< "${candidates}") || return 1
  index=0
  while [[ ${index} -lt ${candidate_count} ]]; do
    candidate_json=$(jq -c ".[$index]" <<< "${candidates}") || return 1
    rule_family=$(jq -r '.family' <<< "${candidate_json}") || return 1
    rule_address=$(jq -r '.address' <<< "${candidate_json}") || return 1
    rule_transport=$(jq -r '.transport' <<< "${candidate_json}") || return 1
    rule_port=$(jq -r '.port' <<< "${candidate_json}") || return 1
    for backend in ufw firewalld iptables ip6tables; do
      if [[ "${backend}" == ufw || "${backend}" == firewalld ]]; then
        [[ "${rule_family}" == ipv4 || "${rule_family}" == ipv6 || "${rule_family}" == any ]] || continue
        if [[ "${backend}" == firewalld ]]; then
          local_rule_family=any
          local_rule_address='*'
        else
          local_rule_family=${rule_family}
          local_rule_address=${rule_address}
        fi
      elif [[ "${backend}" == iptables && "${rule_family}" == ipv4 ]]; then
        local_rule_family=ipv4; local_rule_address=${rule_address}
      elif [[ "${backend}" == ip6tables && "${rule_family}" == ipv6 ]]; then
        local_rule_family=ipv6; local_rule_address=${rule_address}
      else
        continue
      fi
      processed_key="${backend}|${local_rule_family}|${local_rule_address}|${rule_transport}|${rule_port}"
      if [[ "${backend}" == ufw || "${backend}" == firewalld ]]; then
        already_processed=0
        for existing_key in ${processed_keys[@]+"${processed_keys[@]}"}; do
          [[ "${existing_key}" == "${processed_key}" ]] && already_processed=1
        done
        [[ ${already_processed} -eq 0 ]] || continue
        processed_keys+=("${processed_key}")
      fi
      state=$(jq -r --arg backend "${backend}" '.[] | select(.backend == $backend) | .state' <<< "${backend_statuses}") || return 1
      refs_before=$(instance_firewall_refs_for_rule "${old_targets}" "${backend}" "${local_rule_family}" "${local_rule_address}" "${rule_transport}" "${rule_port}") || return 1
      refs_after=$(instance_firewall_refs_for_rule "${new_targets}" "${backend}" "${local_rule_family}" "${local_rule_address}" "${rule_transport}" "${rule_port}") || return 1
      ledger_rule=$(jq -c --arg backend "${backend}" --arg family "${local_rule_family}" --arg address "${local_rule_address}" \
        --arg transport "${rule_transport}" --argjson port "${rule_port}" \
        '[.rules[] | select(.backend == $backend and .family == $family and .address == $address and .transport == $transport and .port == $port)] | if length == 1 then .[0] else null end' <<< "${before_ledger}") || return 1
      comment=$(instance_firewall_rule_comment "${backend}" "${local_rule_family}" "${rule_transport}" "${rule_port}" "${local_rule_address}") || return 1
      action=preserve; ownership=preexisting
      if [[ "${state}" != available ]]; then
        if [[ "${ledger_rule}" != null ]]; then
          instance_firewall_prepare_failure "${journal_file}" owned_backend_unavailable || :; return 1
        fi
        [[ "${refs_after}" == '[]' ]] && continue
        action=unavailable; ownership=unowned
      else
        if [[ "${ledger_rule}" != null ]]; then
          if [[ "${backend}" == firewalld ]]; then
            instance_firewall_prepare_failure "${journal_file}" firewalld_owned_unsupported || :; return 1
          fi
          query_status=0
          instance_firewall_rule_query "${backend}" "${local_rule_family}" "${rule_transport}" "${rule_port}" "${local_rule_address}" "${comment}" 1 || query_status=$?
          if [[ ${query_status} -eq 1 ]]; then
            # The durable ledger can outlive kernel rules after a reboot or
            # external flush. An absent rule is no longer owned live state:
            # drop obsolete entries or plan a normal create for remaining
            # listeners. Never delete an unmarked replacement or recreate a
            # removed listener merely to satisfy the old ledger.
            diagnostics=$(jq -c --arg backend "${backend}" \
              '. + [{code:"owned_rule_missing",backend:$backend,severity:"warning"}]' <<< "${diagnostics}") || return 1
            ledger_rule=null
          elif [[ ${query_status} -ne 0 ]]; then
            instance_firewall_prepare_failure "${journal_file}" owned_rule_inspection_failed || :; return 1
          fi
        fi
        if [[ "${ledger_rule}" != null ]]; then
          ownership=owned
          [[ "${refs_after}" == '[]' ]] && action=delete
        elif [[ "${refs_after}" != '[]' ]]; then
          query_status=0
          instance_firewall_rule_query "${backend}" "${local_rule_family}" "${rule_transport}" "${rule_port}" "${local_rule_address}" "${comment}" || query_status=$?
          case ${query_status} in
            0) action=preserve; ownership=preexisting ;;
            1)
              if [[ "${backend}" == firewalld ]]; then
                instance_firewall_prepare_failure "${journal_file}" firewalld_requires_manual_setup || :; return 1
              fi
              action=create; ownership=owned
              ;;
            *) instance_firewall_prepare_failure "${journal_file}" rule_inspection_failed || :; return 1 ;;
          esac
        else
          continue
        fi
      fi
      if [[ "${action}" == preserve && "${ownership}" == preexisting && "${refs_after}" == '[]' ]]; then
        continue
      fi
      if [[ "${ownership}" == owned && "${refs_after}" != '[]' ]]; then
        after_rules=$(jq -c --arg backend "${backend}" --arg family "${local_rule_family}" --arg address "${local_rule_address}" \
          --arg transport "${rule_transport}" --argjson port "${rule_port}" --arg comment "${comment}" --argjson refs "${refs_after}" \
          '. + [{backend:$backend,family:$family,address:$address,transport:$transport,port:$port,comment:$comment,refs:$refs}]' <<< "${after_rules}") || return 1
      fi
      operations=$(jq -c --arg id "op-${index}-${backend}" --arg backend "${backend}" --arg family "${local_rule_family}" \
        --arg address "${local_rule_address}" --arg transport "${rule_transport}" --argjson port "${rule_port}" \
        --arg comment "${comment}" --arg action "${action}" --arg ownership "${ownership}" --argjson before "${refs_before}" --argjson after "${refs_after}" \
        '. + [{id:$id,backend:$backend,family:$family,address:$address,transport:$transport,port:$port,comment:$comment,action:$action,ownership:$ownership,refs_before:$before,refs_after:$after,state:"planned",rollback_state:"none"}]' <<< "${operations}") || return 1
    done
    index=$((index + 1))
  done
  # UFW reloads its generated iptables chains when a rule is changed.  Apply
  # UFW operations before direct iptables operations so UFW cannot flush rules
  # that this transaction has just created; rollback traverses this order in
  # reverse and remains equally safe.
  operations=$(jq -c 'sort_by((if .backend == "ufw" then 0 elif .backend == "firewalld" then 1 elif .backend == "iptables" then 2 else 3 end), .id)' <<< "${operations}") || return 1
  after_rules=$(jq -c 'unique_by([.backend,.family,.address,.transport,.port])' <<< "${after_rules}") || return 1
  journal_payload=$(jq -cn --argjson version "${INSTANCE_FIREWALL_SCHEMA_VERSION}" --argjson before_exists "${before_ledger_exists}" \
    --argjson before "${before_ledger}" \
    --argjson rules "${after_rules}" --argjson operations "${operations}" --argjson backends "${backend_statuses}" --argjson diagnostics "${diagnostics}" \
    '{schema_version:$version,status:"prepared",before_ledger_exists:$before_exists,before_ledger:$before,after_ledger:{schema_version:$version,rules:$rules},operations:$operations,backend_statuses:$backends,diagnostics:$diagnostics}') || return 1
  instance_firewall_journal_write "${journal_file}" "${journal_payload}"
}

instance_firewall_apply() {
  local journal_file=${1:-} journal status index count operation action backend family address transport port comment op_state
  local verify_status
  local mutation_status=0
  instance_firewall_journal_path_valid "${journal_file}" || return 1
  journal=$(instance_firewall_journal_validate "${journal_file}") || return 1
  status=$(jq -r '.status' <<< "${journal}") || return 1
  [[ "${status}" == prepared || "${status}" == applying || "${status}" == applied ||
     "${status}" == apply_failed || "${status}" == committed ]] || return 1
  [[ "${status}" == committed ]] && return 0
  instance_firewall_journal_update "${journal_file}" '.status="applying"' || return 1
  count=$(jq -r '.operations | length' <<< "${journal}") || return 1
  index=0
  while [[ ${index} -lt ${count} ]]; do
    operation=$(jq -c ".operations[$index]" "${journal_file}") || return 1
    op_state=$(jq -r '.state' <<< "${operation}") || return 1
    [[ "${op_state}" == applied || "${op_state}" == unavailable || "${op_state}" == preserved ]] && { index=$((index + 1)); continue; }
    [[ "${op_state}" == planned ]] || return 1
    action=$(jq -r '.action' <<< "${operation}") || return 1
    if [[ "${action}" == unavailable || "${action}" == preserve ]]; then
      instance_firewall_journal_update "${journal_file}" ".operations[$index].state=\"preserved\"" || return 1
      index=$((index + 1)); continue
    fi
    backend=$(jq -r '.backend' <<< "${operation}") || return 1
    family=$(jq -r '.family' <<< "${operation}") || return 1
    address=$(jq -r '.address' <<< "${operation}") || return 1
    transport=$(jq -r '.transport' <<< "${operation}") || return 1
    port=$(jq -r '.port' <<< "${operation}") || return 1
    comment=$(jq -r '.comment' <<< "${operation}") || return 1
    instance_firewall_journal_update "${journal_file}" ".operations[$index].state=\"intent\"" || return 1
    if instance_firewall_rule_command "${action}" "${backend}" "${family}" "${transport}" "${port}" "${address}" "${comment}"; then
      verify_status=0
      instance_firewall_rule_query "${backend}" "${family}" "${transport}" "${port}" "${address}" "${comment}" 1 || verify_status=$?
      if [[ ("${action}" == create && ${verify_status} -eq 0) ||
            ("${action}" == delete && ${verify_status} -eq 1) ]]; then
        instance_firewall_journal_update "${journal_file}" ".operations[$index].state=\"applied\"" || return 1
      else
        instance_firewall_journal_update "${journal_file}" ".status=\"apply_failed\" | .error_code=\"backend_mutation_unconfirmed\"" || return 1
        return 1
      fi
    else
      mutation_status=$?
      instance_firewall_journal_update "${journal_file}" ".status=\"apply_failed\" | .error_code=\"backend_mutation_failed\"" || return "${mutation_status}"
      return "${mutation_status}"
    fi
    index=$((index + 1))
  done
  if ! mkdir -p "${SB_PROJECT_DIR}" ||
     ! instance_firewall_write_json_atomic "${INSTANCE_FIREWALL_LEDGER_FILE}" "$(jq -c '.after_ledger' "${journal_file}")"; then
    instance_firewall_journal_update "${journal_file}" '.status="apply_failed" | .error_code="ledger_persist_failed"' || return 1
    return 1
  fi
  instance_firewall_journal_update "${journal_file}" '.status="applied"' || return 1
}

instance_firewall_restore_ledger() {
  local journal_file=$1 before_exists before_ledger
  before_exists=false
  if jq -e '.before_ledger_exists == true' "${journal_file}" >/dev/null 2>&1; then
    before_exists=true
  fi
  before_ledger=$(jq -c '.before_ledger' "${journal_file}") || return 1
  if [[ "${before_exists}" == true ]]; then
    instance_firewall_write_json_atomic "${INSTANCE_FIREWALL_LEDGER_FILE}" "${before_ledger}"
  else
    [[ ! -L "${INSTANCE_FIREWALL_LEDGER_FILE}" ]] || return 1
    if [[ -e "${INSTANCE_FIREWALL_LEDGER_FILE}" ]]; then
      rm -f -- "${INSTANCE_FIREWALL_LEDGER_FILE}" || return $?
    fi
  fi
}

instance_firewall_rollback() {
  local journal_file=${1:-} journal status count index operation action backend family address transport port comment op_state rollback_action
  local query_status mutation_status result_status=0
  instance_firewall_journal_path_valid "${journal_file}" || return 1
  journal=$(instance_firewall_journal_validate "${journal_file}") || return 1
  status=$(jq -r '.status' <<< "${journal}") || return 1
  [[ "${status}" == prepared || "${status}" == applying || "${status}" == applied ||
     "${status}" == committed || "${status}" == apply_failed || "${status}" == rolling_back ||
     "${status}" == rollback_failed || "${status}" == rollback_uncertain ||
     "${status}" == rolled_back ]] || return 1
  instance_firewall_journal_update "${journal_file}" '.status="rolling_back"' || return 1
  count=$(jq -r '.operations | length' <<< "${journal}") || return 1
  index=$((count - 1))
  while [[ ${index} -ge 0 ]]; do
    operation=$(jq -c ".operations[$index]" "${journal_file}") || return 1
    action=$(jq -r '.action' <<< "${operation}") || return 1
    op_state=$(jq -r '.state' <<< "${operation}") || return 1
    [[ "${action}" == create || "${action}" == delete ]] || { index=$((index - 1)); continue; }
    [[ "${op_state}" == applied || "${op_state}" == intent ]] || { index=$((index - 1)); continue; }
    backend=$(jq -r '.backend' <<< "${operation}") || return 1
    family=$(jq -r '.family' <<< "${operation}") || return 1
    address=$(jq -r '.address' <<< "${operation}") || return 1
    transport=$(jq -r '.transport' <<< "${operation}") || return 1
    port=$(jq -r '.port' <<< "${operation}") || return 1
    comment=$(jq -r '.comment' <<< "${operation}") || return 1
    query_status=0
    instance_firewall_rule_query "${backend}" "${family}" "${transport}" "${port}" "${address}" "${comment}" 1 || query_status=$?
    if [[ "${op_state}" == intent ]]; then
      if [[ ("${action}" == create && ${query_status} -eq 0) || ("${action}" == delete && ${query_status} -eq 1) ]]; then
        instance_firewall_journal_update "${journal_file}" ".operations[$index].rollback_state=\"uncertain\"" || return 1
        result_status=1
      fi
      if [[ ${query_status} -ne 0 && ${query_status} -ne 1 ]]; then
        instance_firewall_journal_update "${journal_file}" ".operations[$index].rollback_state=\"uncertain\"" || return 1
        result_status=1
      fi
      index=$((index - 1)); continue
    fi
    if [[ ${query_status} -eq 0 && "${action}" == create ]]; then
      rollback_action=delete
    elif [[ ${query_status} -eq 1 && "${action}" == delete ]]; then
      rollback_action=create
    elif [[ ${query_status} -eq 0 && "${action}" == delete || ${query_status} -eq 1 && "${action}" == create ]]; then
      instance_firewall_journal_update "${journal_file}" ".operations[$index].rollback_state=\"already_compensated\"" || return 1
      index=$((index - 1)); continue
    else
      instance_firewall_journal_update "${journal_file}" ".operations[$index].rollback_state=\"uncertain\"" || return 1
      result_status=1; index=$((index - 1)); continue
    fi
    instance_firewall_journal_update "${journal_file}" ".operations[$index].rollback_state=\"intent\"" || return 1
    if instance_firewall_rule_command "${rollback_action}" "${backend}" "${family}" "${transport}" "${port}" "${address}" "${comment}"; then
      query_status=0
      instance_firewall_rule_query "${backend}" "${family}" "${transport}" "${port}" "${address}" "${comment}" 1 || query_status=$?
      if [[ ("${rollback_action}" == delete && ${query_status} -eq 1) ||
            ("${rollback_action}" == create && ${query_status} -eq 0) ]]; then
        instance_firewall_journal_update "${journal_file}" ".operations[$index].rollback_state=\"applied\"" || return 1
      else
        instance_firewall_journal_update "${journal_file}" ".operations[$index].rollback_state=\"uncertain\"" || return 1
        result_status=1
      fi
    else
      mutation_status=$?
      instance_firewall_journal_update "${journal_file}" '.status="rollback_failed" | .error_code="compensation_failed"' || return 1
      result_status=${mutation_status:-1}
    fi
    index=$((index - 1))
  done
  if ! instance_firewall_restore_ledger "${journal_file}"; then
    instance_firewall_journal_update "${journal_file}" '.status="rollback_failed" | .error_code="ledger_restore_failed"' || return 1
    return 1
  fi
  if [[ ${result_status} -eq 0 ]]; then
    instance_firewall_journal_update "${journal_file}" '.status="rolled_back"' || return 1
  else
    instance_firewall_journal_update "${journal_file}" '.status="rollback_uncertain" | .error_code="external_state_uncertain"' || return 1
  fi
  return "${result_status}"
}

instance_firewall_commit() {
  local journal_file=${1:-} status
  instance_firewall_journal_path_valid "${journal_file}" || return 1
  instance_firewall_journal_validate "${journal_file}" >/dev/null || return 1
  status=$(jq -r '.status' "${journal_file}") || return 1
  [[ "${status}" == applied || "${status}" == committed ]] || return 1
  [[ "${status}" == committed ]] || instance_firewall_journal_update "${journal_file}" '.status="committed"'
}


# Verify configuration file
check_config_valid() {
  log_info "正在校验配置文件有效性..."
  if ! validate_config_file; then
    log_error "配置文件校验失败，请检查配置细节。"
  fi
  log_success "配置文件校验成功。"
}

validate_config_file() {
  "${SINGBOX_BIN_PATH}" check -c "${SINGBOX_CONFIG_FILE}"
}

# Check for port conflict
check_port_conflict() {
  local port=$1
  if port_is_in_use "${port}"; then
    local process
    process=$(ss -tunlp | grep ":${port} " | awk '{print $7}' | cut -d'"' -f2 | head -n1)
    log_warn "端口 ${port} 已被进程 [${process}] 占用。"
    echo "1. 保留占用进程并改用随机端口"
    echo "2. 使用随机端口"
    echo "3. 手动输入新端口"
    port_choice=$(prompt_choice "请选择操作 [1-3]: " 1 3 "")

    case "${port_choice}" in
      1|2)
        SB_PORT="$(pick_random_high_port)"
        log_success "已保留占用进程，并自动切换到随机端口: ${SB_PORT}"
        ;;
      3)
        SB_PORT=$(prompt_port "请输入新端口: " "")
        check_port_conflict "${SB_PORT}"
        ;;
    esac
  fi
}

get_os_info() {
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    OS_NAME=$ID
    OS_VERSION=$VERSION_ID
  elif [[ -f /etc/redhat-release ]]; then
    OS_NAME="centos"
    OS_VERSION=$(grep -oE '[0-9]+' /etc/redhat-release | head -n1)
  else
    log_error "不支持的操作系统。"
  fi
}

get_arch() {
  local arch_raw
  arch_raw=$(uname -m)
  case "${arch_raw}" in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) log_error "不支持的架构: ${arch_raw}" ;;
  esac
}
