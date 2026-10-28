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
3. [Wiki Agent Runbook](https://github.com/KnowSky404/sing-box-vps/wiki/Agent-Runbook) (source: `docs/wiki/Agent-Runbook.md`)

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

- Follow the impact-based test boundaries in [AGENTS.md](../../AGENTS.md), section 4.2. Explain the selected scope before running tests; do not select a broad suite solely because `install.sh` or another runtime file changed.
- Run `sing-box check` on affected generated or modified server/client configurations. Run related real Docker scenarios for service, network or lifecycle behavior changes, with their prerequisites prepared.
- Documentation, version-display and menu-only changes need their focused checks. Run changed standalone tests and callers of changed helpers; Bootstrap changes need the download/validation tests.
- Require full regression for core-version adaptation or config/state migrations, broadly affected shared logic or uncertain impact, or an explicit full-test/release-acceptance requirement. Reuse passing results only when the tested code, configuration, tests, dependencies, core version and relevant environment are unchanged; record the original evidence and reason. After a fix, rerun failed and affected checks.
- The current runner still selects by file path and lacks `--plan`, `--base` and complete test groups. Until it is updated, manually select existing tests and required scenarios under section 4.2 and record commands, reasons and omissions. Check the full branch diff after committing; the default runner only detects working-tree changes. `VERIFY_SKIP_REMOTE=1` is not runtime-validation evidence.
- Remote verification runs in Docker locally, auto-building sing-box-vps-verify image. No external SSH target required.
- Use `sing-box-test` for test validation and `sing-box-prod` only after the production gate.

## Documentation

Detailed commands, install steps, recovery procedures and capability boundaries live in the [Wiki](https://github.com/KnowSky404/sing-box-vps/wiki). Repository sources are under `docs/wiki/`; read those files when offline. Start with `Agent-Runbook.md`, then follow `Agent-CLI.md`, `Protocol-Instances.md`, `Advanced-Components.md` or `Upgrade-Rehearsal.md` as needed. Use the staged Bootstrap command in `Getting-Started.md` without replacing it with a download-and-execute pipe.

The runtime authority remains `sbv agent capabilities --json`. Documentation publishing changes the separate Wiki Git repository and must preserve unrelated user pages. Follow `Development.md` for validation and publishing.
