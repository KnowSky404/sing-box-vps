# AI-native operation contract

Status: implemented within the user-confirmed scope; scoped acceptance is recorded
below. The user explicitly selected the common architecture and safe adapters,
with remaining legacy limitations exposed rather than migrating every menu flow. This contract preserves the standalone runtime, Bash,
existing state formats, protocol validators and transaction implementations.

## 1. Audit and objective

The baseline `36fc73e` exposes typed instance/component transactions, diagnostics,
node materials, core upgrades and SubMan synchronization through `sbv agent`.
It does not expose the unified routing transaction or service start/stop/logs.
REALITY instance writes, fresh installation, host stack/BBR changes, SubMan
settings, media checks and removal still require interaction. Existing capability
booleans describe product features, not complete automation coverage. Unknown
top-level commands enter the menu; pending routing transactions block even an
Agent that needs to discover recovery instructions.

The objective is an inspectable operation contract shared by people and Agents:
discover -> describe -> read -> prepare private input -> validate -> commit with
explicit confirmation/CAS -> inspect result/recover. A menu is a user interface,
not an automation API. Never synthesize prompt answers to claim API coverage.

## 2. Command architecture

- No arguments keeps `sbv`'s menu. Explicit `sbv menu` is also supported.
- Canonical commands are `sbv <resource> <verb> ... --json`; common read commands
  (`status`, `nodes`, `links`, `check`, `doctor`, `warp`) retain short forms.
- `sbv commands --json` returns the complete versioned operation catalog.
  `sbv schema <operation-id> --json` describes one operation, including its exact
  argument contract, input-file contract, confirmation, sensitivity, concurrency,
  service impact and documentation. This is an operation descriptor, not a claim
  that every protocol record has a generic JSON Schema validator.
- Existing `sbv agent ...` invocations remain supported with existing envelopes,
  revision meaning, output keys and confirmation requirements. Canonical aliases
  enter the same Agent dispatcher and handlers, preserving locking and guards.
- Unknown commands/extra arguments fail without opening a menu or mutating state.
  Machine commands emit exactly one JSON object on stdout; progress goes to stderr.
- Discovery is independent of installed services and pending transactions. Reads
  and writes otherwise retain the current root and transaction gates.

An embedded operation registry is shipped inside generated `install.sh`; there
is no runtime download or dependency on repository files. Each executable entry
has a stable ID, canonical command, legacy command, usage, summary, mutation and
sensitivity classification, confirmation/CAS, input contract, service impact,
documentation anchor and implementation status. Catalog generation, operation
description, help and the generated reference consume this registry. Explicit
legacy exceptions have `automation=interactive_only`, a reason and a menu/manual
entry. `features.*` remains compatible; automation decisions use this catalog.

## 3. Routing API

`sbv routing view|export|nodes --json` reads the existing unified policy. `view`
redacts URLs, legacy source/domain text and account material, and returns the
current fingerprint. `export` returns a complete sensitive draft for local edits;
redirect it into a private file. `nodes` returns safe per-node routing identities.

`sbv routing validate --json --file draft.json` runs the existing draft validator
without publishing configuration. This validates the input structure and does
not claim target-core/runtime acceptance. `apply --json --yes --file draft.json`
uses the draft's fingerprint as CAS and invokes the existing transaction, which
validates the actual generated configuration and preserves rollback behavior.
`restore --json --yes --expected-fingerprint HASH` restores the previous snapshot
only when the current fingerprint matches. `recover --json --yes` invokes the
existing trusted persistent recovery journal; its journal owns recovery CAS.

Do not expose arbitrary jq filters, shell expressions, unbounded paths or a
second policy format. Guard pending instance/component transactions. Permit
routing recovery through the routing-pending gate; recovery must not grant other
writes. Return failed/unchanged/recovery-required outcomes truthfully. This API
does not add a speculative dry-run that might register a real WARP account.

## 4. Service API

`sbv service status --json` reports service state. `start|stop|restart --json
--yes` require explicit confirmation; start/restart validate the existing config
before invoking systemd, then verify the resulting state. Stop checks that the
unit is inactive rather than treating a successful command exit as sufficient.
Preserve the existing restart response fields. `logs --json [--lines N]` is
bounded (1..1000, default 100), non-following and sensitive; journal output is
not guaranteed to be credential-free. Do not interpolate user values into shell.

## 5. Coverage and legacy exceptions

The catalog maps all current main-menu operation families to an executable
interface or an explicit interactive limitation. New features must ship an
appropriate noninteractive command and descriptor; a new exception needs an
explicit rationale in the SPEC and review. Existing unsafe-to-wrap paths remain
visible limitations until they have typed validation, confirmation, concurrency,
backup/rollback and a reliable postcheck. In particular, do not claim REALITY
write CAS or unattended installation by wrapping the existing prompt workflow.
Any decision to migrate those formats is a separate explicit scope with its own
config/state migration and corresponding acceptance requirements.

## 6. Development workflow

Every added/changed operation updates its handler, embedded descriptor, focused
tests, generated command reference and affected runbook/SPEC/Agent navigation in
the same change. Shared handlers keep menu and CLI semantics aligned. The
generated reference has a read-only `--check` mode. Contract tests compare the
catalog with reference output, validate unique IDs and safety fields, exercise
canonical/legacy dispatch and assert that unknown commands never enter the menu.
The docs verification group includes this gate; lightweight CI runs the same
checks without implicitly triggering full protocol regression.

## 7. Verification plan

Required: build/artifact consistency, shell syntax/version checks, catalog and
generated docs contracts, canonical/legacy parsing, routing fingerprint and
pending-journal guards, existing Agent JSON/command tests and routing transaction
tests. Service and routing entrypoints require representative real systemd Docker
acceptance using a prepared baseline and target `sing-box check`. Preserve
sensitive-output and single-JSON checks on failures. No core-version or state
format migration is planned, so unrelated protocol matrices, real WARP/SubMan
writes and production changes are outside this verification scope. Expected:
focused host checks around 5-10 minutes, isolated runtime around 5-15 minutes;
investigate slow prerequisites rather than restarting a broad suite.

## 8. Acceptance record

- Runtime version: `2026110302`; 56 operations: 44 structured, two legacy text
  CLI operations and ten explicit interactive-only limitations. Existing Agent
  paths and output envelopes remain supported. `schema.parameters`, `cas`,
  output format and external-write fields provide per-operation descriptions.
- Focused host checks: build/source and generated-reference consistency,
  install-build, command-catalog/canonical/strict-parser contract, Agent JSON and
  operation compatibility, routing and service adapters, existing routing
  transactions, old update commands/help, main-menu rendering, Wiki/Agent docs
  and version checks. An initial old-help assertion correctly caught omitted
  legacy update usages; catalog entries/aliases were added and that test passed.
  Original logs: `/tmp/sbv-ai-host-20261103T062251Z`; update rerun:
  `/tmp/sbv-ai-cli-rerun.log`. New service dangling-journal refusal branches and
  later metadata/help changes were checked separately; unchanged domain/runtime
  tests are reused.
- Planner checks: `verification_planner`, `verification_trigger_rules`,
  `verification_tests_only_stays_local`, and
  `verification_run_writes_changed_files` passed. The new runtime fixture is
  explicitly container-only; automatic execution refuses it and reports the
  required separate procedure, including when it is reached through a helper.
- Real isolated systemd Docker acceptance passed with sing-box `1.14.2`, no
  external network: service status/stop/start/restart/logs; routing
  view/nodes/export/validate/apply; target-core checks; real HTTP allowed/rejected
  by the applied rule; stale apply/restore CAS rejection; restore and connectivity
  recovery. Recovery dispatch/cleanup used a completed real transaction journal
  moved back to its pending location. This models interrupted cleanup, not an
  actual signal interruption experiment.
- Docker artifacts: `/tmp/sbv-ai-native-runtime-20261103T062128Z.g7p9uiwq`, result
  zero and `last_phase=complete`; container removed. Tested runtime SHA-256:
  `46082f5deeff5893a5986521ab36e6c6f74962b0cabff539ec76abb75cd1135b`.
  The later changes add service dangling-symlink refusals and catalog/help
  metadata only; real service/routing behavior is unchanged, so this success-path
  evidence is reused under AGENTS section 4.2. New rejection paths have host tests.
- No real WARP/SubMan write, public connectivity or production change was
  performed. Exact-head reviews/merge and Wiki publication are separate delivery
  records in the implementation PR; this SPEC does not assert them in advance.
