#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install

catalog=$(main commands --json)
jq -e '
  .ok and .command=="commands" and .data.catalog.schema_version==1 and
  (.data.catalog.operations as $ops |
    ($ops|length)>40 and ($ops|map(.id)|unique|length)==($ops|length) and
    all($ops[];
      (.automation|IN("structured","interactive_only","legacy_cli")) and
      (.mutation|type)=="boolean" and (.sensitive|type)=="boolean" and
      (.parameters|type)=="array" and (.cas|IN("none","revision","fingerprint","journal")) and
      (.docs|type)=="string" and
      (if .automation=="structured" then
        (.command|type)=="string" and (.agent_command|type)=="string" and .output.format=="json_envelope"
       else (.reason|type)=="string" end) and
      (if .automation=="structured" and .mutation then .confirmation=="--yes" else true end)) and
    any($ops[]; .id=="instance.export" and .sensitive) and
    any($ops[]; .id=="routing.export" and .sensitive) and
    any($ops[]; .id=="service.logs" and .sensitive) and
    any($ops[]; .id=="reality.write" and .automation=="interactive_only" and .service_impact=="restart_possible") and
    any($ops[]; .id=="system.media" and .menu=="12 -> 4" and .mutation and .executes_remote_code) and
    any($ops[]; .id=="core.uninstall" and .service_impact=="stop_and_remove") and
    any($ops[]; .id=="system.stack" and .service_impact=="restart"))
' <<< "${catalog}" >/dev/null

# Discovery remains available without installed service, root or clean journals.
agent_current_user_is_root() { return 1; }
mkdir "${SB_ROUTING_TRANSACTION_DIR}"
for args in 'commands --json' 'capabilities --json' 'schema routing.apply --json'; do
  read -r -a argv <<< "${args}"
  result=$(main "${argv[@]}")
  jq -e '.ok' <<< "${result}" >/dev/null
done
rmdir "${SB_ROUTING_TRANSACTION_DIR}"
agent_current_user_is_root() { return 0; }
result=$(main schema instance.export --json)
jq -e '.data.operation.id=="instance.export" and .data.operation.sensitive' <<< "${result}" >/dev/null
if result=$(main schema absent-operation --json); then exit 1; fi
jq -e '.error=="unknown_operation"' <<< "${result}" >/dev/null
capabilities=$(main capabilities --json)
[[ "$(jq -Sc .operation_catalog <<< "${capabilities}")" == "$(jq -Sc .data.catalog <<< "${catalog}")" ]]

# Every advertised canonical operation resolves to its documented compatibility
# route. Replace the dispatch boundary, never touch real services or files.
original_dispatch=$(declare -f agent_dispatch)
agent_dispatch() { printf '%s\n' "$@" | jq -Rs 'split("\n")[:-1]'; }
while IFS=$'\t' read -r command legacy; do
  read -r -a canonical_args <<< "${command}"
  read -r -a legacy_args <<< "${legacy}"
  if [[ "${command}" == 'subman sync' ]]; then
    actual=$(canonical_cli_dispatch "${canonical_args[@]}" --json --yes)
  else
    actual=$(canonical_cli_dispatch "${canonical_args[@]}" --json)
  fi
  expected=$(printf '%s\n' "${legacy_args[@]}" --json | jq -Rs 'split("\n")[:-1]')
  [[ "${actual}" == "${expected}" ]] || { printf 'mapping failed: %s\n' "${command}" >&2; exit 1; }
done < <(jq -r '.data.catalog.operations[]|select(.automation=="structured")|[.command,.agent_command]|@tsv' <<< "${catalog}")
eval "${original_dispatch}"

# Advertised compatibility paths must reach actual argument validators/handlers,
# not only map back to a string. With all required flags absent, no operation is
# permitted to execute or mutate anything.
while IFS= read -r legacy; do
  read -r -a legacy_args <<< "${legacy}"
  if result=$(agent_cli "${legacy_args[@]}"); then
    printf 'missing arguments accepted: %s\n' "${legacy}" >&2; exit 1
  fi
  jq -e '.ok==false and (.error!= "unknown_command") and (.error!="internal_error")' <<< "${result}" >/dev/null
done < <(jq -r '.data.catalog.operations[]|select(.automation=="structured")|.agent_command' <<< "${catalog}")

# A typo or trailing argument must fail before lock, root checks or menu work.
check_root() { printf 'unexpected root check\n' >&2; return 99; }
acquire_managed_write_lock() { printf 'unexpected lock acquisition\n' >&2; return 99; }
show_banner() { printf 'unexpected interactive menu\n' >&2; return 99; }
ensure_sbv_command_installed() { printf 'unexpected installation\n' >&2; return 99; }
for args in 'typo --json' 'core missing --json' 'menu extra' 'help extra' 'update sbv extra' 'update sing-box latest extra' 'update-sbv extra' 'uninstall --yes' 'subman sync --json'; do
  read -r -a argv <<< "${args}"
  if result=$(main "${argv[@]}" 2>"${TMP_DIR}/error"); then
    printf 'unexpected success: %s\n' "${args}" >&2; exit 1
  fi
  [[ ! -s "${TMP_DIR}/error" ]]
  jq -e '.ok==false and (.error|IN("unknown_command","invalid_arguments","confirmation_required"))' <<< "${result}" >/dev/null
done
bash "${REPO_ROOT}/scripts/build-command-docs.sh" --check
printf 'command catalog, canonical aliases, safe discovery and strict parsing passed\n'
