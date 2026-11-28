---
name: sing-box-vps-operator
description: Use when installing or upgrading sing-box-vps, running local or remote verification, operating sing-box-test or sing-box-prod, troubleshooting sbv or sing-box service issues, retrieving node info for AI agents, managing VLESS REALITY instances or Warp/SubMan/node sharing, modifying repository scripts or docs, validating sing-box configs, or creating rollback/recovery steps for this project.
---

# sing-box-vps Operator

Use this skill for repository maintenance and VPS operations for `sing-box-vps`.

## Required Reading

When invoked from an installed copy, locate the local sing-box-vps checkout for
the task's revision. If needed, obtain that revision from the
[project repository](https://github.com/KnowSky404/sing-box-vps) in a local
checkout. Open that checkout's `skills/sing-box-vps-operator/SKILL.md` and follow
its rules. For required reading, resolve this project's published Wiki pages to
`docs/wiki/<Page>.md` and `blob/main` links to their repository paths in the same
checkout. Stop the corresponding stage if the Skill or required local reading
is unavailable.

Start with the checkout's `AGENTS.md` and follow its required reading routes.
Before operational work, also read `README.md` and `docs/wiki/Agent-Runbook.md`
from the checkout root. Stop the corresponding stage if required reading is
unavailable.

For `sing-box` configuration syntax, version compatibility, migration notes, or official examples, use Context7 first.

The supported core baseline is 1.14.4. Before upgrading, inspect `agent upgrade-check`
and existing manual rules: use `action:"route",outbound:"direct"` instead of the
removed `action:"direct"`. Linux ARM64 1.14.2/1.14.4 `with_purego` namespace builds
are refused before config publication or core replacement; use a verified compatible
build. See [Protocol Coverage](../../docs/wiki/Protocol-Coverage.md) and
[Advanced Components](../../docs/wiki/Advanced-Components.md) for the actual evidence.

For 1.14.4+ targets, `legacy_direct_action` blocks updates before download. Read
the component revision, back up, and separately approve `component rebuild` for
baseline-owned rules; verify manual differences survive. Binary-only updates
never migrate config. The ordinary updater checks core/config/service files and
the live core config without reconstructing or repairing protocol state.

## Discover And Maintain Operations

Run `sbv commands --json`, then `sbv schema <operation-id> --json` before choosing
an operation. Compatible discovery commands use `sbv agent commands` and
`sbv agent schema`. Read automation status, mutation/sensitivity, confirmation,
concurrency/CAS, input contract and service impact; feature booleans do not imply
an automated write or successful runtime acceptance. Use the generated
[Command Catalog](../../docs/wiki/Command-Catalog.md) offline.

Canonical commands and existing `sbv agent ...` commands share the same handlers
and transaction guards. Do not synthesize prompt answers for an interactive-only
operation or hand-edit managed state. Retained exceptions list their reason and
menu entry in the catalog. For routing, save only `.data.draft` from sensitive
`routing export` into an owned private 0400/0600 input file, preserve its
fingerprint, validate it and use the guarded apply/recovery path. Service logs
are bounded but sensitive.

For runtime operation changes follow the
[AI Native delivery contract](../../docs/wiki/Development.md#ai-native-命令与手册同步)
and the affected SPEC. For commit review, push, PR and merge follow the local
[review and merge gates](../../docs/wiki/Development.md#审查与合并).

## Lifecycle And GitHub Boundaries

Menu service controls share the guarded Agent handlers. Recover pending journals before mutations; start/restart require a checked config. Uninstall confirms stopped state before file deletion and reclaims only ledger-owned firewall rules. On failure preserve reported recovery material; whole-uninstall rollback is not claimed. SubMan request files are cleaned on catchable signals, but an interrupted remote write still needs readback reconciliation.

Read the local [Actions authorization and verification rules](../../docs/wiki/Development.md#github-actions-授权与定点验证)
before GitHub writes or any authorized workflow run.

## Storage Layout

Project payloads live under the root account home `.sing-box-vps`. Before operating an upgraded legacy host, use `sbv storage status --json`. Migration and recovery are explicit `sbv storage migrate|recover --json --yes` operations and may restart an active service. Pending migrations block ordinary operations. Read [Storage Layout](../../docs/wiki/Storage-Layout.md); production migrations still require the production gate.

## Classify The Target

- **Local repository**: files in the workspace.
- **Test VPS**: `sing-box-test`.
- **Production VPS**: `sing-box-prod`.
- **Unknown remote host**: treat as production until clarified.

## Production Gate

Before any production-changing command on `sing-box-prod` or an unknown host, present a plan and wait for explicit approval.

Production-changing commands include install, upgrade, restart, stop, reload, uninstall, purge, config mutation, firewall mutation, service mutation, writing `/usr/local/bin/sbv`, or changing `/root/.sing-box-vps/`.

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

## Verification

Use the local [risk and verification rules](../../docs/wiki/Development.md#风险与验证范围)
to plan checks, then read the [scheduler procedure](../../docs/wiki/Development.md#调度器命令与计划)
when using the dispatcher. For real Docker scenarios keep the isolated baseline,
CAS and external-evidence boundaries in the [scoped Docker SPEC](../../docs/specs/scoped-docker-verification.md).
For changes to REALITY regional candidates or their checker pin, follow the
[development-network evidence procedure](../../docs/wiki/Development.md#reality-地区候选的开发门槛).

Local verification auto-builds the disposable Docker image. Use `sing-box-test`
for authorized test VPS work and `sing-box-prod` only after the production gate.

## Documentation

For read-only security review follow the local [security guide](../../SECURITY.md).
For commands, installation and recovery use the [Agent Runbook](../../docs/wiki/Agent-Runbook.md)
and [Agent CLI](../../docs/wiki/Agent-CLI.md), then the relevant protocol or
component pages. Use the staged Bootstrap command in
[Getting Started](../../docs/wiki/Getting-Started.md).

The runtime operation authority is `sbv commands --json` and `sbv schema <operation-id> --json`; compatible product capabilities remain available through `sbv agent capabilities --json`. Documentation publishing changes the separate Wiki Git repository and must preserve unrelated user pages. Follow `Development.md` for validation and publishing.
