#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALL_FILE="${REPO_ROOT}/install.sh"

if grep -Fq 'obfs / Salamander 混淆密码 (当前: 留空隐藏, 留空保持/自动生成)' "${INSTALL_FILE}"; then
  printf 'expected hy2 obfs password update prompt to avoid ambiguous hidden/blank wording\n' >&2
  exit 1
fi

if ! grep -Fq 'obfs / Salamander 混淆密码 (当前: 已设置，留空保持；输入新值则覆盖):' "${INSTALL_FILE}"; then
  printf 'expected hy2 obfs password prompt to say when a password is already set\n' >&2
  exit 1
fi

if ! grep -Fq 'obfs / Salamander 混淆密码 (当前: 未设置，留空自动生成；输入新值则使用输入值):' "${INSTALL_FILE}"; then
  printf 'expected hy2 obfs password prompt to say when no password is set\n' >&2
  exit 1
fi
