# sing-box-vps Agent Runbook

This runbook is for AI agents operating the `sing-box-vps` repository and remote VPS hosts. It is written for Hermes, OpenClaw, Codex, Claude Code, and other automation agents.

The additive `protocol_registry` in `sbv agent capabilities --json` describes each managed protocol family, preset, component role, state ID, public Agent ID and capability. The legacy `protocols` object and JSON envelopes retain their existing meanings. Each protocol's read-only `environment` reports current core/version/build-tag prerequisites; it does not prove that a particular instance is configured or reachable. `available=null` remains an instance-readiness placeholder, while `validated.status=not_assessed` means no instance-specific validation evidence is attached. The additive top-level `managed_registry` merges protocol and advanced-component records and marks each with `registry_kind`; existing registry fields remain compatible. Never treat an implemented adapter or an available environment as deployment approval or successful runtime evidence. The legacy alias `vless` continues to mean VLESS REALITY, the Hysteria2 state ID remains `hy2`, standalone SOCKS is registry/menu item 5 with state and Agent ID `socks`, standalone HTTP is registry/menu item 6 with state and Agent ID `http`, Shadowsocks is registry/menu item 7 with state and Agent ID `shadowsocks` plus alias `ss`, Trojan is registry/menu preset 8 with state/Agent ID `trojan` and protocol management via main menu 2, VMess is registry/menu preset 9 with state/Agent ID `vmess` and protocol management via main menu 2, AnyTLS uses state/Agent ID `anytls` with protocol management via main menu 2, structured Hysteria2 uses Agent ID `hysteria2` with protocol management via main menu 2, Snell uses state/Agent ID `snell` with registry preset 11 and protocol management via main menu 2, TUIC uses state/Agent ID `tuic` with registry preset 12 and protocol management via main menu 2, Hysteria v1 uses Agent ID `hysteria` with registry preset 13 and protocol management via main menu 2, NaiveProxy uses Agent ID `naive` with registry preset 14 and protocol management via main menu 2, and ShadowTLS uses state/Agent ID `shadowtls` with protocol management via main menu 2. SOCKS, HTTP, Shadowsocks, VLESS outbound, Trojan, VMess, Hysteria2, Hysteria v1, AnyTLS, Snell, TUIC, NaiveProxy, ShadowTLS, and the typed WireGuard, Tailscale, OpenConnect, and OpenVPN endpoints are covered by the focused evidence recorded below. Current tracked acceptance and compatibility boundaries are recorded in the [completion contract](https://github.com/KnowSky404/sing-box-vps/blob/main/docs/specs/full-protocol-completion.md). The supported sing-box baseline is `1.14.2`; treat `sbv agent capabilities --json` and its `script_version` as the live contract authority. The Shadowsocks-specific section retains its historical `2026090802` evidence.


运维入口：[命令参考](https://github.com/KnowSky404/sing-box-vps/wiki/Agent-CLI) · [高级组件](https://github.com/KnowSky404/sing-box-vps/wiki/Advanced-Components) · [协议实例](https://github.com/KnowSky404/sing-box-vps/wiki/Protocol-Instances) · [数据面证据](https://github.com/KnowSky404/sing-box-vps/wiki/Data-Plane-Verification)

## First Principles

Instance identity is scoped by protocol and instance ID. Shared read-only adapters expose legacy singleton files as `main` and retain REALITY's existing IDs/default. Agent nodes/links and client rendering for Mixed, standalone SOCKS, HTTP, Shadowsocks, Trojan, VMess, Hysteria2, Hysteria v1, AnyTLS, Snell, TUIC, NaiveProxy and ShadowTLS expose each structured instance and its revision without migrating legacy state or preparing credentials. Existing public Agent fields remain unchanged; the documented SOCKS, HTTP, Shadowsocks, Trojan, VMess, Hysteria2, Hysteria v1, AnyTLS, Snell, TUIC, NaiveProxy and ShadowTLS lifecycle/runtime surfaces are covered by the focused evidence below.

The structured stores under `protocols/instances/<protocol>.json` have typed Mixed, standalone SOCKS, HTTP, Shadowsocks, Trojan, VMess, Hysteria2, Hysteria v1, AnyTLS, Snell, TUIC, NaiveProxy and ShadowTLS validators/renderers and are connected to the guarded instance lifecycle. Read operations use `sbv agent instance view|diagnose|export <protocol> --json [--id ID] [--expected-revision N]`; `view` and `diagnose` use a shared lock and redact credentials, while `export` is sensitive and returns the typed record plus connection material. Use `sbv agent instance create|replace|delete|default|rebuild|takeover|migrate|recover mixed --json --yes --expected-revision N` for Mixed; standalone SOCKS, HTTP, Shadowsocks, Trojan, VMess, Hysteria2, Hysteria v1, AnyTLS, Snell, TUIC, NaiveProxy and ShadowTLS support the same write operations except `migrate`, which is rejected because they have no legacy `.env` migration path. `rebuild` repairs a managed projection drift through the normal candidate, listener/resource, target-core check, firewall journal, service and rollback phases, while `takeover` starts at revision 0 only when no active typed marker/store exists and imports the complete losslessly representable live inventory; non-loopback takeover requires `--allow-public`. Existing live SOCKS/HTTP/Shadowsocks/Trojan/VMess configuration uses takeover; Hysteria2 and AnyTLS takeover accepts only the typed manual-TLS subset and preserves ACME/provider legacy state when that subset is not lossless; Hysteria v1 takeover accepts only the typed manual-TLS QUIC subset; Snell takeover accepts only its typed v5/v6 fields; TUIC takeover accepts only the typed manual-TLS QUIC subset; NaiveProxy takeover accepts only the typed manual-TLS TCP/UDP subset; ShadowTLS takeover accepts only the typed composite outer-plus-loopback-Mixed subset. Create/replace require a complete private `--file` record and delete/default require `--id`. Do not hand-edit stores or treat file rollback as a complete service/resource transaction; lifecycle writes use the managed-state snapshot, configuration publication, listener/resource checks and persistent recovery boundaries. See the [implementation record](https://github.com/KnowSky404/sing-box-vps/wiki/Verification-History) for the evidence boundary and its limits.

Client export includes Mixed and standalone SOCKS as SOCKS5 outbounds with explicit UoT v2, HTTP CONNECT as documented in its own section, and Shadowsocks as full JSON preserving its network/authentication fields. It preserves stored authentication mode and credentials; missing or invalid port/authentication state aborts the whole export without rotating the existing file or backup. `nodes.client_exportable` and `capabilities` reflect this. Export responses include a plaintext transport warning where applicable: SOCKS5 credentials and unencrypted application traffic are exposed on the proxy hop without TLS, so use a trusted network or protected tunnel. UoT encapsulates UDP over TCP, does not encrypt it, and requires no additional fixed server UDP listener. Standalone SOCKS has no HTTP/TLS surface or SubMan sync; its lifecycle/runtime/export paths passed the final gate, while public native UDP remains unverified. The final Shadowsocks export/runtime evidence covers its typed full-JSON path and documented warnings; it does not imply unsupported fields.

Managed server candidates and typed stores now check fixed listener conflicts by canonical address, address family, TCP/UDP, port and inbound tag. Cleanup of a removed listener uses the previous config backup and remaining listeners: it retains any transport/port still referenced and does not delete unrelated transports. An absent/unmodelled inventory blocks cleanup; a backend failure returns nonzero and explicitly reports possibly partial external changes. Do not infer a firewall ownership ledger, other-process port availability, dynamic SOCKS UDP/ACME resource coverage, or full service/resource rollback from this preflight. Existing `agent check` still means the core check, not a port reservation.

The resource contract is `managed_listener_plan <config_file>`: it emits a JSON listener array with `owner` (inbound tag), `protocol` (registered state ID), canonical `address`, `family` (`ipv4`/`ipv6`), `transport` (`tcp`/`udp`), `port`, and `dual_stack`. The registered `listen_networks` for Mixed, standalone SOCKS, HTTP, Shadowsocks and Trojan drive transport projection; IPv6 `::` canonicalizes to the all-zero IPv6 address and is marked dual-stack. Unknown inbound types and `netns`, `bind_interface` or `reuse_addr` listeners are rejected. The plan is a resource preflight, not proof that an existing broad firewall rule belongs to this instance. Trojan projects its actual listener from the typed transport (TCP for native/HTTP/WS/gRPC, UDP for TLS QUIC), not from the registry's possible-network union.

Opening rules now uses the entire committed listener plan without migrating state, and opens only actual registered listening transports. Full removal requires a successful service stop and confirmed inactive state before clearing the config/index; failed stop restores managed files and leaves firewall rules unchanged. A post-publication opening error reports `config_committed`, `firewall_may_be_partial`, and `service_restart_not_attempted`. It is not a successful rollback; inspect the service and external resources manually.

REALITY takeover matches live inbound tags to existing managed instance identities. It preserves their display names, upload/download QoS and default instance while rebuilding connection parameters from the live configuration. The saved public key is reusable only with a matching private key. Ambiguous identity mappings stop reconstruction; a state-write failure restores the previous protocol state tree. These metadata guarantees do not establish lossless handling of arbitrary custom sing-box fields or external system resources.

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
4. Select the smallest sufficient verification set using [AGENTS.md](https://github.com/KnowSky404/sing-box-vps/blob/main/AGENTS.md), section 4.2, and explain the actual behavioral impact. Documentation, version-display and menu-only edits do not require broad regression because of their file path. Configuration changes require `sing-box check` on affected outputs; service, network and lifecycle changes require corresponding real Docker scenarios.
5. Run changed standalone tests and callers of changed helpers. Include Bootstrap download/validation tests when affected. Full regression is required for core-version adaptation or config/state migrations, broadly affected shared logic or uncertain impact, or an explicit full-test/release-acceptance requirement. Reuse prior passing results only under section 4.2's unchanged-input conditions, with the original evidence and reason recorded; after fixes, rerun failed and affected checks.
6. Preview the dispatcher with `bash dev/verification/run.sh --plan --base origin/main`. Use explicit local `--group` and Docker `--scenario` selections for unmapped runtime changes, or request the registered full set with `--full`. Review their scope under section 4.2; groups do not automatically request runtime coverage. The planner supplies scenario baselines and final smoke. Base mode includes committed and working-tree changes; the default without `--base` only sees working-tree differences against HEAD. `VERIFY_SKIP_REMOTE=1` only skips Docker and does not prove runtime validation.
7. For code or script changes, update `SCRIPT_VERSION` and the README version once per conversation turn as required by AGENTS.md.
8. Commit atomically with a conventional commit message after verification and follow the worktree/PR review and merge workflow.

Record expected duration and stop after the selected required checks pass unless new evidence changes the scope. Version-only edits now select local metadata/syntax checks; focused scripts can also be run directly. `VERIFY_SKIP_REMOTE=1` still runs the entire selected local suite before skipping Docker. Section 4.2 defines planning thresholds and result-reuse conditions; review waiting time is separate. For read-only security review, start with [SECURITY.md](https://github.com/KnowSky404/sing-box-vps/blob/main/SECURITY.md); review alone does not require implementation or regression testing.

Every delivered repository change, including documentation, increments `SCRIPT_VERSION` once per conversation turn; synchronize the header and README as required by AGENTS.md.

## Test VPS Verification

Use the repository workflow unless the user asks for a direct manual test.

Remote verification runs via Docker locally.

Preview the complete task-branch difference before selecting tests:

```bash
bash dev/verification/run.sh --plan --base origin/main
```

The planner maps documentation, version metadata, Bootstrap and changed standalone tests; unmapped runtime changes require an explicit local `--group`, Docker `--scenario`, or `--full` selection under section 4.2. Groups do not request Docker by themselves. Review the plan, then remove `--plan` to execute the same selection, or run the necessary tests directly. See [Development](https://github.com/KnowSky404/sing-box-vps/wiki/Development#调度器命令与计划) for scope and prerequisites. Execution writes artifacts under the run directory printed as `run_dir=...`; preserve the actual scope and results. A successful exit does not establish full regression, public reachability, real external-provider behavior or production acceptance.

When remote validation fails:

1. Read `summary.log`.
2. Inspect `remote.stderr.log` and `remote.stdout.log`.
3. Inspect extracted remote artifacts if present.
4. Fix the root cause before rerunning verification.

## Fresh Install On A New VPS

For a test VPS, direct installation is allowed when the user asked for a test installation and the host is clearly `sing-box-test`.

For production or unknown hosts, use the production plan gate first.

Canonical public install command:

Use the complete staged Bootstrap in [Getting Started](https://github.com/KnowSky404/sing-box-vps/wiki/Getting-Started). `bash bootstrap.sh install`
and `bash bootstrap.sh uninstall --yes` select the matching runtime script, download it
into a private `mktemp -d` directory, run Bash syntax and project-identity
checks, and only then execute it. The temporary directory is cleaned on normal
exit and signal; an interrupt before the runtime script starts reports that the
system is unchanged. Do not replace this flow with `curl | bash` or process
substitution.

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
| Protocols | VLESS REALITY, Mixed HTTP/SOCKS, standalone SOCKS, standalone HTTP, Shadowsocks, Trojan, VMess, Hysteria2, Hysteria v1, AnyTLS, Snell, TUIC, NaiveProxy, ShadowTLS; protocols can coexist | Discover with `capabilities`; summaries with `nodes`; general installation uses menus; typed Mixed/SOCKS/HTTP/Shadowsocks/Trojan/VMess/Hysteria2/Hysteria v1/AnyTLS/Snell/TUIC/NaiveProxy/ShadowTLS have shared instance `view|diagnose|export` reads plus Agent `create/replace/delete/default/rebuild/takeover/recover` writes (Mixed additionally supports migrate) |
| REALITY | Multiple instances, independent ports/ShortID/names, per-instance outbound policy and optional upload/download QoS | Read with `nodes`; mutate through the interactive protocol menu |
| TLS | Hysteria2/AnyTLS ACME HTTP-01, Cloudflare DNS-01, or manual certificate paths; Hysteria v1, NaiveProxy, standalone HTTP, Trojan and TUIC use manual certificate paths; Trojan/TUIC/Hysteria v1/NaiveProxy explicitly select certificate or system client trust | Read warnings/check output; mutate interactively |
| Warp | Account registration, enable/disable, all/selective routing, built-in/custom domains, local/remote rule sets | Read with `warp`; mutate through menu 13 |
| Route rule sets | Typed `inline`/`local`/`remote` lifecycle through component CAS; local files are references, remote URLs and named HTTP-client references are sensitive | `component create|replace|delete|takeover|rebuild`; no ordinary node export, share link or SubMan |
| Advanced components | Typed inbounds, endpoints, outbounds/groups, certificate providers, shared HTTP clients and network namespaces with schema-1 revision/CAS, drift checks and durable recovery | `component list|diagnose|export`; guarded `create|replace|delete|takeover|rebuild|recover`; export is sensitive |
| Network/system | IPv4/IPv6/dual inbound stack, outbound/DNS strategy, BBR | Read config/doctor; mutate through menu 14 |
| Node material | Links/QR, bare-core client export, dual-stack labels | `nodes` is log-safe; `links` and `export-client` are sensitive |
| SubMan | Idempotent VLESS/Hysteria2 sync; Trojan and VMess sync only losslessly representable TLS/system-trust users and report per-user skips; revision/error/retry semantics; only encrypted dual-network Shadowsocks entries use the dedicated path, while single-network and `none` entries are skipped; Hysteria v1, Snell, TUIC, NaiveProxy, AnyTLS and ShadowTLS remain explicitly unsupported | `subman-sync` is sensitive and externally mutating; same-snapshot mock passed for VMess (`synced=3`, `skipped=1`, `failed=0`), and no unauthorized real sync |
| Lifecycle | start/stop/restart/status/logs, managed-instance and component takeover/rebuild/recovery, core/script upgrade, two uninstall scopes | Status/check/doctor are read-only; restart, fixed core upgrade, typed instance mutations and component mutations are guarded Agent writes with exact confirmation/CAS where applicable |
| Verification | VMess: native 1.13.18/1.14.0 generated none/http/ws/grpc/quic two-user exports and server/client checks; Hysteria2: typed multi-user lifecycle, independent bandwidth, Agent/share/client-export and SubMan contract; Hysteria v1: typed multi-user manual-TLS QUIC lifecycle, independent bandwidth/obfs, Agent redaction/share and outbound JSON contract; AnyTLS: typed multi-instance lifecycle, Agent credential-safe summary/share and client-export contract; Snell: typed v5/v6 lifecycle, takeover, Agent summary/share and outbound JSON contract; TUIC: typed multi-user manual-TLS QUIC lifecycle, Agent redaction/share and per-user outbound JSON contract; NaiveProxy: typed multi-user manual-TLS TCP/UDP lifecycle, Agent redaction/share and per-user outbound JSON contract with libcronet warning; ShadowTLS: typed composite outer/loopback-detour lifecycle, v1/v2/v3 validation, Agent redaction/share and per-user outbound JSON contract; focused takeover/lifecycle/Agent/share/SubMan/probe tests passed; Docker fresh-install and coexistence evidence is run below | Local VMess/Hysteria2/Hysteria v1/AnyTLS/Snell/TUIC/NaiveProxy/ShadowTLS tests pass, with Hysteria v1/Snell/TUIC/NaiveProxy/ShadowTLS target-core check when configured; SubMan is mock-only, no production or real SubMan sync proof |

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
sbv agent component list --json
sbv agent component diagnose --json
sbv agent component export --json --id ID [--expected-revision N]
sbv agent component recover --json --yes --expected-revision N
sbv agent component takeover --json --yes --expected-revision N [--allow-public]
sbv agent component rebuild --json --yes --expected-revision N
sbv agent component create|replace --json --yes --expected-revision N --file component.json [--allow-public]
sbv agent component delete --json --yes --expected-revision N --id ID
sbv agent instance view <protocol> --json [--id ID] [--expected-revision N]
sbv agent instance diagnose <protocol> --json [--id ID] [--expected-revision N]
sbv agent instance export <protocol> --json [--id ID] [--expected-revision N]
sbv agent instance create|replace <protocol> --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance delete|default <protocol> --json --yes --expected-revision N --id ID
sbv agent instance rebuild <protocol> --json --yes --expected-revision N
sbv agent instance takeover <protocol> --json --yes --expected-revision 0 [--allow-public]
sbv agent instance migrate mixed --json --yes --expected-revision N
sbv agent instance recover <protocol> --json --yes --expected-revision N
sbv update sbv
sbv update sing-box latest
```

The `create|replace` and `delete|default` forms are alternatives for
documentation; execute one operation word at a time. Replace `<protocol>` and
read `--expected-revision` from the same state snapshot before a write.

`<protocol>` read operations support `vless-reality`, `mixed`, `socks`, `http`,
`shadowsocks`, `trojan`, `vmess`, `vless-plain`, `anytls`, `hy2`, `snell`,
`tuic`, `hysteria`, `naive` and `shadowtls`. Instance writes support every ID
except `vless-reality`; only `mixed` supports `migrate`. `view` and `diagnose`
are redacted reads, while `export` and component export are sensitive.

- `status --json` is safe for routine diagnostics. It reports script/core/service/path/protocol state plus inbound/outbound stack modes, BBR, REALITY instance/QoS counts, and whether client export/SubMan files exist; it does not return credentials.
- `capabilities --json` is read-only and returns the supported protocol/feature matrix plus safety labels. `upgrade-check --json 1.14.0` is read-only and must precede an upgrade; require `ready=true` and `blockers=[]`. Its `target_binary_validation.performed=false` means target validation is deferred to the guarded apply transaction, not that compatibility was already proven.
- `nodes --json` is safe for ordinary logs. It reports every protocol and every REALITY/Mixed/SOCKS/HTTP/Shadowsocks/Trojan/VMess/Hysteria2/Hysteria v1/AnyTLS/Snell/TUIC/NaiveProxy/ShadowTLS instance, including names, ports, instance revisions, server names, rate limits, outbound policy, and exportability without UUIDs, keys, full share links, or passwords. For Shadowsocks, VMess, Hysteria2, Hysteria v1, AnyTLS, Snell, TUIC, NaiveProxy, and ShadowTLS, authentication/network-specific summaries expose only bounded metadata; server PSKs, UUIDs, `auth_str`, AnyTLS passwords, Snell PSKs/user keys, TUIC UUIDs, Naive usernames/passwords, ShadowTLS passwords, and user passwords never appear.
- `links --json` returns full connection material for every protocol and every REALITY/Mixed/SOCKS/HTTP/Shadowsocks/Trojan/VMess/Hysteria2/Hysteria v1/AnyTLS/Snell/TUIC/NaiveProxy/ShadowTLS instance. Treat its output as sensitive and avoid pasting it into public logs. A Shadowsocks response has `links: {"<stable-outbound-tag>": "<uri>"}`, `outbounds: [...]` and `warnings: [...]`; VMess responses contain `vmess://` links plus matching outbounds; AnyTLS returns per-user outbound JSON, `links:{}`, and `warnings[].code=anytls_standard_uri_unavailable` because no standard URI can carry the complete configuration. Snell returns per-user outbound JSON, `links:{}`, and `warnings[].code=snell_standard_uri_unavailable` because version, obfs/shaping and user keys have no lossless standard URI. TUIC returns per-user outbound JSON, `links:{}`, and `warnings[].code=tuic_standard_uri_unavailable` because no standard URI carries its QUIC and user fields. Hysteria v1 returns per-user outbound JSON, `links:{}`, and `warnings[].code=hysteria_standard_uri_unavailable`; NaiveProxy returns per-user outbound JSON, `links:{}`, `warnings[].code=naive_standard_uri_unavailable` and `naive_libcronet_required`; ShadowTLS returns per-user outbound JSON, `links:{}`, and `warnings[].code=shadowtls_standard_uri_unavailable`; Hysteria2 returns per-user `hy2://` links when system trust is selected, full outbounds for certificate trust, and explicit warnings for unrepresentable options; manual Ed25519 certificates include `warnings[].code=hy2_ed25519_share_link_requires_client_override` because the share URI cannot carry the required 1.14+ client option.
- `export-client --json` generates `/root/sing-box-vps/client/sing-box-client.json`, validates it with `sing-box check`, and returns the path plus config JSON. It writes the client export file but does not change the running server config or restart services. Mixed and standalone SOCKS export SOCKS5 + UoT v2 with preserved authentication and no TLS/HTTP surface. Shadowsocks uses the full JSON export to preserve its network restriction and method/authentication; Trojan, VMess, ordinary VLESS, Hysteria2, Hysteria v1, AnyTLS, Snell, TUIC, NaiveProxy, and ShadowTLS export one full outbound per user, preserving transport and explicit public-certificate/system trust where applicable. Hysteria v1 preserves `auth_str`, bandwidth, obfs and QUIC fields; AnyTLS sets `client_metadata` to an empty string and embeds only the public certificate when `client_trust=certificate`; Snell maps inbound v5 to outbound v4 and inbound v6 to outbound v6, preserving v5 obfs host and v6 shaping; TUIC preserves congestion control, heartbeat, zero-rtt and outbound-only relay/udp-over-stream; NaiveProxy preserves username/password, TLS, QUIC and stream-window options but requires a `with_naive_outbound` build and runtime `libcronet.so`; ShadowTLS preserves version, handshake, trust, and per-user credentials; none of them exports a server private key or disables verification. For a 1.14+ Hysteria2 Ed25519 target it sets top-level `disable_chrome_parrot: true` and returns `warnings[].code=hy2_ed25519_chrome_parrot_disabled`.
- `check --json` validates the server config with `sing-box check` and returns stdout, stderr, exit code, and pass/fail state.
- `doctor --json` is read-only. It returns status, path existence checks, protocol state, and embedded config-check output for first-pass agent diagnostics.
- `service restart --json --yes` is a guarded mutation. It validates config first and skips restart when validation fails.
- `warp --json` reports Cloudflare Warp state: enabled/disabled, route mode (`all` or `selective`), account registration health, and counts for custom domains, local rule sets, remote rule sets, and builtin AI/streaming domain rules. Safe for routine diagnostics.
- `subman-sync --json` pushes eligible nodes to SubMan without prompting. Missing SubMan config is reported as structured JSON. Shadowsocks uses its dedicated integration only for encrypted entries whose network is `["tcp","udp"]`; single-network entries are skipped with `shadowsocks_uri_network_omitted`, while `none` with an empty password is parser-rejected and skipped with `shadowsocks_subman_none_unsupported`. Trojan, VMess and Hysteria2 use dedicated multi-instance, per-user paths: only lossless TLS/system-trust URIs are eligible; plaintext, certificate trust, unrepresentable transport, partial options and oversized URIs retain explicit skipped counts/warnings, including when every user is skipped. Hysteria v1, Snell, AnyTLS, TUIC, NaiveProxy and ShadowTLS are explicitly unsupported and are never sent as SubMan `other`; use outbound JSON from `links` or `export-client`. Same-snapshot mock coverage passed for VMess (`synced=3`, `skipped=1`, `failed=0`) and Hysteria2 (`synced=2`, `skipped=0`, `failed=0`); do not perform real sync without explicit authorization.
- `update sbv` updates `/usr/local/bin/sbv` from the project main branch.
- `update sing-box [latest|x.y.z]` updates only the sing-box binary, preserves the current server config byte-for-byte, validates it with `sing-box check`, and restarts the service only after validation passes. The aliases are `sbv update-sbv` and `sbv update-sing-box [latest|x.y.z]`.
- `upgrade --json 1.14.0 --yes` is the auditable Hermes path: it is mutating and service-impacting, persists a backup under `/root/sing-box-vps-backups/`, preserves `config.json` byte-for-byte, validates before restart, and attempts automatic binary recovery on failure. For an actual change, require `transaction.result_persisted=true`, then retain the referenced root-only `transaction-result.json`; it records `backup_ready` plus the terminal `success`, `rolled_back`, or `rollback_failed` state, and terminal records include `failure_reason` plus `operation_exit_code` when applicable. If the target is already installed, the no-op response instead has `changed=false`, `transaction.status=not_attempted`, `transaction.reason=already_installed`, and no backup or result file. Recovery is complete only when both `rolled_back` and `rollback_ok` are true; `error=rollback_failed` plus `manual_intervention_required=true` is a hard stop. It never silently rewrites configuration for migration. All public Agent protocol IDs include `vless-reality`, `mixed`, `socks`, `http`, `shadowsocks`, `trojan`, `vmess`, `hysteria2`, `hysteria`, `anytls`, `snell`, `tuic`, `naive` and `shadowtls`; the internal Hysteria2 state filename remains `hy2.env`. `instance` mutations for Mixed, standalone SOCKS, HTTP, Shadowsocks, Trojan, VMess, Hysteria2, Hysteria v1, AnyTLS, Snell, TUIC, NaiveProxy and ShadowTLS require `--yes` and exact `--expected-revision`; `migrate shadowsocks`, `migrate vmess`, `migrate hy2`, `migrate hysteria`, `migrate anytls`, `migrate snell`, `migrate tuic`, `migrate naive` and `migrate shadowtls` are unsupported. `component` mutations use the same confirmation/CAS boundary for advanced state and persistent recovery; `component export` is sensitive. `export-client` and `subman-sync` are also mutating; `links`, instance/component export, and SubMan output are sensitive. Installation, general protocol edits, REALITY/QoS, Warp, BBR, media checks, and uninstall remain interactive-only; typed instance/component takeover, rebuild and recovery are guarded JSON mutations and still require operator approval.

## sing-box 1.14 Compatibility

- Fresh installs and regenerated configs targeting 1.14+ use top-level ACME `certificate_providers`; Hysteria2 and AnyTLS inbounds reference them through `tls.certificate_provider`.
- Remote rule sets targeting 1.14+ use `http_client.detour`. Explicitly pinned or installed 1.13.x targets retain the legacy inline `tls.acme` and rule-set layout.
- A binary-only update never migrates or rewrites the server config. The target binary must accept the existing file via `sing-box check` before the service is restarted.
- Hysteria2 manual Ed25519 certificates are detected with OpenSSL. Generated 1.14+ client outbounds receive top-level `disable_chrome_parrot: true`; share links cannot encode this field, so human and Agent interfaces emit a warning.
- If the manual certificate algorithm cannot be inspected, Agent output uses `warnings[].code=hy2_certificate_algorithm_unknown`; operators should verify the certificate and client compatibility manually.
- Inline `tls.acme` and legacy `download_detour` are deprecated in 1.14 but remain accepted for compatibility; both are scheduled for removal in 1.16. A binary-only upgrade does not migrate them.

For the complete single-host rehearsal, including stop conditions, evidence requirements, and rollback assertions, use [Wiki: Upgrade-Rehearsal](https://github.com/KnowSky404/sing-box-vps/wiki/Upgrade-Rehearsal).

Common paths:

- Runtime directory: `/root/sing-box-vps/`
- Main config: `/root/sing-box-vps/config.json`
- Protocol state: `/root/sing-box-vps/protocols/`
- VLESS REALITY instance state: `/root/sing-box-vps/protocols/vless-reality.d/`
- Mixed instance state: `/root/sing-box-vps/protocols/instances/mixed.json`
- Standalone SOCKS instance state: `/root/sing-box-vps/protocols/instances/socks.json` (active marker schema 2, JSON `schema_version: 1`; lifecycle/export/runtime passed the final verification gate)
- Standalone HTTP instance state: `/root/sing-box-vps/protocols/instances/http.json` (active marker schema 2, JSON `schema_version: 1`; use the typed Agent lifecycle and manual TLS contract below)
- Shadowsocks instance state: `/root/sing-box-vps/protocols/instances/shadowsocks.json` (active marker schema 2, JSON `schema_version: 1`; use the typed Agent lifecycle and bounded export contract below)
- Trojan instance state: `/root/sing-box-vps/protocols/instances/trojan.json` (active marker `/root/sing-box-vps/protocols/trojan.env`, schema 2; JSON `schema_version: 1`; protocol management via main menu 2 and typed Agent lifecycle)
- VMess instance state: `/root/sing-box-vps/protocols/instances/vmess.json` (active marker `/root/sing-box-vps/protocols/vmess.env`, schema 2; JSON `schema_version: 1`; protocol management via main menu 2 and typed Agent lifecycle)
- AnyTLS instance state: `/root/sing-box-vps/protocols/instances/anytls.json` (active marker `/root/sing-box-vps/protocols/anytls.env`, schema 2; JSON `schema_version: 1`; protocol management via main menu 2 and typed Agent lifecycle for manual TLS; legacy ACME/provider configuration retains its existing configuration-update path)
- Hysteria2 instance state: `/root/sing-box-vps/protocols/instances/hy2.json` (active marker `/root/sing-box-vps/protocols/hy2.env`, schema 2; JSON `schema_version: 1`; protocol management via main menu 2 and typed Agent lifecycle for manual TLS and ACME)
- Hysteria v1 instance state: `/root/sing-box-vps/protocols/instances/hysteria.json` (active marker `/root/sing-box-vps/protocols/hysteria.env`, schema 2; JSON `schema_version: 1`; protocol management via main menu 2 and typed Agent lifecycle for the manual-TLS QUIC subset)
- NaiveProxy instance state: `/root/sing-box-vps/protocols/instances/naive.json` (active marker `/root/sing-box-vps/protocols/naive.env`, schema 2; JSON `schema_version: 1`; protocol management via main menu 2 and typed Agent lifecycle for the manual-TLS TCP/UDP subset; outbound requires `with_naive_outbound` and runtime `libcronet.so`)
- ShadowTLS instance state: `/root/sing-box-vps/protocols/instances/shadowtls.json` (active marker `/root/sing-box-vps/protocols/shadowtls.env`, schema 2; JSON `schema_version: 1`; protocol management via main menu 2 and typed Agent lifecycle for the composite outer/loopback-Mixed subset; no standard URI or SubMan path)
- Snell instance state: `/root/sing-box-vps/protocols/instances/snell.json` (active marker `/root/sing-box-vps/protocols/snell.env`, schema 2; JSON `schema_version: 1`; protocol management via main menu 2; typed v5/v6 lifecycle and outbound JSON, no standard URI or SubMan path)
- TUIC instance state: `/root/sing-box-vps/protocols/instances/tuic.json` (active marker `/root/sing-box-vps/protocols/tuic.env`, schema 2; JSON `schema_version: 1`; protocol management via main menu 2; typed manual-TLS QUIC lifecycle and outbound JSON, no standard URI or SubMan path)
- VLESS REALITY QoS state: `/root/sing-box-vps/reality-qos.filters`
- Client export: `/root/sing-box-vps/client/sing-box-client.json`. Trojan exports one full outbound per user, preserving transport and explicit public-certificate/system trust; never exports the private key or disables verification.
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

## Standalone SOCKS Inbound

All structured protocol sections below inherit the common Agent read/write surface:
`view|diagnose|export` are read-only/sensitive reads, while `create|replace|delete|default|rebuild|takeover|recover`
are revision/CAS-guarded writes. A section's shorter command block lists its protocol-specific
record shape; it does not remove the common rebuild/takeover or read-only operations. Only Mixed
also accepts `migrate`.

Mixed/SOCKS URI userinfo is percent-encoded, preserving reserved characters and UTF-8 bytes without changing stored credentials. HTTP Basic excludes colon-containing usernames and ASCII control characters ([RFC 7617, section 2](https://www.rfc-editor.org/rfc/rfc7617#section-2)); for such Mixed credentials, `links.http` is absent and `warnings[].code=mixed_http_auth_unrepresentable`. SOCKS5 remains available. The additive `socks5_uri_transport_options_omitted` warning means a SOCKS5 URI does not carry UoT v2 client options; use `export-client` JSON instead of treating a URI as a full configuration. Percent encoding is not encryption, and links remain sensitive.

Standalone SOCKS is the fifth protocol-registry preset (`state_id=socks`, `agent_id=socks`, menu order 5). It is separate from the Mixed HTTP/SOCKS preset: the server record describes only a SOCKS4/4a/5 inbound, its listen address/port, authentication and outbound policy; it does not add HTTP or TLS. It has no legacy `.env` migration operation; a pre-existing live SOCKS configuration is handled through takeover.

The shared plain-proxy adapter uses `build_socks_inbound_json`, `save_socks_state`, `load_plain_proxy_structured_instance`, and `apply_plain_proxy_instance_change`. Its active marker is schema 2 and its JSON store (`schema_version: 1`) is `/root/sing-box-vps/protocols/instances/socks.json`; there is no `migrate socks` operation. Public Agent mutations are:

```bash
sbv agent instance create socks --json --yes --expected-revision N --file record.json
sbv agent instance replace socks --json --yes --expected-revision N --file record.json
sbv agent instance delete socks --json --yes --expected-revision N --id ID
sbv agent instance default socks --json --yes --expected-revision N --id ID
sbv agent instance recover socks --json --yes --expected-revision N
```

Use `nodes --json` to discover `instance_id`, `tag`, listen fields and `instance_revision`; use `links --json` only in a trusted context. `create` and `replace` require a complete typed record through `--file`, while `delete` and `default` use `--id`; `recover` uses the original journal revision, not a guessed current revision. All writes use the shared file/config/listener/firewall/service transaction and persistent result/journal boundaries. Client export is SOCKS5 with UoT v2 and preserves authentication, but has no TLS and no HTTP surface.

Standalone SOCKS integration passed the final local/runtime verification gate. The six focused tests (`plain_proxy_structured_store.sh`, `socks_instance_lifecycle.sh`, `socks_instance_lifecycle_runtime.sh`, `socks_instance_menu.sh`, `socks_structured_takeover.sh`, and `socks_export_client.sh`), two-core check/runtime coverage, menu 5 selection, and final Docker/TCP gate passed. The implementation record documents the remaining boundaries: no TLS/HTTP/SubMan, public native UDP unverified, and the full protocol goal unfinished.

## Shadowsocks Inbound

Shadowsocks is the registry/menu preset 7 with public protocol and Agent ID `shadowsocks`; `ss` is its public alias. This section is the `2026090802` contract for the integrated surface. Final evidence covers two core targets, all 9 methods in config checks, and four native Bash/Bash 4.2 runtime groups across 1.13.18 and 1.14, each with 7 TCP plus 7 UDP cases, including long-PSK derivation. The Docker rerun recorded 12/12 scenarios, 18/18 TCP probes, `rolled_back` and `success` rollback outcomes, and matching script/container hashes. Its active marker is `CONFIG_SCHEMA_VERSION=2`, while the typed JSON store remains `schema_version: 1` at `/root/sing-box-vps/protocols/instances/shadowsocks.json`. A live pre-existing inbound is handled by takeover; `migrate shadowsocks` is deliberately unsupported and must be rejected rather than routed through the Mixed legacy path.

The public Agent lifecycle is revision/CAS guarded and uses the same transaction boundaries as the other typed plain-proxy stores:

```bash
sbv agent instance create shadowsocks --json --yes --expected-revision N --file record.json
sbv agent instance replace shadowsocks --json --yes --expected-revision N --file record.json
sbv agent instance delete shadowsocks --json --yes --expected-revision N --id ID
sbv agent instance default shadowsocks --json --yes --expected-revision N --id ID
sbv agent instance recover shadowsocks --json --yes --expected-revision N
```

`create` and `replace` require a complete private typed record; `delete` and `default` require `--id`; `recover` uses the original journal revision. There is no `migrate shadowsocks` operation. The minimum record shape is:

```json
{
  "id": "main",
  "name": "Shadowsocks main",
  "tag": "ss-in",
  "listen": {
    "address": "127.0.0.1",
    "port": 8388,
    "network": ["tcp", "udp"]
  },
  "authentication": {
    "method": "2022-blake3-aes-128-gcm",
    "password": "<server-psk>",
    "users": [{"name": "user-1", "password": "<user-psk>"}]
  },
  "outbound_policy": "default",
  "dependencies": []
}
```

`listen.network` is a nonempty canonical subset of `tcp` and `udp`: use exactly `["tcp"]`, `["udp"]` or `["tcp","udp"]`; it is part of the inbound identity/resource plan. The default address is loopback (`127.0.0.1`). A non-loopback create/replace requires `--allow-public`; interactive management asks for the corresponding public-exposure consent. `none` is permitted only as an explicitly acknowledged plaintext transport and returns warning code `shadowsocks_plaintext_transport`.

Authentication supports classic AEAD methods (`aes-128-gcm`, `aes-192-gcm`, `aes-256-gcm`, `chacha20-ietf-poly1305`, `xchacha20-ietf-poly1305`) with one or multiple users, and 2022 AES methods (`2022-blake3-aes-128-gcm`, `2022-blake3-aes-256-gcm`) with server and user keys. `none` and `2022-blake3-chacha20-poly1305` do not support multiple users. The server/user key inputs must meet the core's method minimum (16 bytes for AES-128, 32 bytes for AES-256 or 2022 chacha); longer values are allowed and may be derived by the core. A long 2022 PSK is preserved byte-for-byte in the typed store; the client uses the equivalent fixed-length SHA-256-derived key and emits `warnings[].code=shadowsocks_2022_psk_derived`. Interactive defaults are not a schema maximum. Do not add or imply relay, mux or plugin support; fields outside this typed contract are unsupported/rejected.

`nodes --json` must keep Shadowsocks summaries credential-free: the SS authentication/network details are only `method`, `user_count`, `network` and the instance `revision` (serialized as `instance_revision` in the Agent payload, alongside generic non-secret identity); server PSKs and user passwords/keys are never returned. `links --json` is sensitive and returns the SS object shape `{"links":{"<stable-outbound-tag>":"<uri>"},"outbounds":[...],"warnings":[...]}`. A SIP002 URI cannot express a single-network restriction. For `["tcp"]` or `["udp"]`, emit `warnings[].code=shadowsocks_uri_network_omitted` and use the complete JSON client export when the restriction must be preserved. The `none` warning is also carried in the link response where applicable.

Shadowsocks has a dedicated SubMan path for encrypted SIP002-representable dual-network entries. Single-network entries are skipped with the `shadowsocks_uri_network_omitted` warning because the restriction cannot be encoded. `none` with an empty password is rejected by the current SubMan parser and skipped with `shadowsocks_subman_none_unsupported`. Same-snapshot mock coverage passed with `synced=2`, `skipped=2`, `failed=0`; this is local mock evidence, not a real authorized synchronization.

Protocol-wide removal already short-circuits an active schema-2 Shadowsocks store in `remove_protocol_menu` to `shadowsocks_instance_management_menu delete`; the bulk legacy `PORT`/`close_firewall_port` cleanup is therefore not entered for active SS. Preserve this guard for HTTP/SOCKS/SS and keep instance create/replace/delete/default/recover on the plan-aware `apply_plain_proxy_instance_change` transaction. The remaining old port-only cleanup applies only to non-structured legacy paths; it is not a precise ownership ledger.

Recorded verification boundary: final script hash `8d24fa6e`; the focused two-core/9-method checks and four native Bash/Bash 4.2 runtime groups (7 TCP plus 7 UDP per group) passed, including long-PSK derivation. The Docker rerun at `dev/verification-runs/20260908055118` used `VERIFY_SKIP_LOCAL_TESTS=1` and passed 12/12 scenarios and 18/18 TCP probes, with rollback outcomes `rolled_back` and `success` and matching script/container hashes. The default first gate stopped on an old test assertion; the ordinary 182-item run then fixed five failures and reran affected tests, with 16 framework items passing, but no complete 182-item rerun followed the local SubMan fix. Same-snapshot SubMan mock coverage passed with `synced=2`, `skipped=2`, `failed=0`; real synchronization still requires explicit authorization. The [implementation record](https://github.com/KnowSky404/sing-box-vps/wiki/Verification-History) documents these evidence limits. This is not a new full local 85-test pass and does not imply unsupported relay, mux, plugin or other unmodeled fields.

## Standalone HTTP Inbound

`http` is registry preset 6 and protocol management via main menu 2, separate from Mixed and SOCKS. Its schema-2 marker references `protocols/instances/http.json` (`schema_version:1`). Use the same `instance create|replace|delete|default|recover http --json --yes --expected-revision N` contract; create/replace require `--file`, delete/default require `--id`. No legacy `migrate http` exists. Takeover preserves supported live HTTP authentication, tags, listener, policy and TLS references, and rejects unsupported fields rather than discarding them.

The complete record has the common instance fields plus a required `tls` object. Plain example:

```json
{
  "id": "main", "name": "Private HTTP", "tag": "http-in",
  "listen": {"address": "127.0.0.1", "port": 18080},
  "authentication": {"enabled": true, "username": "proxy-user", "password": "replace-with-a-secret"},
  "tls": {"enabled": false},
  "outbound_policy": "default", "dependencies": []
}
```

For TLS replace the entire `tls` value with `{"enabled":true,"server_name":"proxy.example.com","certificate_path":"/etc/proxy/server.crt","key_path":"/etc/proxy/server.key"}`. Supply valid existing certificate/key files; this preset does not issue ACME certificates, mutate the files, or delete them when an instance is removed. Unsupported TLS/provider/transport fields are rejected. Validate referenced files with the target core before publication. Non-loopback writes still require `--allow-public`; new interactive instances default to loopback and authentication. HTTP Basic rejects colons in usernames and ASCII controls in either credential; it does not impose SOCKS's 255-byte credential limit.

The client uses `type:http`, HTTP CONNECT and TCP only, not SOCKS/UoT. Entry TLS is independent of a destination website using HTTPS. TLS export embeds only public certificate trust and server name, never the server private key. Plain links use encoded `http://` userinfo and return `http_plaintext_transport`: use only trusted networks or protected tunnels. TLS trust cannot be carried faithfully in that URI, so TLS links are omitted with `http_tls_uri_unrepresentable` and callers should use `export-client`; TLS node summaries have `shareable=false` and `client_exportable=true`. HTTP is not synchronized to SubMan. `nodes` remains a credential-free summary; `links` and client exports are sensitive. This HTTP preset does not claim all upstream HTTP options or completion of the full protocol goal.

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

Configure `SUBMAN_API_URL` (the SubMan origin), `SUBMAN_API_TOKEN`, a stable
`SUBMAN_NODE_PREFIX`, and `SUBMAN_EXPECTED_GIST_ID` in that protected file. Obtain
the expected Gist ID from the intended SubMan Workspace. Existing configurations
without this field stop the Agent with a configuration error; interactive sync
prompts for the missing ID and preserves the old configuration in `.bak` before
saving it with mode `600`. Discovery is never automatically accepted as the
intended identity.

Before each write, the caller reads `/api/nodes`, validates the expected Gist and
observed revision, and uses the ETag as `If-Match`. Every successful node response
must agree on Gist ID, `subman.json`, revision/ETag and `Cache-Control: no-store`;
upserts also require the exact external-key marker. Header parsing supports
lowercase and mixed-case names with portable awk. The API has no parameter that
atomically pins discovery to a Gist; the preflight and response checks do not
eliminate a target change between requests.

The complete unencoded external key must fit **119 UTF-8 bytes**, including the
prefix, instance ID, full user digest and address suffix. By-key PUT accepts at
most **63 distinct ordinary labels**, reserving one slot for the server-owned
`external:` marker. Existing identity formats are retained; oversized keys are
rejected, never truncated. Shorten the configured prefix only as an explicit
identity migration, with cleanup of obsolete nodes planned separately.

After transport loss or an uncertain upstream write, GET and compare the exact
key and desired writable state. Reconstruct server name deduplication from the
validated preflight inventory and the returned commit timestamp; arbitrary name
changes remain uncertain. A matching readback can confirm the current state;
otherwise retain the uncertain result and investigate before retrying.
Writes are not blindly replayed and `Idempotency-Key` is unsupported. Agent
JSON `results` retains each `operation` (`upsert` or `delete`), attempted
`external_key`, returned `node_id`, `gist_id`, `revision` and `outcome`
(`committed`, `reconciled`, `failed`, `unknown-outcome`, or `absent` for an
already missing cleanup target) alongside aggregate counts. Legacy deletion
receipts retain their key/target ID even when uncertain, so a later cleanup
failure does not erase earlier successes. Preflight GET transport failures are
retryable reads; they do not imply an uncertain mutation. A key-generation failure has a null `external_key`, protocol,
instance/address context and `invalid_external_key`; no request was sent for it.
Multiple node requests are not one transaction. Updating nodes does not regenerate published
subscriptions or sing-box files; review and publish affected outputs in SubMan.

SubMan sync is non-interactive for agents and pushes VLESS REALITY, ordinary
VLESS, Hysteria2 and representable Trojan/VMess users, plus SIP002-representable
encrypted Shadowsocks dual-network entries through their dedicated paths.
Single-network Shadowsocks entries are skipped and `none` with an empty password
returns `shadowsocks_subman_none_unsupported`. Unsupported protocols and settings
remain explicit skips instead of lossy `other` nodes. Missing API configuration
is reported as structured JSON rather than prompting. Integration verification
uses local synthetic responses and mock APIs; it does not prove real Gist
writes, production deployment or authorized live synchronization.

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
