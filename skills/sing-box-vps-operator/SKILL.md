---
name: sing-box-vps-operator
description: Use when installing or upgrading sing-box-vps, running local or remote verification, operating sing-box-test or sing-box-prod, troubleshooting sbv or sing-box service issues, retrieving node info for AI agents, managing VLESS REALITY instances or Warp/SubMan/client exports, modifying repository scripts or docs, validating sing-box configs, or creating rollback/recovery steps for this project.
---

# sing-box-vps Operator

Use this skill for repository maintenance and VPS operations for `sing-box-vps`.

## Required Reading

Before operational work, read:

1. `AGENTS.md`
2. `README.md`
3. `docs/agents/sing-box-vps-agent-runbook.md`

For `sing-box` configuration syntax, version compatibility, migration notes, or official examples, use Context7 first.

## Classify The Target

- **Local repository**: files in the workspace.
- **Test VPS**: `sing-box-test`.
- **Production VPS**: `sing-box-prod`.
- **Unknown remote host**: treat as production until clarified.

## Production Gate

Before any production-changing command on `sing-box-prod` or an unknown host, present a plan and wait for explicit approval.

Production-changing commands include install, upgrade, restart, stop, reload, uninstall, purge, config mutation, firewall mutation, service mutation, writing `/usr/local/bin/sbv`, or changing `/root/sing-box-vps/`.

Read-only production checks are allowed to prepare the plan.

Use this template:

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

## Verification Rules

- Run `sing-box check` after any generated or modified sing-box server or client configuration.
- Run `bash dev/verification/run.sh` when changes touch `install.sh`, `uninstall.sh`, `configs/`, `utils/`, or `dev/verification/`.
- Remote verification runs in Docker locally, auto-building sing-box-vps-verify image. No external SSH target required.
- Use `sing-box-test` for test validation and `sing-box-prod` only after the production gate.

## Agent-Friendly CLI

Prefer non-interactive JSON commands for AI automation:

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

- Use `status --json` for version/service/path/protocol diagnostics plus network stack, BBR, REALITY/QoS, and integration presence.
- Use `capabilities --json` to discover supported protocols/features and operation safety labels before choosing an action.
- On an existing 1.13 host, run `sbv update sbv` first and start a new invocation before expecting the new Agent commands.
- Use `upgrade-check --json 1.14.0` as a read-only eligibility preflight. Require `ready=true` and `blockers=[]`. It validates the current core and known schema risks without reconciling or migrating protocol state, but does not download the target; `target_binary_validation.performed=false` is expected.
- Use `upgrade --json 1.14.0 --yes` only after approval. It is mutating, creates an automatic root-only backup under `/root/sing-box-vps-backups/`, preserves the server config byte-for-byte, validates the target core before restart, and automatically restores the old binary and previous service activity on failure. Its `SHA256SUMS` covers every regular runtime file plus the binary, `sbv`, service unit, and metadata. It does not silently migrate or rewrite config. Treat the backup contents as sensitive.
- Use `nodes --json` for log-safe summaries of every protocol and every REALITY instance, including rate limits and outbound policy. It intentionally omits UUIDs, keys, full links, and passwords; ShadowTLS summaries also redact all v2/v3 credentials.
- Use `links --json` only in trusted contexts; it returns full connection material for every protocol and REALITY instance, including NaiveProxy and ShadowTLS outbound JSON and explicit URI/libcronet warnings.
- Use `export-client --json` to generate and validate the sing-box bare-core client config. It writes the client export file but does not mutate the running server config or restart service.
- Use `check --json` and `doctor --json` for non-mutating service/config diagnostics.
- Use `service restart --json --yes` only after confirming the target is safe to mutate. It validates config before restart.
- Use `warp --json` to inspect Cloudflare Warp status: enabled state, route mode, account health, custom domain counts, rule-set counts, and builtin AI/streaming rule tallies. Safe for routine diagnostics.
- Use `subman-sync --json` only in trusted contexts with configured SubMan credentials; it pushes only eligible URI-backed node material. NaiveProxy, Hysteria v1, Snell, TUIC, AnyTLS, and ShadowTLS are explicitly unsupported and skipped.
- Safety labels: `status`, `capabilities`, `upgrade-check`, `check`, `doctor`, `nodes`, and `warp` are read-only; `upgrade`, service restart, export, and SubMan sync are mutating; `links`, export, and SubMan sync are sensitive; installation, protocol edits, Warp/BBR/media changes, takeover/repair, and uninstall remain interactive-only.
- Use `update sbv` to refresh `/usr/local/bin/sbv`; alias: `sbv update-sbv`.
- Use `update sing-box [latest|x.y.z]` to update a healthy managed sing-box instance non-interactively. It preserves config, runs `sing-box check`, and restarts only after validation passes. Alias: `sbv update-sing-box [latest|x.y.z]`.
- If `update sing-box` reports an incomplete or missing instance, switch to the interactive `sbv` menu for repair, takeover, or fresh install.

For a 1.13 to 1.14 rehearsal, follow `docs/agents/sing-box-1.13-to-1.14-upgrade-test.md`. Inline `tls.acme` and legacy `download_detour` are deprecated in 1.14 but remain accepted for compatibility; they are scheduled for removal in 1.16. Hysteria2 Ed25519 handling is a client-side compatibility boundary: share links cannot carry the required Chrome QUIC override, while generated 1.14 client exports can.

NaiveProxy is registry preset 14 and management menu 29. Use the typed manual-TLS TCP/UDP instance lifecycle and `export-client` for per-user outbound JSON. The outbound requires an official `with_naive_outbound` build and runtime `libcronet.so`; links return `naive_standard_uri_unavailable` and `naive_libcronet_required`, and no SubMan sync is attempted.

ShadowTLS is registry preset 15 and management menu 30. Use the typed composite lifecycle: each instance owns a ShadowTLS outer listener and a private loopback Mixed detour, with v1/v2/v3 authentication, handshake mappings, explicit client trust, and per-user outbound JSON. Links return `shadowtls_standard_uri_unavailable`; ShadowTLS has no SubMan path. Non-loopback writes require explicit `--allow-public` consent.

## VLESS REALITY Operations

- REALITY may have multiple managed instances under `/root/sing-box-vps/protocols/vless-reality.d/`.
- Each instance can have its own port, ShortID, node name, and optional upload/download Mbps limits.
- Node names may include rate-limit suffixes; keep them intact when diagnosing or syncing nodes.
- When rate limits are configured, runtime QoS state is tracked in `/root/sing-box-vps/reality-qos.filters`.
- Removing or adding REALITY instances is a runtime config mutation. On production, use the production gate first.
- With multiple REALITY instances, the removal menu has separate single-instance and whole-VLESS scopes. Select the intended scope explicitly and verify that removed ports and QoS filters are gone.
- After any REALITY instance or rate-limit change, require config validation and service/QoS refresh through the script rather than hand-editing files.

## Repository Rules

- Keep `install.sh` as the runtime source of truth.
- Do not reveal secrets, private keys, passwords, tokens, full node links, or QR payloads unless explicitly requested and safe.
- Treat `sbv agent links --json`, `sbv agent export-client --json`, and `sbv agent subman-sync --json` outputs as sensitive.
- Back up runtime config before modifying remote state.
- For runtime behavior changes, update `SCRIPT_VERSION` in `install.sh` and the README script version together.
- Documentation-only changes do not require script version changes.

## Detailed Workflows

Use `docs/agents/sing-box-vps-agent-runbook.md` for install, upgrade, troubleshooting, rollback, test verification, and production operation details.
