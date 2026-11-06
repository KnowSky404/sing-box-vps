#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"
source "${REPO_ROOT}/dev/verification/remote/scenarios/protocol_cases.sh"
core=${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}
cert_path="${TMP_DIR}/cert.pem"; key_path="${TMP_DIR}/key.pem"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=sing-box-vps-verification.invalid   -keyout "${key_path}" -out "${cert_path}" > "${TMP_DIR}/openssl.log" 2>&1
for protocol in naive vmess; do
  for preference in true false; do
    verification_protocol_record "${protocol}" | jq --arg protocol "${protocol}" --argjson preference "${preference}" '
      .listen.tcp_fast_open=$preference |
      if $protocol=="naive" then .listen.network=["tcp"] else .transport={type:"none"} end
    ' > "${TMP_DIR}/record.json"
    structured_instance_store_candidate "${protocol}" '' create "${TMP_DIR}/record.json" 0 > "${TMP_DIR}/current.json"
    for mode in udp tcp; do
      jq --arg protocol "${protocol}" --arg mode "${mode}" '
        del(.listen.tcp_fast_open) |
        if $protocol=="naive" then .listen.network=[$mode]
        else .transport={type:(if $mode=="udp" then "quic" else "none" end)} end
      ' "${TMP_DIR}/record.json" > "${TMP_DIR}/replacement.json"
      revision=$(jq -r '.revision' "${TMP_DIR}/current.json")
      structured_instance_store_candidate "${protocol}" "${TMP_DIR}/current.json" replace "${TMP_DIR}/replacement.json" "${revision}" > "${TMP_DIR}/next.json"
      jq -e --argjson preference "${preference}" '.instances[0].listen.tcp_fast_open==$preference' "${TMP_DIR}/next.json" >/dev/null
      render_structured_instance_inbounds "${protocol}" "${TMP_DIR}/next.json" | jq -s '{inbounds:.}' > "${TMP_DIR}/server.json"
      "${core}" check -c "${TMP_DIR}/server.json"
      mv "${TMP_DIR}/next.json" "${TMP_DIR}/current.json"
    done
  done
done
printf 'Explicit TFO true/false survives TCP -> UDP/QUIC -> TCP replacements\n'
