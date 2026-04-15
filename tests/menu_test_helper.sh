#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${TESTS_DIR}/.." && pwd)

setup_menu_test_env() {
  local width=${1:-120}

  TMP_DIR=$(mktemp -d)
  trap 'rm -rf "${TMP_DIR}"' EXIT

  TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"

  perl -0pe 's/^\s*main "\$@"\s*$//m' "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

  mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/bin"

  cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
  chmod +x "${TMP_DIR}/bin/hostname"

  cat > "${TMP_DIR}/bin/tput" <<EOF
#!/usr/bin/env bash

if [[ "\${1:-}" == "cols" ]]; then
  printf '%s\n' '${width}'
  exit 0
fi

if [[ "\${1:-}" == "colors" ]]; then
  printf '256\n'
  exit 0
fi

exit 1
EOF
  chmod +x "${TMP_DIR}/bin/tput"

  cat > "${TMP_DIR}/bin/stty" <<EOF
#!/usr/bin/env bash

if [[ "\${1:-}" == "size" ]]; then
  printf '24 %s\n' '${width}'
  exit 0
fi

exit 1
EOF
  chmod +x "${TMP_DIR}/bin/stty"

  export PATH="${TMP_DIR}/bin:${PATH}"
  export COLUMNS="${width}"
  export TERM=xterm-256color
  MENU_TEST_WIDTH="${width}"
}

source_testable_install() {
  # shellcheck disable=SC1090
  source "${TESTABLE_INSTALL}"

  if declare -F term_columns >/dev/null 2>&1; then
    term_columns() {
      printf '%s' "${MENU_TEST_WIDTH}"
    }
  fi
}

strip_ansi() {
  printf '%s' "${1}" | sed -E $'s/\x1B\\[[0-9;]*[[:alpha:]]//g'
}
