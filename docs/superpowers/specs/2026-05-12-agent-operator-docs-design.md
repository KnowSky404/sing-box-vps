# Agent Operator Documentation Design

## Goal

Create an agent-readable operations package for `sing-box-vps` so Hermes, OpenClaw, Codex, and similar agents can safely maintain the repository and operate test or production VPS hosts.

## Scope

The package will document repository maintenance, fresh installation, upgrade, verification, and production operations. It will not change `install.sh`, `uninstall.sh`, runtime behavior, or the existing verification framework.

## Artifacts

- `docs/agents/sing-box-vps-agent-runbook.md`: the detailed operations manual for agents.
- `skills/sing-box-vps-operator/SKILL.md`: the compact triggerable skill for agent runtimes that support AgentSkills-style skills.
- `docs/agents/llms.txt`: a machine-readable retrieval index for RAG and documentation search systems.

## Safety Model

Test VPS operations may run the repository verification workflow when the target is `sing-box-test` and the command is part of the documented validation process.

Production VPS operations must use a plan-first gate. Before any production-changing command, the agent must present a production operation plan with target, current-state checks, planned actions, risks, backup or recovery steps, verification commands, and an explicit approval wait state. Commands that install, upgrade, restart, stop, uninstall, purge, modify config, modify firewall rules, or overwrite files on `sing-box-prod` are production-changing.

Read-only production checks may be performed when needed to prepare the plan, such as checking service status, reading versions, or inspecting logs. The runbook must distinguish read-only checks from state-changing commands.

## Repository Rules To Encode

- Read `AGENTS.md` and `README.md` before acting.
- Keep `install.sh` as the single runtime source of truth.
- Use `sing-box-test` for test validation and `sing-box-prod` for production operations.
- Use `dev/verification-target.env` when present; fall back to documented environment variables only when needed.
- Run `bash dev/verification/run.sh` for changes touching `install.sh`, `uninstall.sh`, `configs/`, `utils/`, or the verification framework.
- Run `sing-box check` after any generated or modified sing-box server or client configuration.
- Back up existing runtime configuration before modifying it.
- Do not reveal secrets, tokens, private keys, passwords, or full node links unless the user explicitly asks for them and the context is safe.
- Do not perform production uninstall, purge, restart, upgrade, firewall mutation, or config overwrite without approval of the production operation plan.

## Skill Design

The skill should be concise. Its frontmatter description must include the main triggers: installing or upgrading `sing-box-vps`, operating test or production VPS hosts, running remote verification, maintaining the repository, troubleshooting `sbv`, and handling `sing-box` config validation.

The skill body should:

- Tell the agent to read the runbook before executing operational work.
- Define environment classification: local repository, test VPS, production VPS, unknown remote host.
- Require plan-first approval for production-changing commands.
- Provide the production operation plan template.
- Point to the runbook for detailed workflows.

## Retrieval Index Design

The `llms.txt` file should act as a short index rather than a full manual. It should describe the project, list canonical documents, map common agent tasks to files, and include search keywords for installation, upgrades, verification, production operations, rollback, and `sing-box check`.

## Validation

Validation is document-focused:

- Confirm all referenced files exist.
- Confirm the skill has valid YAML frontmatter.
- Run the skill quick validator if available.
- Run a repository status check before committing.

## Non-Goals

- Do not implement automated production deployment scripts in this change.
- Do not add secrets, host-specific credentials, or production-only values.
- Do not change the existing install, uninstall, or verification behavior.
