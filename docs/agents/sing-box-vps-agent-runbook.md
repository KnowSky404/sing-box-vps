# sing-box-vps Agent Runbook

This runbook is for AI agents operating the `sing-box-vps` repository and remote VPS hosts. It is written for Hermes, OpenClaw, Codex, Claude Code, and other automation agents.

The additive `protocol_registry` in `sbv agent capabilities --json` describes each managed protocol family, preset, component role, state ID, public Agent ID and capability. The legacy `protocols` object and JSON envelopes retain their existing meanings. `available=null` and `validated.status=not_assessed` mean that the current environment and instance connection have not been verified; do not treat implemented adapters as deployment approval or successful runtime evidence. The legacy alias `vless` continues to mean VLESS REALITY, and the Hysteria2 state ID remains `hy2`.

Client exports validate component references before the target core check and publication. A rejected candidate returns `client_config_validation_failed` with `ok=false`; the previous export and backup remain unchanged. Graph diagnostics go to stderr without config contents or user-controlled tags. This candidate preflight does not change the read-only `check`/upgrade behavior for existing configurations or imply support for additional managed protocols.

Unknown state IDs or future schema versions block reconstruction while preserving those entries. Live inbound discovery is also all-or-nothing: unknown types, non-REALITY VLESS, duplicate single-instance protocols, and duplicate explicit tags block reconciliation, takeover, and regeneration before resource preparation. `status`, `nodes`, and `links` then return `live_inbound_inventory_untrusted` instead of presenting a partial protocol/node list as complete. This inventory check does not certify custom fields, outbounds, endpoints, or routes as losslessly managed. Restore a compatible script or reviewed backup to recover; do not remove unknown files or config components to bypass the guard. Track the full protocol expansion and evidence in [the implementation record](../superpowers/plans/2026-09-06-unified-protocol-management.md) and [the upstream matrix](../superpowers/specs/2026-09-06-protocol-coverage.md).

## First Principles

- Treat `install.sh` as the single runtime source of truth.
- Read `AGENTS.md` and `README.md` before changing repository behavior.
- Use `sing-box-test` for test VPS validation.
- Use `sing-box-prod` for production VPS operations.
- Remote verification runs in Docker locally, auto-building the sing-box-vps-verify image. No external SSH target required.
- Preserve secrets. Do not print private keys, passwords, tokens, full proxy links, or QR payloads unless the user explicitly requests them and the context is safe.
- Back up runtime config before changing it.
- Run `sing-box check` after generating or modifying any sing-box server or client config.
- Treat client exports, full link JSON, and SubMan sync payloads as sensitive connection material.

## Environment Classification

Classify the target before acting:

- **Local repository**: files under the project workspace.
- **Test VPS**: SSH target `sing-box-test`, used for validation and disposable install tests.
- **Production VPS**: SSH target `sing-box-prod`, used by real users or real traffic.
- **Unknown host**: any host that is not clearly local, test, or production.

If a remote host is unknown, treat it as production until the user clarifies.

## Production Safety Gate

Production operations are plan-first. Before any production-changing command, present a plan and wait for explicit approval.

Production-changing commands include:

- Fresh install or upgrade.
- Service restart, stop, disable, enable, or reload.
- Config rewrite, protocol change, Warp change, or firewall change.
- Uninstall, purge, cleanup, or deletion of runtime files.
- Overwriting `/usr/local/bin/sbv`, `/root/sing-box-vps/`, or sing-box systemd units.

Read-only checks may be used to prepare the plan:

```bash
ssh sing-box-prod 'hostname; uptime; command -v sbv || true; command -v sing-box || true'
ssh sing-box-prod 'systemctl status sing-box --no-pager || true'
ssh sing-box-prod 'sing-box version || true'
ssh sing-box-prod 'ls -la /root/sing-box-vps /usr/local/bin/sbv 2>/dev/null || true'
```

Do not run state-changing production commands until the user approves the plan.

## Production Operation Plan Template

Use this exact structure before changing production:

```md
# Production Operation Plan

## Target
- Host: sing-box-prod
- Purpose:

## Current State Checks
- Commands:
- Expected findings:

## Planned Actions
- Commands:
- Expected effect:

## Risk
- User impact:
- Config/data touched:

## Backup / Recovery
- Backup paths:
- Recovery commands:

## Verification
- Commands:
- Success criteria:

## Awaiting Approval
No production-changing commands will be executed until approved.
```

## Local Repository Workflow

For code or script changes:

1. Inspect the current repository state with `git status --short`.
2. Read the affected files before editing.
3. Keep edits scoped to the task.
4. If `install.sh`, `uninstall.sh`, `configs/`, `utils/`, or `dev/verification/` changes, run:

```bash
bash dev/verification/run.sh
```

5. If only local dispatch rules need validation, use:

```bash
VERIFY_SKIP_REMOTE=1 bash dev/verification/run.sh
```

6. When runtime behavior changes, update `SCRIPT_VERSION` in `install.sh` and the version shown in `README.md`.
7. Commit atomically with a conventional commit message after verification.

Documentation-only changes do not require `SCRIPT_VERSION` updates.

## Test VPS Verification

Use the repository workflow unless the user asks for a direct manual test.

Remote verification runs via Docker locally.

Run:

```bash
bash dev/verification/run.sh
```

The verification runner decides whether remote scenarios are required based on changed files. It writes artifacts under the run directory printed as `run_dir=...`.

When remote validation fails:

1. Read `summary.log`.
2. Inspect `remote.stderr.log` and `remote.stdout.log`.
3. Inspect extracted remote artifacts if present.
4. Fix the root cause before rerunning verification.

## Fresh Install On A New VPS

For a test VPS, direct installation is allowed when the user asked for a test installation and the host is clearly `sing-box-test`.

For production or unknown hosts, use the production plan gate first.

Canonical public install command:

Use the complete staged Bootstrap in `README.md`. It downloads to a `mktemp`
file, validates the script before execution, and must not be replaced with
`curl | bash` or process substitution.

Post-install checks:

```bash
command -v sbv
systemctl status sing-box --no-pager
sing-box check -c /root/sing-box-vps/config.json
```

If the install generates or displays credentials, summarize that credentials were generated without pasting secrets into logs.

## Complete Capability Map

Keep historical functions in scope when planning or documenting a change:

| Area | Current capability | Agent route |
|---|---|---|
| Protocols | VLESS REALITY, Mixed HTTP/SOCKS, Hysteria2, AnyTLS; protocols can coexist | Discover with `capabilities`; summaries with `nodes`; install/edit/remove remain interactive |
| REALITY | Multiple instances, independent ports/ShortID/names, per-instance outbound policy and optional upload/download QoS | Read with `nodes`; mutate through the interactive protocol menu |
| TLS | Hysteria2/AnyTLS ACME HTTP-01, Cloudflare DNS-01, or manual certificate paths | Read warnings/check output; mutate interactively |
| Warp | Account registration, enable/disable, all/selective routing, built-in/custom domains, local/remote rule sets | Read with `warp`; mutate through menu 13 |
| Network/system | IPv4/IPv6/dual inbound stack, outbound/DNS strategy, BBR | Read config/doctor; mutate through menu 14 |
| Node material | Links/QR, bare-core client export, dual-stack labels | `nodes` is log-safe; `links` and `export-client` are sensitive |
| SubMan | Idempotent VLESS/Hysteria2 sync, revision/error/retry semantics | `subman-sync` is sensitive and externally mutating |
| Lifecycle | start/stop/restart/status/logs, managed-instance takeover/repair, core/script upgrade, two uninstall scopes | Status/check/doctor are read-only; only restart and fixed core upgrade have guarded Agent mutations |
| Verification | Config check, live protocol probes, Docker fresh install/reconfigure/takeover/uninstall, four-protocol coexistence, and 1.13→1.14 success/rollback scenarios | Use `bash dev/verification/run.sh` |

Do not invent non-interactive mutations for features marked interactive-only. Use the menu after the appropriate safety gate or stop and ask for operator approval.

## Upgrade Existing VPS

For production, use the plan gate first.

First update only the management command, start a new invocation, and verify the new Agent surface:

```bash
sbv update sbv
sbv agent capabilities --json
```

For automation, use a fixed target and preserve the preflight JSON:

```bash
sbv agent upgrade-check --json 1.14.0
sbv agent upgrade --json 1.14.0 --yes
```

Require `ready=true` and an empty `blockers` array. The read-only preflight validates the currently installed core and reports known schema warnings without reconciling or migrating protocol state, but intentionally does not download the target binary. The guarded upgrade creates a root-only persistent backup, installs the target, runs the target core's `sing-box check` before restart, verifies the exact version/config hash/service, and attempts to restore the old binary and previous service activity on any failed invariant. `SHA256SUMS` covers every regular file in the copied runtime tree plus the binary, `sbv`, service unit, and metadata. `transaction-result.json` is written atomically beside that manifest and records the transaction ID, versions, status history, manifest hash, and rollback result. It never rewrites the server config for migration.

The ordinary operator path `sbv update sing-box [latest|x.y.z]` remains available, but Agent automation should use the fixed-version guarded command. Both paths only operate on a healthy managed instance and return nonzero when the target rejects the config. If the instance is incomplete or missing, enter the interactive `sbv` menu for repair/takeover instead of forcing an upgrade.

After upgrade:

```bash
sing-box version
sing-box check -c /root/sing-box-vps/config.json
systemctl status sing-box --no-pager
```

If service health changed, collect logs:

```bash
journalctl -u sing-box --no-pager -n 200
```

## Operations And Troubleshooting

Useful read-only checks:

```bash
sbv
sbv agent status --json
sbv agent nodes --json
sbv agent check --json
sbv agent doctor --json
systemctl status sing-box --no-pager
journalctl -u sing-box --no-pager -n 200
sing-box check -c /root/sing-box-vps/config.json
ls -la /root/sing-box-vps /root/sing-box-vps/protocols
```

Use the non-interactive Agent interface when automation needs stable output:

```bash
sbv agent capabilities --json
sbv agent upgrade-check --json 1.14.0
sbv agent upgrade --json 1.14.0 --yes
sbv agent status --json
sbv agent nodes --json
sbv agent links --json
sbv agent export-client --json
sbv agent check --json
sbv agent doctor --json
sbv agent service restart --json --yes
sbv agent warp --json
sbv agent subman-sync --json
sbv update sbv
sbv update sing-box latest
```

- `status --json` is safe for routine diagnostics. It reports script/core/service/path/protocol state plus inbound/outbound stack modes, BBR, REALITY instance/QoS counts, and whether client export/SubMan files exist; it does not return credentials.
- `capabilities --json` is read-only and returns the supported protocol/feature matrix plus safety labels. `upgrade-check --json 1.14.0` is read-only and must precede an upgrade; require `ready=true` and `blockers=[]`. Its `target_binary_validation.performed=false` means target validation is deferred to the guarded apply transaction, not that compatibility was already proven.
- `nodes --json` is safe for ordinary logs. It reports every protocol and every REALITY instance, including names, ports, server names, rate limits, outbound policy, and exportability without UUIDs, keys, full share links, or passwords.
- `links --json` returns full connection material for every protocol and every REALITY instance. Treat its output as sensitive and avoid pasting it into public logs. Hysteria2 nodes using a manual Ed25519 certificate include `warnings[].code=hy2_ed25519_share_link_requires_client_override` because the share URI cannot carry the required 1.14+ client option.
- `export-client --json` generates `/root/sing-box-vps/client/sing-box-client.json`, validates it with `sing-box check`, and returns the path plus config JSON. It writes the client export file but does not change the running server config or restart services. For a 1.14+ Hysteria2 Ed25519 target it sets top-level `disable_chrome_parrot: true` and returns `warnings[].code=hy2_ed25519_chrome_parrot_disabled`.
- `check --json` validates the server config with `sing-box check` and returns stdout, stderr, exit code, and pass/fail state.
- `doctor --json` is read-only. It returns status, path existence checks, protocol state, and embedded config-check output for first-pass agent diagnostics.
- `service restart --json --yes` is a guarded mutation. It validates config first and skips restart when validation fails.
- `warp --json` reports Cloudflare Warp state: enabled/disabled, route mode (`all` or `selective`), account registration health, and counts for custom domains, local rule sets, remote rule sets, and builtin AI/streaming domain rules. Safe for routine diagnostics.
- `subman-sync --json` pushes nodes to SubMan without prompting. Missing SubMan config is reported as structured JSON. Hysteria2 manual Ed25519 nodes carry the same share-link compatibility warning as `links --json`.
- `update sbv` updates `/usr/local/bin/sbv` from the project main branch.
- `update sing-box [latest|x.y.z]` updates only the sing-box binary, preserves the current server config byte-for-byte, validates it with `sing-box check`, and restarts the service only after validation passes. The aliases are `sbv update-sbv` and `sbv update-sing-box [latest|x.y.z]`.
- `upgrade --json 1.14.0 --yes` is the auditable Hermes path: it is mutating and service-impacting, persists a backup under `/root/sing-box-vps-backups/`, preserves `config.json` byte-for-byte, validates before restart, and attempts automatic binary recovery on failure. For an actual change, require `transaction.result_persisted=true`, then retain the referenced root-only `transaction-result.json`; it records `backup_ready` plus the terminal `success`, `rolled_back`, or `rollback_failed` state, and terminal records include `failure_reason` plus `operation_exit_code` when applicable. If the target is already installed, the no-op response instead has `changed=false`, `transaction.status=not_attempted`, `transaction.reason=already_installed`, and no backup or result file. Recovery is complete only when both `rolled_back` and `rollback_ok` are true; `error=rollback_failed` plus `manual_intervention_required=true` is a hard stop. It never silently rewrites configuration for migration. All public Agent protocol IDs use `vless-reality`, `mixed`, `hysteria2`, or `anytls`; the internal Hysteria2 state filename remains `hy2.env`. `export-client` and `subman-sync` are also mutating; `links`, export, and SubMan output are sensitive. Installation, protocol edits, REALITY/QoS, Warp, BBR, media checks, takeover/repair, and uninstall remain interactive-only.

## sing-box 1.14 Compatibility

- Fresh installs and regenerated configs targeting 1.14+ use top-level ACME `certificate_providers`; Hysteria2 and AnyTLS inbounds reference them through `tls.certificate_provider`.
- Remote rule sets targeting 1.14+ use `http_client.detour`. Explicitly pinned or installed 1.13.x targets retain the legacy inline `tls.acme` and rule-set layout.
- A binary-only update never migrates or rewrites the server config. The target binary must accept the existing file via `sing-box check` before the service is restarted.
- Hysteria2 manual Ed25519 certificates are detected with OpenSSL. Generated 1.14+ client outbounds receive top-level `disable_chrome_parrot: true`; share links cannot encode this field, so human and Agent interfaces emit a warning.
- If the manual certificate algorithm cannot be inspected, Agent output uses `warnings[].code=hy2_certificate_algorithm_unknown`; operators should verify the certificate and client compatibility manually.
- Inline `tls.acme` and legacy `download_detour` are deprecated in 1.14 but remain accepted for compatibility; both are scheduled for removal in 1.16. A binary-only upgrade does not migrate them.

For the complete single-host rehearsal, including stop conditions, evidence requirements, and rollback assertions, use `docs/agents/sing-box-1.13-to-1.14-upgrade-test.md`.

Common paths:

- Runtime directory: `/root/sing-box-vps/`
- Main config: `/root/sing-box-vps/config.json`
- Protocol state: `/root/sing-box-vps/protocols/`
- VLESS REALITY instance state: `/root/sing-box-vps/protocols/vless-reality.d/`
- VLESS REALITY QoS state: `/root/sing-box-vps/reality-qos.filters`
- Client export: `/root/sing-box-vps/client/sing-box-client.json`
- SubMan config: `/root/sing-box-vps/subman.env`
- Warp domains: `/root/sing-box-vps/warp-domains.txt`
- Global command: `/usr/local/bin/sbv`
- Agent upgrade backups: `/root/sing-box-vps-backups/` (sensitive, root-only)
- systemd service: `sing-box`

For config problems, do not guess from symptoms alone. Run `sing-box check`, inspect the generated JSON, and compare protocol state files to the runtime config.

## VLESS REALITY Multi-Instance Notes

VLESS REALITY can be installed as multiple managed instances. Each instance may have a distinct port, ShortID, node name, and optional upload/download Mbps limit. Instance state is authoritative; do not hand-edit generated `config.json` to add or remove REALITY inbounds.

When more than one REALITY instance exists, the interactive removal flow asks whether to remove one instance or the entire VLESS REALITY protocol. Confirm the scope explicitly; successful removal regenerates and validates the config, refreshes QoS, restarts the service when protocols remain, and closes ports that are no longer managed.

When diagnosing REALITY:

```bash
sbv agent nodes --json
ls -la /root/sing-box-vps/protocols/vless-reality.d 2>/dev/null || true
cat /root/sing-box-vps/reality-qos.filters 2>/dev/null || true
sing-box check -c /root/sing-box-vps/config.json
```

Use `nodes --json` for log-safe summaries. Use `links --json` only in trusted contexts because it includes full share links. If QoS or instance membership changes on production, use the production gate before running the interactive menu or guarded service mutations.

## WARP Operations

WARP state can be inspected non-interactively:

```bash
sbv agent warp --json
```

This returns `enabled`, `route_mode`, account registration health, and routing asset counts (custom domains, local/remote rule sets, builtin AI/streaming rules) plus related file paths.

`status --json` also includes a `warp` block with `enabled` and `route_mode`.

To change WARP state (enable/disable, mode switch, re-register, add domains or rule sets), use the interactive menu:

```bash
sbv
# Navigate: 13 -> Cloudflare Warp
```

On production, WARP mutations are production-changing operations. Use the production gate first.

## Client Export And SubMan

Use client export when an agent or client needs a full sing-box bare-core config:

```bash
sbv agent export-client --json
```

The command writes `/root/sing-box-vps/client/sing-box-client.json`, creates a `.bak` when replacing an existing export, and validates the generated config before returning success. Treat the returned JSON as sensitive because it contains usable connection credentials.

Use SubMan sync only when `/root/sing-box-vps/subman.env` is configured and the output context is trusted:

```bash
sbv agent subman-sync --json
```

SubMan sync is non-interactive for agents and pushes VLESS REALITY and Hysteria2 nodes idempotently. Missing API configuration is reported as structured JSON rather than prompting.

## Rollback And Recovery

The guarded Agent upgrade attempts to restore the old binary automatically when its target validation or postconditions fail. First inspect `error`, `failure_reason`, `rollback_attempted`, `rolled_back`, `rollback_ok`, `manual_intervention_required`, `installed`, `config_preserved`, `service`, the exact `backup` path, and `transaction.{id,result_path,status,result_persisted,manifest,rollback}` in its JSON result. Agent `--json` responses use `schema_version: "1.0"` while retaining top-level `schema: "1"` compatibility. For an actual change, a false `transaction.result_persisted` is a failed operation even if the runtime postconditions otherwise succeeded; an already-installed no-op is the explicit exception described above.

Manual recovery is only for `rollback_ok=false`. Validate the returned path prefix and its manifest before copying anything; on production, present these exact commands in a new plan and wait for approval:

```bash
systemctl stop sing-box
backup=/root/sing-box-vps-backups/upgrade-EXACT-DIRECTORY-FROM-JSON
case "${backup}" in /root/sing-box-vps-backups/upgrade-*) ;; *) exit 1 ;; esac
(cd "${backup}" && sha256sum -c SHA256SUMS)
install -m 0755 "${backup}/sing-box" /usr/local/bin/sing-box
install -m 0644 "${backup}/sing-box.service" /etc/systemd/system/sing-box.service
install -m 0600 "${backup}/runtime/config.json" /root/sing-box-vps/config.json
systemctl daemon-reload
/usr/local/bin/sing-box check -c /root/sing-box-vps/config.json
systemctl start sing-box
systemctl status sing-box --no-pager
```

## External Documentation

When current `sing-box` configuration syntax, migration behavior, or version compatibility is needed, use Context7 first. If Context7 cannot provide enough detail, use official `sing-box` documentation or the official repository before relying on third-party posts.
