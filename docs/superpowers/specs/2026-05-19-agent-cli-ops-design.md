# Agent CLI Ops Design

## Goal

Add non-interactive agent commands for common VPS operations that Hermes, Codex, and other SSH agents can call safely: config validation, read-only diagnostics, guarded service restart, and SubMan sync.

## Scope

Add these commands under the existing `sbv agent` namespace:

- `sbv agent check --json`
- `sbv agent doctor --json`
- `sbv agent service restart --json --yes`
- `sbv agent subman-sync --json`

Do not add non-interactive protocol install, update, remove, or Warp mutation in this iteration. Those flows require many user-specific inputs and should get a separate parameter contract before becoming agent-callable.

## Behavior

`check --json` runs `sing-box check -c /root/sing-box-vps/config.json` and returns structured JSON with `ok`, `exit_code`, `stdout`, `stderr`, and `config_file`. It exits non-zero when validation fails.

`doctor --json` is read-only. It returns the existing status payload plus derived diagnostics: config file existence, protocol index existence, protocol state directory existence, service file existence, client export path, and embedded config-check result. It exits zero when diagnostics were collected, even if config validation failed, so agents can consume the report.

`service restart --json --yes` is a guarded mutation. It refuses to run without `--yes`, runs `check` first, skips restart if validation fails, restarts `sing-box` only after validation passes, and returns before/after service states plus the check result.

`subman-sync --json` wraps the existing SubMan sync orchestration for agent use. It must not prompt interactively. If SubMan configuration is missing, it returns a structured error. When configured, it syncs supported protocols and returns counts for synced, skipped, and failed nodes.

## JSON Contract

All new commands write machine-readable JSON to stdout. Human warnings may still go to stderr, but successful JSON parsing must not depend on stderr.

Mutating commands require an explicit `--yes` flag. Missing confirmation is a command error with JSON output and non-zero exit.

## Safety

- Do not restart on invalid config.
- Do not prompt from agent commands.
- Preserve existing interactive menu behavior.
- Keep full link/password exposure limited to existing `agent links --json`; `doctor` must not include secrets.

## Tests

Extend `tests/agent_cli_outputs_machine_readable_node_info.sh` or add a focused agent ops test to cover:

- `check --json` success and failure JSON.
- `doctor --json` includes embedded failed check without failing the command.
- `service restart --json` requires `--yes`.
- `service restart --json --yes` validates before restart and reports before/after state.
- `subman-sync --json` returns a structured missing-config error without prompting.
