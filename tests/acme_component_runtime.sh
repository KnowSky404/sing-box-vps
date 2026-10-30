#!/usr/bin/env bash

set -euo pipefail
[[ "${SBV_COMPONENT_RUNTIME:-}" == 1 && -f /.dockerenv && -f /tmp/sbv-component-disposable ]] || {
  printf 'requires explicit disposable Docker fixture\n' >&2; exit 64;
}
# Existing service setup installs sbv from $0. This fixture deliberately invokes
# the sourced test as "sbv" so service setup does not download an unrelated
# management script while testing a pinned local runtime.
if [[ "$0" != sbv ]]; then exec bash -c 'source "$1"' sbv "${BASH_SOURCE[0]}"; fi
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[[ "$(/usr/local/bin/sing-box version | sed -n 's/^sing-box version //p')" == 1.14.2 ]]
mkdir -p /etc/dbus-1/system.d
cat > /etc/dbus-1/system.d/sbv-component-resolved.conf <<'DBUS'
<busconfig>
  <policy user="root">
    <allow own="org.freedesktop.resolve1"/>
    <allow send_destination="org.freedesktop.resolve1"/>
  </policy>
</busconfig>
DBUS
systemctl restart dbus
# Reuse the existing private CA, trust, HTTP-01 and service setup. This also
# retains the original HY2 positive transfer and coexistence assertions.
export SBV_HY2_ACME_RUNTIME=1
source "${REPO_ROOT}/tests/hy2_instance_acme_runtime.sh"
component_artifact="${ARTIFACT_DIR}/standalone-provider"
mkdir -p "${component_artifact}"
chmod 700 "${component_artifact}"
component_domain="component-${BASHPID}.provider.example.com"
component_cache="${SB_ACME_DATA_DIR}/standalone-component-${BASHPID}"
printf '127.0.0.1 %s\n' "${component_domain}" >> /etc/hosts
provider_record=$(jq -cn --arg dir "${component_cache}" --arg domain "${component_domain}" '{id:"standalone-provider",role:"certificate_provider",type:"acme",tag:"standalone-provider",enabled:true,route_rules:[],config:{domain:[$domain],data_directory:$dir,provider:"https://localhost:14000/dir",disable_http_challenge:false,disable_tls_alpn_challenge:true}}')
printf '%s\n' "${provider_record}" > "${component_artifact}/record.json"
chmod 600 "${component_artifact}/record.json"
component_revision=$(jq -r '.revision' "${SB_COMPONENT_STATE_FILE}")
bash "${REPO_ROOT}/install.sh" agent component create --json --yes --expected-revision "${component_revision}" --file "${component_artifact}/record.json" > "${component_artifact}/create.json" 2> "${component_artifact}/create.log"
component_revision=$((component_revision+1))
jq -e --argjson revision "${component_revision}" '.operation=="create" and .revision==$revision and .config_check=="passed"' "${component_artifact}/create.json" >/dev/null
# A manual consumer deliberately remains operator-owned. Its provider reference
# is rendered from the actual component record, not a copied inline provider.
jq --arg domain "${component_domain}" '.inbounds += [{type:"http",tag:"operator-provider-consumer",listen:"127.0.0.1",listen_port:21443,tls:{enabled:true,server_name:$domain,certificate_provider:"standalone-provider"}}]' "${SINGBOX_CONFIG_FILE}" > "${component_artifact}/candidate.json"
"${SINGBOX_BIN_PATH}" check -c "${component_artifact}/candidate.json" > "${component_artifact}/consumer.check" 2>&1
cp "${component_artifact}/candidate.json" "${SINGBOX_CONFIG_FILE}"
systemctl restart sing-box
for ((attempt=0;attempt<60;attempt++)); do
  if curl --silent --show-error --fail --max-time 3 --noproxy '' --proxy-cacert "${ARTIFACT_DIR}/root.crt" \
    --proxy "https://${component_domain}:21443" http://127.0.0.1:19081/marker.txt \
    > "${component_artifact}/transfer.txt" 2> "${component_artifact}/transfer.stderr"; then break; fi
  sleep 0.2
done
cmp "${ARTIFACT_DIR}/marker.txt" "${component_artifact}/transfer.txt"
find "${component_cache}" -type f -name '*.crt' -print | sort > "${component_artifact}/certificate-paths.txt"
test -s "${component_artifact}/certificate-paths.txt"
# Deleting a referenced provider must fail and preserve the revision/config.
sha256sum "${SINGBOX_CONFIG_FILE}" > "${component_artifact}/before-rejected-delete.sha256"
if bash "${REPO_ROOT}/install.sh" agent component delete --json --yes --expected-revision "${component_revision}" --id standalone-provider > "${component_artifact}/referenced-delete.json" 2> "${component_artifact}/referenced-delete.log"; then exit 1; fi
[[ "$(jq -r '.revision' "${SB_COMPONENT_STATE_FILE}")" == "${component_revision}" ]]
sha256sum -c "${component_artifact}/before-rejected-delete.sha256"
jq '.inbounds |= map(select(.tag!="operator-provider-consumer"))' "${SINGBOX_CONFIG_FILE}" > "${component_artifact}/without-consumer.json"
"${SINGBOX_BIN_PATH}" check -c "${component_artifact}/without-consumer.json"
cp "${component_artifact}/without-consumer.json" "${SINGBOX_CONFIG_FILE}"
systemctl restart sing-box
bash "${REPO_ROOT}/install.sh" agent component delete --json --yes --expected-revision "${component_revision}" --id standalone-provider > "${component_artifact}/delete.json" 2> "${component_artifact}/delete.log"
while IFS= read -r certificate; do test -f "${certificate}"; done < "${component_artifact}/certificate-paths.txt"
! jq -e 'any(.certificate_providers[]?; .tag=="standalone-provider")' "${SINGBOX_CONFIG_FILE}" >/dev/null
systemctl is-active --quiet sing-box
printf 'FP-01=passed\n' > "${component_artifact}/results.env"
printf 'standalone managed ACME provider private-CA acceptance passed\n'
