# Real old-updater -> new-first-start -> transactional migration rehearsal.
# All destructive preparation is confined to the framework's disposable Docker.
verification_scenario_storage_migration() (
  local mode artifact_dir work before_config_hash backup history_hash candidate_version
  [[ -f /.dockerenv && "$(cat /proc/1/comm)" == systemd ]] || return 64
  verification_prepare_remote_legacy_script
  work=${VERIFY_REMOTE_LOCAL_TREE_DIR}
  artifact_dir=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/proof-boundaries.txt")
  artifact_dir=${artifact_dir%/*}
  cat > "${artifact_dir}/proof-boundaries.txt" <<'BOUNDARIES'
Real: fixed pre-layout runtime c281649d5bd4150810455151b85ecbfe678fea87,
legacy sbv update sbv transaction, new runtime's first CLI start, migration,
real core checks of HTTP plus loopback HY2 file-URI/manual-TLS material, systemd active/stopped preservation and failed
service activation rollback, system command/service symlinks, historical bytes.
Prepared: the archived-owner recovery copies a completed record into pending to
exercise real restoration; SIGKILL interruption is separately covered by host
fixtures. Local curl returns the current candidate only for the script-update
URL; core release downloads use the normal verified installer. A private systemctl
shim removes the owned candidate core execute bit immediately before real systemd
start, exercising an actual activation failure and old-service rollback. Dummy secrets
and local ruleset data are fixture-only. No production or external account writes.
BOUNDARIES
  trap 'verification_cleanup_remote_local_tree' EXIT
  printf 'SCENARIO=storage_migration\n'
  sha256sum "${VERIFY_REMOTE_INSTALL_SCRIPT}" "${VERIFY_REMOTE_LEGACY_INSTALL_SCRIPT}" > "${artifact_dir}/sources.sha256"
  for mode in active stopped; do
    # Every iteration constructs its own installation, including standalone runs.
    bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" --internal-uninstall-purge --yes
    [[ ! -e /root/sing-box-vps && ! -L /root/sing-box-vps ]]
    rm -rf -- /root/.sing-box-vps
    [[ ! -e /usr/local/bin/sbv && ! -e /usr/local/bin/sing-box && ! -e /etc/systemd/system/sing-box.service ]]
    SB_REALITY_SNI_VALIDATION_ASSUME_YES=1 bash "${VERIFY_REMOTE_LEGACY_INSTALL_SCRIPT}" \
      > "${artifact_dir}/${mode}-legacy-install.log" 2>&1 <<'ANSWERS'
1

6
19082
y
storage-user
/root/sing-box-vps/dummy-secret
n
0
ANSWERS
    verification_wait_for_service_active sing-box
    test -f /root/sing-box-vps/config.json
    test ! -e /root/.sing-box-vps/runtime
    # A referenced local file verifies that the migrated core opens new paths;
    # the password deliberately resembles an old-root path and must not change.
    mkdir -p /root/sing-box-vps/rule-set /root/sing-box-vps/site /root/sing-box-vps-backups/upgrade-fixture
    openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=storage.fixture.invalid \
      -keyout /root/sing-box-vps/storage-fixture.key -out /root/sing-box-vps/storage-fixture.crt \
      > "${artifact_dir}/${mode}-certificate.log" 2>&1
    printf 'owned storage masquerade fixture\n' > /root/sing-box-vps/site/index.html
    printf '{"version":3,"rules":[{"domain":["storage.fixture.invalid"]}]}\n' \
      > /root/sing-box-vps/rule-set/storage-fixture.json
    jq '.route.rule_set = ((.route.rule_set // []) + [{tag:"storage-fixture",type:"local",format:"source",path:"/root/sing-box-vps/rule-set/storage-fixture.json"}]) |
      .inbounds += [{type:"hysteria2",tag:"storage-hy2-masquerade-fixture",listen:"127.0.0.1",listen_port:19083,
        users:[{password:"storage-hy2-fixture-password"}],masquerade:"file:///root/sing-box-vps/site",
        tls:{enabled:true,certificate_path:"/root/sing-box-vps/storage-fixture.crt",key_path:"/root/sing-box-vps/storage-fixture.key"}}]' \
      /root/sing-box-vps/config.json > "${work}/config.next"
    cp "${work}/config.next" /root/sing-box-vps/config.json
    cp "${work}/config.next" /root/sing-box-vps/managed-config.generated.json
    chmod -R go-w /root/sing-box-vps
    sing-box check -c /root/sing-box-vps/config.json
    printf 'historical upgrade bytes\n' > /root/sing-box-vps-backups/upgrade-fixture/metadata.json
    (cd /root/sing-box-vps-backups/upgrade-fixture && sha256sum metadata.json > SHA256SUMS)
    # Historical foreign ownership is archive metadata, never runtime input.
    chmod 700 /root/sing-box-vps-backups
    chown 1001:1001 /root/sing-box-vps-backups/upgrade-fixture/metadata.json
    history_hash=$(sha256sum /root/sing-box-vps-backups/upgrade-fixture/metadata.json | awk '{print $1}')
    before_config_hash=$(sha256sum /root/sing-box-vps/config.json | awk '{print $1}')
    # Intercept only the update URL, leaving release downloads and validation real.
    mkdir -p "${work}/update-bin"
    cat > "${work}/update-bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
original=("$@")
output='' url=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output) output=$2; shift 2 ;;
    --connect-timeout|--max-time|--retry|--retry-delay) shift 2 ;;
    -*) shift ;;
    *) url=$1; shift ;;
  esac
done
if [[ "${url}" == https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/install.sh ]]; then
  [[ -n "${output}" ]]
  cp -- "${VERIFY_REMOTE_INSTALL_SCRIPT:?}" "${output}"
else
  exec /usr/bin/curl "${original[@]}"
fi
CURL
    chmod 700 "${work}/update-bin/curl"
    PATH="${work}/update-bin:${PATH}" bash /usr/local/bin/sbv update sbv \
      > "${artifact_dir}/${mode}-old-updater.log" 2>&1
    candidate_version=$(sed -n 's/^readonly SCRIPT_VERSION="\([0-9]*\)"$/\1/p' "${VERIFY_REMOTE_INSTALL_SCRIPT}")
    grep -Fqx "readonly SCRIPT_VERSION=\"${candidate_version}\"" /usr/local/bin/sbv
    bash /usr/local/bin/sbv storage status --json > "${artifact_dir}/${mode}-before.json"
    jq -se 'length==1 and .[0].ok==true and .[0].data.migration_required==true' \
      "${artifact_dir}/${mode}-before.json" >/dev/null
    # Reproduce the production legacy UID 1001 failure without stopping service.
    chown 1001:1001 /usr/local/bin/sing-box
    bash /usr/local/bin/sbv storage status --json > "${artifact_dir}/${mode}-unsafe-owner-status.json"
    jq -e '.ok and .data.blockers==["untrusted_system_entry"] and
      any(.data.blocker_details[]; .entry=="/usr/local/bin/sing-box" and .reason=="non_root_owner")' \
      "${artifact_dir}/${mode}-unsafe-owner-status.json" >/dev/null
    if bash /usr/local/bin/sbv storage migrate --json --yes \
      > "${artifact_dir}/${mode}-unsafe-owner-migrate.json" 2> "${artifact_dir}/${mode}-unsafe-owner.stderr"; then return 1; fi
    [[ ! -e /root/.sing-box-vps/migrations/pending ]]
    verification_wait_for_service_active sing-box
    chown 0:0 /usr/local/bin/sing-box
    if [[ "${mode}" == stopped ]]; then
      systemctl stop sing-box
    else
      # Fail the actual systemd activation after the candidate core check. A
      # private shim alters only the owned candidate's execute bit at start;
      # every systemctl call still reaches real systemd. A drop-in would now
      # be rejected by preflight and could not establish rollback evidence.
      mkdir -p "${work}/activation-bin"
      cat > "${work}/activation-bin/systemctl" <<'ACTIVATION_SYSTEMCTL'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == start && "${2:-}" == sing-box ]]; then
  current_start=$(/usr/bin/systemctl show --property=ExecStart --value sing-box)
  if [[ "${current_start}" == *'/root/.sing-box-vps/bin/sing-box'* && ! -e "${VERIFY_STORAGE_FAIL_MARKER:?}" ]]; then
    [[ -f /root/.sing-box-vps/bin/sing-box && ! -L /root/.sing-box-vps/bin/sing-box ]]
    chmod 000 /root/.sing-box-vps/bin/sing-box
    printf 'candidate_execute_bit_removed_before_real_systemd_start\n' > "${VERIFY_STORAGE_FAIL_MARKER}"
  fi
fi
exec /usr/bin/systemctl "$@"
ACTIVATION_SYSTEMCTL
      chmod 700 "${work}/activation-bin/systemctl"
      if PATH="${work}/activation-bin:${PATH}" VERIFY_STORAGE_FAIL_MARKER="${work}/activation-injected" \
        bash /usr/local/bin/sbv storage migrate --json --yes \
        > "${artifact_dir}/failed-migration.json" 2> "${artifact_dir}/failed-migration.stderr"; then
        printf 'migration accepted a failing service activation\n' >&2
        return 1
      fi
      [[ -f "${work}/activation-injected" ]]
      cp -- "${work}/activation-injected" "${artifact_dir}/activation-injected.txt"
      grep -Fq 'storage migration: postcheck' "${artifact_dir}/failed-migration.stderr"
      grep -Fq 'storage migration: rolled_back' "${artifact_dir}/failed-migration.stderr"
      jq -se 'length==1 and .[0].ok==false' "${artifact_dir}/failed-migration.json" >/dev/null
      [[ ! -L /usr/local/bin/sbv && ! -L /usr/local/bin/sing-box && ! -L /etc/systemd/system/sing-box.service ]]
      [[ "$(sha256sum /root/sing-box-vps/config.json | awk '{print $1}')" == "${before_config_hash}" ]]
      verification_wait_for_service_active sing-box
    fi
    bash /usr/local/bin/sbv storage migrate --json --yes \
      > "${artifact_dir}/${mode}-migration.json" 2> "${artifact_dir}/${mode}-migration.stderr"
    jq -se 'length==1 and .[0].ok==true and .[0].data.migration_required==false and .[0].data.recovery_required==false' \
      "${artifact_dir}/${mode}-migration.json" >/dev/null
    for link in /usr/local/bin/sbv /usr/local/bin/sing-box /etc/systemd/system/sing-box.service; do
      [[ -L "${link}" && "$(readlink "${link}")" == /root/.sing-box-vps/* ]]
    done
    [[ ! -e /root/sing-box-vps && ! -e /root/sing-box-vps-backups ]]
    jq -e 'any(.route.rule_set[]; .path=="/root/.sing-box-vps/runtime/rule-set/storage-fixture.json") and
      any(.inbounds[].users[]; .password=="/root/sing-box-vps/dummy-secret")' \
      /root/.sing-box-vps/runtime/config.json >/dev/null
    # Validate the owned HY2 file-URI fixture with the real target core after
    # migration; both the URI and its TLS/material paths must open in the new root.
    jq -e 'any(.inbounds[]; .tag=="storage-hy2-masquerade-fixture" and
      .masquerade=="file:///root/.sing-box-vps/runtime/site" and
      .tls.certificate_path=="/root/.sing-box-vps/runtime/storage-fixture.crt" and
      .tls.key_path=="/root/.sing-box-vps/runtime/storage-fixture.key")' \
      /root/.sing-box-vps/runtime/config.json >/dev/null
    test -s /root/.sing-box-vps/runtime/storage-fixture.crt
    test -s /root/.sing-box-vps/runtime/storage-fixture.key
    test -s /root/.sing-box-vps/runtime/site/index.html
    cp -- /root/.sing-box-vps/runtime/config.json "${artifact_dir}/${mode}-migrated-config.json"
    sing-box check -c "${artifact_dir}/${mode}-migrated-config.json" > "${artifact_dir}/${mode}-migrated-config.check" 2>&1
    sing-box check -c /root/.sing-box-vps/runtime/managed-config.generated.json > "${artifact_dir}/${mode}-migrated-baseline.check" 2>&1
    printf 'target_core_check=passed\nhy2_file_uri_tls_material_paths=passed\n' > "${artifact_dir}/${mode}-config-check.env"
    backup=$(jq -r .backup /root/.sing-box-vps/migrations/completed.json)
    [[ "$(sha256sum "${backup}/legacy-backups/upgrade-fixture/metadata.json" | awk '{print $1}')" == "${history_hash}" ]]
    [[ "$(stat -c '%u:%g' "${backup}/legacy-backups/upgrade-fixture/metadata.json")" == 1001:1001 ]]
    (cd "${backup}/legacy-backups/upgrade-fixture" && sha256sum -c SHA256SUMS)
    if [[ "${mode}" == active ]]; then
      verification_wait_for_service_active sing-box
      verification_assert_port_listening 19082 "${VERIFY_CURRENT_SCENARIO_DIR}/active-listeners.txt"
    else
      if systemctl is-active --quiet sing-box; then return 1; fi
    fi
    if [[ "${mode}" == active ]]; then
      # Copy the fully completed record back to pending to exercise the same
      # archived-tree recovery validator with real systemd and foreign UID data.
      mkdir -m 700 /root/.sing-box-vps/migrations/pending
      cp -p /root/.sing-box-vps/migrations/completed.json /root/.sing-box-vps/migrations/pending/journal.json
      bash /usr/local/bin/sbv storage recover --json --yes > "${artifact_dir}/archived-owner-recover.json"
      verification_wait_for_service_active sing-box
      [[ "$(stat -c '%u:%g' /root/sing-box-vps-backups/upgrade-fixture/metadata.json)" == 1001:1001 ]]
      bash /usr/local/bin/sbv storage migrate --json --yes > "${artifact_dir}/archived-owner-remigrate.json"
      verification_wait_for_service_active sing-box
    fi
    # Repetition is a no-op even after old paths have been archived.
    bash /usr/local/bin/sbv storage migrate --json --yes > "${artifact_dir}/${mode}-repeat.json"
    jq -e '.ok==true and .data.migration_required==false' "${artifact_dir}/${mode}-repeat.json" >/dev/null
    verification_mark_step "storage_${mode}_migration_passed"
    # Remove only this scenario's extra loopback manual inbound after recording
    # its checked migrated configuration, returning to the HTTP smoke baseline.
    jq '.inbounds |= map(select(.tag!="storage-hy2-masquerade-fixture"))' \
      /root/.sing-box-vps/runtime/config.json > "${work}/http-only.next"
    cp -- "${work}/http-only.next" /root/.sing-box-vps/runtime/config.json
    cp -- "${work}/http-only.next" /root/.sing-box-vps/runtime/managed-config.generated.json
    sing-box check -c /root/.sing-box-vps/runtime/config.json > "${artifact_dir}/${mode}-http-baseline.check" 2>&1
    [[ "${mode}" != active ]] || systemctl restart sing-box
    # The framework's final smoke explicitly needs a running installation.
    [[ "${mode}" != stopped ]] || systemctl start sing-box
  done
)
