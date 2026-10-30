#!/usr/bin/env bash

set -euo pipefail

# Host-side orchestration only: all services, packages, interfaces and state are
# confined to two newly created containers. No provider account is involved.
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SINGBOX_TEST_BIN=${SINGBOX_TEST_BIN:?set SINGBOX_TEST_BIN to the verified sing-box 1.14.2 binary}
ARTIFACT_DIR=${VPN_RUNTIME_ARTIFACT_DIR:-$(mktemp -d /tmp/sbv-vpn-runtime.XXXXXXXX)}
IMAGE=${VERIFY_DOCKER_IMAGE:-sing-box-vps-verify:2026091501-ssh}
RUN_ID="$(date +%s)-$$"
CLIENT="sbv-vpn-client-${RUN_ID}"
PEER="sbv-vpn-peer-${RUN_ID}"
CREATED=()
case "${VPN_RUNTIME_SCOPE:-all}" in
  all) fixture_case=test ;;
  system-lifecycle) fixture_case=lifecycle ;;
  *) printf 'unsupported VPN_RUNTIME_SCOPE\n' >&2; exit 2 ;;
esac
mkdir -p "${ARTIFACT_DIR}"
chmod 700 "${ARTIFACT_DIR}"
cleanup() {
  local status=$? container cleanup_status=0
  trap - EXIT
  for container in "${CREATED[@]}"; do
    if ! docker rm -f "${container}" > "${ARTIFACT_DIR}/${container}.removed" 2>&1; then cleanup_status=1; fi
  done
  if [[ "${cleanup_status}" -ne 0 ]]; then
    printf 'container cleanup incomplete; inspect %s\n' "${ARTIFACT_DIR}" >&2
    [[ "${status}" -ne 0 ]] || status=1
  else
    printf 'owned_containers_removed=%s\n' "${#CREATED[@]}" > "${ARTIFACT_DIR}/cleanup.env"
  fi
  exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
case "$(uname -m)" in
  aarch64) arch=arm64; checksum=7b3c792ebe10e1a81a0c8d9674aee8eb540e7dbb7ccb80a98b71024da4c72a48 ;;
  x86_64) arch=amd64; checksum=7477c374949eea6fb7cf3cbff14dbef49e4d118d9a33557d6764a77ece617e53 ;;
  *) printf 'unsupported fixture architecture\n' >&2; exit 1 ;;
esac
if [[ -n "${HEADSCALE_TEST_BIN:-}" ]]; then
  cp "${HEADSCALE_TEST_BIN}" "${ARTIFACT_DIR}/headscale.part"
else
  curl --fail --silent --show-error --location --max-time 120 \
    "https://github.com/juanfont/headscale/releases/download/v0.29.6/headscale_0.29.6_linux_${arch}" \
    -o "${ARTIFACT_DIR}/headscale.part"
fi
printf '%s  %s\n' "${checksum}" "${ARTIFACT_DIR}/headscale.part" | sha256sum -c - > "${ARTIFACT_DIR}/headscale-checksum.txt"
mv "${ARTIFACT_DIR}/headscale.part" "${ARTIFACT_DIR}/headscale"
chmod 755 "${ARTIFACT_DIR}/headscale"
for container in "${CLIENT}" "${PEER}"; do
  docker create --privileged --name "${container}" "${IMAGE}" > "${ARTIFACT_DIR}/${container}.id"
  container_id=$(<"${ARTIFACT_DIR}/${container}.id")
  CREATED+=("${container_id}")
  docker start "${container_id}" > "${ARTIFACT_DIR}/${container}.started"
  for ((attempt=0;attempt<100;attempt++)); do
    readiness=$(docker exec "${container}" systemctl is-system-running 2>/dev/null || true)
    case "${readiness}" in running|degraded) break ;; esac
    sleep 0.2
  done
  case "${readiness}" in running|degraded) ;; *) printf 'disposable systemd did not become ready\n' >&2; exit 1 ;; esac
  docker exec "${container}" systemctl stop tor tor@default ssh
  docker exec "${container}" mkdir -p /workspace/tests
  docker cp "${SINGBOX_TEST_BIN}" "${container}:/usr/local/bin/sing-box"
  docker cp "${REPO_ROOT}/tests/tailscale_openconnect_marker.py" "${container}:/workspace/tests/"
done
docker exec "${PEER}" bash -c 'set -e; apt-get update -qq; apt-get install -y --no-install-recommends ocserv=1.1.6-3 >/tmp/vpn-packages.log 2>&1; systemctl stop ocserv; touch /tmp/sbv-component-disposable' > "${ARTIFACT_DIR}/packages.log" 2>&1
docker exec "${CLIENT}" touch /tmp/sbv-component-disposable
docker cp "${ARTIFACT_DIR}/headscale" "${CLIENT}:/usr/local/bin/headscale"
docker cp "${REPO_ROOT}/install.sh" "${CLIENT}:/workspace/install.sh"
docker cp "${REPO_ROOT}/tests/tailscale_openconnect_test_helper.sh" "${CLIENT}:/workspace/tests/"
docker cp "${REPO_ROOT}/tests/tailscale_openconnect_test_helper.sh" "${PEER}:/workspace/tests/"
control_address=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${CLIENT}")
vpn_address=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${PEER}")
docker exec -e SBV_COMPONENT_RUNTIME=1 -e TAILSCALE_CONTROL_ADDRESS="${control_address}" "${CLIENT}" \
  bash /workspace/tests/tailscale_openconnect_test_helper.sh prepare > "${ARTIFACT_DIR}/prepare.log" 2>&1
docker cp "${CLIENT}:/tmp/ts-oc-runtime/headscale/headscale.crt" "${ARTIFACT_DIR}/headscale.crt"
docker cp "${ARTIFACT_DIR}/headscale.crt" "${PEER}:/usr/local/share/ca-certificates/sbv-headscale-fixture.crt"
docker exec "${PEER}" update-ca-certificates > "${ARTIFACT_DIR}/peer-trust.log" 2>&1
docker exec -e SBV_COMPONENT_RUNTIME=1 -e OPENCONNECT_SERVER_ADDRESS="${vpn_address}" "${PEER}" \
  bash /workspace/tests/tailscale_openconnect_test_helper.sh counterpart > "${ARTIFACT_DIR}/counterpart.log" 2>&1
docker cp "${PEER}:/tmp/ts-oc-runtime/ocserv.crt" "${ARTIFACT_DIR}/ocserv.crt"
docker cp "${ARTIFACT_DIR}/ocserv.crt" "${CLIENT}:/tmp/ts-oc-runtime/ocserv.crt"
docker cp "${CLIENT}:/tmp/ts-oc-runtime/peer.json" "${ARTIFACT_DIR}/peer.json"
chmod 600 "${ARTIFACT_DIR}/peer.json"
docker cp "${ARTIFACT_DIR}/peer.json" "${PEER}:/tmp/peer.json"
docker exec -d -e TS_NO_LOGS_NO_SUPPORT=true "${PEER}" bash -c 'exec /usr/local/bin/sing-box run -c /tmp/peer.json >/tmp/peer.log 2>&1'
status=0
docker exec -e SBV_COMPONENT_RUNTIME=1 -e OPENCONNECT_SERVER_ADDRESS="${vpn_address}" \
  -e VPN_RUNTIME_SYSTEM_DATA_PLANE="${VPN_RUNTIME_SYSTEM_DATA_PLANE:-1}" "${CLIENT}" bash /workspace/tests/tailscale_openconnect_test_helper.sh "${fixture_case}" \
  > "${ARTIFACT_DIR}/runtime.log" 2>&1 || status=$?
docker cp "${CLIENT}:/tmp/ts-oc-runtime" "${ARTIFACT_DIR}/container"
docker cp "${PEER}:/tmp/ts-oc-runtime" "${ARTIFACT_DIR}/counterpart"
docker cp "${PEER}:/tmp/peer.log" "${ARTIFACT_DIR}/peer.log"
if ! docker exec "${CLIENT}" journalctl -u sing-box --no-pager > "${ARTIFACT_DIR}/journal.log" 2>&1; then
  printf 'journal=unavailable\n' >> "${ARTIFACT_DIR}/journal.log"
fi
if [[ "${status}" -ne 0 ]]; then
  printf 'controlled VPN runtime failed with status %s; private evidence: %s\n' "${status}" "${ARTIFACT_DIR}" >&2
  exit "${status}"
fi
grep -Fq "initiating session for user 'fixture'" "${ARTIFACT_DIR}/counterpart/ocserv.log"
cat "${ARTIFACT_DIR}/container/results.env"
printf 'controlled VPN artifacts=%s\n' "${ARTIFACT_DIR}"
