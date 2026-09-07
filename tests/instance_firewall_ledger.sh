#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"
trap 'printf "instance firewall ledger test failed at line %s\n" "${LINENO}" >&2' ERR

BACKEND_LOG="${TMP_DIR}/backend.log"
UFW_RULES="${TMP_DIR}/ufw.rules"
FIREWALLD_RULES="${TMP_DIR}/firewalld.rules"
FIREWALLD_RUNTIME_RULES="${TMP_DIR}/firewalld.runtime.rules"
FIREWALLD_PERMANENT_RULES="${TMP_DIR}/firewalld.permanent.rules"
IPTABLES_RULES="${TMP_DIR}/iptables.rules"
IP6TABLES_RULES="${TMP_DIR}/ip6tables.rules"
: > "${BACKEND_LOG}"
: > "${UFW_RULES}"
: > "${FIREWALLD_RULES}"
: > "${FIREWALLD_RUNTIME_RULES}"
: > "${FIREWALLD_PERMANENT_RULES}"
: > "${IPTABLES_RULES}"
: > "${IP6TABLES_RULES}"

record_rule() {
  local file=$1 value=$2
  grep -Fqx -- "${value}" "${file}" || printf '%s\n' "${value}" >> "${file}"
}

remove_rule() {
  local file=$1 value=$2 candidate
  candidate=$(mktemp "${file}.XXXXXX")
  awk -v value="${value}" '$0 != value' "${file}" > "${candidate}"
  mv -f -- "${candidate}" "${file}"
}

ufw_upsert_rule() {
  local file=$1 value=$2 key candidate
  key=${value%% # *}
  candidate=$(mktemp "${file}.XXXXXX")
  awk -v key="${key}" 'function rule_key(line, marker) {
    marker=index(line, " # "); return marker ? substr(line, 1, marker - 1) : line
  } rule_key($0) != key' "${file}" > "${candidate}"
  printf '%s\n' "${value}" >> "${candidate}"
  mv -f -- "${candidate}" "${file}"
}

ufw_delete_rule() {
  local file=$1 key=$2 candidate
  candidate=$(mktemp "${file}.XXXXXX")
  awk -v key="${key}" 'function rule_key(line, marker) {
    marker=index(line, " # "); return marker ? substr(line, 1, marker - 1) : line
  } rule_key($0) != key' "${file}" > "${candidate}"
  mv -f -- "${candidate}" "${file}"
}

ufw() {
  if [[ "${1:-}" == status ]]; then
    if [[ "${UFW_MOCK_INACTIVE:-0}" == 1 ]]; then
      printf 'Status: inactive\n'
      return 0
    fi
    printf 'Status: active\n'
    [[ -s "${UFW_RULES}" ]] && sed -n 'p' "${UFW_RULES}"
    return 0
  fi
  printf 'ufw %s\n' "$*" >> "${BACKEND_LOG}"
  local action=${1:-} token proto='' address='' port='' comment='' value status_action
  shift || true
  while [[ $# -gt 0 ]]; do
    token=$1
    case "${token}" in
      proto) proto=${2:-}; shift 2 || true ;;
      to) address=${2:-}; shift 2 || true ;;
      port) port=${2:-}; shift 2 || true ;;
      comment) comment=${2:-}; shift 2 || true ;;
      *) shift ;;
    esac
  done
  [[ -n "${proto}" && -n "${address}" && -n "${port}" ]] || return 2
  [[ "${address}" == 0.0.0.0/0 ]] && value=Anywhere
  [[ "${address}" == ::/0 ]] && value='Anywhere (v6)'
  status_action=${UFW_MOCK_STATUS_ACTION:-ALLOW}
  if [[ -n "${value:-}" ]]; then
    value="${port}/${proto} ${status_action} ${value}"
  else
    value="${address} ${port}/${proto} ${status_action} Anywhere"
  fi
  [[ -n "${comment}" ]] && value="${value} # ${comment}"
  if [[ "${UFW_NO_EFFECT:-0}" == 1 ]]; then
    return 0
  fi
  case "${action}" in
    allow) ufw_upsert_rule "${UFW_RULES}" "${value}" ;;
    delete)
      local candidate=${value%% # *}
      ufw_delete_rule "${UFW_RULES}" "${candidate}"
      ;;
    *) return 2 ;;
  esac
}

firewall_cmd_mock() {
  if [[ "${1:-}" == --state ]]; then
    [[ "${FIREWALLD_MOCK_INACTIVE:-0}" == 1 ]] && return 1
    return 0
  fi
  printf 'firewalld %s\n' "$*" >> "${BACKEND_LOG}"
  [[ "${1:-}" == --reload ]] && return 0
  local option=${1:-} store="${FIREWALLD_RUNTIME_RULES}"
  if [[ "${option}" == --permanent ]]; then
    store="${FIREWALLD_PERMANENT_RULES}"
    option=${2:-}
  fi
  case "${option}" in
    --query-port=*) grep -Fqx -- "${option#--query-port=}" "${store}" ;;
    --add-port=*) record_rule "${store}" "${option#--add-port=}" ;;
    --remove-port=*) remove_rule "${store}" "${option#--remove-port=}" ;;
    *) return 2 ;;
  esac
}

firewall-cmd() { firewall_cmd_mock "$@"; }

iptables_mock() {
  local file=$1 command key
  shift
  command=${1:-}
  shift || true
  key="$*"
  printf '%s %s\n' "$(basename "${file}")" "${command} ${key}" >> "${BACKEND_LOG}"
  case "${command}" in
    -C) grep -Fqx -- "${key}" "${file}" ;;
    -I) record_rule "${file}" "${key}" ;;
    -D) remove_rule "${file}" "${key}" ;;
    *) return 2 ;;
  esac
}

iptables() { iptables_mock "${IPTABLES_RULES}" "$@"; }
ip6tables() { iptables_mock "${IP6TABLES_RULES}" "$@"; }

for firewalld_port in 32100 32101 32105; do
  record_rule "${FIREWALLD_RUNTIME_RULES}" "${firewalld_port}/tcp"
  record_rule "${FIREWALLD_PERMANENT_RULES}" "${firewalld_port}/tcp"
done
record_rule "${FIREWALLD_RUNTIME_RULES}" '39999/tcp'
UFW_MOCK_INACTIVE=1
FIREWALLD_MOCK_INACTIVE=1

old_config="${TMP_DIR}/old.json"
new_config="${TMP_DIR}/new.json"
journal="${TMP_DIR}/transaction.json"
jq -n '{inbounds:[]}' > "${old_config}"
jq -n '{inbounds:[
  {type:"mixed",tag:"public-v4",listen:"192.0.2.10",listen_port:32100},
  {type:"mixed",tag:"public-v6",listen:"2001:db8::10",listen_port:32101},
  {type:"mixed",tag:"wildcard-v4",listen:"0.0.0.0",listen_port:32105},
  {type:"mixed",tag:"loopback",listen:"127.0.0.1",listen_port:32102}
]}' > "${new_config}"

for api in instance_firewall_prepare instance_firewall_apply instance_firewall_rollback instance_firewall_commit; do
  declare -F "${api}" >/dev/null || { printf 'missing API: %s\n' "${api}" >&2; exit 1; }
done

instance_firewall_prepare "${old_config}" "${new_config}" "${journal}"
[[ $(stat -c '%a' "${journal}") == 600 ]]
! grep -Eq 'ufw allow|firewalld --permanent --add-port|iptables -I|ip6tables -I' "${BACKEND_LOG}"
jq -e '
  .status == "prepared" and
  ([.operations[] | select(.action == "create")] | length == 3) and
  ([.operations[] | select(.backend == "firewalld")] | length == 3 and all(.action == "unavailable")) and
  ([.backend_statuses[] | select(.backend == "ufw" or .backend == "firewalld") | .state] | all(. == "unavailable")) and
  ([.operations[] | select(.address == "127.0.0.1")] | length == 0) and
  ([.operations[] | select(.backend == "ip6tables" and .family == "ipv6")] | length == 1) and
  ([.after_ledger.rules[] | select(.backend == "ip6tables")] | length == 1)
' "${journal}" >/dev/null

instance_firewall_apply "${journal}"
[[ -s "${BACKEND_LOG}" ]]
! grep -Fq '32102' "${BACKEND_LOG}"
grep -Fq 'ip6tables.rules -I' "${BACKEND_LOG}"
jq -e '.status == "applied" and (.operations | all(.state == "applied" or .state == "preserved"))' "${journal}" >/dev/null
jq -e '.schema_version == 1 and (.rules | length == 3)' "${SB_PROJECT_DIR}/managed-firewall.json" >/dev/null
grep -Fqx '39999/tcp' "${FIREWALLD_RUNTIME_RULES}"
! grep -Eq 'firewalld --permanent --(add|remove)-port|firewalld --reload' "${BACKEND_LOG}"

instance_firewall_commit "${journal}"
jq -e '.status == "committed"' "${journal}" >/dev/null

# Selecting both UFW and firewalld is ambiguous and fails before any backend
# inspection or mutation.
rm -f -- "${journal}" "${SB_PROJECT_DIR}/managed-firewall.json"
: > "${BACKEND_LOG}"
jq -n '{inbounds:[{type:"mixed",tag:"missing-firewalld",listen:"192.0.2.13",listen_port:32106}]}' > "${new_config}"
unset UFW_MOCK_INACTIVE FIREWALLD_MOCK_INACTIVE
if instance_firewall_prepare "${old_config}" "${new_config}" "${journal}"; then
  printf 'expected frontend conflict prepare failure\n' >&2
  exit 1
fi
jq -e '.status == "prepare_failed" and .error_code == "backend_conflict"' "${journal}" >/dev/null
! grep -Eq 'ufw status|firewalld --query|iptables -C|ip6tables -C|ufw allow|firewalld --(permanent )?--(add|remove)-port|iptables -I|ip6tables -I' "${BACKEND_LOG}"

# With UFW inactive, firewalld is a read-only frontend: both stores are
# required and a missing rule remains a manual-setup failure.
UFW_MOCK_INACTIVE=1
if instance_firewall_prepare "${old_config}" "${new_config}" "${journal}"; then
  printf 'expected missing firewalld prepare failure\n' >&2
  exit 1
fi
jq -e '.status == "prepare_failed" and .error_code == "firewalld_requires_manual_setup"' "${journal}" >/dev/null
! grep -Eq 'ufw allow|firewalld --(permanent )?--(add|remove)-port|firewalld --reload|iptables -I|ip6tables -I' "${BACKEND_LOG}"

# A preexisting firewalld rule in both stores is preserved and remains
# unowned; raw backends are external-managed and are never queried.
rm -f -- "${journal}" "${SB_PROJECT_DIR}/managed-firewall.json"
: > "${BACKEND_LOG}"
jq -n '{inbounds:[{type:"mixed",tag:"preexisting-firewalld",listen:"192.0.2.10",listen_port:32105}]}' > "${new_config}"
instance_firewall_prepare "${old_config}" "${new_config}" "${journal}"
jq -e '
  ([.operations[] | select(.backend == "firewalld")] | length == 1 and all(.action == "preserve" and .ownership == "preexisting")) and
  ([.operations[] | select(.backend == "iptables" or .backend == "ip6tables")] | all(.action == "unavailable")) and
  ([.after_ledger.rules[] | select(.backend == "firewalld")] | length == 0)
' "${journal}" >/dev/null
! grep -Eq 'iptables -C|ip6tables -C|iptables -I|ip6tables -I' "${BACKEND_LOG}"

# A previously recorded firewalld rule is unsupported because the plain port
# API cannot prove ownership after an external delete/recreate.
rm -f -- "${journal}"
firewalld_comment=$(instance_firewall_rule_comment firewalld any tcp 32100 '*')
jq -n --arg comment "${firewalld_comment}" \
  '{schema_version:1,rules:[{backend:"firewalld",family:"any",address:"*",transport:"tcp",port:32100,comment:$comment,refs:[{owner:"old",protocol:"mixed",address:"192.0.2.10",transport:"tcp",port:32100}]}]}' \
  > "${SB_PROJECT_DIR}/managed-firewall.json"
chmod 600 "${SB_PROJECT_DIR}/managed-firewall.json"
: > "${BACKEND_LOG}"
jq -n '{inbounds:[]}' > "${new_config}"
if instance_firewall_prepare "${old_config}" "${new_config}" "${journal}"; then
  printf 'expected owned firewalld prepare failure\n' >&2
  exit 1
fi
jq -e '.status == "prepare_failed" and .error_code == "firewalld_owned_unsupported"' "${journal}" >/dev/null
! grep -Eq 'ufw allow|firewalld --(permanent )?--(add|remove)-port|firewalld --reload|iptables -I|ip6tables -I' "${BACKEND_LOG}"
rm -f -- "${journal}" "${SB_PROJECT_DIR}/managed-firewall.json"

# An absent firewalld backend is an unavailable warning, not a reason to
# reject otherwise usable UFW/iptables changes.
unset UFW_MOCK_INACTIVE
unset -f firewall-cmd
jq -n '{inbounds:[{type:"mixed",tag:"absent-firewalld",listen:"192.0.2.14",listen_port:32107}]}' > "${new_config}"
instance_firewall_prepare "${old_config}" "${new_config}" "${journal}"
jq -e '
  ([.backend_statuses[] | select(.backend == "firewalld")][0].state == "unavailable") and
  ([.diagnostics[] | select(.backend == "firewalld" and .code == "backend_unavailable")] | length == 1) and
  ([.operations[] | select(.backend == "firewalld")] | all(.action == "unavailable"))
' "${journal}" >/dev/null
instance_firewall_apply "${journal}"
rm -f -- "${journal}" "${SB_PROJECT_DIR}/managed-firewall.json"

# An inactive firewalld backend has the same bounded unavailable behavior.
firewall-cmd() { firewall_cmd_mock "$@"; }
FIREWALLD_MOCK_INACTIVE=1
jq -n '{inbounds:[{type:"mixed",tag:"inactive-firewalld",listen:"192.0.2.15",listen_port:32108}]}' > "${new_config}"
instance_firewall_prepare "${old_config}" "${new_config}" "${journal}"
jq -e '([.backend_statuses[] | select(.backend == "firewalld")][0].state == "unavailable") and ([.operations[] | select(.backend == "firewalld")] | all(.action == "unavailable"))' "${journal}" >/dev/null
instance_firewall_apply "${journal}"
unset FIREWALLD_MOCK_INACTIVE
rm -f -- "${journal}" "${SB_PROJECT_DIR}/managed-firewall.json"

# A user-owned coarse rule is observed and is never entered into the ledger.
FIREWALLD_MOCK_INACTIVE=1
record_rule "${FIREWALLD_RUNTIME_RULES}" '32103/tcp'
record_rule "${FIREWALLD_PERMANENT_RULES}" '32103/tcp'
record_rule "${FIREWALLD_RUNTIME_RULES}" '32110/tcp'
record_rule "${FIREWALLD_PERMANENT_RULES}" '32110/tcp'
record_rule "${FIREWALLD_RUNTIME_RULES}" '32111/tcp'
record_rule "${FIREWALLD_PERMANENT_RULES}" '32111/tcp'
record_rule "${FIREWALLD_RUNTIME_RULES}" '32112/tcp'
record_rule "${FIREWALLD_PERMANENT_RULES}" '32112/tcp'
record_rule "${UFW_RULES}" '192.0.2.11 32103/tcp ALLOW Anywhere'
record_rule "${UFW_RULES}" '192.0.2.10 32123/tcp ALLOW OUT Anywhere'
record_rule "${UFW_RULES}" '198.51.100.20 32111/tcp ALLOW IN Anywhere # user-marker'
record_rule "${UFW_RULES}" '192.0.2.10 32115/tcp ALLOW Anywhere # sbv-instance-test-marker-suffix'
record_rule "${UFW_RULES}" '2001:db8::12 32112/tcp ALLOW Anywhere (v6)'
jq -n '{inbounds:[
  {type:"mixed",tag:"user-rule",listen:"192.0.2.11",listen_port:32103},
  {type:"mixed",tag:"user-broad-rule",listen:"192.0.2.17",listen_port:32110},
  {type:"mixed",tag:"wrong-target-rule",listen:"192.0.2.10",listen_port:32111},
  {type:"mixed",tag:"compressed-ipv6-rule",listen:"2001:db8::12",listen_port:32112}
]}' > "${new_config}"
record_rule "${UFW_RULES}" '32110/tcp ALLOW Anywhere'
if instance_firewall_rule_query ufw ipv4 tcp 32123 192.0.2.10 '' 0; then
  printf 'outbound UFW rule was incorrectly treated as inbound\n' >&2
  exit 1
fi
if instance_firewall_rule_query ufw ipv4 tcp 32115 192.0.2.10 sbv-instance-test-marker 1; then
  printf 'UFW marker prefix was incorrectly treated as owned\n' >&2
  exit 1
fi
instance_firewall_prepare "${old_config}" "${new_config}" "${journal}"
jq -e '
  ([.operations[] | select(.backend == "ufw")] | length == 4 and
   ([.[] | select(.port == 32111)] | all(.ownership == "owned" and .action == "create")) and
   ([.[] | select(.port != 32111)] | all(.ownership == "preexisting" and .action == "preserve"))) and
  ([.after_ledger.rules[] | select(.backend == "ufw")] | length == 1)
' "${journal}" >/dev/null

# A positively marked UFW rule is removed by rollback using its complete
# destination key; comment text is not used as the deletion identity.
rm -f -- "${journal}" "${SB_PROJECT_DIR}/managed-firewall.json"
record_rule "${FIREWALLD_RUNTIME_RULES}" '32114/tcp'
record_rule "${FIREWALLD_PERMANENT_RULES}" '32114/tcp'
jq -n '{inbounds:[{type:"mixed",tag:"rollback-owned",listen:"192.0.2.20",listen_port:32114}]}' > "${new_config}"
instance_firewall_prepare "${old_config}" "${new_config}" "${journal}"
instance_firewall_apply "${journal}"
created_ufw_rule=$(grep -F '32114/tcp' "${UFW_RULES}")
[[ "${created_ufw_rule}" == *'sbv-instance-'* ]]
: > "${BACKEND_LOG}"
instance_firewall_rollback "${journal}"
! grep -Fq '32114/tcp' "${UFW_RULES}"
grep -Fq 'ufw delete' "${BACKEND_LOG}"

# If an owned rule is externally replaced with an unowned rule at the same
# destination (including a changed comment), rollback must not delete it.
rm -f -- "${journal}" "${SB_PROJECT_DIR}/managed-firewall.json"
record_rule "${FIREWALLD_RUNTIME_RULES}" '32113/tcp'
record_rule "${FIREWALLD_PERMANENT_RULES}" '32113/tcp'
jq -n '{inbounds:[{type:"mixed",tag:"rollback-replaced",listen:"192.0.2.19",listen_port:32113}]}' > "${new_config}"
instance_firewall_prepare "${old_config}" "${new_config}" "${journal}"
instance_firewall_apply "${journal}"
created_ufw_rule=$(grep -F '32113/tcp' "${UFW_RULES}")
[[ "${created_ufw_rule}" == *'sbv-instance-'* ]]
ufw_delete_rule "${UFW_RULES}" "${created_ufw_rule%% # *}"
ufw_upsert_rule "${UFW_RULES}" "${created_ufw_rule%%# *}# replacement"
: > "${BACKEND_LOG}"
if instance_firewall_rollback "${journal}"; then
  printf 'expected replaced-rule rollback uncertainty\n' >&2
  exit 1
fi
jq -e '.status == "rollback_uncertain" and ([.operations[] | select(.backend == "ufw")] | any(.rollback_state == "uncertain"))' "${journal}" >/dev/null
grep -Fqx "${created_ufw_rule%%# *}# replacement" "${UFW_RULES}"
! grep -Fq 'ufw delete' "${BACKEND_LOG}"
rm -f -- "${journal}" "${SB_PROJECT_DIR}/managed-firewall.json"

# A backend returning success without changing state is unconfirmed and must
# remain recoverable rather than being recorded as applied.
jq -n '{inbounds:[{type:"mixed",tag:"no-effect-create",listen:"192.0.2.21",listen_port:32117}]}' > "${new_config}"
rm -f -- "${journal}"
instance_firewall_prepare "${old_config}" "${new_config}" "${journal}"
UFW_NO_EFFECT=1
if instance_firewall_apply "${journal}"; then
  printf 'expected no-effect UFW apply failure\n' >&2
  exit 1
fi
unset UFW_NO_EFFECT
jq -e '.status == "apply_failed" and .error_code == "backend_mutation_unconfirmed"' "${journal}" >/dev/null
! grep -Fq '192.0.2.21 32117/tcp' "${UFW_RULES}"
rm -f -- "${journal}" "${SB_PROJECT_DIR}/managed-firewall.json"

# The same no-effect behavior during rollback is uncertain and must not lose
# the external rule or claim that compensation completed.
jq -n '{inbounds:[{type:"mixed",tag:"no-effect-rollback",listen:"192.0.2.22",listen_port:32116}]}' > "${new_config}"
instance_firewall_prepare "${old_config}" "${new_config}" "${journal}"
instance_firewall_apply "${journal}"
grep -Fq '192.0.2.22 32116/tcp' "${UFW_RULES}"
UFW_NO_EFFECT=1
if instance_firewall_rollback "${journal}"; then
  printf 'expected no-effect UFW rollback failure\n' >&2
  exit 1
fi
unset UFW_NO_EFFECT
jq -e '.status == "rollback_uncertain" and ([.operations[] | select(.port == 32116)] | any(.rollback_state == "uncertain"))' "${journal}" >/dev/null
grep -Fq '192.0.2.22 32116/tcp' "${UFW_RULES}"
rm -f -- "${journal}" "${SB_PROJECT_DIR}/managed-firewall.json"

# A failed mutation leaves a durable journal, and rollback restores the old
# ledger without touching the pre-existing UFW rule.
rm -f -- "${journal}"
: > "${BACKEND_LOG}"
ufw() {
  if [[ "${1:-}" == status ]]; then printf 'Status: active\n'; return 0; fi
  printf 'ufw %s\n' "$*" >> "${BACKEND_LOG}"
  return "${UFW_FAILURE:-0}"
}
jq -n '{inbounds:[{type:"mixed",tag:"failure",listen:"192.0.2.12",listen_port:32104}]}' > "${new_config}"
record_rule "${FIREWALLD_RUNTIME_RULES}" '32104/tcp'
record_rule "${FIREWALLD_PERMANENT_RULES}" '32104/tcp'
instance_firewall_prepare "${old_config}" "${new_config}" "${journal}"
UFW_FAILURE=1
if instance_firewall_apply "${journal}"; then
  printf 'expected apply failure\n' >&2
  exit 1
fi
[[ -s "${journal}" ]]
unset UFW_FAILURE
instance_firewall_rollback "${journal}"
jq -e '.status == "rolled_back" and (.operations | any(.rollback_state == "none"))' "${journal}" >/dev/null
[[ ! -e "${SB_PROJECT_DIR}/managed-firewall.json" ]]
grep -Fq '32103/tcp' "${UFW_RULES}"

# A minimal or structurally incomplete journal is rejected before rollback can
# update it or remove/restore the durable ledger.
jq -n --arg comment "$(instance_firewall_rule_comment iptables ipv4 tcp 32109 192.0.2.16)" \
  '{schema_version:1,rules:[{backend:"iptables",family:"ipv4",address:"192.0.2.16",transport:"tcp",port:32109,comment:$comment,refs:[{owner:"keep",protocol:"mixed",address:"192.0.2.16",transport:"tcp",port:32109}]}]}' \
  > "${SB_PROJECT_DIR}/managed-firewall.json"
chmod 600 "${SB_PROJECT_DIR}/managed-firewall.json"
jq -n '{schema_version:1,operations:[],before_ledger:{}}' > "${journal}"
chmod 600 "${journal}"
cp -- "${SB_PROJECT_DIR}/managed-firewall.json" "${TMP_DIR}/ledger.before-malformed"
if instance_firewall_rollback "${journal}"; then
  printf 'expected malformed rollback journal failure\n' >&2
  exit 1
fi
cmp -s -- "${SB_PROJECT_DIR}/managed-firewall.json" "${TMP_DIR}/ledger.before-malformed"
jq -e '.schema_version == 1 and (.operations | length == 0) and (.before_ledger | type == "object" and (has("rules") | not))' "${journal}" >/dev/null

printf 'instance firewall ledger checks passed (mock backends only)\n'
