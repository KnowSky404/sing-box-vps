# Lifecycle and verification debt remediation

[简体中文](technical-debt-remediation.zh-CN.md)

Status: TD-01–TD-06 implemented; focused host and Docker acceptance passed.
The contract was specified before implementation. Baseline: `efd8166`; runtime
version: `2026110502`. Review/merge and Wiki publication remain separate delivery gates.

## Scope

Address the six findings from the 2026-11-05 repository audit without changing
the supported core version, configuration/state formats, protocol features or
production hosts. Keep the standalone generated installer and existing locks,
ownership checks, recovery barriers and conditional SubMan writes.

| ID | Finding | Required result |
| --- | --- | --- |
| TD-01 | Uninstall ignores failed service stop/disable | Confirm the unit is stopped before deleting runtime artifacts. Report failures and retain configuration/recovery material. |
| TD-02 | Menu service controls bypass Agent validation | Menu and canonical/compatible Agent commands use the same guarded service implementation, including config checks, pending-journal rejection and final-state checks. |
| TD-03 | Uninstall loses the instance firewall ownership ledger | Remove only positively owned instance firewall rules before deleting their ledger. Preserve unrelated rules and recovery evidence on failure. |
| TD-04 | Interrupted SubMan requests retain credential files | Clean request-private files on normal return and catchable signals, preserve caller traps and in-process result variables, and never retry an uncertain write blindly. |
| TD-05 | CI runs only a fixed contract list | Retain contract gates and execute the planner's additional host tests for the complete branch diff. Unmapped impact needs an explicit, baseline-bound scope; retain plans, logs and timings. |
| TD-06 | Takeover tests call an unused legacy wrapper | Remove `install_or_update_singbox` and move its tests to live installation/menu or shared business entrypoints. |

## Lifecycle contract

Uninstall follows prepare/validate, service stop/postcheck, owned-resource cleanup,
artifact removal and final checks. Prepare the removal plan before mutation.
A failed or unconfirmed stop must not delete configuration, executables, unit
files, ownership ledgers or recovery snapshots. A missing unit is acceptable only
when its absence and lack of a running service are positively established.
Disable errors are visible and do not become successful deletion results.

Use the existing firewall transaction primitive for the transition to no managed
listeners. Validate the ledger before mutation, preserve unmarked or unrelated
rules, and retain the journal when cleanup/compensation cannot be confirmed.
Do not infer complete rollback from restoring files or restart a partially
removed installation. Stop/cleanup failure leaves an actionable final state.

Menu service commands render human messages while canonical/compatible Agent
commands keep exactly one JSON envelope. Neither path may start/restart an
invalid configuration or bypass an instance/component/routing recovery barrier.
The existing `service.start|stop|restart` descriptors and manuals describe the
shared behavior.

The existing `core.uninstall`, `script.uninstall` and legacy protocol-removal
operations remain `interactive_only`. They do not have a durable whole-uninstall
rollback journal or stable structured result contract. This change hardens their
existing business function and internal purge caller; it does not invent an
unattended result contract or feed answers into prompts. Their catalog reasons
remain explicit and receive local review.

## SubMan request cleanup

Keep credentials in the existing private directory and curl config, never argv
or routine logs. Catch INT/TERM/HUP and clean the request directory at the
request boundary, then restore/propagate the caller's signal behavior. Preserve
the global response fields needed by existing callers. A signal after a mutation
may mean the remote outcome is unknown; cleanup is not proof of remote rollback.
SIGKILL/power-loss cleanup is not claimed. Existing destination, Gist, ETag and
readback reconciliation checks stay in force.

## CI scope contract

Use the existing planner and standalone-test validation, including all committed,
staged/unstaged and untracked changes supported by `--base`. CI checks out the
tested head with enough history and passes the PR base/push-before revision as
data, never shell code.

An explicit repository scope is bound to the actual merge base. Reusing an
unchanged scope from another branch must not silently resolve `needs_scope`.
PR scope must match its actual merge base. On a protected `main` push after
GitHub rebase merge, a changed scope may name an ancestor of the push-before
revision; unchanged scopes remain rejected. Only validated planner selectors are
accepted; no shell evaluation or arbitrary commands. Automatically selected checks are additive. Unknown or stale scope
fails before tests. CI reuses the host executor directly. A dedicated container fixture may leave
the full plan at `needs_scope` while host checks pass; its separate runtime
requirement is recorded as `required_not_run`. CI never executes container
fixtures as host tests and records selected Docker scenes as unexecuted; a green CI result is not runtime acceptance.

Preserve the `command-contract` job name, read-only GitHub permissions and safe
`pull_request` event. Upload the plan, per-test logs and elapsed times even after
test failure. Do not require a full suite for ordinary changes.

## Verification and delivery

- Host: failing/no-op stop and disable, malformed/foreign ledger, precise owned
  firewall removal and failure recovery, menu/CLI parity, invalid config and
  pending journals, SubMan signal cleanup/trap preservation, migrated takeover
  entrypoints, CI fresh/stale/missing/invalid scope and planner mapping tests.
- Runtime: disposable systemd/sing-box Docker acceptance for real menu/CLI
  service guards and uninstall/firewall cleanup, with a fresh baseline. Check
  affected fixture configs with the target `sing-box check`; retain artifacts.
- Docs/build: bilingual SPEC/index, affected Wiki/Agent manuals/navigation,
  generated installer/catalog sync, command catalog contract and one version
  increment for this delivery.
- Excluded: full protocol matrix, core/state migrations, real SubMan/WARP writes,
  public connectivity and production. New evidence may justify focused additions.
- Delivery: atomic Conventional Commit(s), current-HEAD local complete-diff
  review, PR checks and automatically triggered current-head Security Review,
  rebase merge and clean worktree/branch cleanup under AGENTS.md section 6.

## Acceptance record

- Host CI entrypoint: 35/35 distinct selected tests passed in 253 seconds,
  `dev/verification-runs/20261105045921/local-tests/results.tsv`. The later
  compensation-failure journal assertion and dispatcher-scope assertion were
  rechecked through their exact tests; documentation checks were refreshed.
  Unchanged test/runtime content reused its passing result.
- Final Docker: `dev/verification-runs/20261105054049` reports exit 0 and all three
  registered scenes successful: `fresh_install_socks`, `lifecycle_safety`,
  `runtime_smoke`. Real systemd/menu/CLI guards, both families' owned-rule
  cleanup, unrelated-rule preservation, reinstall and final proxy smoke pass.
  Fixture configs passed `sing-box check`.
- The first Docker attempt (`20261105050043`) exposed an incomplete fixture:
  fresh installation used an unmarked legacy rule, not a ledger. The successful
  scene replaces only that exact fixture-created rule with the real scoped
  reconciler before testing uninstall. Production unmarked rules are preserved;
  this is not an ownership/state migration.
- SubMan tests use dummy credentials and mocked HTTP, including INT/TERM/HUP,
  caller traps, response globals and uncertain-write handling. No real request
  or production operation is included.
- CI keeps its original contract gates, adds diff-selected tests and uploads
  plans/logs/timings. Its Docker/dedicated-runtime result is required_not_run, not passed.
- Follow-up isolated checks reproduced an inherited skip-local flag bypass
  and suppressed uninstall signal diagnostics. CI now forces host execution;
  uninstall reports uncertain interruption state; firewall snapshot failures
  fail the scene. All seven affected host checks (55 seconds) and the final
  three Docker scenes were rerun successfully. Unchanged business functions
  and tests reused their original results without unrelated full regression.
- Current-head review findings were fixed: early-signal private-path
  protection, ancestor scope handling for rebased main pushes, and host
  readiness separate from dedicated container acceptance. Seven exact
  regressions (59 seconds) and the final three Docker scenes passed. PR
  scope matching remains strict; standard runtime `needs_scope` is retained.
- Tested generated runtime SHA-256: `6f0ddf69c5dd902f48d9ae27e0f01219db1cc345d0693b1080f68b1b7a215e08`.
- Local/current-head review, PR/remote review/merge and Wiki publication are
  recorded in the implementation PR, not inferred from the above test results.
