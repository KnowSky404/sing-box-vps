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
- Prefer `dev/verification-target.env` for remote verification.
- Use `sing-box-test` for test validation and `sing-box-prod` only after the production gate.

## Agent-Friendly CLI

Prefer non-interactive JSON commands for AI automation:

```bash
sbv agent status --json
sbv agent nodes --json
sbv agent links --json
sbv agent export-client --json
sbv agent check --json
sbv agent doctor --json
sbv agent service restart --json --yes
sbv agent subman-sync --json
sbv update sbv
sbv update sing-box latest
```

- Use `status --json` for version, service, path, and installed protocol diagnostics.
- Use `nodes --json` for log-safe node summaries. It intentionally omits full links and passwords.
- Use `links --json` only in trusted contexts; it returns full connection material.
- Use `export-client --json` to generate and validate the sing-box bare-core client config. It writes the client export file but does not mutate the running server config or restart service.
- Use `check --json` and `doctor --json` for non-mutating service/config diagnostics.
- Use `service restart --json --yes` only after confirming the target is safe to mutate. It validates config before restart.
- Use `subman-sync --json` only in trusted contexts with configured SubMan credentials; it pushes VLESS REALITY and Hysteria2 node material.
- Use `update sbv` to refresh `/usr/local/bin/sbv`; alias: `sbv update-sbv`.
- Use `update sing-box [latest|x.y.z]` to update a healthy managed sing-box instance non-interactively. It preserves config, runs `sing-box check`, and restarts only after validation passes. Alias: `sbv update-sing-box [latest|x.y.z]`.
- If `update sing-box` reports an incomplete or missing instance, switch to the interactive `sbv` menu for repair, takeover, or fresh install.

## VLESS REALITY Operations

- REALITY may have multiple managed instances under `/root/sing-box-vps/protocols/vless-reality.d/`.
- Each instance can have its own port, ShortID, node name, and optional upload/download Mbps limits.
- Node names may include rate-limit suffixes; keep them intact when diagnosing or syncing nodes.
- When rate limits are configured, runtime QoS state is tracked in `/root/sing-box-vps/reality-qos.filters`.
- Removing or adding REALITY instances is a runtime config mutation. On production, use the production gate first.
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
