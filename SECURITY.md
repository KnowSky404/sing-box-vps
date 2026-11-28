# Security review guide

Repository-specific context for local and cloud Codex security reviews. This guide
is not a security certification, deployment approval or cloud-task configuration.
Read this guide before any local or cloud Codex security review. Establish the
base and current head SHA and inspect the complete diff and affected callers.
For PR review and remote automation, follow the local
[review and merge gates](docs/wiki/Development.md#审查与合并).

## Required runtime safeguards

- Keep remote content away from live or future executable paths. Download it in
  full, validate it in a same-directory staging file and replace the target
  atomically on the same filesystem. Make a `.bak` backup before modifying
  critical system files or existing configurations.
- Critical changes must cover prepare, validate, backup, commit, postcheck,
  rollback and cleanup. Report the final state on failure. Low-level download,
  file and validation functions return status. Only entry points or the
  outermost unrecoverable boundary may exit.
- Never hide mutation errors with `2>/dev/null || true`. Read-only best-effort
  checks may degrade and must report `unavailable` or an equivalent diagnostic.
  On interruption clean up temporary files and report whether the target changed.
- Redact tokens, passwords, complete Authorization headers and complete share
  links in routine output, diagnostics, logs and shared evidence, including error
  paths. Preserve explicitly authorized sensitive exports in their designated
  output and handle them as private data.

## Scope and trust model

sing-box-vps is a root-operated Linux installer and manager. Intended operations
include installing executables, managing systemd and configuration, and changing
explicitly requested firewall and routing resources. The runtime artifact is the
standalone `install.sh`, generated from the maintained `src/install/` modules by
`scripts/build-install.sh`. The builder validates and concatenates files without
executing them. Review source changes together with the generated artifact and
check their consistency. `bootstrap.sh` downloads and starts the selected runtime,
and `uninstall.sh` delegates removal to an available local runtime.

Review the complete PR diff and affected callers first. Expand inspection only
as needed to establish reachability, existing defenses or shared impact.

- A root administrator can intentionally install executables and authorize
  destructive operations. Do not assume an attacker can already replace protected
  root-owned scripts or state without identifying how that access is obtained.
- CLI values, typed JSON records, names, paths, API responses and downloaded
  artifacts must not gain unintended shell, filesystem or network authority.
  State sourced as shell requires trusted ownership and safe serialization.
- Downloads rely on the configured source and transport trust. Syntax checks,
  project identity strings and locally computed hashes are not cryptographic
  proof of publisher authenticity.
- The Agent interface is a local CLI. Confirmation flags, revisions and locks
  protect operations and concurrency; they are not remote authentication.

PR contract runs on a disposable GitHub-hosted runner with read-only contents
access. PR code supplies the candidate workflow and tests, so these jobs must
stay free of repository secrets, writable tokens, deployment environments and
shared privileged runners. Require approval for every external fork contributor
before enabling the workflow. Inspect the exact candidate workflow and
permissions before approving an external run or relying on a green check. The manually authorized host workflow and
production controls use their own trust boundaries.

## Review priorities

1. **Input to execution:** quoting, option injection, dynamic dispatch, unsafe
   `source`/`eval`, JSON and shell serialization, and path traversal. Trace ordinary
   input to the actual command or write; administrator input is still data unless
   executing it is an explicit feature.
2. **Downloads and updates:** private staging, complete validation before execution
   or publication, safe archive extraction, same-filesystem atomic replacement,
   backups, signal cleanup, postchecks and truthful rollback outcomes.
3. **Filesystem boundaries:** symlinks, writable parents, temporary-file races,
   credential/config/backup ownership and permissions, and deletion restricted to
   the intended managed resources.
4. **State and concurrency:** management locks, exact revision checks, tombstones,
   fail-closed inventory validation, and preservation of unmanaged configuration
   during takeover, rebuild and recovery. Check stale or partial state paths.
5. **Network authority:** public-exposure consent where required, authentication
   and TLS trust, listener/resource matching, and cleanup that preserves unrelated
   firewall and routing resources. Configuration validity alone does not prove
   safe host policy or successful recovery of external resources.
6. **Secrets:** tokens, passwords, UUID credentials, private keys, complete share
   links and sensitive exports. Check routine summaries, diagnostics, tracing,
   process arguments, temporary files and shared artifacts, including failure and
   interruption paths. Authorized sensitive exports must remain distinguishable
   from credential-free inventory.
7. **SubMan writes:** validate the intended Workspace Gist ID, revision/ETag and
   external-key identity; retain conditional-write protection. After an uncertain
   mutation, read back and reconcile the complete intended state before any retry.
   Changed destinations must not silently receive saved credentials.
8. **Activation and recovery:** check affected configurations before activation,
   preserve recovery material, and distinguish unchanged, committed, partial,
   rolled-back and rollback-failed states. A file rollback does not establish that
   service, firewall or remote state has also been restored.

## Intended behavior and finding quality

Root execution, authorized uninstall, explicit credential exports, public proxy
listeners and administrator-configured destinations are intended capabilities.
Their existence alone is not a finding; a bypass of consent, validation, secrecy
or resource boundaries can be. Do not dismiss a reachable injection solely because
an administrator entered the value, or treat a local hash as a publisher signature.

For each finding provide:

- Reviewed head SHA, affected file and the smallest useful line range.
- Attacker-controlled input, required access and a reachable input-to-impact path.
- Concrete security impact, severity rationale and relevant existing defenses.
- A minimal safe reproducer or precise static evidence, using dummy secrets.
- Focused remediation and the smallest meaningful regression coverage.

Separate confirmed vulnerabilities from unverified hypotheses, general hardening
and pre-existing unrelated issues. Avoid duplicate findings for one root cause.
When there are no findings, state the reviewed scope and material limitations;
do not imply the entire system has been proven safe. Documentation-only PRs still
need inspection for unsafe executable examples, leaked secrets or weakened gates.

## Safe and proportional verification

Start with static inspection. A read-only review does not require implementation,
version changes, commits, the full local suite or a Docker matrix. Follow
[risk and verification rules](docs/wiki/Development.md#风险与验证范围) for any
necessary tests. Use a minimal isolated reproduction only to verify a concrete
risk when static evidence is insufficient. Keep reporting and remediation
separate from read-only review. Do not expand to repository-wide refactoring or
full regression based on speculation.

Configuration changes require `sing-box check` on affected outputs. Service,
network and lifecycle changes need corresponding runtime evidence when delivering
a fix. Local mocks, Docker, public reachability, external providers and production
are separate evidence; report missing coverage explicitly. Stop after the required
scope is covered unless new evidence warrants expansion.

Do not use production credentials, contact configured private services, perform
real SubMan writes or modify production hosts as part of an ordinary PR review.
Read fixtures before executing them; local code review does not authorize arbitrary
host changes or privileged containers. Do not run untrusted downloaded artifacts
to establish whether they are safe.

## Reporting sensitive vulnerabilities

Keep real credentials, deployment details and sensitive exploit material out of
public issues and PR comments. Use a maintainer-approved private reporting channel
for sensitive details; do not assume a security mailbox or private-reporting
feature is configured. Use redacted evidence in shared review records.
