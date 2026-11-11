#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
core=${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}
ln -s "${core}" "${TMP_DIR}/bin/sing-box"
source_testable_install
export MEDIA_FIXTURE_ROOT=${TMP_DIR}
export MEDIA_FIXTURE_INSTALL=${TESTABLE_INSTALL}
export MEDIA_FIXTURE_CONFIG=${SINGBOX_CONFIG_FILE}
export MEDIA_FIXTURE_BACKEND=${SB_MEDIA_CHECK_SCRIPT}
export MEDIA_FIXTURE_CORE=${core}
mkdir -p "${SB_MEDIA_CHECK_DIR}"
cat > "${TMP_DIR}/bin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *is-active*) [[ ! -f "${MEDIA_FIXTURE_ROOT}/stopped" ]] ;;
  *MainPID*) printf 'MainPID=%s\n' "$(cat "${MEDIA_FIXTURE_ROOT}/pid")" ;;
  *) exit 1 ;;
esac
EOF_SYSTEMCTL
cat > "${TMP_DIR}/bin/curl" <<'EOF_CURL'
#!/usr/bin/env bash
set -euo pipefail
[[ "${*: -2:1}" == --config ]]
config=${*: -1}
[[ $(stat -c %a "${config}") == 600 ]]
grep -q '^proxy-user = "fixture:secret"$' "${config}"
! grep -q 'private_key\|wireguard' "${config}"
printf '%s\n' "$*" >> "${CASE_DIR}/curl-args"
if [[ -f "${CASE_DIR}/trace-off" ]]; then printf 'warp=off\n'; else printf 'warp=on\n'; fi
EOF_CURL
cat > "${TMP_DIR}/bin/setsid" <<'EOF_SETSID'
#!/usr/bin/env bash
set -euo pipefail
[[ ! -f "${CASE_DIR}/start-fail" ]] || exit 76
exec /usr/bin/setsid "$@"
EOF_SETSID
chmod 700 "${TMP_DIR}/bin/systemctl" "${TMP_DIR}/bin/curl" "${TMP_DIR}/bin/setsid"
printf '13579\n' > "${TMP_DIR}/pid"
cat > "${SB_MEDIA_CHECK_SCRIPT}" <<'EOF_BACKEND'
#!/usr/bin/env bash
set -euo pipefail
curl_command=''
while getopts 'P:C:' option; do
  case "${option}" in C) curl_command=${OPTARG} ;; P) [[ ${OPTARG} != *secret* ]] ;; esac
done
printf 'private cookie\n' > "${HOME}/cookie"
printf '%s\n%s\n%s\n' "${HOME}" "${BASHPID}" "${PPID}" > "${CASE_DIR}/active.${BASHPID}"
if [[ -n ${curl_command} ]]; then
  if [[ ${MEDIA_FIXTURE_MODE:-ok} == pid-change ]]; then printf '24680\n' > "${MEDIA_FIXTURE_ROOT}/pid"; fi
  "${curl_command}" -fsS https://media.fixture.invalid/ >/dev/null
  curl -fsS https://aux.fixture.invalid/ >/dev/null
fi
case "${MEDIA_FIXTURE_MODE:-ok}" in
  fail) exit 37 ;;
  hang)
    sleep 600 &
    printf '%s\n' "$!" > "${CASE_DIR}/child.${BASHPID}"
    wait "$!" ;;
esac
EOF_BACKEND
chmod 700 "${SB_MEDIA_CHECK_SCRIPT}"

jq -n '{log:{disabled:true},endpoints:[{type:"wireguard",tag:"warp-ep",address:["172.16.0.2/32"],
  private_key:"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",peers:[{address:"127.0.0.1",port:51820,
  public_key:"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",allowed_ips:["0.0.0.0/0"]}]}],
  inbounds:[{type:"mixed",tag:"probe",listen:"127.0.0.1",listen_port:28080,users:[{username:"fixture",password:"secret"}]}],
  outbounds:[{type:"direct",tag:"direct"}],route:{final:"warp-ep",rules:[]}}' > "${SINGBOX_CONFIG_FILE}"
cp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/good.json"
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
create_media_check_warp_curl_config "${TMP_DIR}/proxy.conf"
grep -q '^proxy = "socks5h://127.0.0.1:28080"' "${TMP_DIR}/proxy.conf"
! grep -q 'private_key\|wireguard' "${TMP_DIR}/proxy.conf"
# A first unconditional route to WARP is safe even if the default is DIRECT.
jq '.route={final:"direct",rules:[{inbound:["probe"],action:"route",outbound:"warp-ep"}]}' "${TMP_DIR}/good.json" > "${SINGBOX_CONFIG_FILE}"
create_media_check_warp_curl_config "${TMP_DIR}/proxy.conf"
# Prior rules on disjoint inbounds cannot change this ingress destination.
jq '.inbounds += [{type:"socks",tag:"other",listen:"127.0.0.1",listen_port:28081}] |
 .route.rules=[{inbound:["other"],action:"route",outbound:"direct"}]' "${TMP_DIR}/good.json" > "${SINGBOX_CONFIG_FILE}"
create_media_check_warp_curl_config "${TMP_DIR}/proxy.conf"
# Trace success alone cannot justify domain-only, inverted, logical or fallback routing.
for filter in \
  'del(.endpoints)' \
  '.route.final="direct"' \
  '.inbounds[0].users=[]' \
  '.route.rules=[{domain:["www.cloudflare.com"],action:"route",outbound:"warp-ep"}] | .route.final="direct"' \
  '.route.rules=[{inbound:["probe"],domain:["media.fixture.invalid"],action:"route",outbound:"direct"}]' \
  '.route.rules=[{inbound:[],domain_suffix:["netflix.com"],action:"route",outbound:"direct"}]' \
  '.route.rules=[{inbound:["other"],invert:true,action:"route",outbound:"direct"}]' \
  '.route.rules=[{type:"logical",mode:"or",rules:[{domain_suffix:["invalid"]}],action:"route",outbound:"direct"}]' \
  '.route.rules=[{action:"route-options",override_address:"127.0.0.1"}]'; do
  jq "${filter}" "${TMP_DIR}/good.json" > "${SINGBOX_CONFIG_FILE}"
  if create_media_check_warp_curl_config "${TMP_DIR}/rejected.conf" > "${TMP_DIR}/reject.log" 2>&1; then
    printf 'unsafe ingress accepted: %s\n' "${filter}" >&2; exit 1
  fi
  [[ ! -e "${TMP_DIR}/rejected.conf" ]]
done
printf '{broken\n' > "${SINGBOX_CONFIG_FILE}"
if create_media_check_warp_curl_config "${TMP_DIR}/rejected.conf"; then exit 1; fi
cp "${TMP_DIR}/good.json" "${SINGBOX_CONFIG_FILE}"

cat > "${TMP_DIR}/driver.sh" <<'EOF_DRIVER'
#!/usr/bin/env bash
set -euo pipefail
source "${MEDIA_FIXTURE_INSTALL}"
ensure_media_check_backend() { :; }
show_media_check_backend_info() { :; }
media_check_service_snapshot() {
  [[ ! -f "${MEDIA_FIXTURE_ROOT}/stopped" ]] || return 1
  printf '%s:%s' "$(cat "${MEDIA_FIXTURE_ROOT}/pid")" "$(sha256sum "${MEDIA_FIXTURE_CONFIG}" | cut -d ' ' -f1)"
}
run_media_check_backend "${MEDIA_FIXTURE_ROUTE:-warp}"
EOF_DRIVER
# Shorten only the fixture watchdog limit, exercising the identical timeout path.
sed -i 's/elapsed<900/elapsed<2/' "${TESTABLE_INSTALL}"
python3 "${TESTS_DIR}/media_warp_lifecycle.py"
[[ $(sha256sum "${SINGBOX_CONFIG_FILE}" | cut -d ' ' -f1) == $(sha256sum "${TMP_DIR}/good.json" | cut -d ' ' -f1) ]]
[[ ! -e "${SB_WARP_KEY_FILE}" ]]
[[ -z "$(find "${TMP_DIR}/tmp" -mindepth 1 -print -quit)" ]]
! declare -F create_media_check_warp_proxy_config >/dev/null
printf 'media WARP routing, refusal and lifecycle checks passed\n'
