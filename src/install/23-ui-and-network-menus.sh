
# --- UI & Main ---
term_columns() {
  local cols=${COLUMNS:-}

  if [[ "${cols}" =~ ^[0-9]+$ ]] && (( cols > 0 )); then
    printf '%s' "${cols}"
    return 0
  fi

  if command -v tput >/dev/null 2>&1; then
    cols=$(tput cols 2>/dev/null || true)
    if [[ "${cols}" =~ ^[0-9]+$ ]] && (( cols > 0 )); then
      printf '%s' "${cols}"
      return 0
    fi
  fi

  cols=$(stty size 2>/dev/null | awk '{print $2}' || true)
  if [[ "${cols}" =~ ^[0-9]+$ ]] && (( cols > 0 )); then
    printf '%s' "${cols}"
    return 0
  fi

  printf '80'
}

compact_ui_width() {
  local width

  width=$(term_columns)
  if (( width < 1 )); then
    width=1
  elif (( width > UI_COMPACT_MAX_WIDTH )); then
    width=${UI_COMPACT_MAX_WIDTH}
  fi

  printf '%s' "${width}"
}

repeat_char() {
  local char=$1
  local count=$2
  local output=""
  local i

  for ((i = 0; i < count; i++)); do
    output+="${char}"
  done

  printf '%s' "${output}"
}

safe_clear_screen() {
  if [[ -z "${TERM:-}" ]] || [[ "${TERM}" == "dumb" ]]; then
    return 0
  fi

  if [[ ! -t 1 ]]; then
    return 0
  fi

  if command -v clear >/dev/null 2>&1; then
    clear 2>/dev/null || true
  fi
}

is_ascii_text() {
  LC_ALL=C grep -q '^[ -~]*$' <<< "${1}"
}

estimate_text_width() {
  local text=$1
  local char_count byte_count extra_bytes

  if is_ascii_text "${text}"; then
    printf '%s' "${#text}"
    return 0
  fi

  char_count=$(printf '%s' "${text}" | wc -m | tr -d '[:space:]')
  byte_count=$(printf '%s' "${text}" | wc -c | tr -d '[:space:]')

  if [[ ! "${char_count}" =~ ^[0-9]+$ ]] || [[ ! "${byte_count}" =~ ^[0-9]+$ ]]; then
    printf '%s' "${#text}"
    return 0
  fi

  extra_bytes=$((byte_count - char_count))
  printf '%s' "$((char_count + (extra_bytes / 2)))"
}

render_section_title() {
  local title=$1
  local width divider

  width=$(term_columns)
  if (( width < 56 )); then
    echo -e "\n${BLUE}${title}${NC}"
    return 0
  fi

  divider=$(repeat_char "·" 8)
  echo -e "\n${BLUE}${divider} ${title} ${divider}${NC}"
}

render_menu_item() {
  local number=$1
  local label=$2
  local hint=${3:-}
  local status=${4:-}
  local width line

  width=$(term_columns)
  line="${number}. ${label}"

  if [[ -n "${status}" ]]; then
    if (( width >= 72 )); then
      echo -e "${line} ${GREEN}${status}${NC}"
    else
      echo "${line}"
      echo -e "   ${GREEN}${status}${NC}"
    fi
    return 0
  fi

  if [[ -n "${hint}" ]]; then
    if (( width >= 72 )); then
      echo -e "${line} ${BLUE}${hint}${NC}"
    else
      echo "${line}"
      echo -e "   ${BLUE}${hint}${NC}"
    fi
    return 0
  fi

  echo "${line}"
}

render_summary_item() {
  local label=$1
  local value=${2:-}
  printf '%s: %b\n' "${label}" "${value}"
}

render_main_menu_brand_block() {
  local width divider brand_info brand_meta brand_info_width brand_meta_width
  local project_url_without_scheme project_url_base project_url_path
  local current_path_line path_segment candidate
  local -a project_path_segments

  width=$(compact_ui_width)
  divider=$(repeat_char "═" "${width}")
  brand_info="作者: ${PROJECT_AUTHOR} · 项目: ${PROJECT_URL}"
  brand_meta="专为 VPS 稳定部署与安全运维设计 · 版本: ${SCRIPT_VERSION}"
  brand_info_width=$(estimate_text_width "${brand_info}")
  brand_meta_width=$(estimate_text_width "${brand_meta}")

  echo -e "${BLUE}${divider}${NC}"
  echo -e "${GREEN}sing-box-vps 一键安装管理脚本${NC}"

  if (( brand_info_width <= width && brand_meta_width <= width )); then
    echo -e "${YELLOW}${brand_info}${NC}"
    echo -e "${BLUE}${brand_meta}${NC}"
  else
    echo -e "${YELLOW}作者: ${PROJECT_AUTHOR}${NC}"
    echo -e "${YELLOW}项目:${NC}"
    project_url_without_scheme=${PROJECT_URL#*://}
    project_url_base="${PROJECT_URL%%://*}://${project_url_without_scheme%%/*}/"
    if [[ "${project_url_without_scheme}" == */* ]]; then
      project_url_path=${project_url_without_scheme#*/}
    else
      project_url_path=""
    fi

    echo -e "${YELLOW}${project_url_base}${NC}"

    if [[ -n "${project_url_path}" ]]; then
      IFS='/' read -r -a project_path_segments <<< "${project_url_path}"
      current_path_line=""

      for path_segment in "${project_path_segments[@]}"; do
        if [[ -z "${current_path_line}" ]]; then
          candidate="${path_segment}"
        else
          candidate="${current_path_line}/${path_segment}"
        fi

        if (( $(estimate_text_width "${candidate}") <= width )); then
          current_path_line="${candidate}"
        else
          [[ -n "${current_path_line}" ]] && echo -e "${YELLOW}${current_path_line}${NC}"
          current_path_line="${path_segment}"
        fi
      done

      [[ -n "${current_path_line}" ]] && echo -e "${YELLOW}${current_path_line}${NC}"
    fi

    echo -e "${BLUE}专为 VPS 稳定部署与安全运维设计${NC}"
    echo -e "${BLUE}版本: ${SCRIPT_VERSION}${NC}"
  fi

  echo -e "${BLUE}${divider}${NC}"
}

render_left_aligned_page_header() {
  local title=$1
  local subtitle=${2:-}
  local width divider

  width=$(compact_ui_width)
  divider=$(repeat_char "═" "${width}")

  echo -e "${BLUE}${divider}${NC}"
  echo -e "${GREEN}${title}${NC}"
  if [[ -n "${subtitle}" ]]; then
    echo -e "${BLUE}${subtitle}${NC}"
  fi
  echo -e "${BLUE}${divider}${NC}"
}

render_menu_group_start() {
  local title=${1:-}

  if [[ -n "${title}" ]]; then
    render_section_title "${title}"
  else
    echo
  fi
}

show_banner() {
  safe_clear_screen
  render_main_menu_brand_block
  echo
}

render_main_menu_footer() {
  :
}

# Helper: Check BBR Status
check_bbr_status() {
  local cc
  cc=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}' || true)

  if [[ -z "${cc}" ]]; then
    BBR_STATUS="${YELLOW}(状态未知)${NC}"
  elif [[ "${cc}" == "bbr" ]]; then
    BBR_STATUS="${GREEN}(已开启 BBR)${NC}"
  else
    BBR_STATUS="${YELLOW}(未开启 BBR)${NC}"
  fi
}

apply_stack_mode_changes() {
  local selected_inbound selected_outbound snapshot_dir
  selected_inbound="${SB_INBOUND_STACK_MODE}"
  selected_outbound="${SB_OUTBOUND_STACK_MODE}"

  if [[ -f "${SINGBOX_CONFIG_FILE}" || -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    load_current_config_state
    snapshot_dir=$(create_managed_state_snapshot) || log_error "无法创建配置状态事务快照。"
    if ! ensure_existing_generated_config_baseline; then
      abort_managed_state_transaction "${snapshot_dir}" "协议栈变更前的生成基线无法建立"
      return 1
    fi
    SB_INBOUND_STACK_MODE="${selected_inbound}"
    SB_OUTBOUND_STACK_MODE="${selected_outbound}"
  fi

  if [[ ! -f "${SINGBOX_CONFIG_FILE}" && ! -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    save_stack_mode_state
    log_success "协议栈设置已保存，将在首次安装或下次生成配置时生效。"
    return 0
  fi

  if ! save_stack_mode_state || ! generate_config; then
    abort_managed_state_transaction "${snapshot_dir}" "协议栈配置生成或校验失败"
  fi
  if ! discard_managed_state_snapshot "${snapshot_dir}"; then
    log_warn "协议栈配置已提交，但临时事务快照未能删除: ${snapshot_dir}。"
  fi
  refresh_vless_reality_qos_rules
  setup_service
  open_committed_protocol_ports || return $?
  run_with_progress "重启 sing-box（ACME 签发或 DNS 验证可能需要较长时间）" systemctl restart sing-box
  log_success "协议栈设置已保存并重启服务。"
}

configure_inbound_stack_mode() {
  local host_stack choice selected_mode
  local available_modes=()
  local index

  ensure_stack_mode_state_loaded
  host_stack=$(detect_host_ip_stack)

  case "${host_stack}" in
    dual) available_modes=(ipv4_only ipv6_only dual_stack) ;;
    ipv6) available_modes=(ipv6_only) ;;
    *) available_modes=(ipv4_only) ;;
  esac

  while true; do
    echo
    render_left_aligned_page_header "入站协议栈" "按主机能力选择监听栈"
    render_section_title "当前设置"
    render_summary_item "系统网络能力" "$(host_ip_stack_display_name "${host_stack}")"
    render_summary_item "当前入站协议栈" "$(inbound_stack_mode_display_name "${SB_INBOUND_STACK_MODE}")"
    render_section_title "可选模式"

    for index in "${!available_modes[@]}"; do
      render_menu_item "$((index + 1))" "$(inbound_stack_mode_display_name "${available_modes[$index]}")"
    done
    echo "0. 返回"
    choice=$(prompt_choice "请选择 [0-${#available_modes[@]}]: " 0 "${#available_modes[@]}" "")

    if [[ "${choice}" == "0" ]]; then
      return 0
    fi

    if [[ "${choice}" =~ ^[1-9][0-9]*$ ]] && (( choice >= 1 && choice <= ${#available_modes[@]} )); then
      selected_mode="${available_modes[$((choice - 1))]}"
      [[ "${selected_mode}" == "${SB_INBOUND_STACK_MODE}" ]] && return 0
      SB_INBOUND_STACK_MODE="${selected_mode}"
      apply_stack_mode_changes
      return 0
    fi

    log_warn "无效选项，请重新选择。"
  done
}

configure_outbound_stack_mode() {
  local choice selected_mode
  local available_modes=(ipv4_only ipv6_only prefer_ipv4 prefer_ipv6)
  local index

  ensure_stack_mode_state_loaded

  if [[ "${SB_ENABLE_WARP}" == "y" ]]; then
    log_warn "当前已开启 Warp，出站协议栈设置不生效，已禁止修改。"
    return 0
  fi

  while true; do
    echo
    render_left_aligned_page_header "出站协议栈" "调整 sing-box 的 DNS 与直连出站策略"
    render_section_title "当前设置"
    render_summary_item "当前出站协议栈" "$(outbound_stack_mode_display_name "${SB_OUTBOUND_STACK_MODE}")"
    render_section_title "可选模式"

    for index in "${!available_modes[@]}"; do
      render_menu_item "$((index + 1))" "$(outbound_stack_mode_display_name "${available_modes[$index]}")"
    done
    echo "0. 返回"
    choice=$(prompt_choice "请选择 [0-${#available_modes[@]}]: " 0 "${#available_modes[@]}" "")

    if [[ "${choice}" == "0" ]]; then
      return 0
    fi

    if [[ "${choice}" =~ ^[1-9][0-9]*$ ]] && (( choice >= 1 && choice <= ${#available_modes[@]} )); then
      selected_mode="${available_modes[$((choice - 1))]}"
      [[ "${selected_mode}" == "${SB_OUTBOUND_STACK_MODE}" ]] && return 0
      SB_OUTBOUND_STACK_MODE="${selected_mode}"
      apply_stack_mode_changes
      return 0
    fi

    log_warn "无效选项，请重新选择。"
  done
}

stack_management_menu() {
  local host_stack
  local warp_status

  while true; do
    if [[ -f "${SINGBOX_CONFIG_FILE}" || -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
      load_current_config_state
    else
      ensure_stack_mode_state_loaded
      SB_ENABLE_WARP="n"
    fi

    host_stack=$(detect_host_ip_stack)
    if [[ "${SB_ENABLE_WARP}" == "y" ]]; then
      warp_status="已开启 (出站协议栈当前不生效)"
    else
      warp_status="未开启"
    fi

    echo
    render_left_aligned_page_header "协议栈管理" "统一调整入站 / 出站网络栈策略"
    render_section_title "协议栈摘要"
    render_summary_item "系统网络能力" "$(host_ip_stack_display_name "${host_stack}")"
    render_summary_item "当前入站协议栈" "$(inbound_stack_mode_display_name "${SB_INBOUND_STACK_MODE}")"
    render_summary_item "当前出站协议栈" "$(outbound_stack_mode_display_name "${SB_OUTBOUND_STACK_MODE}")"
    render_summary_item "Warp 状态" "${warp_status}"
    render_section_title "操作选项"
    render_menu_item "1" "修改入站协议栈"
    render_menu_item "2" "修改出站协议栈"
    echo "0. 返回上一级"
    stack_choice=$(prompt_choice "请选择 [0-2]: " 0 2 "")

    case "${stack_choice}" in
      1) configure_inbound_stack_mode || true ;;
      2) configure_outbound_stack_mode || true ;;
      0) return ;;
      *) log_warn "无效选项，请重新选择。" ;;
    esac
  done
}

system_management_menu() {
  while true; do
    check_bbr_status
    echo
    render_left_aligned_page_header "系统管理" "维护内核优化与网络协议栈设置"
    render_section_title "系统摘要"
    render_summary_item "BBR 状态" "${BBR_STATUS}"
    render_section_title "操作选项"
    render_menu_item "1" "开启 BBR"
    render_menu_item "2" "协议栈管理"
    echo "0. 返回主菜单"
    system_choice=$(prompt_choice "请选择 [0-2]: " 0 2 "")

    case "${system_choice}" in
      1) enable_bbr ;;
      2) stack_management_menu ;;
      0) return ;;
      *) log_warn "无效选项，请重新选择。" ;;
    esac
  done
}

# Detect whether the current config enables Warp.
# Prefer the current endpoint-based schema, but keep compatibility with older configs.
config_has_warp_enabled() {
  local config_file=$1
  local saved_enabled

  if [[ "${config_file}" == "${SINGBOX_CONFIG_FILE}" && -f "${SB_ROUTING_POLICY_FILE}" &&
        -f "${SB_WARP_ROUTE_SETTINGS_FILE}" && ! -L "${SB_WARP_ROUTE_SETTINGS_FILE}" ]]; then
    saved_enabled=$(sed -n 's/^WARP_ENABLED=\([yn]\)$/\1/p' "${SB_WARP_ROUTE_SETTINGS_FILE}") || return 1
    case "${saved_enabled}" in y) return 0 ;; n) return 1 ;; esac
  fi

  jq -e '
    (
      any(.endpoints[]?; .tag == "warp-ep") and
      (
        (.route.final // "") == "warp-ep" or
        any(.route.rules[]?; (.outbound // "") == "warp-ep" and (has("inbound") | not))
      )
    ) or any(.outbounds[]?; .tag == "warp")
  ' "${config_file}" &>/dev/null
}

config_detect_warp_route_mode() {
  local config_file=$1

  if jq -e '(.route.final // "") == "warp-ep"' "${config_file}" &>/dev/null; then
    printf 'all'
    return 0
  fi

  if jq -e 'any(.route.rules[]?; (.outbound // "") == "warp-ep")' "${config_file}" &>/dev/null; then
    printf 'selective'
    return 0
  fi

  printf 'selective'
}

# Detect whether advanced route rules are enabled in either the current or legacy schema.
config_has_advanced_route() {
  local config_file=$1

  jq -e '
    any(
      .route.rules[]?;
      (.ip_is_private == true and .action == "reject") or
      (.geosite == "category-ads-all")
    )
  ' "${config_file}" &>/dev/null
}

load_config_generation_settings() {
  local config_file=${1:-}

  [[ -f "${config_file}" && ! -L "${config_file}" ]] || return 0
  jq -e 'type == "object"' "${config_file}" >/dev/null 2>&1 || return 0

  if config_has_advanced_route "${config_file}"; then
    SB_ADVANCED_ROUTE="y"
  else
    SB_ADVANCED_ROUTE="n"
  fi
  if config_has_warp_enabled "${config_file}"; then
    SB_ENABLE_WARP="y"
  else
    SB_ENABLE_WARP="n"
  fi
  load_warp_route_settings
}

normalize_acme_extra_json() {
  local acme_json=$1

  if ! jq -n -e --argjson acme "${acme_json}" '$acme | type == "object"' >/dev/null 2>&1; then
    return 1
  fi
  if jq -n -e --argjson acme "${acme_json}" '$acme | has("http_client")' >/dev/null 2>&1; then
    local http_client_json http_client_type
    http_client_type=$(jq -n -r --argjson acme "${acme_json}" '$acme.http_client | type') || return 1
    case "${http_client_type}" in
      string)
        jq -n -e --argjson acme "${acme_json}" \
          '$acme.http_client | length > 0 and (any(explode[]; . < 32 or . == 127) | not)' \
          >/dev/null 2>&1 || return 1
        ;;
      object)
        # Both legacy tls.acme and top-level certificate_provider records may
        # carry an upstream inline HTTPClientOptions object. Keep it typed and
        # lossless; managed component state still uses a shared reference when
        # the client is represented as a first-class top-level component.
        http_client_json=$(jq -c -n --argjson acme "${acme_json}" '$acme.http_client') || return 1
        managed_component_http_client_config_validate_json "${http_client_json}" || return 1
        ;;
      *) return 1 ;;
    esac
  fi

  jq -cnS \
    --argjson acme "${acme_json}" \
    --arg default_data_directory "${SB_ACME_DATA_DIR}" \
    '$acme
    | if .domain == null then
        del(.domain)
      elif (.domain | type) != "array" or (.domain | length) == 0 then
        error("invalid ACME domain")
      elif (.domain | length) == 1 then
        del(.domain)
      else
        .
      end
    | del(.type, .tag, .email)
    | if .data_directory == $default_data_directory then del(.data_directory) else . end
    | if .dns01_challenge == null then
        del(.dns01_challenge)
      elif (.dns01_challenge | type) == "object" then
        .dns01_challenge |= del(.provider, .api_token)
        | if .dns01_challenge == {} then del(.dns01_challenge) else . end
      else
        .
      end'
}

inline_acme_extra_json_from_config() {
  local config_file=$1
  local inbound_index=$2
  local acme_json

  acme_json=$(jq -c --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme' "${config_file}") || return 1
  normalize_acme_extra_json "${acme_json}"
}

# Resolve an inbound certificate provider into the state fields consumed by all
# protocol readers.  A certificate_provider may be either a shared tag or an
# inline object, but only an ACME provider can be represented by the script's
# state model.  Returning an error for anything else prevents a later rewrite
# from silently changing the certificate configuration.
load_certificate_provider_from_config() {
  local config_file=$1
  local inbound_index=$2
  local provider_kind provider_tag provider_count provider_json provider_type server_name
  local http_client_type http_client_tag http_client_count http_client_json

  CERT_PROVIDER_MODE="none"
  CERT_PROVIDER_TAG=""
  CERT_PROVIDER_EMAIL=""
  CERT_PROVIDER_DOMAIN=""
  CERT_PROVIDER_EXTRA_JSON='{}'
  CERT_PROVIDER_ACME_MODE="http"
  CERT_PROVIDER_DNS_PROVIDER="cloudflare"
  CERT_PROVIDER_CF_API_TOKEN=""
  CERT_PROVIDER_ERROR=""

  if ! provider_kind=$(jq -r --argjson idx "${inbound_index}" '
    .inbounds[$idx].tls.certificate_provider? |
    if . == null then "none"
    elif type == "string" then "shared"
    elif type == "object" then "inline"
    else "invalid"
    end
  ' "${config_file}"); then
    CERT_PROVIDER_ERROR="无法读取 certificate_provider"
    return 1
  fi

  case "${provider_kind}" in
    none)
      return 0
      ;;
    shared)
      provider_tag=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_provider' "${config_file}") || {
        CERT_PROVIDER_ERROR="无法读取 shared certificate_provider tag"
        return 1
      }
      provider_count=$(jq -r --arg tag "${provider_tag}" '[.certificate_providers[]? | select(type == "object" and .tag == $tag)] | length' "${config_file}") || {
        CERT_PROVIDER_ERROR="无法读取 shared certificate_provider 映射"
        return 1
      }
      if [[ "${provider_count}" != "1" ]]; then
        CERT_PROVIDER_ERROR="shared certificate_provider 未唯一映射"
        return 1
      fi
      provider_json=$(jq -c --arg tag "${provider_tag}" 'first(.certificate_providers[]? | select(type == "object" and .tag == $tag)) // null' "${config_file}") || {
        CERT_PROVIDER_ERROR="无法读取 shared certificate_provider"
        return 1
      }
      CERT_PROVIDER_TAG="${provider_tag}"
      ;;
    inline)
      provider_json=$(jq -c --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_provider' "${config_file}") || {
        CERT_PROVIDER_ERROR="无法读取 inline certificate_provider"
        return 1
      }
      ;;
    *)
      CERT_PROVIDER_ERROR="certificate_provider 类型不受支持"
      return 1
      ;;
  esac

  provider_type=$(jq -n -r --argjson provider "${provider_json}" '$provider.type // ""' 2>/dev/null) || {
    CERT_PROVIDER_ERROR="无法读取 certificate_provider type"
    return 1
  }
  if [[ "${provider_type}" != "acme" ]]; then
    CERT_PROVIDER_ERROR="certificate_provider 不是 ACME provider"
    return 1
  fi

  if jq -n -e --argjson provider "${provider_json}" '$provider | has("http_client")' >/dev/null 2>&1; then
    http_client_type=$(jq -n -r --argjson provider "${provider_json}" '$provider.http_client | type') || {
      CERT_PROVIDER_ERROR="无法读取 shared http_client 类型"
      return 1
    }
    case "${http_client_type}" in
      string)
        http_client_tag=$(jq -n -r --argjson provider "${provider_json}" '$provider.http_client // empty') || {
          CERT_PROVIDER_ERROR="无法读取 shared http_client tag"
          return 1
        }
        http_client_count=$(jq -r --arg tag "${http_client_tag}" '
          [(.http_clients // [])[]? |
            select(type == "object" and .tag == $tag)] | length
        ' "${config_file}") || {
          CERT_PROVIDER_ERROR="无法读取 shared http_client 映射"
          return 1
        }
        if [[ "${http_client_count}" != "1" ]]; then
          CERT_PROVIDER_ERROR="shared http_client 未唯一映射"
          return 1
        fi
        http_client_json=$(jq -c --arg tag "${http_client_tag}" '
          first((.http_clients // [])[]? |
            select(type == "object" and .tag == $tag)) // null
        ' "${config_file}") || {
          CERT_PROVIDER_ERROR="无法读取 shared http_client"
          return 1
        }
        if ! managed_component_http_client_config_validate_json "$(jq -c 'del(.tag)' <<< "${http_client_json}")"; then
          CERT_PROVIDER_ERROR="shared http_client 配置无效"
          return 1
        fi
        ;;
      object)
        # Upstream also permits an inline HTTPClientOptions object. Keep this
        # legacy form typed and lossless; only a string uses the top-level
        # shared-client reference lookup above.
        http_client_json=$(jq -c -n --argjson provider "${provider_json}" '$provider.http_client') || {
          CERT_PROVIDER_ERROR="无法读取 inline http_client"
          return 1
        }
        if ! managed_component_http_client_config_validate_json "${http_client_json}"; then
          CERT_PROVIDER_ERROR="inline http_client 配置无效"
          return 1
        fi
        ;;
      *)
        CERT_PROVIDER_ERROR="certificate_provider 的 http_client 类型不受支持"
        return 1
        ;;
    esac
  fi

  if ! CERT_PROVIDER_EXTRA_JSON=$(normalize_acme_extra_json "${provider_json}"); then
    CERT_PROVIDER_ERROR="无法保留 ACME provider 的扩展字段"
    return 1
  fi

  server_name=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.server_name // ""' "${config_file}") || {
    CERT_PROVIDER_ERROR="无法读取 certificate_provider fallback domain"
    return 1
  }
  CERT_PROVIDER_MODE="acme"
  if ! CERT_PROVIDER_EMAIL=$(jq -n -r --argjson provider "${provider_json}" '$provider.email // ""' 2>/dev/null); then
    CERT_PROVIDER_ERROR="无法读取 ACME provider email"
    return 1
  fi
  if ! CERT_PROVIDER_DOMAIN=$(jq -n -r --argjson provider "${provider_json}" --arg fallback "${server_name}" '$provider.domain[0] // $fallback' 2>/dev/null); then
    CERT_PROVIDER_ERROR="无法读取 ACME provider domain"
    return 1
  fi
  if jq -n -e --argjson provider "${provider_json}" '$provider.dns01_challenge? != null' &>/dev/null; then
    CERT_PROVIDER_ACME_MODE="dns"
    if ! CERT_PROVIDER_DNS_PROVIDER=$(jq -n -r --argjson provider "${provider_json}" '$provider.dns01_challenge.provider // "cloudflare"' 2>/dev/null); then
      CERT_PROVIDER_ERROR="无法读取 ACME DNS provider"
      return 1
    fi
    if ! CERT_PROVIDER_CF_API_TOKEN=$(jq -n -r --argjson provider "${provider_json}" '$provider.dns01_challenge.api_token // ""' 2>/dev/null); then
      CERT_PROVIDER_ERROR="无法读取 ACME DNS API token"
      return 1
    fi
  fi
}

load_current_config_state() {
  local first_protocol
  local empty_baseline=n
  local installed_protocols=()

  if [[ $# -ge 1 && -z "$1" ]] && instance_management_empty_config_baseline; then
    empty_baseline=y
  else
    migrate_legacy_single_protocol_state_if_needed || return $?
  fi

  if [[ ! -f "${SINGBOX_CONFIG_FILE}" && ! -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    log_error "未找到配置文件，请先安装。"
  fi

  if [[ -f "${SINGBOX_CONFIG_FILE}" ]]; then
    if config_has_advanced_route "${SINGBOX_CONFIG_FILE}"; then
      SB_ADVANCED_ROUTE="y"
    else
      SB_ADVANCED_ROUTE="n"
    fi

    if config_has_warp_enabled "${SINGBOX_CONFIG_FILE}"; then
      SB_ENABLE_WARP="y"
    else
      SB_ENABLE_WARP="n"
    fi

    load_warp_route_settings
  fi

  load_stack_mode_state

  if [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    if [[ $# -ge 1 ]]; then
      if [[ -n "$1" ]]; then
        mapfile -t installed_protocols <<< "$1"
      fi
    else
      mapfile -t installed_protocols < <(list_installed_protocols)
    fi
    first_protocol="${installed_protocols[0]:-}"
    if [[ -n "${first_protocol}" ]]; then
      load_protocol_state "${first_protocol}" || return 1
      return 0
    fi
  fi

  if [[ "${empty_baseline}" == y ]]; then
    SB_PROTOCOL=""
    SB_PORT=""
    return 0
  fi

  if [[ ! -f "${SINGBOX_CONFIG_FILE}" ]]; then
    log_error "未找到配置文件，请先安装。"
  fi

  SB_PROTOCOL=$(jq -r '.inbounds[0].type' "${SINGBOX_CONFIG_FILE}")
  case "${SB_PROTOCOL}" in
    vless) SB_PROTOCOL="vless+reality" ;;
    mixed) SB_PROTOCOL="mixed" ;;
    hysteria2) SB_PROTOCOL="hy2" ;;
    anytls) SB_PROTOCOL="anytls" ;;
    *) log_error "当前配置中的协议类型不受脚本支持: ${SB_PROTOCOL}" ;;
  esac

  SB_PORT=$(jq -r '.inbounds[0].listen_port' "${SINGBOX_CONFIG_FILE}")

  if [[ "${SB_PROTOCOL}" == "vless+reality" ]]; then
    SB_NODE_NAME="$(default_node_name_for_protocol "vless+reality")"
    SB_UUID=$(jq -r '.inbounds[0].users[0].uuid' "${SINGBOX_CONFIG_FILE}")
    SB_SNI=$(jq -r '.inbounds[0].tls.server_name' "${SINGBOX_CONFIG_FILE}")
    SB_PRIVATE_KEY=$(jq -r '.inbounds[0].tls.reality.private_key' "${SINGBOX_CONFIG_FILE}")
    SB_SHORT_ID_1=$(jq -r '.inbounds[0].tls.reality.short_id[0]' "${SINGBOX_CONFIG_FILE}")
    SB_SHORT_ID_2=$(jq -r '.inbounds[0].tls.reality.short_id[1]' "${SINGBOX_CONFIG_FILE}")
    SB_MIXED_AUTH_ENABLED="y"
    SB_MIXED_USERNAME=""
    SB_MIXED_PASSWORD=""
  elif [[ "${SB_PROTOCOL}" == "mixed" ]]; then
    SB_NODE_NAME="$(default_node_name_for_protocol "mixed")"
    SB_UUID=""
    SB_SNI=""
    SB_PRIVATE_KEY=""
    SB_SHORT_ID_1=""
    SB_SHORT_ID_2=""
    if jq -e '(.inbounds[0].users // []) | length > 0' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
      SB_MIXED_AUTH_ENABLED="y"
      SB_MIXED_USERNAME=$(jq -r '.inbounds[0].users[0].username // ""' "${SINGBOX_CONFIG_FILE}")
      SB_MIXED_PASSWORD=$(jq -r '.inbounds[0].users[0].password // ""' "${SINGBOX_CONFIG_FILE}")
    else
      SB_MIXED_AUTH_ENABLED="n"
      SB_MIXED_USERNAME=""
      SB_MIXED_PASSWORD=""
    fi
  elif [[ "${SB_PROTOCOL}" == "hy2" ]]; then
    SB_NODE_NAME="$(default_node_name_for_protocol "hy2")"
    SB_HY2_DOMAIN=$(jq -r '.inbounds[0].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")
    SB_HY2_PASSWORD=$(jq -r '.inbounds[0].users[0].password // ""' "${SINGBOX_CONFIG_FILE}")
    SB_HY2_USER_NAME=$(jq -r '.inbounds[0].users[0].name // ""' "${SINGBOX_CONFIG_FILE}")
    SB_HY2_UP_MBPS=$(jq -r '.inbounds[0].up_mbps // ""' "${SINGBOX_CONFIG_FILE}")
    SB_HY2_DOWN_MBPS=$(jq -r '.inbounds[0].down_mbps // ""' "${SINGBOX_CONFIG_FILE}")
    if jq -e '.inbounds[0].obfs.type == "salamander"' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
      SB_HY2_OBFS_ENABLED="y"
      SB_HY2_OBFS_TYPE="salamander"
      SB_HY2_OBFS_PASSWORD=$(jq -r '.inbounds[0].obfs.password // ""' "${SINGBOX_CONFIG_FILE}")
    else
      SB_HY2_OBFS_ENABLED="n"
      SB_HY2_OBFS_TYPE=""
      SB_HY2_OBFS_PASSWORD=""
    fi
    if jq -e '.inbounds[0].tls.acme? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
      SB_HY2_TLS_MODE="acme"
      SB_HY2_ACME_EMAIL=$(jq -r '.inbounds[0].tls.acme.email // ""' "${SINGBOX_CONFIG_FILE}")
      SB_HY2_ACME_DOMAIN=$(jq -r '.inbounds[0].tls.acme.domain[0] // .inbounds[0].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")
      if jq -e '.inbounds[0].tls.acme.dns01_challenge? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
        SB_HY2_ACME_MODE="dns"
        SB_HY2_DNS_PROVIDER=$(jq -r '.inbounds[0].tls.acme.dns01_challenge.provider // "cloudflare"' "${SINGBOX_CONFIG_FILE}")
        SB_HY2_CF_API_TOKEN=$(jq -r '.inbounds[0].tls.acme.dns01_challenge.api_token // ""' "${SINGBOX_CONFIG_FILE}")
      else
        SB_HY2_ACME_MODE="http"
        SB_HY2_DNS_PROVIDER="cloudflare"
        SB_HY2_CF_API_TOKEN=""
      fi
      if ! SB_HY2_ACME_EXTRA_JSON=$(inline_acme_extra_json_from_config "${SINGBOX_CONFIG_FILE}" 0); then
        log_error "当前 Hysteria2 tls.acme 扩展字段无法安全保留。"
      fi
      SB_HY2_CERT_PATH=""
      SB_HY2_KEY_PATH=""
    elif jq -e '.inbounds[0].tls.certificate_provider? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
      if ! load_certificate_provider_from_config "${SINGBOX_CONFIG_FILE}" 0; then
        log_error "当前 Hysteria2 certificate_provider 无法安全解析: ${CERT_PROVIDER_ERROR}"
      fi
      SB_HY2_TLS_MODE="acme"
      SB_HY2_ACME_MODE="${CERT_PROVIDER_ACME_MODE}"
      SB_HY2_ACME_EMAIL="${CERT_PROVIDER_EMAIL}"
      SB_HY2_ACME_DOMAIN="${CERT_PROVIDER_DOMAIN}"
      SB_HY2_ACME_EXTRA_JSON="${CERT_PROVIDER_EXTRA_JSON}"
      SB_HY2_DNS_PROVIDER="${CERT_PROVIDER_DNS_PROVIDER}"
      SB_HY2_CF_API_TOKEN="${CERT_PROVIDER_CF_API_TOKEN}"
      SB_HY2_CERT_PATH=""
      SB_HY2_KEY_PATH=""
    else
      SB_HY2_TLS_MODE="manual"
      SB_HY2_ACME_MODE="http"
      SB_HY2_ACME_EMAIL=""
      SB_HY2_ACME_DOMAIN="${SB_HY2_DOMAIN}"
      SB_HY2_ACME_EXTRA_JSON='{}'
      SB_HY2_DNS_PROVIDER="cloudflare"
      SB_HY2_CF_API_TOKEN=""
      SB_HY2_CERT_PATH=$(jq -r '.inbounds[0].tls.certificate_path // ""' "${SINGBOX_CONFIG_FILE}")
      SB_HY2_KEY_PATH=$(jq -r '.inbounds[0].tls.key_path // ""' "${SINGBOX_CONFIG_FILE}")
    fi
    SB_HY2_MASQUERADE=$(jq -r '.inbounds[0].masquerade // ""' "${SINGBOX_CONFIG_FILE}")
    SB_ANYTLS_DOMAIN=""
    SB_ANYTLS_PASSWORD=""
    SB_ANYTLS_USER_NAME=""
  else
    SB_NODE_NAME="$(default_node_name_for_protocol "anytls")"
    SB_ANYTLS_DOMAIN=$(jq -r '.inbounds[0].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")
    SB_ANYTLS_PASSWORD=$(jq -r '.inbounds[0].users[0].password // ""' "${SINGBOX_CONFIG_FILE}")
    SB_ANYTLS_USER_NAME=$(jq -r '.inbounds[0].users[0].name // ""' "${SINGBOX_CONFIG_FILE}")
    if jq -e '.inbounds[0].tls.acme? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
      SB_ANYTLS_TLS_MODE="acme"
      SB_ANYTLS_ACME_EMAIL=$(jq -r '.inbounds[0].tls.acme.email // ""' "${SINGBOX_CONFIG_FILE}")
      SB_ANYTLS_ACME_DOMAIN=$(jq -r '.inbounds[0].tls.acme.domain[0] // .inbounds[0].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")
      if jq -e '.inbounds[0].tls.acme.dns01_challenge? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
        SB_ANYTLS_ACME_MODE="dns"
        SB_ANYTLS_DNS_PROVIDER=$(jq -r '.inbounds[0].tls.acme.dns01_challenge.provider // "cloudflare"' "${SINGBOX_CONFIG_FILE}")
        SB_ANYTLS_CF_API_TOKEN=$(jq -r '.inbounds[0].tls.acme.dns01_challenge.api_token // ""' "${SINGBOX_CONFIG_FILE}")
      else
        SB_ANYTLS_ACME_MODE="http"
        SB_ANYTLS_DNS_PROVIDER="cloudflare"
        SB_ANYTLS_CF_API_TOKEN=""
      fi
      if ! SB_ANYTLS_ACME_EXTRA_JSON=$(inline_acme_extra_json_from_config "${SINGBOX_CONFIG_FILE}" 0); then
        log_error "当前 AnyTLS tls.acme 扩展字段无法安全保留。"
      fi
      SB_ANYTLS_CERT_PATH=""
      SB_ANYTLS_KEY_PATH=""
    elif jq -e '.inbounds[0].tls.certificate_provider? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
      if ! load_certificate_provider_from_config "${SINGBOX_CONFIG_FILE}" 0; then
        log_error "当前 AnyTLS certificate_provider 无法安全解析: ${CERT_PROVIDER_ERROR}"
      fi
      SB_ANYTLS_TLS_MODE="acme"
      SB_ANYTLS_ACME_MODE="${CERT_PROVIDER_ACME_MODE}"
      SB_ANYTLS_ACME_EMAIL="${CERT_PROVIDER_EMAIL}"
      SB_ANYTLS_ACME_DOMAIN="${CERT_PROVIDER_DOMAIN}"
      SB_ANYTLS_ACME_EXTRA_JSON="${CERT_PROVIDER_EXTRA_JSON}"
      SB_ANYTLS_DNS_PROVIDER="${CERT_PROVIDER_DNS_PROVIDER}"
      SB_ANYTLS_CF_API_TOKEN="${CERT_PROVIDER_CF_API_TOKEN}"
      SB_ANYTLS_CERT_PATH=""
      SB_ANYTLS_KEY_PATH=""
    else
      SB_ANYTLS_TLS_MODE="manual"
      SB_ANYTLS_ACME_MODE="http"
      SB_ANYTLS_ACME_EMAIL=""
      SB_ANYTLS_ACME_DOMAIN="${SB_ANYTLS_DOMAIN}"
      SB_ANYTLS_ACME_EXTRA_JSON='{}'
      SB_ANYTLS_DNS_PROVIDER="cloudflare"
      SB_ANYTLS_CF_API_TOKEN=""
      SB_ANYTLS_CERT_PATH=$(jq -r '.inbounds[0].tls.certificate_path // ""' "${SINGBOX_CONFIG_FILE}")
      SB_ANYTLS_KEY_PATH=$(jq -r '.inbounds[0].tls.key_path // ""' "${SINGBOX_CONFIG_FILE}")
    fi
  fi

  if [[ "${SB_PROTOCOL}" == "vless+reality" && -f "${SB_KEY_FILE}" ]]; then
    SB_PUBLIC_KEY=$(grep "PUBLIC_KEY" "${SB_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
  elif [[ "${SB_PROTOCOL}" == "vless+reality" ]]; then
    SB_PUBLIC_KEY="[密钥丢失，请更新配置]"
  else
    SB_PUBLIC_KEY=""
  fi
}

# Cloudflare Warp Management
warp_management() {
  routing_management_menu
}

# Helper to extract config values and display info
view_status() {
  load_current_config_state
  display_status_summary
}
