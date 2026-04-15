# Remove Legacy Entrypoints Design

## Goal

Eliminate the obsolete single-protocol entrypoint implementation so the repository has one authoritative runtime path: `install.sh`.

## Scope

- Delete `main.sh`.
- Delete files in `scripts/` that only exist to support the old `main.sh` flow and are not referenced by the current `install.sh`-based workflow.
- Keep `install.sh` as the sole installation and management implementation.
- Update documentation and tests that still describe or validate `main.sh` as a maintained entrypoint or metadata source.

## Non-Goals

- No behavior changes to the multi-protocol flow in `install.sh`.
- No refactor of `install.sh` back into modular runtime files.
- No changes to legacy migration behavior beyond what is required to remove references to deleted entrypoints.

## Current State

The repository currently contains two different implementation eras:

- `install.sh` is the real, maintained script with multi-protocol support, legacy migration logic, state-layer management, and the current version metadata.
- `main.sh` and the files under `scripts/` represent an older single-protocol flow centered on `VLESS + REALITY`.

This creates three concrete problems:

1. Documentation and repository structure imply `main.sh` is still a valid primary entrypoint.
2. Some tests treat `main.sh` as a version/support-version source of truth.
3. Future maintenance can accidentally keep obsolete files in sync even though users are not supposed to run them.

## Approach Options

### Option A: Full removal now

Delete `main.sh` and all dead `scripts/` files, then update docs/tests to reflect `install.sh` as the only maintained entrypoint.

Pros:

- Removes ambiguity in one pass.
- Prevents future drift between old and current implementations.
- Keeps tests aligned with the code users actually execute.

Cons:

- Requires careful reference audit before deleting files.

### Option B: Remove `main.sh`, keep `scripts/` temporarily

Delete only the top-level legacy entrypoint and keep the old helper scripts for one transition cycle.

Pros:

- Slightly lower short-term deletion risk.

Cons:

- Leaves dead code in the repo.
- Does not fully solve maintenance ambiguity.

### Option C: Convert old entrypoints into deprecation stubs

Keep files but replace behavior with warnings that redirect users to `install.sh`.

Pros:

- Lowest deletion risk.

Cons:

- Still preserves duplicate entrypoint surface area.
- Keeps tests and readers exposed to obsolete files.

## Recommended Approach

Adopt Option A.

The repo already has a single real implementation in `install.sh`. The cleanest fix is to remove dead entrypoints entirely and update dependent docs/tests so they validate the maintained path instead of historical artifacts.

## Deletion Rules

Before deleting any file, run a repository-wide static reference check.

- If a file is only referenced by `main.sh` or not referenced at all, it is eligible for deletion.
- If a file is referenced by current tests, docs, or runtime paths only because they still point at legacy entrypoints, update those references first and then delete the file.
- If any file under `scripts/` is still genuinely used by the active `install.sh` workflow, do not delete it in this task.

Expected deletion candidates:

- `main.sh`
- `scripts/config_generator.sh`
- `scripts/singbox_manager.sh`
- `scripts/system_check.sh`
- `scripts/uninstaller.sh`

## Documentation Changes

Update repository documentation to remove outdated claims that `main.sh` is the project main entrypoint.

Required documentation outcomes:

- `install.sh` is described as the source of truth for installation.
- `sbv` remains the post-install management entrypoint for users.
- Any file-structure section that names `main.sh` as a primary runtime file is corrected or removed.

## Test Changes

Adjust tests that currently enforce metadata duplication across legacy files.

Required test outcomes:

- Version metadata tests validate the maintained source of truth rather than deleted files.
- Support-version tests validate the maintained source of truth rather than deleted files.
- No test should require keeping `main.sh` alive solely as a mirror of `install.sh`.

## Error Handling

If the reference audit reveals an unexpected active dependency on a legacy file:

- Stop short of deleting that file.
- Update the implementation scope to preserve the live dependency.
- Document the dependency in the final change summary.

## Verification

Minimum verification for this task:

- Static reference audit for legacy entrypoints.
- Run tests covering version metadata and support-version expectations.
- Run any additional targeted tests affected by deleted-path references.

## Success Criteria

- The repository contains one maintained runtime path: `install.sh`.
- No documentation presents `main.sh` as a valid maintained entrypoint.
- No test depends on keeping deleted legacy entrypoints.
- Deletions do not alter `install.sh` runtime behavior.
