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

title_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "sing-box-vps 一键安装管理脚本") { print NR; exit }')
author_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "作者: KnowSky404") { print NR; exit }')
project_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "项目: https://github.com/KnowSky404/sing-box-vps") { print NR; exit }')
subtitle_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "专为 VPS 稳定部署与安全运维设计") { print NR; exit }')
version_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "版本: ") { print NR; exit }')
deployment_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "部署管理") { print NR; exit }')

if [[ -z "${author_line}" || -z "${project_line}" || -z "${subtitle_line}" || -z "${version_line}" ]]; then
  printf 'expected narrow main menu brand block to split long metadata into shorter lines, got:\n%s\n' "${output}" >&2
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

if ! (( title_line < author_line && author_line < project_line && project_line < subtitle_line && subtitle_line < version_line && version_line < deployment_line )); then
  printf 'expected narrow main menu brand block lines to stay grouped before the deployment section, got:\n%s\n' "${output}" >&2
  exit 1
fi

while IFS= read -r brand_line; do
  [[ -z "${brand_line}" ]] && continue

  if (( $(estimate_text_width "${brand_line}") > 56 )); then
    printf 'expected narrow main menu brand text line to fit within 56 columns, got:\n%s\n' "${output}" >&2
    exit 1
  fi
done <<EOF
sing-box-vps 一键安装管理脚本
作者: KnowSky404
项目: https://github.com/KnowSky404/sing-box-vps
专为 VPS 稳定部署与安全运维设计
版本: 2026041505
EOF
