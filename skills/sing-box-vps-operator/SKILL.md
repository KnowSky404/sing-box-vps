---
name: sing-box-vps-operator
description: Operate and maintain the sing-box-vps project and VPS deployments. Use when installing or upgrading sing-box-vps, running local or remote verification, operating test VPS host sing-box-test, preparing production operations for sing-box-prod, troubleshooting sbv or sing-box service issues, modifying repository scripts or docs, validating sing-box configs, or creating rollback/recovery steps for this project.
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

## Repository Rules

- Keep `install.sh` as the runtime source of truth.
- Do not reveal secrets, private keys, passwords, tokens, full node links, or QR payloads unless explicitly requested and safe.
- Back up runtime config before modifying remote state.
- For runtime behavior changes, update `SCRIPT_VERSION` in `install.sh` and the README script version together.
- Documentation-only changes do not require script version changes.

## Detailed Workflows

Use `docs/agents/sing-box-vps-agent-runbook.md` for install, upgrade, troubleshooting, rollback, test verification, and production operation details.
