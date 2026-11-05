---
name: sing-box-vps-operator
description: Use when installing or upgrading sing-box-vps, running local or remote verification, operating sing-box-test or sing-box-prod, troubleshooting sbv or sing-box service issues, retrieving node info for AI agents, managing VLESS REALITY instances or Warp/SubMan/node sharing, modifying repository scripts or docs, validating sing-box configs, or creating rollback/recovery steps for this project.
---

# sing-box-vps Operator

Use this skill for repository maintenance and VPS operations for `sing-box-vps`.

## Required Reading

Before operational work, read:

1. `AGENTS.md`
2. `README.md`
3. [Wiki Agent Runbook](https://github.com/KnowSky404/sing-box-vps/wiki/Agent-Runbook) (source: `docs/wiki/Agent-Runbook.md`)

For `sing-box` configuration syntax, version compatibility, migration notes, or official examples, use Context7 first.

The supported core baseline is 1.14.4. Before upgrading, inspect `agent upgrade-check`
and existing manual rules: use `action:"route",outbound:"direct"` instead of the
removed `action:"direct"`. Linux ARM64 1.14.2/1.14.4 `with_purego` namespace builds
are refused before config publication or core replacement; use a verified compatible
build. See [Protocol Coverage](../../docs/wiki/Protocol-Coverage.md) and
[Advanced Components](../../docs/wiki/Advanced-Components.md) for the actual evidence.

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

For added/adjusted runtime operations, ship each feature with its noninteractive
command, embedded descriptor, focused test, generated reference and affected
Agent runbooks/navigation. Build install.sh, run
`bash scripts/build-command-docs.sh`, check both builds with `--check`, and run
`tests/command_catalog_contract.sh`. New interactive-only exceptions need an
explicit SPEC rationale and review. Follow AGENTS.md section 4.2 for the remaining
behavior verification; this contract does not require unrelated full regression.
Development tooling and ordinary prose changes follow section 4.2 without
automatically rerunning the runtime operation catalog contract.

## Repository Review And Merge

Local current-HEAD/full-diff review remains mandatory before every push or PR.
Remote GPT/Codex review is automatic only. Never manually request code/security
review or retrigger through draft/ready transitions, empty commits or similar
actions. Wait for a Security Review only when automatically triggered for the
current head; it must complete without unresolved findings. Automatic code review
is not a waiting gate, though reported issues require handling. If no bot was
automatically triggered, record `not_triggered` and directly rebase merge after
local review, necessary validation and required GitHub checks pass. Automatic code
review alone adds no remote wait. Absence is not review success; running, failed,
cancelled or unreadable state is not absence. Recheck a new head under this same
policy without manually triggering review. Follow AGENTS.md section 6.

## Lifecycle And CI Boundaries

Menu service controls share the guarded Agent handlers. Recover pending journals before mutations; start/restart require a checked config. Uninstall confirms stopped state before file deletion and reclaims only ledger-owned firewall rules. On failure preserve reported recovery material; whole-uninstall rollback is not claimed. SubMan request files are cleaned on catchable signals, but an interrupted remote write still needs readback reconciliation.

CI uses the complete branch diff plus a changed `.github/verification-scope.txt` bound to its merge-base when impact is unmapped. It runs host tests and preserves plans/logs/timings; selected Docker scenes remain a separate acceptance boundary. See [the debt remediation contract](../../docs/specs/technical-debt-remediation.md).

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

## Verification Rules

- Prefer repeatable `--test tests/<name>.sh` for exact standalone host tests, combined with `--base origin/main` to retain automatic checks for the entire diff. It rejects helpers, symlinks and container-only fixtures. Use groups only when their whole scope is needed; choose runtime scenarios separately. Ordinary docs select links, source/version edits select build sync, and planner/selection edits select their three focused contracts. Do not add broad docs/verification groups by habit.

- Follow the impact-based test boundaries in [AGENTS.md](../../AGENTS.md), section 4.2. Explain the selected scope before running tests; do not select a broad suite solely because `install.sh` or another runtime file changed.
- Section 4.2 is the single authority for test scope. Record a short plan with affected behavior, required checks/prerequisites, exclusions and expected duration. Investigate local runs expected to exceed 10 minutes or Docker runs expected to exceed 20 minutes before proceeding; these are planning thresholds, not permission to skip required checks. Stop when the required checks pass unless new evidence changes the scope.
- Run `sing-box check` on affected generated or modified server and protocol-probe configurations. Run related real Docker scenarios for service, network or lifecycle behavior changes, with their prerequisites prepared.
- Documentation, version-display and menu-only changes need their focused checks. Run changed standalone tests and callers of changed helpers; Bootstrap changes need the download/validation tests.
- REALITY regional seeds require actual development-network DNS/TLS evidence. After changing the pool or checker pin, run `bash scripts/check-reality-region-candidates.sh NEW_OUTPUT_DIRECTORY`, retain the raw reports, and update `docs/verification/reality-region-candidates.json` only after exit 0. Run `tests/reality_region_candidate_evidence.sh` and its `_contract.sh` regression. Every DNS endpoint must pass basic TLS/compatibility; ancillary WARN remains subject to fresh installation-time consent. Never pad a regional pool with failing/unknown candidates. See Development.md for the exact evidence and runtime boundaries.
- Require full regression for core-version adaptation or config/state migrations, broadly affected shared logic or uncertain impact, or an explicit full-test/release-acceptance requirement. Reuse passing results only when the tested code, configuration, tests, dependencies, core version and relevant environment are unchanged; record the original evidence and reason. After a fix, rerun failed and affected checks.
- Preview `bash dev/verification/run.sh --plan --base origin/main`. Base mode uses the merge base and includes committed, staged, unstaged and untracked changes. Without `--base`, only working-tree differences against HEAD are considered. Docs, version metadata, Bootstrap and changed host tests map automatically; unmapped runtime impact needs an explicit local `--test`, `--group`, Docker `--scenario`, or `--full` before execution. Groups and scenarios are repeatable; choose runtime coverage separately when required. Full means the registered host-safe manifest and scenario set, not every script in tests/. Container-only fixtures stay out of host selection. See Development.md for examples and prerequisites.
- Choose the exact runtime leaf: outbound/policy components such as `component_vless_outbound` / `component_tproxy_inbound`, a single `protocol_probe_hy2`, or `protocol_naive_transition` / `protocol_snell_transition`. All leaves receive their own fresh SOCKS baseline; protocol leaves add only the target protocol, and final smoke follows all mutations once. An empty post-deletion component store retains an increased revision, not revision 0. The selectable catalog includes all decomposed units, while default `--full` remains the original 17 scenarios through shared aggregate assertions without repeating leaves. Shared fixture/assertion/aggregate/dispatcher and external REALITY/Tor changes retain `needs_scope` for explicit impact classification. REALITY probes / `protocol_coexistence` use an external TLS cover; Tor needs a real circuit. Neither is an implicit dependency of ordinary leaves, and mocks cannot substitute for external evidence. See [the scoped Docker SPEC](../../docs/specs/scoped-docker-verification.md) for exact IDs, the accepted 32 independent Stage 2 scenes plus aggregate compatibility (33/33), and their timings. Timings include internal installation work and exclude separately scheduled baselines, final smoke and transfer. This finite acceptance did not rerun unrelated upgrade/uninstall scenes. Stage 1 historical acceptance, implementation, current Docker and production evidence remain distinct.
- Remote verification runs in Docker locally, auto-building sing-box-vps-verify image. No external SSH target required.
- Use `sing-box-test` for test validation and `sing-box-prod` only after the production gate.

## Documentation

For read-only security reviews, start with [SECURITY.md](../../SECURITY.md). Review the full change and relevant callers statically; use only a necessary, isolated reproduction. A review alone does not require tests, version changes, commits or production operations. Security-review waiting time is separate from test time and does not justify rerunning tests or bypassing the merge gate.

Detailed commands, install steps, recovery procedures and capability boundaries live in the [Wiki](https://github.com/KnowSky404/sing-box-vps/wiki). Repository sources are under `docs/wiki/`; read those files when offline. Start with `Agent-Runbook.md`, then follow `Agent-CLI.md`, `Protocol-Instances.md`, `Advanced-Components.md` or `Upgrade-Rehearsal.md` as needed. Use the staged Bootstrap command in `Getting-Started.md` without replacing it with a download-and-execute pipe.

The runtime operation authority is `sbv commands --json` and `sbv schema <operation-id> --json`; compatible product capabilities remain available through `sbv agent capabilities --json`. Documentation publishing changes the separate Wiki Git repository and must preserve unrelated user pages. Follow `Development.md` for validation and publishing.
