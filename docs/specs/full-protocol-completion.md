# Protocol and component completion contract

[简体中文](full-protocol-completion.zh-CN.md) · [Specification status](README.md)

Status: implemented and accepted for **FP-01–FP-11** within the recorded build,
protocol and counterpart scopes. Optional modes, other vendor control planes,
public connectivity beyond the explicit Cloudflare marker and production proxy
hosts remain separate boundaries. The inventory baseline is `f498234` from
2026-10-30; new evidence does not retrospectively rerun historical suites.

## Scope and existing implementation

The baseline contains **15 proxy presets and 38 component records**. All are
implemented in the runtime registry; the component lifecycle exposes create,
replace, delete, rebuild, takeover, recover and sensitive export. This describes
the existing adapters, not successful authentication or a working data path for
every instance. `validated.status=not_assessed` in `capabilities` is intentionally
a per-instance evidence placeholder; it is not a list of missing implementations.

The inventory is exhaustive for the current registries:

| Surface | Records | Existing evidence boundary |
| --- | --- | --- |
| Proxy presets (15) | `vless-reality`, `vless-plain`, `mixed`, `hy2`, `anytls`, `socks`, `http`, `shadowsocks`, `trojan`, `vmess`, `snell`, `tuic`, `hysteria`, `naive`, `shadowtls` | Local lifecycle/configuration and bounded isolated data-plane evidence is recorded in the upstream matrix. Sharing, TLS and SubMan remain limited to each protocol's declared representation. |
| Advanced inbounds with runtime evidence (4) | `direct-inbound`, `tun-inbound`, `redirect-inbound`, `tproxy-inbound` | Existing isolated marker/resource/cleanup slices; optional Redirect/TProxy host policies have explicit IPv4 scope. |
| Endpoints with runtime evidence (3) | `wireguard-endpoint`, `openvpn-client-endpoint`, `openvpn-server-endpoint` | Internal/system-interface slices, peer/tunnel evidence and disposable marker traffic; no external account or production claim. |
| Outbound components (20) | `ssh`, `tor`, `direct`, `bridge`, `selector`, `urltest`, `block`, `socks`, `http`, `shadowsocks`, `vmess`, `trojan`, `naive`, `hysteria2`, `hysteria`, `tuic`, `vless`, `anytls`, `snell`, `shadowtls` (registry IDs end in `-outbound`) | Existing protocol-specific isolated proofs; the additional group/rejection checks below retain their narrower unverified branches. |
| Rule sets (3) | `route-rule-set-inline`, `route-rule-set-local`, `route-rule-set-remote` | Managed CRUD, core check and local HTTP fetch evidence; referenced source files remain operator-owned. |
| Additional component acceptance (8) | `cloudflared-inbound`, `tailscale-endpoint`, `openconnect-endpoint`, `certificate-provider-acme`, `http-client-shared`, `resolved-service`, `network-namespace-default`, `network-namespace-unshare` | Typed state, configuration and lifecycle exist; accepted runtime scopes and remaining counterpart conditions are recorded below. |

Use the [upstream matrix](../wiki/Protocol-Coverage.md),
[component contract](../wiki/Advanced-Components.md) and
[data-plane records](../wiki/Data-Plane-Verification.md) for original evidence.
Dated statements that a component was previously absent or configuration-only
must be read with later slices. In particular, WireGuard/OpenVPN system traffic,
TUN/bridge traffic, managed Redirect/TProxy host policy and rule-set CRUD were
implemented after earlier incomplete records; they are not new missing adapters.

## Finite acceptance matrix

The current status below preserves the original requirements. Local fixtures use disposable credentials, certificate authorities, routes and namespaces. No row is marked passed on the basis of a mock response or a `sing-box check` alone.

| ID | Surface and required acceptance | Execution boundary | Current status |
| --- | --- | --- | --- |
| FP-01 | Managed ACME certificate provider: issue a certificate from a private test CA through a real managed provider reference, use it in a TLS connection, verify lifecycle/CAS and cleanup while preserving operator-owned files. | Isolated Docker; reuse the existing Pebble approach in `tests/hy2_instance_acme_runtime.sh`. That HY2 fixture is not itself proof for standalone component-provider CRUD. | Accepted: private-CA component issuance/TLS/reference guard/cache-preserving cleanup |
| FP-02 | Shared HTTP client: bind a managed named client to a real consumer, fetch an exact local response and observe its configured routing; verify reference protection and CAS cleanup. | Isolated local HTTP endpoint and managed consumer; test the declared HTTP version without silently falling back. | Accepted: real named-client consumer, header/version/detour observation and guarded cleanup |
| FP-03 | Resolved service: register on a disposable system bus, answer exact TCP and UDP DNS questions through the managed listener, and verify service/listener cleanup and preservation of the host's resolver configuration. | Disposable Linux Docker with its own DBus and a private policy permitting the test user to own `org.freedesktop.resolve1`; socket presence is insufficient. | Accepted: private bus ownership, exact TCP/UDP DNS and listener/name cleanup |
| FP-04 | Default network namespace: bind a managed record to a disposable existing namespace, route marker traffic through it, reject a missing namespace and prove the component does not delete the external namespace. | Privileged isolated Docker; namespace and routes owned by the fixture. | Accepted: safe same-version glibc build, real Agent lifecycle and isolated TCP/closed-port proof; unsafe/unknown builds refused |
| FP-05 | Unshare network namespace: create the managed core namespace, observe traffic isolation and a controlled marker path, then verify lifecycle cleanup. | Privileged isolated Docker; no host route or DNS capture. | Accepted: safe same-version glibc build, holder lifecycle and isolated TCP/closed-port proof; unsafe/unknown builds refused |
| FP-06 | Cloudflared inbound: accept a valid disposable tunnel identity, observe a real control connection and marker traffic, then disconnect/clean up without exposing the token. | Requires an identified authorized Cloudflare test tunnel and network path; missing-token rejection is only a negative check. | Accepted: authorized real tunnel, HTTP/2 control, public HTTPS-to-HTTP/1.1 marker and resource cleanup |
| FP-07 | Tailscale endpoint: authenticate against an identified disposable control plane, exchange marker traffic with a peer, and verify persistent-state and interface cleanup. Relay, advertised routes, exit-node and SSH branches require their own evidence before claiming those branches. | Requires a controlled compatible test control plane/peer or authorized test account. | Accepted: controlled Headscale authentication, internal/system IPv4 TCP+UDP, persisted identity and cleanup |
| FP-08 | OpenConnect endpoint: authenticate against an identified test VPN server and exchange marker traffic; verify the selected system/internal path and cleanup. A tested server flavor does not validate every supported vendor flavor or interactive form. | Requires a controlled compatible server/profile; production credentials are not test fixtures. | Accepted: private-CA AnyConnect/ocserv internal/system IPv4 TCP+UDP and independently rechecked interface/CAS cleanup |
| FP-09 | Selector: use two distinguishable working members, verify the configured default and an explicit selection change with exact responses. | Isolated local upstreams; keep existing single-member evidence. | Accepted: two-member default and explicit selection change |
| FP-10 | URLTest: use distinguishable healthy/unhealthy members and a local health URL, observe a failed member and recovery, and verify the selected marker path after a bounded wait. | Isolated local upstreams with controlled failure; keep existing single-member evidence. | Accepted: observed healthy → failed → recovered member routing |
| FP-11 | Block outbound: send UDP traffic through the managed block route, verify no marker reaches the destination and a direct positive control succeeds; retain target-core and deletion evidence. | Isolated local UDP marker; a timeout without the positive control is insufficient. | Accepted: UDP rejection with successful direct positive control |

## Compatibility and external boundaries that remain explicit

- HTTPUpgrade and WebSocket early data remain blocked by the current transport
  guard. Existing rejection tests must keep the original profile and error code;
  removing the guard requires target-core positive/negative runtime evidence.
- Removed ShadowsocksR, DNS outbound and legacy WireGuard outbound are not
  pending implementations. WireGuard uses the modern endpoint role.
- HTTP/SOCKS plaintext limitations, unrepresentable standard URIs, certificate
  trust skips and absent SubMan adapters remain protocol contracts; no invented
  URI or lossy payload can satisfy completion.
- Platform/build conditions, `with_naive_outbound` plus `libcronet`, embedded Tor,
  kernel privileges and additional modes such as HY2 Realm keep their stated
  boundaries. Existing marker results do not validate every option combination,
  native UDP mode or vendor control plane.
- Real SubMan identity/aggregate preservation belongs to the naming acceptance
  record. Public connectivity, real provider accounts, production acceptance,
  PR review/merge and Wiki publication each require their own evidence. They
  cannot be completed by relabeling isolated results.

## Evidence and execution order

Prioritize FP-01 through FP-05, then FP-09 through FP-11; these can use isolated
fixtures without real account writes. Prepare controlled counterparts and record
the selected scope before FP-06 through FP-08. A local counterpart may prove its
tested protocol path, while real vendor/account and production acceptance remain
separate. Missing prerequisites or an unsuccessful experiment remain incomplete.

For each completed row, record the tested code/core version or hash, exact
command, configuration-check result, observed marker or expected rejection,
relevant CAS/rollback checks, artifact location and cleanup result. Sanitize
credentials and keep sensitive configuration private. Reuse unchanged prior
results under AGENTS.md section 4.2; this contract does not require rerunning every
existing protocol or platform. Add only the tests and scenarios needed by each
actual change, and never substitute an empty, skipped or cancelled run for proof.

## 2026-10-30 execution record

The private local evidence bundle is `/tmp/sbv-protocol-spec-evidence-20261030`
(mode 700). It contains the component/client, resolved, namespace, group and ACME
results and logs. Credentials and full fixture configurations are not PR output.

- FP-01 reuses the existing HY2 Pebble fixture: two HTTP-01 issuances, verified
  transfers, cache reuse and coexistence passed. The standalone extension then
  created its own managed provider, obtained a fresh private-CA certificate,
  verified an HTTPS proxy transfer, rejected deletion while an operator-owned
  consumer referenced it with `config_check_failed`/unknown-reference evidence,
  preserved revision/config on rejection, and deleted the provider after removing
  the consumer while retaining its cache. A fixture-only retry used a fresh
  domain/cache after the private CA was restarted; earlier failed issuer-trust
  attempts are retained and are not counted as success.
- FP-02 observed `HTTP/1.1`, the configured `X-Component-Marker` header and the
  configured first-hop source `127.0.0.2` at the actual rule-set HTTP server.
  Deleting the referenced client returned `component_referenced`; revision and
  configuration were preserved, then all three records were deleted normally.
- FP-03 registered `org.freedesktop.resolve1` on the private system bus and returned
  the exact `203.0.113.7` answer over TCP and UDP. The fixture grants only the
  disposable root user's ownership permission; socket presence by itself is not
  sufficient. Deletion removed the listener/name without replacing host DNS.
- FP-04/FP-05 combine actual managed Agent create/delete and missing-path rejection
  with the separate `namespace_core_runtime.sh` positive and closed-port checks.
  The official **1.14.2 Linux ARM64 glibc** archive SHA-256 is
  `87db5c3a96ebad1c44c0be1fe7955db2f76b8c97bbc0ed62173063d675e078cf`;
  its binary SHA-256 is
  `2d3a13a6c4661d8a89af73a79e6c78289f41ebca83ed7a20a15d7f4c2b576366`.
  Both namespace modes returned their exact marker, kept the core alive after a
  closed-port refusal, and cleaned up their resources. Agent lifecycle used
  runtime SHA-256 `5ae09c09e99c0c4603164e09c361a4231472a86ccdf21adb236994a34c7a3982`.
- The official same-version ARM64 `with_purego` binary instead exited **139**:
  default namespace dial reproduced it with a ready marker, and unshare
  reproduced it at startup. GDB captured SIGSEGV in libc `start_thread`; the
  pinned upstream namespace code uses a locked OS thread. This establishes the
  tested build failure, not a fully diagnosed native-code root cause. The normal
  installer version and asset URL were not changed. Component writes now refuse
  this exact Linux/ARM64/1.14.2/tag combination with
  `namespace_runtime_unsafe_build`, including raw `netns`, `control_dialer.netns`
  and `tunnel_dialer.netns` references. On that exact platform/version, missing
  build metadata stays `not_assessed` in inventory and refuses writes with
  `namespace_runtime_build_not_assessed`; it is not labeled a confirmed crash.
  Missing/default-path access errors fail before publication separately.
  The staged-candidate binary gate also inspects existing namespace declarations
  and known Dial fields, rejecting the same unsafe/unassessed combination before
  binary/library/marker replacement during installation, update or repair;
  unrelated header keys do not trigger it. This is covered by
  `binary_namespace_guard.sh` and the [RT-01 contract](runtime-transactions.md).
  The actual official purego/glibc binaries separately returned refused/allowed
  at the candidate metadata gate, without installation or activation; results
  and hashes are `/tmp/sbv-binary-namespace-actual.env` and `.sha256`.
- FP-06 used the owner-authorized temporary Cloudflare tunnel with HTTP/2 control
  transport and an HTTP/1.1 loopback origin. Managed create/delete, target-core
  checks and an exact public HTTPS marker passed; unrelated private destinations
  remained blocked. Runtime SHA-256 was
  `37f96a49d06c6ac3fe9f858d31717d3797fedda640a9e71c3d71be18385ff519`.
  The exact temporary tunnel and DNS record were removed and API readback found
  zero matching resources. This does not prove arbitrary TCP/UDP tunnel modes.
- FP-07 used a private compatible Headscale **0.29.6** control plane with trusted
  TLS, embedded DERP and STUN, plus a disposable peer. Actual authentication,
  internal and named-system-interface IPv4 TCP/UDP markers, persistent node-ID
  reuse across restart, revision/CAS deletion and system TUN removal passed.
  No manual route workaround was required. Evidence is
  `/tmp/sbv-vpn-runtime-20261030-final4/fp07-accepted/`; runtime SHA-256 was
  `5ae09c09e99c0c4603164e09c361a4231472a86ccdf21adb236994a34c7a3982` and
  core SHA-256 was
  `b8610f45abb7e967e195264383f5cbd20fba7821a3c37e3a8c4c5ab6cad28eac`.
  This is controlled-peer evidence, not Tailscale vendor-cloud, SSH, exit-node,
  advertised-route or peer-relay acceptance.
- FP-08 used pinned **ocserv 1.1.6-3**, the AnyConnect flavor and strict
  throwaway-CA verification. Actual DTLS and internal/system IPv4 TCP/UDP marker
  paths passed with VPN source `10.91.0.82`; no crypto override was used. Traffic
  evidence is `/tmp/sbv-vpn-runtime-20261030-final4/` under the same FP-07 frozen
  runtime/core hashes. A corrected explicit absence assertion was independently
  rechecked in a fresh system-mode create/IPv4-assignment/CAS-delete run:
  `/tmp/sbv-vpn-runtime-20261030-lifecycle/container/actual-interface-cleanup.env`
  records `openconnect_system_interface_absent=1` and
  `managed_components_empty=1`. That run used runtime SHA-256
  `f9d015ab9fbe0e68a65b43d763347139f6a1b493660f9261ca66ec407ee8c5b3`;
  the intervening binary gate did not change the already tested VPN data path.
  The fresh fixture containers and prior diagnostic/prototype containers were
  confirmed removed. This does not validate every vendor flavor or interactive
  authentication flow.
- FP-09/FP-10/FP-11 used the production component serializers and a real 1.14.2
  core: distinguishable selector members, observed URLTest failure/recovery, and
  UDP block with an exact direct control all passed. Existing Agent lifecycle
  evidence remains separate from this deeper data-plane check.

The namespace safe-build result is **Debian 12 / glibc 2.36 / ARM64** only. An
operator may supply a verified compatible native/same-version build; the project
never silently replaces the global core with a glibc variant. Official glibc
assets have their own runtime requirements; **Rocky 8's glibc 2.28 is not covered**
and must not be assumed compatible. Other platforms, versions and parseable safe
builds keep their existing handling; this is not a universal safety guarantee.

Use `SBV_COMPONENT_RUNTIME=1` only in a new disposable Docker container containing
`/tmp/sbv-component-disposable`. `component_runtime_acceptance.sh` additionally
refuses an existing installation. Its `COMPONENT_RUNTIME_CASES` selects
`shared`, `resolved`, `default`, `unshare` or the expected-rejection `bad-build`
case; `NAMESPACE_LIFECYCLE_ONLY=1` splits managed namespace CRUD from the separate
core data-plane fixture. The ACME wrapper reuses `hy2_instance_acme_runtime.sh`
and requires a privately supplied Pebble binary; its provider has a fresh
per-run domain/cache. `selector_urltest_runtime.sh` and
`namespace_core_runtime.sh` require fresh artifact paths. These fixtures never
alter host DBus, resolver configuration, firewall or namespaces.
