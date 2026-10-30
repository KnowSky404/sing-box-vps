# Runtime transaction completion contract

[简体中文](runtime-transactions.zh-CN.md) · [SPEC index](README.md)

Status: implemented and accepted for the finite operations below on 2026-10-30.
Local fault injection, platform checks and the real-core Docker lifecycle have
separate evidence. A live Cloudflare WARP account registration, production
upgrade or public-network acceptance is not claimed by this record.

## Scope and completed acceptance

`install.sh` remains the runtime source of truth. This contract completes the
binary-install, managed-upgrade, WARP-registration and latest-version-query
items formerly listed as transaction migrations in the Transactions guide.
It does not introduce a global replacement for every historical `log_error`,
`systemctl`, firewall, QoS or package-manager command.

| ID | Operation | Completed acceptance |
| --- | --- | --- |
| RT-01 | `install_binary()` | Private staging; bounded download and diagnostics; strict archive and exact executable-version validation; binary/library/marker preparation before publication; atomic file replacement; verified postcheck, rollback and signal cleanup. |
| RT-02 | `update_singbox_binary_preserving_config()` and Agent upgrade | Explicit failure propagation, protected backups, unchanged configuration, target-core check before restart, service recovery after failure, and persisted Agent transaction results. Downgrades remain rejected by Agent preflight. |
| RT-03 | `register_warp()` and credential publication | One POST attempt per outstanding receipt, HTTP/JSON validation, explicit uncertain outcomes, durable received-result recovery, private safely serialized credentials, backup/postcheck/rollback, and preserved save/signal exit status. |
| RT-04 | `query_latest_singbox_release()` / `get_latest_version()` | Bounded HTTP read; transport, HTTP and single-document JSON classification; visible supported-version fallback for lookup failures; cancellation returns 129/130/143 without selecting a fallback. |

## RT-01: binary and optional runtime publication

1. Allocate a private random workspace and same-filesystem destination candidates;
   never reuse or recursively clear a fixed shared `/tmp/sing-box-install` path.
2. Download the official release archive with finite connection/total timeouts,
   retries and retry budget. Drain stderr while retaining at most the configured
   diagnostic limit; do not print raw downloaded responses or secret-bearing errors.
3. Inspect the complete archive manifest before extraction. Require the expected
   version/architecture root, one regular `sing-box`, at most one regular
   `libcronet.so`, safe relative paths, and regular-file/directory entry types.
   Reject traversal, symlinks, hardlinks, duplicate core entries and invalid archives.
4. Extract selected members into the private workspace. Validate the candidate's
   executable version with a bounded `version` command before publishing it.
   This accepts artifacts through the existing official-release trust boundary;
   locally computed hashes are not publisher signatures.
   When the existing server configuration uses a namespace declaration or a known
   namespace Dial field, inspect the staged binary's build metadata as well.
   Reject the reproduced Linux ARM64/1.14.2/`with_purego` combination and the
   exact platform/version with unknown build metadata before replacing any
   binary, library or marker. Unrelated header keys named `netns` are not namespace
   use. This protects an operator-installed compatible core during updates or
   repairs; see the [namespace completion record](full-protocol-completion.md).
5. Prepare the optional managed library and its hash marker before committing any
   binary. Preserve an unowned existing library. Snapshot previous files and
   metadata, preserve existing ownership, and set the intended candidate modes.
6. Publish each file by same-filesystem atomic rename. The three files are an
   operation-level rollback group, not one filesystem-wide atomic rename.
   Postcheck the binary version/hash/metadata and library/marker hash/metadata.
7. Failures and INT/TERM/HUP clean candidates. After publication, restore and
   verify the previous files, including an absent previous library/marker.
   Account for a signal between rename and the in-memory commit flag. Preserve
   private recovery material and report manual intervention when rollback fails.
   Cleanup failure after a verified commit reports the committed state and
   recovery path instead of claiming successful cleanup.

The namespace candidate gate was also checked against the actual official
1.14.2 ARM64 binaries: the `with_purego` candidate was refused and the compatible
glibc candidate allowed for a namespace-bearing server configuration. This was
bounded candidate metadata validation with no installation or runtime activation;
`/tmp/sbv-binary-namespace-actual.env` and `.sha256` preserve that evidence.
`binary_namespace_guard.sh` separately covers full-install failure/no-write
behavior for unsafe/unknown candidates, a safe candidate and unrelated headers.

## RT-02: managed core upgrade

The update caller explicitly handles dependency and binary-install failures,
including when invoked inside a conditional. It snapshots the previous binary,
managed library/marker and configuration before mutation. A changed configuration
or invalid target binary/configuration fails before the target service restart.

A failed restart restores the previous binary/library/configuration and the prior
service activity state. Recovery checks include file content and metadata;
failed recovery retains backups. Signals propagate and the caller's previous
signal handlers are restored. Package-manager changes remain within apt/yum's
own boundary; this contract does not claim rollback of installed OS packages.

Agent upgrade retains its existing preflight, private backup manifest and JSON
result contract. Successful results require the target version, unchanged config,
valid target-core configuration and an active service. Failure results distinguish
verified rollback, rollback failure and transaction-result persistence failure.
The Agent `changed` field describes its documented final-state result; it must
not be inferred from another operation's stderr field with the same name.

## RT-03: WARP registration and local credential commit

Before the POST, create a private
`${SB_PROJECT_DIR}.warp-registration.pending.json` receipt in phase `sent`.
Its location outside the project snapshot prevents a config rollback from losing
an outstanding external-write record. Automatic POST retries are disabled.

A DNS/connect failure or explicit HTTP 4xx rejection can clear the receipt. A
possibly sent request, timeout, unexpected response or server failure retains it;
a later invocation must not send another POST while that outcome is unresolved.
This is a client-side replay-prevention contract, not a distributed exactly-once
guarantee from the provider. An uncertain external result requires operator
reconciliation; deleting its receipt blindly is not a recovery procedure.

Validate the HTTP status and required response types, address families and
three-byte client ID. Once a valid response is available, atomically persist
phase `received` with the recovery data. A later invocation validates the saved
keypair and response and retries local saving only, with no second POST.

Serialize credential fields as inert Bash data, stage them privately, validate
syntax, keep a private `.bak`, atomically publish and verify the file hash and
mode. A postcheck failure or post-rename signal restores the previous credentials.
Save failures preserve their real status, including signal codes; received data
remains available for recovery. Logs omit tokens, private keys and response bodies.

## RT-04: latest-version lookup

A query uses private temporary files, finite time/response-size limits and bounded
diagnostics. Accept exactly one JSON object with a stable numeric release tag.
Malformed/multiple documents, missing/wrong-type tags, prerelease tags, transport
failure and non-success HTTP status have explicit failure classification.

Ordinary lookup failures visibly report `unavailable` and select
`SB_SUPPORT_MAX_VERSION`. Successful lookups warn only when the returned version
is higher than that support version. HUP/INT/TERM, including matching curl exit
codes, return 129/130/143 and leave `SB_VERSION=latest`; guarded install/update
callers stop instead of proceeding with a cancellation fallback.

## Verification record

The final real-core Docker lifecycle used runtime SHA-256
`420ea43d54daa0001dac04bacd917fb7beaadd53e8d32572ffbfe27dedeb81d1`,
which matched the worktree byte-for-byte when checked. Later version-metadata or
documentation changes can reuse these results only under AGENTS.md section 4.2.

| Evidence | Observed result | Local evidence / reproducible checks |
| --- | --- | --- |
| Binary fault injection | Transport 6/7/18/28; malformed/traversing/link/duplicate archives; wrong executable version; prepare/commit/postcheck failures; pre/post-commit TERM; rollback of previously absent files; retained material on rollback failure all passed. | `bash tests/binary_install_transactions.sh`; `/tmp/sbv-binary_install_transactions-final.log` |
| Update fault injection | Dependency/install errors, config mutation and TERM restore files without an unintended target restart; previous signal trap restored. | `bash tests/binary_update_transactions.sh`; `/tmp/sbv-binary_update_transactions-final.log` |
| Existing update/Agent regressions | Install metadata/library ownership, config preservation, invalid config, failed/inactive restart, wrong installed version and Agent transaction-record cases passed. | `tests/update_binary_path_initializes_system_info.sh`, `tests/update_keeps_existing_config.sh`, `tests/update_skips_restart_when_config_invalid.sh`, both `tests/update_rolls_back_binary_when_*.sh`, `tests/agent_upgrade_commands.sh` |
| WARP and version mocks | Uncertain POST does not replay; received-result recovery, response validation, inert token serialization, credential rollback/post-rename signal and exact writer status pass. Version transport/HTTP/JSON/fallback/cancellation cases pass. | `bash tests/warp_registration_transactions.sh`; `bash tests/latest_version_lookup.sh`; `tests/secret_diagnostics_redaction.sh`; `tests/register_warp_reregisters_when_client_id_missing.sh` |
| Ubuntu 22.04 / Rocky Linux 8 | All four new transaction tests passed in disposable containers. Rocky exercised Bash 4.4.20 and GNU coreutils 8.30. WARP/version fixes were rerun on both platforms with unchanged runtime hash `adf3ca63eff293eea1abcf576884781a6b0f98f6fe411925a7fa4f61c0d9d11d`; the later standard Bash writer-status fix has focused local coverage. | `/tmp/sbv-platform-ubuntu.log`, `/tmp/sbv-platform-rocky-final.log`, `/tmp/sbv-platform-ubuntu-updated.log`, `/tmp/sbv-platform-rocky-updated.log` |
| Real-core Docker lifecycle | Fresh HTTP 1.14.2; rejected Agent downgrade; actual 1.14.0→1.14.2 upgrade with unchanged config/active service; exact HTTP marker; forced target-version restart failure with verified rollback to 1.14.0 and another marker all passed. Agent transaction results persisted; container removed. | `/tmp/sbv-spec-binary-docker-v2/result.env`: `lifecycle_exit=0`; `agent-results/{downgrade,upgrade,rollback}.summary.json`; `upgraded/` and `rolled-back/` probe bundles; `/tmp/sbv-spec-binary-docker.sh` |

Artifact paths identify private, session-local acceptance evidence, not published
Wiki attachments or permanent external storage. Configuration checks, local mocks,
platform behavior, isolated data-plane markers, real provider effects and production
acceptance are separate claims. This completed contract requires no live WARP
account write or production change.

## Maintenance rule

Keep these assertions when changing affected operations. Select additional tests
from the changed callers and side effects under AGENTS.md section 4.2. New service,
network, configuration or external-write behavior needs its own corresponding
acceptance; do not turn this completed checklist into an unbounded global rewrite
or rerun unrelated protocols merely because `install.sh` changed.
