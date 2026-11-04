# Unified runtime storage and legacy migration

[完整中文契约](unified-storage.zh-CN.md)

Status: implemented. This contract describes the implementation; acceptance evidence is recorded below and in the delivery PR. Production migration requires separate authorization.

Project-owned payloads belong to the root account home directory's `.sing-box-vps`, resolved through the account database rather than inherited HOME. Keep `runtime/` as the atomic snapshot/restore boundary; `bin/`, `lib/`, `modules/`, logs, temporary files, backups and migration records live beside it. Existing `runtime.*` transaction names stay within the private root. SELinux systems require project-scoped persistent file-context metadata and verified labels before executable activation; this system-managed metadata is an integration entry, not another payload copy. Keep SELinux enabled, preserve conflicting administrator rules, and fail explicitly if dependencies or labeling are unavailable. System PATH and systemd locations contain managed integration entries. Packages, journal and kernel/network settings remain system managed; explicit external input paths stay external.

Provide structured `storage status`, `storage migrate --yes` and `storage recover --yes` operations with one JSON envelope, strict arguments, ownership checks and exclusive legacy/new locks. Discovery stays read only. An old installation (including a retained manager after core uninstall) or pending migration blocks ordinary operations, including Agent commands. Historical paths remain literal /root locations even on custom-home hosts; relative script invocation is supported. Known sidecars are enumerated precisely and similarly named user files stay untouched. Unsupported custom unit paths/drop-ins and special source-tree entries require operator reconciliation. The interactive entry uses the same handlers.

Migration requires source/new-root/system-entry parents on the same filesystem for atomic rollback, and rejects unresolved implicit writable state (Tor/Tailscale/Taildrop, ACME/OriginCA storage and API dashboards) or relative material paths. Migration validates sources and collisions, rejects pending legacy transactions, journals the old service/entrypoints, and pauses an active service before copying mutable state. Downtime includes copying and validation. Prepare private staging, selectively rewrite owned path fields and check candidate scripts/state/configuration with the target core. Preserve identity, revision, secrets, unknown files and external references. Normalize repeated separators only for owned material references; arbitrary transport headers and official free-form data maps remain opaque to both validation and rewriting. Journal publication and restore the original layout/activity state on failure; retain recovery records when rollback cannot be proved. Success archives the old layout under the private backup root. Legacy upgrade backups retain original bytes/checksums as offline recovery material, rather than transparently accepted new-layout restore inputs.

Updates atomically replace internal regular files; publish and remove only owned global entries. Runtime uninstall preserves the manager and recovery backups. Full uninstall reports retained backups and never removes unrelated entries or external inputs. Bootstrap and internal temporary artifacts stay beneath the private root.

The configuration/state migration requires the registered full suite under AGENTS.md, plus dedicated migration Docker coverage: fresh install, old updater handoff, active/inactive service, retries, conflicts, symlinks, ownership, pending transactions, old/new lock contention and inherited descriptors, path-only rewriting, unchanged secrets/legacy checksums, temporary containment, snapshot isolation, updates, interruption/recovery and uninstall. Core checks, Docker, external providers, public reachability, production and review/merge evidence remain separate.

Recorded acceptance on 2026-11-03 includes 27 isolated migration cases; real old-updater handoff, active/stopped migration, HY2 local file URI and systemd 203/EXEC rollback; manager-only/relative-entry migration, DNS hosts and object/URI masquerade preservation, complete material-path auditing and custom-unit rejection; isolated Agent/routing/component runtime fixtures; controlled VPN storage/restart identity; HTTP/HY2 IPv4+IPv6; and actual REALITY checker/handshake/cancellation. Build, operation catalog, Bootstrap and version checks pass. The complete registered host/Docker inventory, corrected-test results, content hashes and current-head reviews are recorded in the delivery PR. See the Chinese contract's acceptance table for boundaries. No provider writes, public reachability, external SubMan synchronization or production migration are claimed. Private bundles can contain fixture secrets and are not public Wiki attachments.

SELinux acceptance uses a separate AlmaLinux 9.5 kernel in Enforcing mode: reproduce the unlabeled 203/EXEC failure, then verify service activation, atomic publication/rollback, label repair and active legacy migration followed by restart after archival. Final entrypoint and administrator-rule protection evidence remains separately recorded in the delivery PR. Mock policy checks and a disabled Docker host do not establish Enforcing acceptance.

## Ownership diagnostics correction (2026-11-04)

Legacy system entries must remain root-owned regular files with trusted parents.
Status and migration share the same check; status adds `blocker_details` records
with `code`, `entry`, `path` and `reason`, and corresponding unique codes in
`blockers`. Status success still means the read succeeded, not migration readiness.
Migration retains `migration_failed` and reports the precise rejected path on stderr.
Checks are read-only and never repair ownership or accept source symlinks.
Validated new core/library/marker candidates are published as root:root; rollback
preserves the original bytes and metadata. Unmanaged external libraries remain
outside this repair. Production recovery first requires a trusted-release byte
comparison, a private backup, explicit approval and separate service verification.
