---
name: sing-box-vps-operator
description: Use when installing or upgrading sing-box-vps, running local or remote verification, operating sing-box-test or sing-box-prod, troubleshooting sbv or sing-box service issues, retrieving node info for AI agents, managing VLESS REALITY instances or Warp/SubMan/client exports, modifying repository scripts or docs, validating sing-box configs, or creating rollback/recovery steps for this project.
---

# sing-box-vps Operator

Use this skill for repository maintenance and VPS operations for `sing-box-vps`.

## Required Reading

Before operational work, read:

1. `AGENTS.md`
2. `README.md`
3. `docs/agents/sing-box-vps-agent-runbook.md`

For `sing-box` configuration syntax, version compatibility, migration notes, or official examples, use Context7 first.

## Classify The Target

- **Local repository**: files in the workspace.
- **Test VPS**: `sing-box-test`.
- **Production VPS**: `sing-box-prod`.
- **Unknown remote host**: treat as production until clarified.

## Production Gate

Before any production-changing command on `sing-box-prod` or an unknown host, present a plan and wait for explicit approval.

Production-changing commands include install, upgrade, restart, stop, reload, uninstall, purge, config mutation, firewall mutation, service mutation, writing `/usr/local/bin/sbv`, or changing `/root/sing-box-vps/`.

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

- Run `sing-box check` after any generated or modified sing-box server or client configuration.
- Run `bash dev/verification/run.sh` when changes touch `install.sh`, `uninstall.sh`, `configs/`, `utils/`, or `dev/verification/`.
- Remote verification runs in Docker locally, auto-building sing-box-vps-verify image. No external SSH target required.
- Use `sing-box-test` for test validation and `sing-box-prod` only after the production gate.

## Agent-Friendly CLI

Prefer non-interactive JSON commands for AI automation:

```bash
sbv agent capabilities --json
sbv agent upgrade-check --json 1.14.0
sbv agent upgrade --json 1.14.0 --yes
sbv agent status --json
sbv agent nodes --json
sbv agent links --json
sbv agent export-client --json
sbv agent check --json
sbv agent doctor --json
sbv agent service restart --json --yes
sbv agent warp --json
sbv agent subman-sync --json
sbv update sbv
sbv update sing-box latest
```

Use the advanced component API for non-shareable inbounds, endpoints and
reusable outbounds/groups:

```bash
sbv agent component list --json
sbv agent component create|replace --json --yes --expected-revision N --file component.json [--allow-public]
sbv agent component delete --json --yes --expected-revision N --id COMPONENT_ID
```

Component state is stored in `/root/sing-box-vps/components.json` with an
independent schema-1 revision. `list` returns only metadata and config keys;
it never returns tokens, passwords or private keys. Mutations rebuild the
combined config, enforce component references and listener conflicts, run the
target core check, and restart an active service after publication. The
registry covers direct/tun/redirect/tproxy/cloudflared inbounds,
WireGuard/Tailscale/OpenConnect/OpenVPN endpoints, and SSH/Tor/direct/bridge/
selector/urltest/block plus protocol outbounds. SSH records use the sing-box
1.14 SSH/Dial Field allowlist and require password, private key or private-key
path authentication; metadata reports only config keys and
`host_key_verification=pinned|unverified`. Tor records use the sing-box 1.14
`executable_path`, `extra_args`, `data_directory`, string-valued `torrc` and
Dial Field allowlist; inventory reports `runtime_mode=external` or
`embedded_unverified` and never treats the default build as embedded-Tor
runtime proof. Selector and URLTest groups require unique non-empty outbound
members, enforce selector defaults and URLTest field types, and expose only a
redacted `member_count`. SOCKS outbound components enforce the sing-box 1.14
server/version/auth, TCP/UDP network, UDP-over-TCP and shared Dial Field
allowlist; invalid versions, networks, ports, deprecated fields and control
characters fail before CAS/takeover, and credentials remain export-only.
HTTP outbound components enforce the sing-box 1.14 TCP-only server/auth/path,
headers, recursive outbound TLS and shared Dial Field allowlist; invalid nested
fields and header/scalar values fail before CAS/takeover, and credentials remain
export-only.
Shadowsocks outbound components enforce sing-box 1.14 method/password (including
strict Base64 SS2022 key sizes), network, SIP003 plugin, UDP-over-TCP, multiplex
and shared Dial Fields; invalid methods/keys/plugins/nested values fail before
CAS/takeover, and credentials remain export-only. Non-loopback listeners, TUN,
tunnels and OpenVPN server require `--allow-public`. External account
authentication, system routes/firewall, runtime libraries and data-plane
reachability remain separate operator-reviewed gates. The registry keeps
static `available:null` separate from its per-read `environment` observation;
inspect `environment.status`, dependency reasons and `validated` before
claiming a component is usable.

VMess and Trojan outbound components enforce the sing-box 1.14 authentication,
TCP/UDP, TLS, guarded V2Ray transport, multiplex and shared Dial Field shapes;
HTTPUpgrade, WebSocket early data, plaintext QUIC and lite-gRPC
`permit_without_stream` fail closed before CAS/takeover, while credentials stay
in sensitive export only. A target-core `check` is configuration evidence, not
proof of remote protocol handshake or data-plane reachability.

VLESS outbound components use the same typed TLS, V2Ray transport, multiplex
and Dial Field path. The empty flow supports native transports, while
`xtls-rprx-vision` requires enabled TLS with no transport; omitted
`packet_encoding` retains the upstream xudp default. Unsafe transport and
flow combinations fail closed before CAS/takeover and credentials remain in
sensitive export only.

WireGuard endpoint components use the modern endpoint role, never the removed
`wireguard` outbound. Preserve standard 32-byte Base64 private/public/PSK keys,
CIDR address and allowed IPs, peer keepalive/reserved tuples, MTU/listen/
workers, UDP NAT behavior and shared Dial Fields; reject malformed keys,
prefixes, peer tuples, deprecated fields and unknown fields before state/CAS.
Fixed 1.14 full-field and 1.13.18 base-subset `check` results are configuration
evidence only, not system-interface permission, peer-handshake or UDP
data-plane proof.

Tailscale endpoint components validate persistent state/auth/control fields,
route advertisement and exit-node conflicts, relay AddrPort values, optional
SSH settings and shared Dial Fields. OpenConnect is client-only and validates
flavor, token secret/path, mobile identity, CSD/HIP/TNCC, TLS material,
form-entry pairing and compression/keepalive constraints. OpenVPN client and
server components validate TLS/static-key unions, remotes and address-family
rules, certificate/key material, control wrapping, users and pushed DNS/routes.
Inline PEM/key material may contain LF/CR; paths and ordinary fields remain
control-character safe. These state/render contracts and fixed-core checks do
not prove external VPN/Tailscale authentication, certificate loading,
system-interface privileges or TCP/UDP data-plane reachability.

AnyTLS outbound components require `server`, `server_port`, a non-empty
`password`, and enabled outbound TLS. Idle-session fields and `client_metadata`
are optional typed values; AnyTLS has no configurable network, transport, or
multiplex field, and `tcp_fast_open=true` is rejected to match the target
adapter. Keep credentials in sensitive component export only; a target-core
`check` does not prove an AnyTLS handshake or TCP/UDP data plane.

Snell outbound components accept only sing-box 1.14 version 4 or 6. Version 4
uses typed HTTP obfuscation fields; version 6 uses typed traffic shaping and a
PSK of at least 12 bytes. Keep userkey/reuse, TCP/UDP network, and shared Dial
Fields typed, reject fields from the other version, and do not expose Snell v5
QUIC proxy as a separate outbound. 1.13.18 lacks the Snell outbound type, and a
1.14 target-core `check` is not remote Snell handshake or data-plane proof.

Hysteria2 outbound components accept sing-box 1.14 server/server-port ranges,
port hopping, bandwidth, salamander/gecko obfs, TCP/UDP network, required TLS,
QUIC fields, BBR profile, Chrome QUIC control, shared Dial Fields and optional
Hysteria Realm. Keep Realm server/STUN/port-mapping/HTTP-client shapes typed,
reject Hysteria v1/deprecated receive-window fields, and treat target-core
`check` as configuration evidence only, not remote QUIC or UDP data-plane proof.

Hysteria v1 outbound components preserve sing-box 1.14 `auth`/`auth_str`,
string or Mbps bandwidth, hop interval, string obfs, TCP/UDP network, required
TLS, QUIC fields and shared Dial Fields. Keep Hysteria v1 separate from the
Hysteria2 password/obfs/BBR/Realm schema, reject deprecated receive-window
aliases, and treat target-core `check` as configuration evidence only, not a
remote Hysteria handshake or UDP data-plane proof.

TUIC outbound components preserve sing-box 1.14 UUID/password, congestion
control, native/quic relay, optional UDP-over-stream, zero-RTT, heartbeat,
TCP/UDP network, required TLS, QUIC fields and shared Dial Fields. Reject
`udp_relay_mode` plus `udp_over_stream` conflicts before state/CAS, keep the
outbound-only relay fields out of TUIC inbound records, and treat target-core
`check` as configuration evidence only, not a remote TUIC handshake or UDP
data-plane proof.

NaiveProxy outbound components preserve sing-box 1.14 server/port,
username/password, extra headers, HTTP/2 or QUIC, UDP-over-TCP, receive
windows, the documented restricted TLS fields and shared Dial Fields. Reject
non-zero `insecure_concurrency` with QUIC and unsupported TLS/UoT/header/window
fields before state/CAS; the `with_naive_outbound` build and `libcronet.so`
runtime remain separate availability requirements.

ShadowTLS outbound components are TCP-only wrappers with typed server/port,
version 1–3, optional password, required outbound TLS and shared Dial Fields.
Keep this outbound separate from the local ShadowTLS outer-plus-loopback-Mixed
inbound composite, and do not treat target-core `check` as remote handshake or
TCP data-plane proof.

- Use `status --json` for version/service/path/protocol diagnostics plus network stack, BBR, REALITY/QoS, and integration presence.
- Use `capabilities --json` to discover supported protocols/features and operation safety labels before choosing an action.
- On an existing 1.13 host, run `sbv update sbv` first and start a new invocation before expecting the new Agent commands.
- Use `upgrade-check --json 1.14.0` as a read-only eligibility preflight. Require `ready=true` and `blockers=[]`. It validates the current core and known schema risks without reconciling or migrating protocol state, but does not download the target; `target_binary_validation.performed=false` is expected.
- Use `upgrade --json 1.14.0 --yes` only after approval. It is mutating, creates an automatic root-only backup under `/root/sing-box-vps-backups/`, preserves the server config byte-for-byte, validates the target core before restart, and automatically restores the old binary and previous service activity on failure. Its `SHA256SUMS` covers every regular runtime file plus the binary, `sbv`, service unit, and metadata. It does not silently migrate or rewrite config. Treat the backup contents as sensitive.
- Use `nodes --json` for log-safe summaries of every protocol and every REALITY instance, including rate limits and outbound policy. It intentionally omits UUIDs, keys, full links, and passwords; ShadowTLS summaries also redact all v2/v3 credentials.
- Use `links --json` only in trusted contexts; it returns full connection material for every protocol and REALITY instance, including NaiveProxy and ShadowTLS outbound JSON and explicit URI/libcronet warnings.
- Use `export-client --json` to generate and validate the sing-box bare-core client config. It writes the client export file but does not mutate the running server config or restart service.
- Use `check --json` and `doctor --json` for non-mutating service/config diagnostics.
- Use `service restart --json --yes` only after confirming the target is safe to mutate. It validates config before restart.
- Use `warp --json` to inspect Cloudflare Warp status: enabled state, route mode, account health, custom domain counts, rule-set counts, and builtin AI/streaming rule tallies. Safe for routine diagnostics.
- Use `subman-sync --json` only in trusted contexts with configured SubMan credentials; it pushes only eligible URI-backed node material. NaiveProxy, Hysteria v1, Snell, TUIC, AnyTLS, and ShadowTLS are explicitly unsupported and skipped.
- Safety labels: `status`, `capabilities`, `upgrade-check`, `check`, `doctor`, `nodes`, and `warp` are read-only; `upgrade`, service restart, export, and SubMan sync are mutating; `links`, export, and SubMan sync are sensitive; installation, protocol edits, Warp/BBR/media changes, takeover/repair, and uninstall remain interactive-only.
- Use `update sbv` to refresh `/usr/local/bin/sbv`; alias: `sbv update-sbv`.
- Use `update sing-box [latest|x.y.z]` to update a healthy managed sing-box instance non-interactively. It preserves config, runs `sing-box check`, and restarts only after validation passes. Alias: `sbv update-sing-box [latest|x.y.z]`.
- If `update sing-box` reports an incomplete or missing instance, switch to the interactive `sbv` menu for repair, takeover, or fresh install.

For a 1.13 to 1.14 rehearsal, follow `docs/agents/sing-box-1.13-to-1.14-upgrade-test.md`. Inline `tls.acme` and legacy `download_detour` are deprecated in 1.14 but remain accepted for compatibility; they are scheduled for removal in 1.16. Hysteria2 Ed25519 handling is a client-side compatibility boundary: share links cannot carry the required Chrome QUIC override, while generated 1.14 client exports can.

NaiveProxy is registry preset 14 and management menu 29. Use the typed manual-TLS TCP/UDP instance lifecycle and `export-client` for per-user outbound JSON. The outbound requires an official `with_naive_outbound` build and runtime `libcronet.so`; links return `naive_standard_uri_unavailable` and `naive_libcronet_required`, and no SubMan sync is attempted.

ShadowTLS is registry preset 15 and management menu 30. Use the typed composite lifecycle: each instance owns a ShadowTLS outer listener and a private loopback Mixed detour, with v1/v2/v3 authentication, handshake mappings, explicit client trust, and per-user outbound JSON. Links return `shadowtls_standard_uri_unavailable`; ShadowTLS has no SubMan path. Non-loopback writes require explicit `--allow-public` consent.

## VLESS REALITY Operations

- REALITY may have multiple managed instances under `/root/sing-box-vps/protocols/vless-reality.d/`.
- Each instance can have its own port, ShortID, node name, and optional upload/download Mbps limits.
- Node names may include rate-limit suffixes; keep them intact when diagnosing or syncing nodes.
- When rate limits are configured, runtime QoS state is tracked in `/root/sing-box-vps/reality-qos.filters`.
- Removing or adding REALITY instances is a runtime config mutation. On production, use the production gate first.
- With multiple REALITY instances, the removal menu has separate single-instance and whole-VLESS scopes. Select the intended scope explicitly and verify that removed ports and QoS filters are gone.
- After any REALITY instance or rate-limit change, require config validation and service/QoS refresh through the script rather than hand-editing files.

## Repository Rules

- Keep `install.sh` as the runtime source of truth.
- Do not reveal secrets, private keys, passwords, tokens, full node links, or QR payloads unless explicitly requested and safe.
- Treat `sbv agent links --json`, `sbv agent export-client --json`, and `sbv agent subman-sync --json` outputs as sensitive.
- Back up runtime config before modifying remote state.
- For runtime behavior changes, update `SCRIPT_VERSION` in `install.sh` and the README script version together.
- Documentation-only changes do not require script version changes.

## Detailed Workflows

Use `docs/agents/sing-box-vps-agent-runbook.md` for install, upgrade, troubleshooting, rollback, test verification, and production operation details.
