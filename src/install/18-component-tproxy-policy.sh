
managed_component_tproxy_host_policy_plan_for_record() {
  local record=${1:-} component_id interface_name listen_port destination_ports management_ports networks
  local digest policy_id chain marker mark route_table rule_priority
  managed_component_tproxy_host_policy_validate_record "${record}" || return 1
  jq -e 'has("host_policy")' <<< "${record}" >/dev/null 2>&1 || return 2
  component_id=$(jq -r '.id' <<< "${record}") || return 1
  interface_name=$(jq -r '.host_policy.ingress_interface' <<< "${record}") || return 1
  listen_port=$(jq -r '.config.listen_port' <<< "${record}") || return 1
  destination_ports=$(jq -r '.host_policy.destination_ports | sort | map(tostring) | join(",")' <<< "${record}") || return 1
  management_ports=$(jq -r '.host_policy.management_ports | sort | map(tostring) | join(",")' <<< "${record}") || return 1
  networks=$(jq -r '.config.network | sort | join(",")' <<< "${record}") || return 1
  digest=$(printf '%s\0' "${component_id}" "${interface_name}" "${destination_ports}" \
    "${management_ports}" "${listen_port}" "${networks}" | sha256sum | awk '{print $1}') || return 1
  [[ "${digest}" =~ ^[[:xdigit:]]{64}$ ]] || return 1
  policy_id=${digest:0:20}
  chain="${MANAGED_TPROXY_POLICY_CHAIN_PREFIX}${policy_id}"
  marker="${MANAGED_TPROXY_POLICY_COMMENT_PREFIX}${policy_id}"
  mark="0x5b${digest:20:6}"
  route_table=$((10000 + (16#${digest:6:8} % 2000000000)))
  # Keep the fwmark lookup ahead of Linux's default `main` rule (32766).
  # A hash-selected priority avoids owning a single global preference while
  # retaining a deterministic plan; collisions with existing rules fail closed.
  rule_priority=$((10000 + (16#${digest:14:8} % 20000)))
  jq -cn --arg id "${component_id}" --arg tag "$(jq -r '.tag' <<< "${record}")" \
    --arg interface "${interface_name}" --arg chain "${chain}" --arg marker "${marker}" \
    --arg mark "${mark}" --argjson route_table "${route_table}" \
    --argjson rule_priority "${rule_priority}" --argjson listen_port "${listen_port}" \
    --argjson destination_ports "$(jq -c '.host_policy.destination_ports | sort' <<< "${record}")" \
    --argjson management_ports "$(jq -c '.host_policy.management_ports | sort' <<< "${record}")" \
    --argjson networks "$(jq -c '.config.network | sort' <<< "${record}")" \
    '{id:$id,tag:$tag,chain:$chain,marker:$marker,interface:$interface,
      destination_ports:$destination_ports,management_ports:$management_ports,
      listen_port:$listen_port,networks:$networks,family:"ipv4",mark:$mark,
      mark_mask:"0xffffffff",route_table:$route_table,rule_priority:$rule_priority}'
}

managed_component_tproxy_host_policy_plan_json() {
  local state=${1:-} record plan
  local plans=()
  managed_component_state_validate_json "${state}" || return 1
  while IFS= read -r record; do
    [[ -n "${record}" ]] || continue
    jq -e '.type == "tproxy" and has("host_policy") and .enabled == true' \
      <<< "${record}" >/dev/null 2>&1 || continue
    plan=$(managed_component_tproxy_host_policy_plan_for_record "${record}") || return 1
    plans+=("${plan}")
  done < <(jq -c '.components[]' <<< "${state}")
  if ((${#plans[@]} == 0)); then
    printf '[]\n'
  else
    printf '%s\n' "${plans[@]}" | jq -sc 'sort_by(.id)'
  fi
}

managed_component_tproxy_host_policy_plan_validate_json() {
  local plans=${1:-} plan digest component_id interface_name destination_ports management_ports
  local listen_port networks policy_id expected_chain expected_marker expected_mark expected_table expected_priority
  [[ -n "${plans}" ]] || return 1
  jq -s -e '
    length == 1 and
    (.[0] | type == "array" and length <= 128 and
      all(.[]; . as $plan |
        ($plan | type == "object" and
          ((keys - ["id","tag","chain","marker","interface","destination_ports","management_ports",
            "listen_port","networks","family","mark","mark_mask","route_table","rule_priority"]) | length == 0) and
          (.id | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")) and
          (.tag | type == "string" and length > 0 and length <= 128) and
          (.chain | type == "string" and test("^SBVT_[a-f0-9]{20}$")) and
          (.marker | type == "string" and test("^sbv-tproxy-[a-f0-9]{20}$")) and
          (.interface | type == "string" and length >= 1 and length <= 15 and test("^[A-Za-z0-9_.:-]+$")) and
          (.destination_ports | type == "array" and length >= 1 and length <= 15 and
            all(.[]; type == "number" and . == floor and . >= 1 and . <= 65535) and
            (unique | length) == length) and
          (.management_ports | type == "array" and length >= 1 and length <= 15 and
            all(.[]; type == "number" and . == floor and . >= 1 and . <= 65535) and
            (unique | length) == length) and
          (.listen_port | type == "number" and . == floor and . >= 1 and . <= 65535) and
          (.networks | type == "array" and length >= 1 and length <= 2 and
            all(.[]; type == "string" and IN("tcp","udp")) and (unique | length) == length) and
          .family == "ipv4" and .mark_mask == "0xffffffff" and
          (.mark | type == "string" and test("^0x5b[0-9a-f]{6}$")) and
          (.route_table | type == "number" and . == floor and . >= 10000 and . <= 2000010000) and
          (.rule_priority | type == "number" and . == floor and . >= 10000 and . < 30000)) and
        all($plan.destination_ports[]; . as $port | ($plan.management_ports | index($port)) == null) and
        ($plan.destination_ports | index($plan.listen_port)) == null
      ) and
      ([.[].chain] | unique | length) == length and
      ([.[].marker] | unique | length) == length and
      ([.[].mark] | unique | length) == length and
      ([.[].route_table] | unique | length) == length and
      ([.[].rule_priority] | unique | length) == length and
      ([.[].id] | unique | length) == length)
  ' <<< "${plans}" >/dev/null 2>&1 || return 1

  while IFS= read -r plan; do
    [[ -n "${plan}" ]] || continue
    component_id=$(jq -r '.id' <<< "${plan}") || return 1
    interface_name=$(jq -r '.interface' <<< "${plan}") || return 1
    destination_ports=$(jq -r '.destination_ports | sort | map(tostring) | join(",")' <<< "${plan}") || return 1
    management_ports=$(jq -r '.management_ports | sort | map(tostring) | join(",")' <<< "${plan}") || return 1
    listen_port=$(jq -r '.listen_port' <<< "${plan}") || return 1
    networks=$(jq -r '.networks | sort | join(",")' <<< "${plan}") || return 1
    digest=$(printf '%s\0' "${component_id}" "${interface_name}" "${destination_ports}" \
      "${management_ports}" "${listen_port}" "${networks}" | sha256sum | awk '{print $1}') || return 1
    [[ "${digest}" =~ ^[[:xdigit:]]{64}$ ]] || return 1
    policy_id=${digest:0:20}
    expected_chain="${MANAGED_TPROXY_POLICY_CHAIN_PREFIX}${policy_id}"
    expected_marker="${MANAGED_TPROXY_POLICY_COMMENT_PREFIX}${policy_id}"
    expected_mark="0x5b${digest:20:6}"
    expected_table=$((10000 + (16#${digest:6:8} % 2000000000)))
    expected_priority=$((10000 + (16#${digest:14:8} % 20000)))
    [[ "$(jq -r '.chain' <<< "${plan}")" == "${expected_chain}" &&
       "$(jq -r '.marker' <<< "${plan}")" == "${expected_marker}" &&
       "$(jq -r '.mark' <<< "${plan}")" == "${expected_mark}" &&
       "$(jq -r '.route_table' <<< "${plan}")" == "${expected_table}" &&
       "$(jq -r '.rule_priority' <<< "${plan}")" == "${expected_priority}" ]] || return 1
  done < <(jq -c '.[]' <<< "${plans}")
}

managed_component_tproxy_policy_plan_has_chain() {
  local plans=${1:-} chain=${2:-}
  jq -e --arg chain "${chain}" 'any(.[]; .chain == $chain)' <<< "${plans}" >/dev/null 2>&1
}

managed_component_tproxy_policy_route_rule_status() {
  local plan=${1:-} rules priority mark mask table status
  managed_component_tproxy_host_policy_plan_validate_json "[${plan}]" || { printf 'conflict\n'; return 0; }
  command -v ip >/dev/null 2>&1 || { printf 'unavailable\n'; return 0; }
  rules=$(ip -4 rule show) || { printf 'unavailable\n'; return 0; }
  priority=$(jq -r '.rule_priority' <<< "${plan}") || return 1
  mark=$(jq -r '.mark' <<< "${plan}") || return 1
  mask=$(jq -r '.mark_mask' <<< "${plan}") || return 1
  table=$(jq -r '.route_table' <<< "${plan}") || return 1
  status=$(awk -v priority="${priority}:" -v mark="${mark}" -v mask="${mask}" -v table="${table}" '
    $1 == priority {
      lines++
      if (NF == 7 && $2 == "from" && $3 == "all" && $4 == "fwmark" &&
          ($5 == mark || $5 == mark "/" mask) &&
          ($6 == "lookup" || $6 == "table") && $7 == table) exact++
    }
    END {
      if (lines == 0) print "absent"
      else if (lines == 1 && exact == 1) print "present"
      else print "conflict"
    }' <<< "${rules}") || return 1
  printf '%s\n' "${status}"
}

managed_component_tproxy_policy_route_status() {
  local plan=${1:-} routes table status
  managed_component_tproxy_host_policy_plan_validate_json "[${plan}]" || { printf 'conflict\n'; return 0; }
  command -v ip >/dev/null 2>&1 || { printf 'unavailable\n'; return 0; }
  table=$(jq -r '.route_table' <<< "${plan}") || return 1
  # Querying a route table by ID fails on iproute2 when that table does not
  # exist yet. Enumerating all IPv4 routes lets an empty owned table be
  # distinguished from an unavailable route query without parsing stderr.
  routes=$(ip -4 route show table all) || { printf 'unavailable\n'; return 0; }
  status=$(awk -v table="${table}" '
    NF > 0 {
      route_table=""
      for (i=1; i<NF; i++) {
        if ($i == "table") {
          route_table=$(i+1)
          break
        }
      }
      if (route_table != table) next
      lines++
      if ($1 == "local" && ($2 == "default" || $2 == "0.0.0.0/0") &&
          $3 == "dev" && $4 == "lo") exact++
    }
    END {
      if (lines == 0) print "absent"
      else if (lines == 1 && exact == 1) print "present"
      else print "conflict"
    }' <<< "${routes}") || return 1
  printf '%s\n' "${status}"
}

managed_component_tproxy_policy_probe() {
  local plan=${1:-} rules chain_output chain marker interface_name destination_ports listen_port
  local mark mask table priority network chain_count marker_count reference_count rule_count exact_count
  local route_rule_status route_status mangle_status=absent status jump_status=1 check_status
  managed_component_tproxy_host_policy_plan_validate_json "[${plan}]" || { printf 'conflict\n'; return 0; }
  command -v iptables >/dev/null 2>&1 && command -v ip >/dev/null 2>&1 || { printf 'unavailable\n'; return 0; }
  rules=$(iptables -t mangle -S) || { printf 'unavailable\n'; return 0; }
  chain=$(jq -r '.chain' <<< "${plan}") || return 1
  marker=$(jq -r '.marker' <<< "${plan}") || return 1
  interface_name=$(jq -r '.interface' <<< "${plan}") || return 1
  destination_ports=$(jq -r '.destination_ports | sort | map(tostring) | join(",")' <<< "${plan}") || return 1
  listen_port=$(jq -r '.listen_port' <<< "${plan}") || return 1
  mark=$(jq -r '.mark' <<< "${plan}") || return 1
  mask=$(jq -r '.mark_mask' <<< "${plan}") || return 1
  table=$(jq -r '.route_table' <<< "${plan}") || return 1
  priority=$(jq -r '.rule_priority' <<< "${plan}") || return 1
  chain_count=$(awk -v chain="${chain}" '$1 == "-N" && $2 == chain { count++ } END { print count+0 }' <<< "${rules}") || return 1
  marker_count=$(awk -v marker="${marker}" 'index($0, marker) { count++ } END { print count+0 }' <<< "${rules}") || return 1
  reference_count=$(awk -v chain="${chain}" '$1 == "-A" && $2 != chain && $NF == chain { count++ } END { print count+0 }' <<< "${rules}") || return 1
  if [[ "${chain_count}" == 1 ]]; then
    chain_output=$(iptables -t mangle -S "${chain}") || { printf 'unavailable\n'; return 0; }
    rule_count=$(awk '$1 == "-A" { count++ } END { print count+0 }' <<< "${chain_output}") || return 1
    exact_count=0
    while IFS= read -r network; do
      [[ -n "${network}" ]] || continue
      if iptables -t mangle -C "${chain}" -i "${interface_name}" -p "${network}" \
        -m multiport --dports "${destination_ports}" -j TPROXY --on-ip 0.0.0.0 \
        --on-port "${listen_port}" --tproxy-mark "${mark}/${mask}" >/dev/null 2>&1; then
        exact_count=$((exact_count + 1))
      else
        check_status=$?
        [[ "${check_status}" == 1 ]] || { printf 'unavailable\n'; return 0; }
      fi
    done < <(jq -r '.networks[]' <<< "${plan}")
    if (( exact_count == $(jq -r '.networks | length' <<< "${plan}") )) &&
       [[ "${rule_count}" == "$(jq -r '.networks | length' <<< "${plan}")" ]]; then
      mangle_status=present
    elif (( exact_count == rule_count )) && (( rule_count <= $(jq -r '.networks | length' <<< "${plan}") )); then
      mangle_status=partial
    else
      mangle_status=conflict
    fi
  elif [[ "${chain_count}" == 0 && "${marker_count}" == 0 && "${reference_count}" == 0 ]]; then
    mangle_status=absent
  else
    mangle_status=conflict
  fi
  if [[ "${chain_count}" == 1 ]]; then
    if iptables -t mangle -C PREROUTING -m comment --comment "${marker}" -j "${chain}" >/dev/null 2>&1; then
      jump_status=0
    else
      check_status=$?
      [[ "${check_status}" == 1 ]] || { printf 'unavailable\n'; return 0; }
    fi
  elif [[ "${marker_count}" != 0 || "${reference_count}" != 0 ]]; then
    mangle_status=conflict
  fi
  if [[ "${mangle_status}" == present && "${marker_count}" == 1 &&
        "${reference_count}" == 1 && "${jump_status}" == 0 ]]; then
    mangle_status=present
  elif [[ "${mangle_status}" == absent && "${marker_count}" == 0 &&
          "${reference_count}" == 0 && "${jump_status}" == 1 ]]; then
    mangle_status=absent
  elif [[ "${mangle_status}" != conflict &&
          "${marker_count}" -le 1 && "${reference_count}" -le 1 ]]; then
    mangle_status=partial
  else
    mangle_status=conflict
  fi
  route_rule_status=$(managed_component_tproxy_policy_route_rule_status "${plan}") || return 1
  route_status=$(managed_component_tproxy_policy_route_status "${plan}") || return 1
  if [[ "${mangle_status}" == conflict || "${route_rule_status}" == conflict ||
        "${route_status}" == conflict ]]; then
    status=conflict
  elif [[ "${mangle_status}" == unavailable || "${route_rule_status}" == unavailable ||
          "${route_status}" == unavailable ]]; then
    status=unavailable
  elif [[ "${mangle_status}" == absent && "${route_rule_status}" == absent &&
          "${route_status}" == absent ]]; then
    status=absent
  elif [[ "${mangle_status}" == present && "${route_rule_status}" == present &&
          "${route_status}" == present ]]; then
    status=present
  else
    status=partial
  fi
  printf '%s\n' "${status}"
}

managed_component_tproxy_policy_ensure_plan() {
  local plan=${1:-} allow_partial=${2:-false} status chain marker interface_name destination_ports
  local listen_port mark mask table priority network route_rule_status route_status rule_status
  managed_component_tproxy_host_policy_plan_validate_json "[${plan}]" || return 1
  status=$(managed_component_tproxy_policy_probe "${plan}") || return 1
  [[ "${status}" == present ]] && return 0
  [[ "${status}" == absent || ( "${status}" == partial && "${allow_partial}" == true ) ]] || return 1
  chain=$(jq -r '.chain' <<< "${plan}") || return 1
  marker=$(jq -r '.marker' <<< "${plan}") || return 1
  interface_name=$(jq -r '.interface' <<< "${plan}") || return 1
  destination_ports=$(jq -r '.destination_ports | sort | map(tostring) | join(",")' <<< "${plan}") || return 1
  listen_port=$(jq -r '.listen_port' <<< "${plan}") || return 1
  mark=$(jq -r '.mark' <<< "${plan}") || return 1
  mask=$(jq -r '.mark_mask' <<< "${plan}") || return 1
  table=$(jq -r '.route_table' <<< "${plan}") || return 1
  priority=$(jq -r '.rule_priority' <<< "${plan}") || return 1
  route_rule_status=$(managed_component_tproxy_policy_route_rule_status "${plan}") || return 1
  route_status=$(managed_component_tproxy_policy_route_status "${plan}") || return 1
  case "${route_rule_status}:${route_status}" in
    absent:absent)
      ip -4 route add local 0.0.0.0/0 dev lo table "${table}" || return 1
      ip -4 rule add priority "${priority}" fwmark "${mark}/${mask}" table "${table}" || return 1 ;;
    present:present) ;;
    absent:present)
      ip -4 rule add priority "${priority}" fwmark "${mark}/${mask}" table "${table}" || return 1 ;;
    present:absent)
      ip -4 route add local 0.0.0.0/0 dev lo table "${table}" || return 1 ;;
    *) return 1 ;;
  esac
  status=$(managed_component_tproxy_policy_probe "${plan}") || return 1
  [[ "${status}" == partial ]] || return 1
  local rules chain_count marker_count reference_count
  rules=$(iptables -t mangle -S) || return 1
  chain_count=$(awk -v chain="${chain}" '$1 == "-N" && $2 == chain { count++ } END { print count+0 }' <<< "${rules}") || return 1
  marker_count=$(awk -v marker="${marker}" 'index($0, marker) { count++ } END { print count+0 }' <<< "${rules}") || return 1
  reference_count=$(awk -v chain="${chain}" '$1 == "-A" && $2 != chain && $NF == chain { count++ } END { print count+0 }' <<< "${rules}") || return 1
  [[ "${chain_count}" == 1 || "${chain_count}" == 0 ]] || return 1
  if [[ "${chain_count}" == 0 ]]; then iptables -t mangle -N "${chain}" || return 1; fi
  while IFS= read -r network; do
    [[ -n "${network}" ]] || continue
    if ! iptables -t mangle -C "${chain}" -i "${interface_name}" -p "${network}" \
      -m multiport --dports "${destination_ports}" -j TPROXY --on-ip 0.0.0.0 \
      --on-port "${listen_port}" --tproxy-mark "${mark}/${mask}" >/dev/null 2>&1; then
      iptables -t mangle -A "${chain}" -i "${interface_name}" -p "${network}" \
        -m multiport --dports "${destination_ports}" -j TPROXY --on-ip 0.0.0.0 \
        --on-port "${listen_port}" --tproxy-mark "${mark}/${mask}" || return 1
    fi
  done < <(jq -r '.networks[]' <<< "${plan}")
  if [[ "${marker_count}" == 0 && "${reference_count}" == 0 ]]; then
    iptables -t mangle -A PREROUTING -m comment --comment "${marker}" -j "${chain}" || return 1
  elif [[ "${marker_count}" != 1 || "${reference_count}" != 1 ]]; then
    return 1
  fi
  [[ "$(managed_component_tproxy_policy_probe "${plan}")" == present ]]
}

managed_component_tproxy_policy_remove_plan() {
  local plan=${1:-} allow_partial=${2:-false} status chain marker mark mask table priority network
  local route_rule_status route_status rule_status check_status rules chain_count
  managed_component_tproxy_host_policy_plan_validate_json "[${plan}]" || return 1
  status=$(managed_component_tproxy_policy_probe "${plan}") || return 1
  [[ "${status}" == absent ]] && return 0
  [[ "${status}" == present || ( "${status}" == partial && "${allow_partial}" == true ) ]] || return 1
  chain=$(jq -r '.chain' <<< "${plan}") || return 1
  marker=$(jq -r '.marker' <<< "${plan}") || return 1
  mark=$(jq -r '.mark' <<< "${plan}") || return 1
  mask=$(jq -r '.mark_mask' <<< "${plan}") || return 1
  table=$(jq -r '.route_table' <<< "${plan}") || return 1
  priority=$(jq -r '.rule_priority' <<< "${plan}") || return 1
  rules=$(iptables -t mangle -S) || return 1
  chain_count=$(awk -v chain="${chain}" '$1 == "-N" && $2 == chain { count++ } END { print count+0 }' <<< "${rules}") || return 1
  if iptables -t mangle -C PREROUTING -m comment --comment "${marker}" -j "${chain}" >/dev/null 2>&1; then
    iptables -t mangle -D PREROUTING -m comment --comment "${marker}" -j "${chain}" || return 1
  else
    check_status=$?
    [[ "${check_status}" == 1 ]] || return 1
  fi
  if [[ "${chain_count}" == 1 ]]; then
    while IFS= read -r network; do
      [[ -n "${network}" ]] || continue
      if iptables -t mangle -C "${chain}" -i "$(jq -r '.interface' <<< "${plan}")" -p "${network}" \
        -m multiport --dports "$(jq -r '.destination_ports | sort | map(tostring) | join(",")' <<< "${plan}")" \
        -j TPROXY --on-ip 0.0.0.0 --on-port "$(jq -r '.listen_port' <<< "${plan}")" \
        --tproxy-mark "${mark}/${mask}" >/dev/null 2>&1; then
        iptables -t mangle -D "${chain}" -i "$(jq -r '.interface' <<< "${plan}")" -p "${network}" \
          -m multiport --dports "$(jq -r '.destination_ports | sort | map(tostring) | join(",")' <<< "${plan}")" \
          -j TPROXY --on-ip 0.0.0.0 --on-port "$(jq -r '.listen_port' <<< "${plan}")" \
          --tproxy-mark "${mark}/${mask}" || return 1
      else
        check_status=$?
        [[ "${check_status}" == 1 ]] || return 1
      fi
    done < <(jq -r '.networks[]' <<< "${plan}")
    iptables -t mangle -F "${chain}" || return 1
    iptables -t mangle -X "${chain}" || return 1
  fi
  route_rule_status=$(managed_component_tproxy_policy_route_rule_status "${plan}") || return 1
  route_status=$(managed_component_tproxy_policy_route_status "${plan}") || return 1
  if [[ "${route_rule_status}" == present ]]; then
    ip -4 rule del priority "${priority}" fwmark "${mark}/${mask}" table "${table}" || return 1
  elif [[ "${route_rule_status}" != absent ]]; then
    return 1
  fi
  if [[ "${route_status}" == present ]]; then
    ip -4 route del local 0.0.0.0/0 dev lo table "${table}" || return 1
  elif [[ "${route_status}" != absent ]]; then
    return 1
  fi
  [[ "$(managed_component_tproxy_policy_probe "${plan}")" == absent ]]
}

managed_component_tproxy_policy_preflight() {
  local before=${1:-} after=${2:-} plan status interface_name
  managed_component_tproxy_host_policy_plan_validate_json "${before}" || return 1
  managed_component_tproxy_host_policy_plan_validate_json "${after}" || return 1
  if ((${#after} > 2)); then
    command -v iptables >/dev/null 2>&1 && command -v ip >/dev/null 2>&1 || return 1
    iptables -t mangle -S >/dev/null 2>&1 || return 1
    iptables -j TPROXY -h >/dev/null 2>&1 || return 1
    iptables -m multiport -h >/dev/null 2>&1 || return 1
    ip -4 rule show >/dev/null 2>&1 || return 1
  fi
  while IFS= read -r plan; do
    [[ -n "${plan}" ]] || continue
    status=$(managed_component_tproxy_policy_probe "${plan}") || return 1
    [[ "${status}" == present ]] || return 1
  done < <(jq -c '.[]' <<< "${before}")
  while IFS= read -r plan; do
    [[ -n "${plan}" ]] || continue
    if managed_component_tproxy_policy_plan_has_chain "${before}" "$(jq -r '.chain' <<< "${plan}")"; then
      continue
    fi
    status=$(managed_component_tproxy_policy_probe "${plan}") || return 1
    [[ "${status}" == absent ]] || return 1
    interface_name=$(jq -r '.interface' <<< "${plan}") || return 1
    ip link show dev "${interface_name}" >/dev/null 2>&1 || return 1
  done < <(jq -c '.[]' <<< "${after}")
}

managed_component_tproxy_policy_journal_path_valid() {
  local journal_file=${1:-}
  [[ "${journal_file}" == "${SB_COMPONENT_TRANSACTION_DIR}/snapshot/component-tproxy-policy.json" &&
     -d "${SB_COMPONENT_TRANSACTION_DIR}/snapshot" &&
     ! -L "${SB_COMPONENT_TRANSACTION_DIR}" && ! -L "${SB_COMPONENT_TRANSACTION_DIR}/snapshot" ]] || return 1
}

managed_component_tproxy_policy_journal_validate() {
  local journal_file=${1:-} before after
  managed_component_tproxy_policy_journal_path_valid "${journal_file}" || return 1
  [[ -f "${journal_file}" && ! -L "${journal_file}" && -r "${journal_file}" ]] || return 1
  [[ "$(stat -c '%a' "${journal_file}")" == 600 ]] || return 1
  jq -ce 'type == "object" and ((keys - ["schema_version","status","before","after"]) | length == 0) and
    .schema_version == 1 and (.status | IN("prepared","applying","applied","rolling_back","rolled_back")) and
    (.before | type == "array") and (.after | type == "array")' "${journal_file}" >/dev/null 2>&1 || return 1
  before=$(jq -c '.before' "${journal_file}") || return 1
  after=$(jq -c '.after' "${journal_file}") || return 1
  managed_component_tproxy_host_policy_plan_validate_json "${before}" || return 1
  managed_component_tproxy_host_policy_plan_validate_json "${after}"
}

managed_component_tproxy_policy_journal_write() {
  local journal_file=${1:-} before=${2:-} after=${3:-} candidate payload
  managed_component_tproxy_policy_journal_path_valid "${journal_file}" || return 1
  [[ ! -e "${journal_file}" && ! -L "${journal_file}" ]] || return 1
  managed_component_tproxy_host_policy_plan_validate_json "${before}" || return 1
  managed_component_tproxy_host_policy_plan_validate_json "${after}" || return 1
  payload=$(jq -cn --argjson before "${before}" --argjson after "${after}" \
    '{schema_version:1,status:"prepared",before:$before,after:$after}') || return 1
  candidate=$(storage_mktemp "${journal_file%/*}/.component-tproxy-policy.XXXXXX") || return 1
  if ! printf '%s\n' "${payload}" > "${candidate}" || ! chmod 600 "${candidate}" ||
     ! mv -f -- "${candidate}" "${journal_file}"; then
    rm -f -- "${candidate}"
    return 1
  fi
  managed_component_tproxy_policy_journal_validate "${journal_file}"
}

managed_component_tproxy_policy_journal_set_status() {
  local journal_file=${1:-} status=${2:-} candidate
  managed_component_tproxy_policy_journal_validate "${journal_file}" || return 1
  [[ "${status}" =~ ^(prepared|applying|applied|rolling_back|rolled_back)$ ]] || return 1
  candidate=$(storage_mktemp "${journal_file%/*}/.component-tproxy-policy.XXXXXX") || return 1
  if ! jq --arg status "${status}" '.status=$status' "${journal_file}" > "${candidate}" ||
     ! chmod 600 "${candidate}" || ! mv -f -- "${candidate}" "${journal_file}"; then
    rm -f -- "${candidate}"
    return 1
  fi
  managed_component_tproxy_policy_journal_validate "${journal_file}"
}

managed_component_tproxy_policy_apply_journal() {
  local journal_file=${1:-} before after plan
  managed_component_tproxy_policy_journal_validate "${journal_file}" || return 1
  before=$(jq -c '.before' "${journal_file}") || return 1
  after=$(jq -c '.after' "${journal_file}") || return 1
  managed_component_tproxy_policy_journal_set_status "${journal_file}" applying || return 1
  while IFS= read -r plan; do
    [[ -n "${plan}" ]] || continue
    managed_component_tproxy_policy_ensure_plan "${plan}" false || return 1
  done < <(jq -c '.[]' <<< "${after}")
  while IFS= read -r plan; do
    [[ -n "${plan}" ]] || continue
    if ! managed_component_tproxy_policy_plan_has_chain "${after}" "$(jq -r '.chain' <<< "${plan}")"; then
      managed_component_tproxy_policy_remove_plan "${plan}" || return 1
    fi
  done < <(jq -c '.[]' <<< "${before}")
  managed_component_tproxy_policy_journal_set_status "${journal_file}" applied
}

managed_component_tproxy_policy_remove_delta() {
  local journal_file=${1:-} status before after plan
  managed_component_tproxy_policy_journal_validate "${journal_file}" || return 1
  status=$(jq -r '.status' "${journal_file}") || return 1
  [[ "${status}" == prepared || "${status}" == rolled_back ]] && return 0
  managed_component_tproxy_policy_journal_set_status "${journal_file}" rolling_back || return 1
  before=$(jq -c '.before' "${journal_file}") || return 1
  after=$(jq -c '.after' "${journal_file}") || return 1
  while IFS= read -r plan; do
    [[ -n "${plan}" ]] || continue
    if ! managed_component_tproxy_policy_plan_has_chain "${before}" "$(jq -r '.chain' <<< "${plan}")"; then
      managed_component_tproxy_policy_remove_plan "${plan}" true || return 1
    fi
  done < <(jq -c '.[]' <<< "${after}")
}

managed_component_tproxy_policy_restore_before() {
  local journal_file=${1:-} status before plan
  managed_component_tproxy_policy_journal_validate "${journal_file}" || return 1
  status=$(jq -r '.status' "${journal_file}") || return 1
  [[ "${status}" == prepared || "${status}" == rolled_back ]] && return 0
  before=$(jq -c '.before' "${journal_file}") || return 1
  while IFS= read -r plan; do
    [[ -n "${plan}" ]] || continue
    managed_component_tproxy_policy_ensure_plan "${plan}" true || return 1
  done < <(jq -c '.[]' <<< "${before}")
  managed_component_tproxy_policy_journal_set_status "${journal_file}" rolled_back
}

managed_component_tproxy_policy_precedence_json() {
  local plan=${1:-} marker rules preceding status route_rules=''
  local rule_priority route_preceding=null route_status=unavailable
  managed_component_tproxy_host_policy_plan_validate_json "[${plan}]" || return 1
  marker=$(jq -r '.marker' <<< "${plan}") || return 1
  rule_priority=$(jq -r '.rule_priority' <<< "${plan}") || return 1
  if ! command -v iptables >/dev/null 2>&1 || ! rules=$(iptables -t mangle -S PREROUTING 2>/dev/null); then
    jq -cn '{status:"unavailable",preceding_rule_count:null,
      policy_routing_status:"unavailable",preceding_policy_rule_count:null}'
    return 0
  fi
  preceding=$(awk -v marker="${marker}" '
    $1 == "-A" && $2 == "PREROUTING" {
      if (index($0, marker)) { found=1; exit }
      count++
    }
    END { if (!found) exit 1; print count+0 }
  ' <<< "${rules}") || { jq -cn '{status:"unavailable",preceding_rule_count:null,
    policy_routing_status:"unavailable",preceding_policy_rule_count:null}'; return 0; }
  if [[ "${preceding}" == 0 ]]; then status=unshadowed_in_observed_order; else status=not_assessed_earlier_rules_present; fi
  if command -v ip >/dev/null 2>&1 && route_rules=$(ip -4 rule show 2>/dev/null); then
    route_preceding=$(awk -v target="${rule_priority}:" '
      $1 == target { found=1; exit }
      $1 ~ /^[0-9]+:$/ {
        value=$1; sub(/:$/, "", value)
        if (value != 0) count++
      }
      END { if (!found) exit 1; print count+0 }
    ' <<< "${route_rules}") || {
      route_preceding=null
      route_status=unavailable
    }
    if [[ "${route_preceding}" != null ]]; then
      if [[ "${route_preceding}" == 0 ]]; then route_status=unshadowed_in_observed_order
      else route_status=not_assessed_earlier_rules_present
      fi
    fi
  fi
  jq -cn --arg status "${status}" --argjson count "${preceding}" \
    --arg route_status "${route_status}" --argjson route_count "${route_preceding}" \
    '{status:$status,preceding_rule_count:$count,policy_routing_status:$route_status,
      preceding_policy_rule_count:$route_count}'
}

managed_component_tproxy_policy_diagnose_json() {
  local state=${1:-} plans plan status precedence row resources_json
  local resources=() operators='[]' overall=available
  plans=$(managed_component_tproxy_host_policy_plan_json "${state}") || return 1
  managed_component_tproxy_host_policy_plan_validate_json "${plans}" || return 1
  while IFS= read -r plan; do
    [[ -n "${plan}" ]] || continue
    status=$(managed_component_tproxy_policy_probe "${plan}") || return 1
    precedence=$(managed_component_tproxy_policy_precedence_json "${plan}") || return 1
    [[ "${status}" == present ]] || overall=unavailable
    row=$(jq -cn --argjson plan "${plan}" --arg status "${status}" --argjson precedence "${precedence}" \
      '$plan + {resource_scope:"installer_owned_ipv4_tcp_udp_prerouting_policy_route",status:$status,
        precedence:$precedence.status,preceding_rule_count:$precedence.preceding_rule_count,
        policy_routing_precedence:$precedence.policy_routing_status,
        preceding_policy_rule_count:$precedence.preceding_policy_rule_count}') || return 1
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
    '{status:$status,managed_backend:"iptables+iproute2",managed_family:"ipv4",
      managed_transports:["tcp","udp"],ordering:"append_after_existing_mangle_prerouting_rules",
      policy_routing_ordering:"priority_after_local_before_main",
      resources:$resources,operator_managed:$operators,
      limitations:["only explicit IPv4/TCP+UDP policies are installer-owned","TProxy packets are limited to the configured ingress interface and destination ports","earlier mangle PREROUTING or ip rules may change effective precedence; effectiveness is not assessed when such rules exist"]}'
}

managed_component_tproxy_policy_uninstall() {
  local plans=${1:-} plan status mangle_rules ip_rules
  managed_component_tproxy_host_policy_plan_validate_json "${plans}" || return 1
  if [[ "${plans}" == '[]' ]]; then
    if command -v iptables >/dev/null 2>&1 && mangle_rules=$(iptables -t mangle -S 2>/dev/null) &&
       grep -E 'SBVT_[a-f0-9]{20}|sbv-tproxy-[a-f0-9]{20}' <<< "${mangle_rules}" >/dev/null; then
      printf '[ERROR] 检测到缺少 state 所属记录的 TProxy 受管 mangle 链；拒绝卸载以避免遗留或误删主机规则。\n' >&2
      return 1
    fi
    if command -v ip >/dev/null 2>&1 && ip_rules=$(ip -4 rule show) &&
       grep -E 'fwmark 0x5b[0-9a-f]{6}(/0xffffffff)?([[:space:]]|$)' <<< "${ip_rules}" >/dev/null; then
      printf '[ERROR] 检测到保留 TProxy fwmark 前缀的策略规则，但没有对应 state；拒绝卸载。\n' >&2
      return 1
    fi
  fi
  while IFS= read -r plan; do
    [[ -n "${plan}" ]] || continue
    status=$(managed_component_tproxy_policy_probe "${plan}") || return 1
    case "${status}" in absent|present|partial) ;; *) return 1 ;; esac
  done < <(jq -c '.[]' <<< "${plans}")
  while IFS= read -r plan; do
    [[ -n "${plan}" ]] || continue
    managed_component_tproxy_policy_remove_plan "${plan}" true || return 1
  done < <(jq -c '.[]' <<< "${plans}")
}
