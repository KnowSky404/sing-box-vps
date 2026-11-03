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
