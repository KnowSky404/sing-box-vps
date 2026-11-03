# The data root is never snapshotted or replaced as a unit. Only runtime/ is.
SB_STORAGE_READY_ROOT=''

storage_directory_is_safe() {
  local directory=${1:-} current mode owner metadata
  [[ "${directory}" == /* && "${directory}" != *'/../'* &&
     "${directory}" != *'/./'* && "${directory}" != *$'\n'* &&
     "${directory}" != *$'\r'* ]] || return 1
  current=${directory}
  while :; do
    [[ ! -L "${current}" ]] || return 1
    if [[ -e "${current}" ]]; then
      [[ -d "${current}" ]] || return 1
      metadata=$(stat -c '%u:%a' -- "${current}") || return 1
      owner=${metadata%%:*}; mode=${metadata#*:}
      [[ "${owner}" == 0 && "${mode}" =~ ^[0-7]{3,4}$ ]] || return 1
      # A root-owned sticky ancestor (e.g. /tmp in isolated fixtures) cannot
      # replace a protected root-owned child; the managed directory itself
      # must always reject group/world writes.
      if (( (8#${mode} & 0022) != 0 )); then
        [[ "${current}" != "${directory}" ]] && (( (8#${mode} & 01000) != 0 )) || return 1
      fi
    fi
    [[ "${current}" != / ]] || break
    current=${current%/*}
    [[ -n "${current}" ]] || current=/
  done
}

storage_private_directory() {
  local directory=${1:-}
  [[ "${EUID}" == 0 ]] || return 1
  storage_directory_is_safe "${directory}" || return 1
  (umask 077; mkdir -p -- "${directory}") || return 1
  storage_directory_is_safe "${directory}" || return 1
  chmod 0700 -- "${directory}" || return 1
}

storage_prepare_tmp() {
  local metadata entry
  if [[ "${SB_STORAGE_READY_ROOT:-}" == "${SB_DATA_ROOT}" ]]; then
    # These two directories and their ancestry were fully validated in this
    # shell before caching. Root owns the non-writable ancestors; recheck the
    # actual write boundary on every use in one stat invocation.
    [[ ! -L "${SB_DATA_ROOT}" && ! -L "${SB_DATA_ROOT}/tmp" ]] || return 1
    metadata=$(LC_ALL=C stat -c '%u:%a:%F' -- "${SB_DATA_ROOT}" "${SB_DATA_ROOT}/tmp") || return 1
    while IFS= read -r entry; do [[ "${entry}" == '0:700:directory' ]] || return 1; done <<< "${metadata}"
    return 0
  fi
  [[ -n "${SB_ROOT_HOME:-}" && "${SB_ROOT_HOME}" == /* &&
     "${SB_ROOT_HOME}" != / && "${SB_ROOT_HOME}" != *'%'* &&
     "${SB_ROOT_HOME}" != *'"'* && "${SB_ROOT_HOME}" != *'\'* ]] || return 1
  storage_private_directory "${SB_DATA_ROOT}" || return 1
  storage_private_directory "${SB_DATA_ROOT}/tmp" || return 1
  SB_STORAGE_READY_ROOT=${SB_DATA_ROOT}
}

storage_initialize() {
  local directory
  storage_prepare_tmp || return 1
  for directory in bin lib runtime modules logs backups backups/upgrades systemd migrations; do
    storage_private_directory "${SB_DATA_ROOT}/${directory}" || return 1
  done
  export TMPDIR="${SB_DATA_ROOT}/tmp"
}

# Call only from a subshell/child runner: auxiliary tools must not inherit the
# operator's home or working directory for their default caches and state.
storage_enter_module_workspace() {
  local workspace=$1
  [[ "${workspace}" == "${SB_DATA_ROOT}" || "${workspace}" == "${SB_DATA_ROOT}/"* ]] || return 1
  storage_private_directory "${workspace}" || return 1
  export HOME="${workspace}"
  export XDG_CACHE_HOME="${workspace}/.cache"
  export XDG_CONFIG_HOME="${workspace}/.config"
  export XDG_STATE_HOME="${workspace}/.local/state"
  export XDG_DATA_HOME="${workspace}/.local/share"
  cd -- "${workspace}" || return 1
}

# Preserve explicit same-directory staging, but put anonymous and legacy /tmp
# workspaces under the private data root. Keep the real mktemp command visible
# so existing fault-injection fixtures can exercise it.
storage_mktemp() {
  local argument template='' has_template=n
  local -a arguments=()
  storage_prepare_tmp || return 1
  for argument in "$@"; do
    case "${argument}" in
      "${SB_DATA_ROOT}/"*) has_template=y ;;
      /tmp/sbv-*|/tmp/sing-box-vps-state.*|/tmp/subman-api.*)
        argument="${SB_DATA_ROOT}/tmp/${argument#/tmp/}"; has_template=y ;;
      /*) has_template=y ;;
      -*) ;;
      *) template=${argument}; has_template=y ;;
    esac
    arguments+=("${argument}")
  done
  if [[ "${has_template}" == n ]]; then
    arguments+=("${SB_DATA_ROOT}/tmp/tmp.XXXXXXXXXX")
  elif [[ -n "${template}" && "${template}" != */* ]]; then
    arguments=("${arguments[@]:0:${#arguments[@]}-1}" "${SB_DATA_ROOT}/tmp/${template}")
  fi
  TMPDIR="${SB_DATA_ROOT}/tmp" mktemp "${arguments[@]}"
}

storage_publish_system_link() {
  local link=${1:-} target=${2:-} parent
  [[ "${target}" == "${SB_DATA_ROOT}/"* && -f "${target}" && ! -L "${target}" ]] || return 1
  storage_selinux_label "${target}" || return 1
  parent=$(dirname -- "${link}") || return 1
  storage_directory_is_safe "${parent}" || return 1
  [[ -d "${parent}" ]] || return 1
  if [[ -L "${link}" ]]; then
    [[ "$(readlink -- "${link}")" == "${target}" ]] || return 1
    return 0
  fi
  # Legacy regular files are replaced only by the migration transaction after
  # its ownership checks and backup, never by this publishing helper.
  [[ ! -e "${link}" ]] || return 1
  # Creating the final symlink with ln is atomic and refuses a racing existing
  # destination; it needs neither executable staging nor cross-filesystem mv.
  ln -sT -- "${target}" "${link}" || return 1
  [[ -L "${link}" && "$(readlink -- "${link}")" == "${target}" ]]
}

storage_publish_system_links() {
  case "${1:-all}" in
    sbv) storage_publish_system_link "${SBV_LINK_PATH}" "${SBV_BIN_PATH}" ;;
    sing-box) storage_publish_system_link "${SINGBOX_LINK_PATH}" "${SINGBOX_BIN_PATH}" ;;
    service) storage_publish_system_link "${SINGBOX_SERVICE_LINK_PATH}" "${SINGBOX_SERVICE_FILE}" ;;
    all)
      storage_publish_system_links sbv && storage_publish_system_links sing-box && storage_publish_system_links service
      ;;
    *) return 1 ;;
  esac
}

storage_remove_system_link() {
  local link=${1:-} target=${2:-}
  [[ "${target}" == "${SB_DATA_ROOT}/"* ]] || return 1
  if [[ -L "${link}" ]]; then
    [[ "$(readlink -- "${link}")" == "${target}" ]] || return 1
    rm -f -- "${link}" || return 1
  elif [[ -e "${link}" ]]; then
    printf '[ERROR] 系统入口不属于当前安装，已保留：%s\n' "${link}" >&2
    return 1
  fi
}

storage_system_link_is_owned() {
  local link=${1:-} target=${2:-}
  [[ "${target}" == "${SB_DATA_ROOT}/"* ]] || return 1
  [[ ! -e "${link}" && ! -L "${link}" ]] ||
    [[ -L "${link}" && "$(readlink -- "${link}")" == "${target}" ]]
}

storage_publish_library_link() {
  local library="${SB_DATA_ROOT}/lib/libcronet.so" link="${SB_DATA_ROOT}/bin/libcronet.so"
  if [[ -f "${library}" && ! -L "${library}" ]]; then
    storage_publish_system_link "${link}" "${library}"
  elif [[ ! -e "${library}" && ! -L "${library}" ]]; then
    storage_remove_system_link "${link}" "${library}"
  else
    return 1
  fi
}

# SELinux stays enabled. Local mappings belong only to this private subtree;
# staging files receive the final path's context before an atomic rename.
storage_selinux_active() {
  local mode
  if command -v getenforce >/dev/null 2>&1; then
    mode=$(getenforce) || return 2
    case "${mode}" in Enforcing|Permissive) return 0 ;; Disabled) return 1 ;; *) return 2 ;; esac
  fi
  [[ ! -e /sys/fs/selinux/enforce ]] || return 2
  return 1
}

storage_selinux_tools() {
  local tool
  for tool in semanage restorecon matchpathcon chcon jq; do
    command -v "${tool}" >/dev/null 2>&1 || {
      printf '[ERROR] SELinux 工具缺失：%s；请先安装 policycoreutils 及当前发行版的 policycoreutils-python(-utils)，未更改 SELinux 模式。\n' "${tool}" >&2
      return 1
    }
  done
}

storage_selinux_root_regex() {
  local character result='' index
  for ((index=0;index<${#SB_DATA_ROOT};index++)); do
    character=${SB_DATA_ROOT:index:1}
    case "${character}" in
      '.'|'['|']'|'('|')'|'{'|'}'|'*'|'+'|'?'|'^'|'$'|'|'|'\') result+="\\${character}" ;;
      *) result+="${character}" ;;
    esac
  done
  printf '%s' "${result}"
}

storage_selinux_private_type() {
  case "${1:-}" in
    "${SB_DATA_ROOT}/bin"|"${SB_DATA_ROOT}/bin/"*) printf bin_t ;;
    "${SB_DATA_ROOT}/lib"|"${SB_DATA_ROOT}/lib/"*) printf lib_t ;;
    "${SB_DATA_ROOT}/systemd"|"${SB_DATA_ROOT}/systemd/"*) printf systemd_unit_file_t ;;
    "${SB_DATA_ROOT}"|"${SB_DATA_ROOT}/"*) printf var_lib_t ;;
    *) return 1 ;;
  esac
}

storage_selinux_system_path() {
  case "${1:-}" in
    "${SBV_LINK_PATH}"|"${SINGBOX_LINK_PATH}"|"${SINGBOX_SERVICE_LINK_PATH}"|"$(dirname "$(dirname "${SINGBOX_LINK_PATH}")")/lib/libcronet.so") return 0 ;;
    *) return 1 ;;
  esac
}

storage_selinux_prepare() (
  local active_status=0 root_regex rules inventory records probes_file='' rule expression type directory
  storage_selinux_active || active_status=$?
  case "${active_status}" in 1) return 0 ;; 0) ;; *) return 1 ;; esac
  storage_selinux_tools || return 1
  storage_directory_is_safe "${SB_DATA_ROOT}" || return 1
  root_regex=$(storage_selinux_root_regex) || return 1
  rules=$(jq -cn --arg root "${root_regex}" '[
    {spec:($root+"(/.*)?"),type:"var_lib_t"},
    {spec:($root+"/bin(/.*)?"),type:"bin_t"},
    {spec:($root+"/lib(/.*)?"),type:"lib_t"},
    {spec:($root+"/systemd(/.*)?"),type:"systemd_unit_file_t"}]') || return 1
  inventory=$(LC_ALL=C semanage fcontext -l -C) || return 1
  # Read the stable C-locale table as data, including local equivalences. Never
  # eval semanage's shell export or modify an administrator's existing mapping.
  records=$(printf '%s\n' "${inventory}" | jq -Rsc '
    split("\n") | map(select((test("^\\s*$")|not) and (test("^SELinux (fcontext|Local fcontext Equivalence)")|not))) |
    map(if test(" = ") then (capture("^(?<destination>.+) = (?<source>.+)$") // error("invalid_fcontext_equivalence"))
      else (capture("^(?<spec>.+?)\\s+(?<kind>all files|regular file|directory|character device|block device|socket|symbolic link|named pipe)\\s+(?<context>[^[:space:]]+:[^[:space:]]+:[^[:space:]]+:[^[:space:]]+)\\s*$") // error("invalid_fcontext_record")) end)') || return 1
  # Local rules use newest-first matching. Adding the broad rule after an
  # existing child rule would silently override that administrator mapping.
  if ! jq -e --argjson rules "${rules}" '
    any(.[]; .spec?==$rules[0].spec) or
    all(.[]; . as $entry | all($rules[1:][]; .spec!=$entry.spec))' <<< "${records}" >/dev/null; then
    printf '[ERROR] SELinux 已有项目子目录规则但缺少根规则；已保留原有效映射，未新增或重排规则。\n' >&2
    return 1
  fi
  probes_file=$(mktemp "${SB_DATA_ROOT}/tmp/.selinux-probes.XXXXXXXX") || return 1
  trap 'rm -f -- "${probes_file}"' EXIT
  find "${SB_DATA_ROOT}" -xdev -print0 | jq -Rsc --arg root "${SB_DATA_ROOT}" '
    split("\u0000") | map(select(length>0)) + [$root,$root+"/bin/sing-box",$root+"/lib/libcronet.so",$root+"/systemd/sing-box.service",$root+"/runtime/config.json"]' > "${probes_file}" || return 1
  if ! jq -e --arg root "${SB_DATA_ROOT}" --arg escaped "${root_regex}" --argjson rules "${rules}" --slurpfile probes "${probes_file}" '
    all(.[]; . as $entry |
      if has("destination") then
        ($entry.destination==$root or ($entry.destination|startswith($root+"/")) or ($root|startswith($entry.destination+"/"))) | not
      elif any($rules[]; .spec==$entry.spec) then
        .kind=="all files" and any($rules[]; .spec==$entry.spec and $entry.context==("system_u:object_r:"+.type+":s0"))
      else
        (($entry.spec|contains($root) or contains($escaped)) or any($probes[0][]; test("^(?:"+$entry.spec+")$"))) | not
      end)' <<< "${records}" >/dev/null; then
    printf '[ERROR] SELinux 本地文件上下文与项目目录冲突；已保留管理员规则，未覆盖。\n' >&2
    return 1
  fi
  while IFS= read -r rule; do
    expression=$(jq -r .spec <<< "${rule}") || return 1
    type=$(jq -r .type <<< "${rule}") || return 1
    if ! jq -e --arg expression "${expression}" 'any(.[]; .spec?==$expression)' <<< "${records}" >/dev/null; then
      # Keep successful project-only additions if a later step fails: backups
      # and recovery material may already need them, and retries are idempotent.
      semanage fcontext -a -t "${type}" "${expression}" || return 1
    fi
  done < <(jq -c '.[]' <<< "${rules}")
  for directory in "${SB_DATA_ROOT}" "${SB_DATA_ROOT}/bin" "${SB_DATA_ROOT}/lib" "${SB_DATA_ROOT}/systemd" "${SB_PROJECT_DIR}"; do
    [[ ! -e "${directory}" ]] || storage_selinux_label "${directory}" "${directory}" directory-only || return 1
  done
)

storage_selinux_label() {
  local path=${1:-} final=${2:-${1:-}} scope=${3:-} active_status=0 expected type actual
  storage_selinux_active || active_status=$?
  case "${active_status}" in 1) return 0 ;; 0) ;; *) return 1 ;; esac
  storage_selinux_tools || return 1
  [[ "${path}" == "${SB_DATA_ROOT}" || "${path}" == "${SB_DATA_ROOT}/"* ]] || return 1
  [[ ! -L "${path}" && ( -f "${path}" || -d "${path}" ) ]] || return 1
  storage_directory_is_safe "$(dirname -- "${path}")" || return 1
  [[ "${final}" != *'/../'* && "${final}" != *'/./'* && "${final}" != *$'\n'* && "${final}" != *$'\r'* ]] || return 1
  if type=$(storage_selinux_private_type "${final}"); then :
  elif storage_selinux_system_path "${final}"; then type=''
  else return 1
  fi
  expected=$(matchpathcon -n "${final}") || return 1
  [[ -n "${expected}" && "${expected}" != '<<none>>' ]] || return 1
  if [[ -n "${type}" ]]; then
    actual=${expected#*:*:}; actual=${actual%%:*}
    [[ "${actual}" == "${type}" ]] || {
      printf '[ERROR] SELinux 项目路径的有效上下文与受管规则不一致，未发布候选文件。\n' >&2
      return 1
    }
  fi
  if [[ "${path}" == "${final}" ]]; then
    if [[ "${path}" == "${SB_PROJECT_DIR}" && "${scope}" != directory-only ]]; then
      # Migration calls this only on a validated, link-free copied runtime.
      [[ -z "$(find "${path}" -type l -print -quit)" ]] || return 1
      restorecon -RF -- "${path}" || return 1
    else restorecon -F -- "${path}" || return 1
    fi
    matchpathcon -V "${path}" >/dev/null || return 1
  else
    chcon "${expected}" -- "${path}" || return 1
    actual=$(stat -c %C -- "${path}") || return 1
    [[ "${actual}" == "${expected}" ]] || return 1
  fi
}

storage_selinux_restore_system_path() {
  local path=${1:-} active_status=0
  storage_selinux_active || active_status=$?
  case "${active_status}" in 1) return 0 ;; 0) ;; *) return 1 ;; esac
  storage_selinux_tools || return 1
  storage_selinux_system_path "${path}" || return 1
  [[ -f "${path}" && ! -L "${path}" ]] || return 1
  storage_directory_is_safe "$(dirname -- "${path}")" || return 1
  restorecon -F -- "${path}" && matchpathcon -V "${path}" >/dev/null
}
