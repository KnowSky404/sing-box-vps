#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install
original_home=${HOME}
original_directory=${PWD}
export MODULE_PROBE_LOG="${TMP_DIR}/module-probe.json"
probe="${TMP_DIR}/module-probe.sh"
cat > "${probe}" <<'EOF_PROBE'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "${HOME}/.cache"
printf 'private cache\n' > "${HOME}/.cache/probe"
temporary=$(mktemp)
jq -n --arg home "${HOME}" --arg cwd "${PWD}" --arg tmp "${temporary}" \
  --arg cache "${XDG_CACHE_HOME}" '{home:$home,cwd:$cwd,tmp:$tmp,cache:$cache}' > "${MODULE_PROBE_LOG}"
rm -f -- "${temporary}"
EOF_PROBE
chmod 700 "${probe}"
storage_initialize
mkdir -p "${SB_MEDIA_CHECK_DIR}"
cp "${probe}" "${SB_MEDIA_CHECK_SCRIPT}"
ensure_media_check_backend() { return 0; }
show_media_check_backend_info() { :; }
log_info() { :; }
run_media_check_backend
jq -e --arg root "${SB_DATA_ROOT}" --arg module "${SB_MEDIA_CHECK_DIR}" \
  '.home==$module and .cwd==$module and (.tmp|startswith($root+"/tmp/")) and .cache==($module+"/.cache")' \
  "${MODULE_PROBE_LOG}" >/dev/null
[[ -f "${SB_MEDIA_CHECK_DIR}/.cache/probe" ]]
[[ "${HOME}" == "${original_home}" && "${PWD}" == "${original_directory}" ]]

workspace=$(storage_mktemp -d)
cp "${probe}" "${workspace}/checker.sh"
run_reality_target_check "${workspace}/checker.sh" example.test "${workspace}/report.json"
jq -e --arg workspace "${workspace}" \
  '.home==$workspace and .cwd==$workspace and (.tmp|startswith($workspace+"/"))' "${MODULE_PROBE_LOG}" >/dev/null
run_reality_target_discovery "${workspace}/checker.sh" "${workspace}/discovery.json" plan 64512
jq -e --arg workspace "${workspace}" \
  '.home==$workspace and .cwd==$workspace and (.tmp|startswith($workspace+"/"))' "${MODULE_PROBE_LOG}" >/dev/null
[[ "${HOME}" == "${original_home}" && "${PWD}" == "${original_directory}" ]]
printf 'auxiliary module home, cache, cwd and temporary containment passed\n'
