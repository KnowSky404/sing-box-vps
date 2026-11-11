#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install
original_home=${HOME}
original_directory=${PWD}
export XDG_DATA_HOME="${TMP_DIR}/operator-data"
original_data_home=${XDG_DATA_HOME}
export MODULE_PROBE_LOG="${TMP_DIR}/module-probe.json"
probe="${TMP_DIR}/module-probe.sh"
cat > "${probe}" <<'EOF_PROBE'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "${HOME}/.cache" "${XDG_DATA_HOME}"
printf 'private cache\n' > "${HOME}/.cache/probe"
printf 'private data\n' > "${XDG_DATA_HOME}/probe"
temporary=$(mktemp)
jq -n --arg home "${HOME}" --arg cwd "${PWD}" --arg tmp "${temporary}" \
  --arg cache "${XDG_CACHE_HOME}" --arg data "${XDG_DATA_HOME}" '{home:$home,cwd:$cwd,tmp:$tmp,cache:$cache,data:$data}' > "${MODULE_PROBE_LOG}"
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
jq -e --arg root "${SB_DATA_ROOT}" \
  '. as $probe | (.home|startswith($root+"/tmp/")) and .cwd==.home and (.tmp|startswith($probe.home+"/")) and
   .cache==(.home+"/.cache") and .data==(.home+"/.local/share")' "${MODULE_PROBE_LOG}" >/dev/null
[[ ! -e "$(jq -r .home "${MODULE_PROBE_LOG}")" ]]
[[ "${HOME}" == "${original_home}" && "${PWD}" == "${original_directory}" ]]

workspace=$(storage_mktemp -d)
cp "${probe}" "${workspace}/checker.sh"
run_reality_target_check "${workspace}/checker.sh" example.test "${workspace}/report.json"
jq -e --arg workspace "${workspace}" \
  '.home==$workspace and .cwd==$workspace and (.tmp|startswith($workspace+"/")) and .data==($workspace+"/.local/share")' "${MODULE_PROBE_LOG}" >/dev/null
run_reality_target_discovery "${workspace}/checker.sh" "${workspace}/discovery.json" plan 64512
jq -e --arg workspace "${workspace}" \
  '.home==$workspace and .cwd==$workspace and (.tmp|startswith($workspace+"/")) and .data==($workspace+"/.local/share")' "${MODULE_PROBE_LOG}" >/dev/null
[[ "${HOME}" == "${original_home}" && "${PWD}" == "${original_directory}" ]]
[[ "${XDG_DATA_HOME}" == "${original_data_home}" && ! -e "${original_data_home}" ]]
printf 'auxiliary module home, cache, data, cwd and temporary containment passed\n'
