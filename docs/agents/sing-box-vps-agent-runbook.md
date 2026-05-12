# sing-box-vps Agent Runbook

This runbook is for AI agents operating the `sing-box-vps` repository and remote VPS hosts. It is written for Hermes, OpenClaw, Codex, Claude Code, and other automation agents.

## First Principles

- Treat `install.sh` as the single runtime source of truth.
- Read `AGENTS.md` and `README.md` before changing repository behavior.
- Use `sing-box-test` for test VPS validation.
- Use `sing-box-prod` for production VPS operations.
- Prefer `dev/verification-target.env` for remote verification target configuration when the file exists.
- Preserve secrets. Do not print private keys, passwords, tokens, full proxy links, or QR payloads unless the user explicitly requests them and the context is safe.
- Back up runtime config before changing it.
- Run `sing-box check` after generating or modifying any sing-box server or client config.

## Environment Classification

Classify the target before acting:

- **Local repository**: files under the project workspace.
- **Test VPS**: SSH target `sing-box-test`, used for validation and disposable install tests.
- **Production VPS**: SSH target `sing-box-prod`, used by real users or real traffic.
- **Unknown host**: any host that is not clearly local, test, or production.

If a remote host is unknown, treat it as production until the user clarifies.

## Production Safety Gate

Production operations are plan-first. Before any production-changing command, present a plan and wait for explicit approval.

Production-changing commands include:

- Fresh install or upgrade.
- Service restart, stop, disable, enable, or reload.
- Config rewrite, protocol change, Warp change, or firewall change.
- Uninstall, purge, cleanup, or deletion of runtime files.
- Overwriting `/usr/local/bin/sbv`, `/root/sing-box-vps/`, or sing-box systemd units.

Read-only checks may be used to prepare the plan:

```bash
ssh sing-box-prod 'hostname; uptime; command -v sbv || true; command -v sing-box || true'
ssh sing-box-prod 'systemctl status sing-box --no-pager || true'
ssh sing-box-prod 'sing-box version || true'
ssh sing-box-prod 'ls -la /root/sing-box-vps /usr/local/bin/sbv 2>/dev/null || true'
```

Do not run state-changing production commands until the user approves the plan.

## Production Operation Plan Template

Use this exact structure before changing production:

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

## Local Repository Workflow

For code or script changes:

1. Inspect the current repository state with `git status --short`.
2. Read the affected files before editing.
3. Keep edits scoped to the task.
4. If `install.sh`, `uninstall.sh`, `configs/`, `utils/`, or `dev/verification/` changes, run:

```bash
bash dev/verification/run.sh
```

5. If only local dispatch rules need validation, use:

```bash
VERIFY_SKIP_REMOTE=1 bash dev/verification/run.sh
```

6. When runtime behavior changes, update `SCRIPT_VERSION` in `install.sh` and the version shown in `README.md`.
7. Commit atomically with a conventional commit message after verification.

Documentation-only changes do not require `SCRIPT_VERSION` updates.

## Test VPS Verification

Use the repository workflow unless the user asks for a direct manual test.

The preferred target is declared in `dev/verification-target.env`:

```bash
VERIFY_REMOTE_HOST_ALIAS=sing-box-test
```

Run:

```bash
bash dev/verification/run.sh
```

The verification runner decides whether remote scenarios are required based on changed files. It writes artifacts under the run directory printed as `run_dir=...`.

When remote validation fails:

1. Read `summary.log`.
2. Inspect `remote.stderr.log` and `remote.stdout.log`.
3. Inspect extracted remote artifacts if present.
4. Fix the root cause before rerunning verification.

## Fresh Install On A New VPS

For a test VPS, direct installation is allowed when the user asked for a test installation and the host is clearly `sing-box-test`.

For production or unknown hosts, use the production plan gate first.

Canonical public install command:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/install.sh)
```

Post-install checks:

```bash
command -v sbv
systemctl status sing-box --no-pager
sing-box check -c /root/sing-box-vps/config.json
```

If the install generates or displays credentials, summarize that credentials were generated without pasting secrets into logs.

## Upgrade Existing VPS

For production, use the plan gate first.

Before upgrade:

```bash
cp -a /root/sing-box-vps "/root/sing-box-vps.bak.$(date +%Y%m%d%H%M%S)"
sing-box check -c /root/sing-box-vps/config.json
systemctl status sing-box --no-pager
```

Upgrade using the script's supported menu or update path. After upgrade:

```bash
sing-box version
sing-box check -c /root/sing-box-vps/config.json
systemctl status sing-box --no-pager
```

If service health changed, collect logs:

```bash
journalctl -u sing-box --no-pager -n 200
```

## Operations And Troubleshooting

Useful read-only checks:

```bash
sbv
systemctl status sing-box --no-pager
journalctl -u sing-box --no-pager -n 200
sing-box check -c /root/sing-box-vps/config.json
ls -la /root/sing-box-vps /root/sing-box-vps/protocols
```

Common paths:

- Runtime directory: `/root/sing-box-vps/`
- Main config: `/root/sing-box-vps/config.json`
- Protocol state: `/root/sing-box-vps/protocols/`
- Warp domains: `/root/sing-box-vps/warp-domains.txt`
- Global command: `/usr/local/bin/sbv`
- systemd service: `sing-box`

For config problems, do not guess from symptoms alone. Run `sing-box check`, inspect the generated JSON, and compare protocol state files to the runtime config.

## Rollback And Recovery

Use backups before restoring production files. A typical recovery path is:

```bash
systemctl stop sing-box
cp -a /root/sing-box-vps.bak.YYYYMMDDHHMMSS /root/sing-box-vps
sing-box check -c /root/sing-box-vps/config.json
systemctl start sing-box
systemctl status sing-box --no-pager
```

For production, present the rollback commands in a plan and wait for approval before execution unless the user has already approved emergency recovery.

## External Documentation

When current `sing-box` configuration syntax, migration behavior, or version compatibility is needed, use Context7 first. If Context7 cannot provide enough detail, use official `sing-box` documentation or the official repository before relying on third-party posts.
