#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 56
source_testable_install

check_root() {
  :
}

ensure_sbv_command_installed() {
  :
}

check_script_status() {
  SCRIPT_VER_STATUS="(脚本已是最新)"
}

check_sb_version() {
  SB_VER_STATUS="(sing-box 已安装)"
}

check_bbr_status() {
  BBR_STATUS="(已开启 BBR)"
}

clear() {
  :
}

exit_script() {
  exit 0
}

output=$(main 2>&1 <<'EOF'
0
EOF
)

plain_output=$(strip_ansi "${output}")
project_url_without_scheme=${PROJECT_URL#*://}
project_url_base_line="${PROJECT_URL%%://*}://${project_url_without_scheme%%/*}/"
project_url_path_line="${project_url_without_scheme#*/}"
expected_version_line="版本: ${SCRIPT_VERSION}"

title_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "sing-box-vps 一键安装管理脚本") { print NR; exit }')
author_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "作者: KnowSky404") { print NR; exit }')
project_label_line=$(printf '%s\n' "${plain_output}" | awk '$0 == "项目:" { print NR; exit }')
project_base_line=$(printf '%s\n' "${plain_output}" | awk -v target="${project_url_base_line}" '$0 == target { print NR; exit }')
project_path_line=$(printf '%s\n' "${plain_output}" | awk -v target="${project_url_path_line}" '$0 == target { print NR; exit }')
subtitle_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "专为 VPS 稳定部署与安全运维设计") { print NR; exit }')
version_line=$(printf '%s\n' "${plain_output}" | awk -v target="${expected_version_line}" '$0 == target { print NR; exit }')
deployment_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "部署管理") { print NR; exit }')

if [[ -z "${author_line}" || -z "${project_label_line}" || -z "${project_base_line}" || -z "${project_path_line}" || -z "${subtitle_line}" || -z "${version_line}" ]]; then
  printf 'expected narrow main menu brand block to split project metadata into explicit short lines, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" == *"作者: KnowSky404 · 项目: https://github.com/KnowSky404/sing-box-vps"* ]]; then
  printf 'expected narrow main menu brand block to avoid the combined author/project line, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" == *"专为 VPS 稳定部署与安全运维设计 · 版本: "* ]]; then
  printf 'expected narrow main menu brand block to avoid the combined subtitle/version line, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" == *"项目: ${PROJECT_URL}"* ]]; then
  printf 'expected narrow main menu brand block to avoid a single oversized project URL line, got:\n%s\n' "${output}" >&2
  exit 1
fi

if ! (( title_line < author_line && author_line < project_label_line && project_label_line < project_base_line && project_base_line < project_path_line && project_path_line < subtitle_line && subtitle_line < version_line && version_line < deployment_line )); then
  printf 'expected narrow main menu brand block lines to stay grouped before the deployment section, got:\n%s\n' "${output}" >&2
  exit 1
fi

while IFS= read -r brand_line; do
  [[ -z "${brand_line}" ]] && continue

  if (( $(estimate_text_width "${brand_line}") > 56 )); then
    printf 'expected narrow main menu brand text line to fit within 56 columns, got:\n%s\n' "${output}" >&2
    exit 1
  fi
done < <(printf '%s\n' \
  "sing-box-vps 一键安装管理脚本" \
  "作者: ${PROJECT_AUTHOR}" \
  "项目:" \
  "${project_url_base_line}" \
  "${project_url_path_line}" \
  "专为 VPS 稳定部署与安全运维设计" \
  "${expected_version_line}")
