#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf -- "${TMP_DIR}"' EXIT
sed -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  "${REPO_ROOT}/install.sh" > "${TMP_DIR}/install.sh"
mkdir -p "${TMP_DIR}/project"
# shellcheck disable=SC1090
source "${TMP_DIR}/install.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

prepare_reality_target_checker() {
  printf '%s\n' "$1" >> "${TMP_DIR}/prepared"
  printf '#!/usr/bin/env bash\n' > "$1"
}

run_reality_target_check() {
  local domain=$2 report=$3 status=0
  printf '%s\n' "${domain}" >> "${TMP_DIR}/probed"
  case "${domain}" in
    failed.example.com) return 1 ;;
    timeout.example.com) return 124 ;;
    malformed.example.com) printf 'not JSON\n' > "${report}"; return 0 ;;
    warn.example.com) status=3 ;;
  esac
  jq -n --arg domain "${domain}" --argjson status "${status}" '
    {schema_version:"1.0",tool_version:"0.1.0",target:$domain,sni:$domain,port:443,
     selection:{scope:"dns",complete:true,limit:16},
     endpoints:[{ip:"192.0.2.1",family:4,checks:
       (["tcp443","tls13","cert_chain","cert_san","cert_validity","alpn_h2","x25519"] |
        map({id:.,status:"PASS",reason:"fixture"}))}],
     risks:[],unknowns:(if $status==3 then [{scope:"192.0.2.1",id:"cdn",reason:"fixture unknown"}] else [] end),
     summary:{basic_tls:"PASS",compatibility:"PASS",ancillary:(if $status==0 then "PASS" else "WARN" end),
       status:(if $status==0 then "PASS" else "WARN" end),exit_code:$status}}
  ' > "${report}"
  return "${status}"
}

prompt_yes_no() {
  local answer
  read -r answer || return 1
  printf '%s' "${answer}"
}

selected=$(select_reality_sni_candidate failed.example.com timeout.example.com malformed.example.com good.example.com later.example.com)
[[ "${selected}" == good.example.com ]] || fail "expected first accepted checker result, got ${selected}"
[[ "$(cat "${TMP_DIR}/probed")" == $'failed.example.com\ntimeout.example.com\nmalformed.example.com\ngood.example.com' ]] || fail 'wrong candidate order or probed after success'
[[ "$(wc -l < "${TMP_DIR}/prepared")" -eq 1 ]] || fail 'checker should be prepared once for the candidate list'
while IFS= read -r prepared; do
  [[ ! -e "$(dirname "${prepared}")" ]] || fail 'successful selection left its private temporary directory'
done < "${TMP_DIR}/prepared"

if selected=$(select_reality_sni_candidate failed.example.com timeout.example.com malformed.example.com); then
  fail 'failed probes must not choose a fixed fallback'
fi
[[ -z "${selected}" ]] || fail 'failed selection leaked output as an SNI'

if selected=$(select_reality_sni_candidate); then
  fail 'an empty candidate list must not select an implicit domain'
fi
[[ -z "${selected}" ]] || fail 'empty candidate selection leaked stdout'

selected=$(select_reality_sni_candidate warn.example.com good.example.com <<'INPUT'
n
INPUT
)
[[ "${selected}" == good.example.com ]] || fail 'declined ancillary warnings should continue to next candidate'

selected=$(select_reality_sni_candidate warn.example.com <<'INPUT'
y
INPUT
)
[[ "${selected}" == warn.example.com ]] || fail 'explicitly accepted ancillary warnings should select their domain'

if selected=$(select_reality_sni_candidate warn.example.com </dev/null); then
  fail 'EOF must not accept ancillary risks'
fi
[[ -z "${selected}" ]] || fail 'EOF warning rejection leaked an SNI'

# A signal delivered inside a probe must terminate selection instead of
# accepting a later domain after the operator interrupted the operation.
run_reality_target_check() {
  if [[ "$2" == interrupted.example.com ]]; then
    kill -TERM "${BASHPID}"
    return 1
  fi
  : > "${TMP_DIR}/probe-after-interrupt"
  return 1
}
status=0
selected=$(select_reality_sni_candidate interrupted.example.com good.example.com) || status=$?
[[ "${status}" -eq 143 ]] || fail "SIGTERM did not terminate selection: ${status}"
[[ ! -e "${TMP_DIR}/probe-after-interrupt" ]] || fail 'selection continued after SIGTERM'
prepared=$(tail -n 1 "${TMP_DIR}/prepared")
[[ ! -e "$(dirname "${prepared}")" ]] || fail 'signal left its private temporary directory'
[[ -z "${selected}" ]] || fail 'signal produced an SNI'

prepare_reality_target_checker() { return 1; }
if selected=$(select_reality_sni_candidate good.example.com); then
  fail 'download failure must stop target selection'
fi
[[ -z "${selected}" ]] || fail 'download failure leaked an SNI'
# Installation, update and new-instance menus supply only the operator's list.
select_reality_sni_candidate() {
  printf '%s\n' "$@" > "${TMP_DIR}/menu-candidates"
  printf '%s' "${!#}"
}
SB_SNI="existing.example.com"
prompt_reality_sni_install <<'INPUT' > "${TMP_DIR}/menu-output"
1
first.example.com, installed.example.com
INPUT
[[ "${SB_SNI}" == installed.example.com ]] || fail 'install did not use supplied candidate list'
[[ "$(cat "${TMP_DIR}/menu-candidates")" == $'first.example.com\ninstalled.example.com' ]] || fail 'candidate list splitting failed'
SB_SNI="existing.example.com"
prompt_reality_sni_update <<'INPUT' > "${TMP_DIR}/menu-output"
2
updated.example.com
INPUT
[[ "${SB_SNI}" == updated.example.com ]] || fail 'update menu did not probe supplied domain'
prompt_reality_sni_for_new_instance existing.example.com <<'INPUT' > "${TMP_DIR}/menu-output"
2
new-instance.example.com
INPUT
[[ "${SB_SNI}" == new-instance.example.com ]] || fail 'new-instance menu did not probe supplied domain'

SB_SNI="existing.example.com"
prompt_reality_sni_update <<'INPUT' > "${TMP_DIR}/menu-output"

INPUT
[[ "${SB_SNI}" == existing.example.com ]] || fail 'update default did not preserve existing SNI'
prompt_reality_sni_for_new_instance reuse.example.com <<'INPUT' > "${TMP_DIR}/menu-output"

INPUT
[[ "${SB_SNI}" == reuse.example.com ]] || fail 'new-instance default did not reuse existing SNI'

for menu in install update new_instance; do
  SB_SNI="unchanged.example.com"
  case "${menu}" in
    install) if prompt_reality_sni_install </dev/null > "${TMP_DIR}/menu-output"; then fail 'install accepted EOF'; fi ;;
    update) if prompt_reality_sni_update </dev/null > "${TMP_DIR}/menu-output"; then fail 'update accepted EOF'; fi ;;
    new_instance) if prompt_reality_sni_for_new_instance existing.example.com </dev/null > "${TMP_DIR}/menu-output"; then fail 'new-instance accepted EOF'; fi ;;
  esac
  [[ "${SB_SNI}" == unchanged.example.com ]] || fail "${menu} mutated SNI at EOF"
done

select_reality_sni_candidate() { return 1; }
SB_SNI="unchanged.example.com"
if prompt_reality_sni_install <<'INPUT' > "${TMP_DIR}/menu-output"
1
failed.example.com
INPUT
then
  fail 'install continued after failed probe and EOF'
fi
[[ "${SB_SNI}" == unchanged.example.com ]] || fail 'probe failure mutated install SNI'
SB_SNI="unchanged.example.com"
if prompt_reality_sni_update <<'INPUT' > "${TMP_DIR}/menu-output"
2
failed.example.com
INPUT
then
  fail 'update continued after failed probe and EOF'
fi
[[ "${SB_SNI}" == unchanged.example.com ]] || fail 'probe failure mutated existing SNI'
# Signals must propagate through the prompt wrappers without retrying a menu.
select_reality_sni_candidate() { return 143; }
for menu in prompt_reality_sni_install prompt_reality_sni_update prompt_reality_sni_for_new_instance; do
  SB_SNI="unchanged.example.com"
  status=0
  choice=2
  [[ "${menu}" == prompt_reality_sni_install ]] && choice=1
  "${menu}" existing.example.com <<< "${choice}
interrupted.example.com" > "${TMP_DIR}/menu-output" || status=$?
  [[ "${status}" == 143 && "${SB_SNI}" == unchanged.example.com ]] || fail "${menu} did not propagate interruption unchanged"
done
printf 'REALITY checker candidate selection and menu tests passed.\n'
