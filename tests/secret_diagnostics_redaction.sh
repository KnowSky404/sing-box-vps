#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120

cat > "${TMP_DIR}/bin/sing-box" <<'EOF_SINGBOX'
#!/usr/bin/env bash

if [[ "${1:-}" == "generate" ]]; then
  printf 'Private key: private-generation-secret\n' >&2
  printf 'Public key: public-generation-secret\n' >&2
  exit 23
fi

exit 0
EOF_SINGBOX
chmod +x "${TMP_DIR}/bin/sing-box"

source_testable_install

if (run_singbox_generate_command "reality-keypair" "REALITY 密钥" >/dev/null 2>"${TMP_DIR}/generate.stderr"); then
  printf 'expected generate failure to return non-zero\n' >&2
  exit 1
fi

if grep -Fq 'private-generation-secret' "${SBV_LOG_FILE}" ||
   grep -Fq 'public-generation-secret' "${SBV_LOG_FILE}" ||
   grep -Fq 'private-generation-secret' "${TMP_DIR}/generate.stderr" ||
   grep -Fq 'public-generation-secret' "${TMP_DIR}/generate.stderr"; then
  printf 'generate diagnostics leaked sensitive output\n' >&2
  exit 1
fi
grep -Fq '退出码 23；原始输出未记录' "${SBV_LOG_FILE}"

run_singbox_generate_command() {
  cat <<'EOF_KEYS'
PrivateKey: 8DcUSmPINFuK1xkA1TncAJh46Ra8Mq8o42XL3b+rT2s=
PublicKey: j/gT24P0qv0p5RFqYVehc7Y88S5fDhcJ8E3HGqpCPVg=
EOF_KEYS
}

curl() {
  if [[ "${WARP_RESPONSE_MODE:-success}" == "error" ]]; then
    printf '%s\n' '{"errors":[{"message":"warp-error-secret"}]}'
    return 0
  fi

  printf '%s\n' '{"id":"new-id","token":"warp-token-secret","config":{"client_id":"warp-client-id","interface":{"addresses":{"v4":"172.16.0.2","v6":"2606:4700:110:8cde:1234:5678:90ab:cdef"}}}}'
}

register_warp >/dev/null

if grep -Fq 'warp-token-secret' "${SBV_LOG_FILE}" ||
   grep -Fq 'warp-client-id' "${SBV_LOG_FILE}" ||
   grep -Fq 'new-id' "${SBV_LOG_FILE}"; then
  printf 'successful Warp diagnostics leaked API response material\n' >&2
  exit 1
fi
grep -Fq '敏感响应原文未记录' "${SBV_LOG_FILE}"

rm -f "${SB_WARP_KEY_FILE}"
export WARP_RESPONSE_MODE=error
if (register_warp >/dev/null 2>"${TMP_DIR}/warp-error.stderr"); then
  printf 'expected Warp registration error to return non-zero\n' >&2
  exit 1
fi

if grep -Fq 'warp-error-secret' "${SBV_LOG_FILE}" ||
   grep -Fq 'warp-error-secret' "${TMP_DIR}/warp-error.stderr"; then
  printf 'failed Warp diagnostics leaked API error material\n' >&2
  exit 1
fi
grep -Fq 'Warp 注册失败（API 返回错误）' "${SBV_LOG_FILE}"

if grep -Fq '生成原始输出:' "${TESTS_DIR}/../install.sh" ||
   grep -Fq '注册原始响应:' "${TESTS_DIR}/../install.sh"; then
  printf 'install.sh still contains raw secret diagnostic templates\n' >&2
  exit 1
fi
