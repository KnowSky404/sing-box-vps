# 高级组件

## Managed advanced components

The component registry also manages top-level ACME `certificate_provider`,
shared `http_client`, `default`/`unshare` `network_namespace` and
`route.rule_set` records through the same schema-1 CAS/render/takeover/rebuild path. ACME records are bounded to
the fields validated by this repository; a string `http_client` reference is
allowed only when it resolves to an enabled managed shared client, while other
unmodeled provider extensions remain rejected. A live provider, HTTP client or
namespace must match its enabled state record exactly before ordinary
regeneration can publish a candidate, so manual drift is reported instead of
being overwritten.

Rule sets use role `rule_set` and one stable tag per record. `inline` accepts at
most 128 matcher-only rules; `local` accepts `source` or `binary` format plus an
absolute path reference, and the component does not own or delete that file;
`remote` accepts `source` or `binary`, an HTTP(S) URL, optional initial path and
update interval, and an optional named shared `http_client` reference (1.14+).
Legacy `download_detour` and inline HTTP-client objects are rejected. Warp tags
remain generator-owned and type-checked. Takeover imports registered non-Warp
rule sets; a live object must match its enabled state record exactly before
ordinary regeneration. Rule sets have no ordinary client export, share-link or
SubMan surface; full configuration, including remote URLs, is available only
from the explicitly sensitive component export, never list/diagnose.

Component state uses schema version `1` and the current runtime baseline is
the version shown in the repository README, with sing-box support through `1.14.2`; there is no separate
manual component contract revision. Component-owned `route_rules` use a typed sing-box 1.14 default/logical matcher and
route-action allowlist; nested rules are match-only and unknown fields/actions
are rejected before state/CAS or takeover. This closes the arbitrary route JSON
passthrough path without claiming general host policy-routing, nftables or
transparent data-plane support.

Advanced inbounds, endpoints, reusable outbounds/groups, certificate providers, shared HTTP clients and network namespaces live in `/root/sing-box-vps/components.json`, an independent schema-1 revisioned store. Use `sbv agent component list --json` for a metadata-only inventory or `sbv agent component diagnose --json` for a read-only state/config/listener/core/service/resource health snapshot. `sbv agent component export --json --id ID [--expected-revision N]` returns the complete record for a trusted caller and is explicitly sensitive; list/diagnose never return config values. `sbv agent component takeover --json --yes --expected-revision N [--allow-public]` scans the live configuration and imports all registered advanced inbounds, Endpoints, custom outbounds/groups, certificate providers, shared HTTP clients and network namespaces, preserving object fields and route rules; built-in `direct`/`block` owners and generator-owned `warp-ep` stay generated defaults. Unknown outbound/HTTP-client types, reserved tag conflicts and unowned global route rules remain fail-closed. If any existing object or rule would be lost, the transaction is rejected and rolled back. `sbv agent component rebuild --json --yes --expected-revision N` re-renders the same state through the normal candidate, resource and service rollback path without changing the component revision. If a writer is interrupted after its durable publish/resource journal, run `sbv agent component recover --json --yes --expected-revision N`; it verifies the dead owner, exact CAS revision, phase, snapshot and external-resource journal before removing or rolling back the transaction directory. Mutations use `sbv agent component create|replace --json --yes --expected-revision N --file component.json [--allow-public]` and `sbv agent component delete --json --yes --expected-revision N --id ID`. The input may be a complete `{id,role,type,tag,enabled,route_rules,config}` record with optional top-level `host_policy`, or a record with the upstream fields at the top level; unknown wrapper fields are rejected. During any `--json` mutation, stdout contains exactly one JSON envelope and human-readable progress is sent to stderr; component regeneration restores live advanced-route/Warp switches before rendering.

The registry covers `direct`, `tun`, `redirect`, `tproxy` and `cloudflared` inbounds; WireGuard, Tailscale, OpenConnect, OpenVPN client/server endpoints; shared HTTP clients; and SSH, Tor, direct, bridge, selector, urltest, block and protocol outbounds. Component records are composed with existing protocol inbounds, Warp endpoint state, route rules and base `direct`/`block` outbounds. Every candidate passes reference/loop validation, the managed listener plan and target-core `sing-box check`; active services are restarted only after a successful publish. For an enabled TUN with `auto_route=true`, generation adds `route.auto_detect_interface=true` unless a safe route guard/default interface is already declared; an explicit false guard without `route.default_interface` is rejected. After an active service restart, a candidate containing TUN must also observe each core-owned interface and, when enabled, its iproute2 rule/route and auto-redirect nftables state; a missing resource rolls back managed firewall changes and restores the previous state/config/service with `transparent_resource_check_failed`. This is a config-level loop guard plus core-resource postcheck, not general host policy-routing or nftables ownership. Optional Redirect `host_policy` owns a dedicated IPv4/TCP iptables PREROUTING chain; optional TProxy `host_policy` owns dedicated IPv4/TCP+UDP mangle PREROUTING rules, a fwmark rule before the default `main` lookup, and a `local` route table. Both are limited to an explicit ingress interface and destination-port allowlist, require `config.listen:"0.0.0.0"`, protected `management_ports`, and `--allow-public`, and use transaction journals for rollback/recovery and deletion. `redirect_host_policy` and `tproxy_host_policy` report resource state and observed ordering; records without an enabled policy remain operator-managed, and earlier firewall or routing rules may still affect effective precedence. There is no default route or DNS capture. TUN, tunnels, OpenVPN server and non-loopback listeners require `--allow-public`; loopback direct/redirect/TProxy records without an enabled `host_policy` do not. The registry keeps static `available:null` separate from a per-read `environment` observation (`available`, `unavailable`, or `not_assessed`) containing target-core/platform/build-tag/dependency status. The observation parses the target binary's `Tags:` line: a reported missing required tag is `unavailable`, while a wrapper that omits the line is `not_assessed`. Each persisted record additionally receives `instance_environment` in `component list`: this refines root, `/dev/net/tun`, `with_gvisor`, and optional Redirect/TProxy iptables/interface/iproute2 prerequisites from typed config without performing login, route or DNS changes. External account authentication, broader firewall policy, public reachability, and production remain unverified; inspect both `environment` and `validated` in `capabilities` and complete operator-reviewed steps before production use.
The privileged Docker `fresh_install_vless` scenario now supplies bounded runtime evidence for this core-owned portion: it creates and deletes a managed `sbv-tun`, observes the interface and priority-9000/table-2022 resources, and verifies that deletion clears them. Run `dev/verification-runs/20260916064328` additionally proves the core-owned TUN `auto_route` L3 TCP+UDP path through a disposable veth/network namespace. The artifact remains verification-container-only and does not establish host policy ownership, DNS/firewall takeover, public reachability, or production deployment.

The advanced inbound validators are explicit typed contracts rather than arbitrary JSON passthrough: Direct/Redirect/TProxy use the v1.14 ListenOptions and protocol-specific TCP/UDP or UDP-NAT fields; TUN accepts the current address/DNS, auto-route/redirect mark, route-set, UID/package/MAC, UDP-NAT, stack and platform HTTP-proxy fields while rejecting removed `inet4_*`/`inet6_*`, GSO and legacy sniff fields; Cloudflared accepts token, HA/protocol/edge/datagram/grace/region and nested control/tunnel DialerOptions. Direct/TProxy network lists are unique and enum-bounded, Dialer network types use the upstream interface enum, UID ranges use `start:end`, and an enabled platform HTTP proxy requires server and port. State/CAS validation does not prove host interfaces, policy routes/nftables, transparent routing or an external Cloudflared control connection.

SSH component records are typed against the sing-box 1.14 SSH and shared Dial Field allowlist. They require at least one of `password`, `private_key` or `private_key_path`; deprecated `domain_strategy` and arbitrary keys are rejected before state/CAS or takeover publication. `host_key` remains optional for upstream compatibility, but metadata reports `host_key_verification=pinned` only when a non-empty host-key list is present, otherwise `unverified`; list/diagnose never return credential values. Client exports validate component references before the target core check and publication. A rejected candidate returns `client_config_validation_failed` with `ok=false`; the previous export and backup remain unchanged. Graph diagnostics go to stderr without config contents or user-controlled tags. This candidate preflight does not change the read-only `check`/upgrade behavior for existing configurations or imply support for additional managed protocols.

Tor component records are typed against the sing-box 1.14 Tor outbound and shared Dial Field allowlist: `executable_path`, `extra_args`, `data_directory` and a string-valued `torrc` map are the only Tor-specific fields. Omitting `executable_path` preserves the upstream embedded form, but inventory reports `runtime_mode=embedded_unverified` because the default official build does not include `with_embedded_tor`+CGO; a non-empty path reports `runtime_mode=external` without asserting that the executable exists or that a Tor circuit works. Deprecated `domain_strategy`, control characters and non-string torrc values are rejected before state/CAS or takeover publication. Tor is an outbound runtime dependency, not a share-link/server protocol; complete the external Tor installation or reviewed embedded build and data-plane checks separately.

Selector and URLTest component records are typed against the sing-box 1.14 group schemas. Both require a non-empty unique `outbounds` list; selector `default` is optional but must name one of those members, while URLTest only accepts `url`, `interval`, `tolerance`, `idle_timeout` and `interrupt_exist_connections` in addition to the member list. Unknown group fields and wrong scalar types are rejected before state/CAS or takeover publication; the graph validator then resolves every member and detects cycles. Inventory exposes only a redacted `member_count`, not the member tags. URLTest duration syntax and probe URL reachability remain target-core/runtime concerns.

SOCKS outbound component records are typed against sing-box 1.14 `SOCKSOutboundOptions`: `server`/`server_port`, optional version `4|4a|5`, username/password, listable TCP/UDP network, optional UDP-over-TCP boolean/object, and shared Dial Fields. Deprecated `domain_strategy`, unknown fields, invalid versions/networks/ports and control characters are rejected before state/CAS or takeover publication. Credentials appear only in sensitive component export; the two-core check evidence does not claim an upstream SOCKS handshake or data-plane result.

HTTP outbound component records are typed against sing-box 1.14 `HTTPOutboundOptions`: TCP-only server/port/auth/path, HTTP header map, recursive outbound TLS (including ECH/uTLS/REALITY) and shared Dial Fields. Unknown or deprecated nested fields, invalid scalar/list values and control characters are rejected before state/CAS or takeover publication; component export is sensitive and does not imply an upstream HTTP proxy handshake.

Redirect host-policy details: `host_policy` is applied only for enabled records and is limited to IPv4/TCP iptables. `destination_ports` must not overlap `management_ports`, and the Redirect listener port must not appear in the destination allowlist. Creating the first enabled policy requires the sing-box service to be active. The transaction appends its dedicated jump after existing PREROUTING rules; `component diagnose` reports the observed position and reports `not_assessed_earlier_rules_present` when prior rules could affect precedence. Neither an empty preceding-rule count nor a successful marker in the disposable Docker fixture proves public reachability or the behavior of unrelated host firewall policy.

An enabled `network_namespace:default` record additionally requires an accessible
Linux network-namespace handle. Component mutations, takeover and rebuild check
candidate handles with a bounded `nsenter` before starting a transaction; absent
tools, a missing/nonregular path or insufficient permissions return
`network_namespace_unavailable` without publishing state/config or restarting the
service. Typed/offline state validation remains separate. Removing a broken
record is allowed when the remaining candidate has no inaccessible namespace.
The component never creates or deletes the operator-owned namespace path.

The reproduced **Linux ARM64 / sing-box 1.14.2 / `with_purego`** build crashes
in namespace thread handling. Namespace records and component `netns` references
are refused before publication with `namespace_runtime_unsafe_build` on that
exact combination. Missing build tags on that platform/version remain
`not_assessed` in inventory and refuse writes as
`namespace_runtime_build_not_assessed`; they are not labeled a confirmed crash.
The official same-version glibc build passed isolated namespace data and lifecycle
acceptance on Debian 12/glibc 2.36. Operators must supply a verified compatible
build; the installer does not silently switch its default core asset. Rocky 8's
glibc 2.28 is outside this result. See the
[completion contract](https://github.com/KnowSky404/sing-box-vps/blob/main/docs/specs/full-protocol-completion.md)
for exact build hashes, positive/negative cases and cleanup evidence.
Core installation/update also checks the staged candidate's bounded version/build
metadata when the existing server config uses namespace declarations or known
namespace Dial fields. Known-unsafe and exact-platform unassessed candidates are
refused before binary/library/marker replacement; ordinary header keys are not
treated as namespace use. A compatible operator-installed core is not silently
replaced by the unsafe default asset during an update or repair.

The `resolved` service needs a system DBus policy that permits its runtime user to
own `org.freedesktop.resolve1`, with no conflicting owner already active. A DBus
socket alone does not establish this permission. Keep the distribution's resolver
and bus policies under operator control; the installer does not grant this name
or replace an existing system resolver. Disposable runtime tests supply their
own narrow root ownership policy inside their container.
