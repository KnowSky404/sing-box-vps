# sing-box-vps Agent Runbook

This runbook is for AI agents operating the `sing-box-vps` repository and remote VPS hosts. It is written for Hermes, OpenClaw, Codex, Claude Code, and other automation agents.

The additive `protocol_registry` in `sbv agent capabilities --json` describes each managed protocol family, preset, component role, state ID, public Agent ID and capability. The legacy `protocols` object and JSON envelopes retain their existing meanings. `available=null` and `validated.status=not_assessed` mean that the current environment and instance connection have not been verified; do not treat implemented adapters as deployment approval or successful runtime evidence. The legacy alias `vless` continues to mean VLESS REALITY, the Hysteria2 state ID remains `hy2`, standalone SOCKS is registry/menu item 5 with state and Agent ID `socks`, standalone HTTP is registry/menu item 6 with state and Agent ID `http`, Shadowsocks is registry/menu item 7 with state and Agent ID `shadowsocks` plus alias `ss`, Trojan is registry/menu preset 8 with state/Agent ID `trojan` and management menu 21, VMess is registry/menu preset 9 with state/Agent ID `vmess` and management menu 22, AnyTLS uses state/Agent ID `anytls` with management menu 24, structured Hysteria2 uses Agent ID `hysteria2` with management menu 25, Snell uses state/Agent ID `snell` with registry preset 11 and management menu 26, TUIC uses state/Agent ID `tuic` with registry preset 12 and management menu 27, Hysteria v1 uses Agent ID `hysteria` with registry preset 13 and management menu 28, NaiveProxy uses Agent ID `naive` with registry preset 14 and management menu 29, and ShadowTLS uses state/Agent ID `shadowtls` with management menu 30. SOCKS, HTTP, Shadowsocks, VLESS outbound, Trojan, VMess, Hysteria2, Hysteria v1, AnyTLS, Snell, TUIC, NaiveProxy, ShadowTLS, and the typed WireGuard, Tailscale, OpenConnect, and OpenVPN endpoints are covered by the focused evidence recorded below. The full protocol goal remains unfinished. The current protocol contract revision is `2026091205`; the Shadowsocks-specific section retains its historical `2026090802` evidence.

## Managed advanced components

The current component contract revision is `2026091205`. Component-owned
`route_rules` use a typed sing-box 1.14 default/logical matcher and
route-action allowlist; nested rules are match-only and unknown fields/actions
are rejected before state/CAS or takeover. This closes the arbitrary route JSON
passthrough path without claiming host policy-routing, nftables or transparent
data-plane support.

Advanced inbounds, endpoints and reusable outbounds/groups live in `/root/sing-box-vps/components.json`, an independent schema-1 revisioned store. Use `sbv agent component list --json` for a metadata-only inventory or `sbv agent component diagnose --json` for a read-only state/config/listener/core/service/resource health snapshot. `sbv agent component export --json --id ID [--expected-revision N]` returns the complete record for a trusted caller and is explicitly sensitive; list/diagnose never return config values. `sbv agent component takeover --json --yes --expected-revision N [--allow-public]` scans the live configuration and imports all registered advanced inbounds, Endpoints and custom outbounds/groups, preserving object fields and route rules; built-in `direct`/`block` owners and generator-owned `warp-ep` stay generated defaults. Unknown outbound types, reserved tag conflicts and unowned global route rules remain fail-closed. If any existing object or rule would be lost, the transaction is rejected and rolled back. `sbv agent component rebuild --json --yes --expected-revision N` re-renders the same state through the normal candidate, resource and service rollback path without changing the component revision. If a writer is interrupted after its durable publish/resource journal, run `sbv agent component recover --json --yes --expected-revision N`; it verifies the dead owner, exact CAS revision, phase, snapshot and external-resource journal before removing or rolling back the transaction directory. Mutations use `sbv agent component create|replace --json --yes --expected-revision N --file component.json [--allow-public]` and `sbv agent component delete --json --yes --expected-revision N --id ID`. The input may be a complete `{id,role,type,tag,enabled,route_rules,config}` record or a record with the upstream fields at the top level; unknown wrapper fields are rejected. During any `--json` mutation, stdout contains exactly one JSON envelope and human-readable progress is sent to stderr; component regeneration restores live advanced-route/Warp switches before rendering.

The registry covers `direct`, `tun`, `redirect`, `tproxy` and `cloudflared` inbounds; WireGuard, Tailscale, OpenConnect, OpenVPN client/server endpoints; and SSH, Tor, direct, bridge, selector, urltest, block and protocol outbounds. Component records are composed with existing protocol inbounds, Warp endpoint state, route rules and base `direct`/`block` outbounds. Every candidate passes reference/loop validation, the managed listener plan and target-core `sing-box check`; active services are restarted only after a successful publish. For an enabled TUN with `auto_route=true`, generation adds `route.auto_detect_interface=true` unless a safe route guard/default interface is already declared; an explicit false guard without `route.default_interface` is rejected. After an active service restart, a candidate containing TUN must also observe each core-owned interface and, when enabled, its iproute2 rule/route and auto-redirect nftables state; a missing resource rolls back managed firewall changes and restores the previous state/config/service with `transparent_resource_check_failed`. This is a config-level loop guard plus core-resource postcheck, not host policy-routing or nftables ownership. TUN, tunnels, OpenVPN server and non-loopback listeners require `--allow-public`; loopback direct/redirect/TProxy records do not. The registry keeps static `available:null` separate from a per-read `environment` observation (`available`, `unavailable`, or `not_assessed`) containing target-core/platform/build-tag/dependency status. The observation parses the target binary's `Tags:` line: a reported missing required tag is `unavailable`, while a wrapper that omits the line is `not_assessed`. Each persisted record additionally receives `instance_environment` in `component list`: this refines root, `/dev/net/tun`, and `with_gvisor` prerequisites from the typed system/internal mode without performing login, interface, route, DNS or firewall changes. The component layer still does not claim external account authentication, route/firewall ownership or data-plane validation: inspect both `environment` and `validated` in `capabilities` and complete the relevant operator-reviewed resource steps before production use.
The privileged Docker `fresh_install_vless` scenario now supplies bounded runtime evidence for this core-owned portion: it creates and deletes a managed `sbv-tun`, observes the interface and priority-9000/table-2022 resources, and verifies that deletion clears them. The artifact does not establish packet forwarding, host policy ownership, public reachability, or production deployment.

The advanced inbound validators are explicit typed contracts rather than arbitrary JSON passthrough: Direct/Redirect/TProxy use the v1.14 ListenOptions and protocol-specific TCP/UDP or UDP-NAT fields; TUN accepts the current address/DNS, auto-route/redirect mark, route-set, UID/package/MAC, UDP-NAT, stack and platform HTTP-proxy fields while rejecting removed `inet4_*`/`inet6_*`, GSO and legacy sniff fields; Cloudflared accepts token, HA/protocol/edge/datagram/grace/region and nested control/tunnel DialerOptions. Direct/TProxy network lists are unique and enum-bounded, Dialer network types use the upstream interface enum, UID ranges use `start:end`, and an enabled platform HTTP proxy requires server and port. State/CAS validation does not prove host interfaces, policy routes/nftables, transparent routing or an external Cloudflared control connection.

SSH component records are typed against the sing-box 1.14 SSH and shared Dial Field allowlist. They require at least one of `password`, `private_key` or `private_key_path`; deprecated `domain_strategy` and arbitrary keys are rejected before state/CAS or takeover publication. `host_key` remains optional for upstream compatibility, but metadata reports `host_key_verification=pinned` only when a non-empty host-key list is present, otherwise `unverified`; list/diagnose never return credential values. Client exports validate component references before the target core check and publication. A rejected candidate returns `client_config_validation_failed` with `ok=false`; the previous export and backup remain unchanged. Graph diagnostics go to stderr without config contents or user-controlled tags. This candidate preflight does not change the read-only `check`/upgrade behavior for existing configurations or imply support for additional managed protocols.

Tor component records are typed against the sing-box 1.14 Tor outbound and shared Dial Field allowlist: `executable_path`, `extra_args`, `data_directory` and a string-valued `torrc` map are the only Tor-specific fields. Omitting `executable_path` preserves the upstream embedded form, but inventory reports `runtime_mode=embedded_unverified` because the default official build does not include `with_embedded_tor`+CGO; a non-empty path reports `runtime_mode=external` without asserting that the executable exists or that a Tor circuit works. Deprecated `domain_strategy`, control characters and non-string torrc values are rejected before state/CAS or takeover publication. Tor is an outbound runtime dependency, not a share-link/server protocol; complete the external Tor installation or reviewed embedded build and data-plane checks separately.

Selector and URLTest component records are typed against the sing-box 1.14 group schemas. Both require a non-empty unique `outbounds` list; selector `default` is optional but must name one of those members, while URLTest only accepts `url`, `interval`, `tolerance`, `idle_timeout` and `interrupt_exist_connections` in addition to the member list. Unknown group fields and wrong scalar types are rejected before state/CAS or takeover publication; the graph validator then resolves every member and detects cycles. Inventory exposes only a redacted `member_count`, not the member tags. URLTest duration syntax and probe URL reachability remain target-core/runtime concerns.

SOCKS outbound component records are typed against sing-box 1.14 `SOCKSOutboundOptions`: `server`/`server_port`, optional version `4|4a|5`, username/password, listable TCP/UDP network, optional UDP-over-TCP boolean/object, and shared Dial Fields. Deprecated `domain_strategy`, unknown fields, invalid versions/networks/ports and control characters are rejected before state/CAS or takeover publication. Credentials appear only in sensitive component export; the two-core check evidence does not claim an upstream SOCKS handshake or data-plane result.

HTTP outbound component records are typed against sing-box 1.14 `HTTPOutboundOptions`: TCP-only server/port/auth/path, HTTP header map, recursive outbound TLS (including ECH/uTLS/REALITY) and shared Dial Fields. Unknown or deprecated nested fields, invalid scalar/list values and control characters are rejected before state/CAS or takeover publication; component export is sensitive and does not imply an upstream HTTP proxy handshake.

## HTTP outbound data-plane verification

The bounded Docker probe in `multi_protocol_coexistence` creates `http-outbound-verification` through the Agent component CAS API, waits for the service, runs the target `sing-box check`, and verifies the rendered HTTP outbound and domain route. A disposable loopback marker server is reachable only through an authenticated loopback HTTP proxy; the existing SOCKS5 inbound sends CONNECT through the typed outbound. The artifact must contain the exact Basic `Proxy-Authorization`, `X-SBV-Proxy` header and marker body, and `http-outbound.result.env` must report `RESULT=success`. Run `dev/verification-runs/20260912051138` satisfies these checks.

This is fixed 1.14.0, isolated-container/loopback evidence using a synthetic domain. It does not prove public reachability, an external HTTP proxy, production deployment, external authentication or completion of the full protocol goal.

## SSH outbound direct-tcpip verification

The privileged Docker `multi_protocol_coexistence` scenario (run
`dev/verification-runs/20260915051357`) creates a disposable
OpenSSH server with a generated ed25519 host key and test user, then publishes a
typed `ssh-outbound-verification` component with that key pinned. The existing
authenticated SOCKS5 inbound routes `localhost` through the SSH outbound; the
SSH server opens a direct-tcpip channel to a loopback HTTP marker. Artifacts
include the target-core `check`, pinned-key configuration, sshd password-accept
log, exact marker response and component CAS deletion (`ssh-outbound.result.env`
uses `DATA_PLANE=ssh_direct_tcpip_loopback`).

This proves only an isolated-container SSH TCP channel. It does not prove an
external SSH service, credential deployment, public reachability, UDP, production
operation or SubMan synchronization; the disposable SSH process and user are not
installer-managed resources.

## SOCKS outbound CONNECT verification

The same privileged Docker scenario (run
`dev/verification-runs/20260915053927`) starts a disposable username/password
SOCKS5 upstream and a loopback HTTP marker. A typed
`socks-outbound-verification` component routes the marker domain through that
upstream from the existing authenticated SOCKS5 inbound. Artifacts retain the
upstream authentication/destination record, target-core `check`, exact response,
and the revision-10 create/revision-11 delete envelope; the result label is
`DATA_PLANE=socks5_connect_loopback`.

This proves only an isolated-container SOCKS5 TCP CONNECT path. It does not
prove an external proxy, UDP relay, public reachability, production operation
or SubMan synchronization; the upstream server and credentials are disposable
verification fixtures, not installer-managed resources.

## Selector group verification

The privileged Docker `multi_protocol_coexistence` scenario (run
`dev/verification-runs/20260915060132`) creates a typed selector whose only
member is the built-in `direct` outbound. The existing authenticated SOCKS5
inbound routes `localhost` through that group to the disposable loopback marker;
artifacts retain the target-core `check`, exact response, and revision-12
create/revision-13 delete envelopes. The result label is
`DATA_PLANE=selector_direct_loopback`.

This proves only single-member selector resolution in an isolated container. It
does not prove multi-member failover, URLTest probing, public reachability,
production operation or SubMan synchronization.

## Direct inbound override data plane

Direct inbound component records may include the upstream `network` string (`tcp` or `udp`) and destination override fields `override_address`/`override_port`. The component validator rejects control characters, empty override addresses and ports outside 1-65535 while preserving the normal listen fields. A loopback direct record does not require `--allow-public`; non-loopback listeners still do.

The bounded Docker proof in `multi_protocol_coexistence` creates TCP and UDP direct components through the component CAS API, waits for service activity, runs the target `sing-box check`, and asserts their rendered listeners. Disposable loopback HTTP and UDP marker/echo fixtures receive requests only through the managed direct listeners' override destinations; exact responses are stored in `direct-inbound-response.txt` and `direct-inbound-udp-response.txt`, and the corresponding `direct-inbound.result.env` files report `RESULT=success`. Run `dev/verification-runs/20260912073323` contains the successful artifacts. This is fixed-core/loopback TCP+UDP evidence for direct forwarding only. It does not establish TUN/redirect/TProxy transparent routing, host firewall policy, public reachability, production deployment or full-protocol completion.

## Redirect/TProxy transparent data-plane evidence

The privileged Docker `multi_protocol_coexistence` scenario in
`dev/verification-runs/20260915013127` creates a redirect inbound at revision 4
and a TProxy inbound at revision 5. After the target ARM64 `sing-box 1.14.0`
check, `verification_execute_redirect_probe` installs a temporary owner-scoped
`OUTPUT REDIRECT` rule and proves a TCP marker; it removes that rule before
returning. `verification_execute_tproxy_probe` creates a disposable veth pair
and network namespace, installs a fwmark policy route and mangle `PREROUTING`
`TPROXY` rules, and proves both TCP and UDP markers before removing every
resource. The resulting `transparent/redirect` and `transparent/tproxy`
artifacts retain exact responses, rule/resource snapshots and
`POLICY_OWNERSHIP=not_managed`.

The same scenario checks `component diagnose` instance requirements (root is
required; TUN is not), deletes TProxy and redirect through revision 6/7, and
asserts their rendered inbounds are gone. These temporary rules are verification
container policy only and are not installer-owned host PREROUTING, policy
routing, public, production, external-authentication, or SubMan evidence.

## OpenVPN endpoint TCP and UDP closure

OpenVPN client/server component records remain typed and reference-protected. The bounded Docker scenario `fresh_install_vless` creates separate synthetic `system:false` server/client pairs with a short-lived SAN/serverAuth certificate and username/password, routes managed direct inbounds through each client endpoint, and verifies `peer connected`, `tunnel established`, the exact marker response and target-core `sing-box check` for both TCP and UDP. It then deletes each proxy/client/server set through revision CAS and verifies the listeners and component resources are gone. Run `dev/verification-runs/20260914151532` contains successful `fresh_install_vless/openvpn-endpoint/` and `openvpn-endpoint-udp/` result and cleanup artifacts. `tests/managed_openvpn_endpoint_runtime.sh` provides the same local TCP+UDP fixtures when `SINGBOX_BINARY_114` is configured and prints `SKIP` when the core or dependencies are unavailable.

This is fixed 1.14.0, isolated synthetic server/client evidence for `system:false` TCP and UDP only. It does not prove external VPN control-plane authentication, external certificate deployment, public reachability, production deployment, SubMan or completion of the full protocol goal.

## OpenVPN system-device resource closure

The same privileged Docker `fresh_install_vless` scenario also creates named
`system:true` OpenVPN server/client endpoints (`sbv-ovpn-srv` and
`sbv-ovpn-cli`) in run `dev/verification-runs/20260914210913`. It verifies the
target-core `check`, exact Linux interfaces and `10.79.0.1/24`/`10.79.0.2/24`
addresses with MTU 1500, `peer connected`/`tunnel established` journal lines,
and `component diagnose` resource status, then deletes both through revision
CAS and confirms the interfaces are gone. This is core-owned interface and
tunnel lifecycle evidence only: no host route, transparent forwarding, packet
payload, public reachability, external control-plane authentication, production
or SubMan claim is made. Named system endpoints participate in the transaction
postcheck; an unset interface name remains `not_assessed`.

The same read-only resource contract applies to named `system:true` WireGuard
and OpenConnect endpoints and named `system_interface:true` Tailscale
endpoints. `component diagnose --json` observes the exact interface, configured
addresses when the endpoint declares them, and configured MTU when it is
non-zero; a missing resource is `unavailable` and participates in the active
component transaction postcheck. It does not install routes/DNS, authenticate
an external control plane, or prove a VPN data path.

Shadowsocks outbound component records are typed against sing-box 1.14 `ShadowsocksOutboundOptions`: server/port, method/password, TCP/UDP network, SIP003 plugin, UDP-over-TCP, outbound multiplex and shared Dial Fields. SS2022 passwords use strict Base64 decoding with method-specific 16/32-byte keys; unknown/deprecated fields, unsupported methods/plugins, malformed nested options and control characters are rejected before state/CAS or takeover publication. Credentials remain export-only; core `check` evidence does not imply a remote Shadowsocks handshake or data plane.

VMess and Trojan outbound component records are typed against sing-box 1.14 `VMessOutboundOptions` and `TrojanOutboundOptions`. VMess requires a UUID and supported `security`, `alter_id`, packet-encoding, TCP/UDP network and shared Dial Fields; Trojan requires a password and the same network/dial boundaries. Both reuse the guarded outbound TLS, V2Ray transport and multiplex contracts. Native HTTP, WebSocket without early data, gRPC and TLS-only QUIC are representable; HTTPUpgrade, WebSocket early data, plaintext QUIC and lite-gRPC `permit_without_stream` are rejected before state/CAS or takeover publication. Credentials remain export-only, and target-core `check` does not imply a remote protocol handshake or data plane.

VLESS outbound component records are typed against sing-box 1.14 `VLESSOutboundOptions` and the same shared Dial Fields, outbound TLS, V2Ray transport and multiplex contracts. They require a UUID, allow only the empty flow or `xtls-rprx-vision`, and preserve the upstream xudp default when `packet_encoding` is omitted. Vision requires enabled TLS with no V2Ray transport; HTTP, WebSocket without early data, gRPC and TLS-only QUIC are representable for the empty flow. HTTPUpgrade, WebSocket early data, plaintext QUIC, lite-gRPC `permit_without_stream` and incompatible Vision combinations fail closed before state/CAS or takeover publication. Credentials remain export-only, and target-core `check` does not imply a remote VLESS handshake or data plane.

AnyTLS outbound component records are typed against sing-box 1.14 `AnyTLSOutboundOptions`. They require `server`, `server_port`, a non-empty `password`, and enabled outbound TLS; optional idle-session fields and `client_metadata` retain their upstream scalar types, and shared Dial Fields remain bounded. AnyTLS does not have a configurable `network`, transport, or multiplex field, and `tcp_fast_open=true` is rejected at the state/CAS and takeover boundary to match the target adapter. Credentials remain in sensitive export only; target-core `check` does not imply an upstream AnyTLS handshake or TCP/UDP data plane.

Snell outbound component records are typed against sing-box 1.14 `SnellOutboundOptions`. They require version 4 or 6, a non-empty PSK, and typed optional userkey/reuse, network and shared Dial Fields; v4 accepts only HTTP obfuscation fields, while v6 accepts only traffic-shaping fields and requires a 12-byte minimum PSK. The v5 QUIC proxy is not exposed as a separate outbound, and UDP uses Snell's TCP packet API. Credentials remain in sensitive export only; 1.13.18 does not register this 1.14-only type, and a target-core `check` does not imply a remote Snell handshake or TCP/UDP data plane.

Hysteria2 outbound component records are typed against sing-box 1.14 `Hysteria2OutboundOptions`. They cover server with mutually exclusive server-port or server-port ranges, port hopping, bandwidth, salamander/gecko obfs, TCP/UDP network, required outbound TLS, QUIC fields, BBR profile, Chrome QUIC control, shared Dial Fields and optional Hysteria Realm rendezvous. Realm server/STUN/port-mapping/HTTP-client objects are bounded, Hysteria v1 authentication and deprecated receive-window fields are rejected, and credentials remain in sensitive export only. Target-core `check` does not imply a remote QUIC handshake or UDP data plane.

Hysteria v1 outbound component records are typed against sing-box 1.14 `HysteriaOutboundOptions`. They cover mutually exclusive server-port/range selection, hop interval, `up`/`down` network-byte compatibility fields, Mbps bandwidth, string obfs, auth/auth_str, TCP/UDP network, required outbound TLS, QUIC fields and shared Dial Fields. Deprecated receive-window aliases and Hysteria2-only fields are rejected; target-core `check` does not imply a remote Hysteria handshake or UDP data plane.

TUIC outbound component records are typed against sing-box 1.14 `TUICOutboundOptions`. They cover server/port, UUID/password, congestion control, native/quic UDP relay, optional UDP-over-stream, zero-RTT, heartbeat, TCP/UDP network, required outbound TLS, QUIC fields and shared Dial Fields. `udp_relay_mode` conflicts with `udp_over_stream`; target-core `check` does not imply a remote TUIC handshake or UDP data plane.

NaiveProxy outbound component records are typed against sing-box 1.14 `NaiveOutboundOptions`. They cover server/port, username/password, extra headers, HTTP/2 or QUIC, UDP-over-TCP, receive windows, the documented restricted TLS fields and shared Dial Fields. Non-zero `insecure_concurrency` cannot be combined with QUIC, and unsupported TLS/UoT/header/window fields fail closed; `with_naive_outbound` and `libcronet.so` remain independent environment requirements.

ShadowTLS outbound component records are typed against sing-box 1.14 `ShadowTLSOutboundOptions`. They are TCP-only wrappers with server/port, versions 1–3, optional password, required outbound TLS and shared Dial Fields. This outbound contract is intentionally separate from the local ShadowTLS inbound outer-plus-loopback-Mixed composite; target-core `check` does not imply a remote ShadowTLS handshake or TCP data plane.

WireGuard endpoint component records are typed against sing-box 1.14 `WireGuardEndpointOptions`. They use the modern endpoint role (the removed WireGuard outbound is never reconstructed), preserve 32-byte standard Base64 keys, CIDR addresses/allowed IPs, peer keepalive/reserved tuples, MTU/listen/workers, UDP NAT and shared Dial Fields. A 1.14 full-field check and a 1.13.18 compatible base subset are configuration evidence only; system-interface permissions, peer handshake and UDP data plane remain separate checks.

Tailscale endpoint records validate the 1.14 `TailscaleEndpointOptions` state, including persistent/auth/control fields, route advertisements, relay AddrPort values, exit-node conflicts, optional SSH and shared Dial Fields. OpenConnect records are client-only and validate flavor, token secret/path, required mobile identity, CSD/HIP/TNCC, TLS material, form-entry pairing and keepalive/compression constraints. OpenVPN client/server records validate their TLS/static-key unions, remote and address-family rules, certificate/key material, control wrapping, users and pushed DNS/routes. Inline PEM/key content may contain LF/CR while paths and non-material fields remain control-character safe. These checks cover state/render and fixed-core configuration boundaries only; external VPN/Tailscale authentication, certificate files, host routing/firewall and real data paths remain unverified. The isolated named OpenVPN `system:true` interface/tunnel resource slice is recorded separately above; WireGuard/OpenConnect/Tailscale system-interface observation is a read-only resource contract, not data-plane evidence.

Unknown state IDs or future schema versions block reconstruction while preserving those entries. Live inbound discovery is also all-or-nothing: unknown types, non-REALITY VLESS, duplicate single-instance protocols, and duplicate explicit tags block reconciliation, takeover, and regeneration before resource preparation. `status`, `nodes`, and `links` then return `live_inbound_inventory_untrusted` instead of presenting a partial protocol/node list as complete. All three commands require the normalized index to match the complete live protocol set exactly and require every base state to be present, recognized, canonical, and indexed; failures return `protocol_index_untrusted` or `protocol_state_untrusted`. `nodes` and `links` additionally capture and validate the complete REALITY instance list before public-address lookup, and discard all rendered nodes if any state load or final state restoration fails. This inventory check does not certify custom fields, outbounds, endpoints, or routes as losslessly managed. Restore a compatible script or reviewed backup to recover; do not remove unknown files or config components to bypass the guard. Track the full protocol expansion and evidence in [the implementation record](../superpowers/plans/2026-09-06-unified-protocol-management.md) and [the upstream matrix](../superpowers/specs/2026-09-06-protocol-coverage.md).

## First Principles

Instance identity is scoped by protocol and instance ID. Shared read-only adapters expose legacy singleton files as `main` and retain REALITY's existing IDs/default. Agent nodes/links and client rendering for Mixed, standalone SOCKS, HTTP, Shadowsocks, Trojan, VMess, Hysteria2, Hysteria v1, AnyTLS, Snell, TUIC, NaiveProxy and ShadowTLS expose each structured instance and its revision without migrating legacy state or preparing credentials. Existing public Agent fields remain unchanged; the documented SOCKS, HTTP, Shadowsocks, Trojan, VMess, Hysteria2, Hysteria v1, AnyTLS, Snell, TUIC, NaiveProxy and ShadowTLS lifecycle/runtime surfaces are covered by the focused evidence below.

The structured stores under `protocols/instances/<protocol>.json` have typed Mixed, standalone SOCKS, HTTP, Shadowsocks, Trojan, VMess, Hysteria2, Hysteria v1, AnyTLS, Snell, TUIC, NaiveProxy and ShadowTLS validators/renderers and are connected to the guarded instance lifecycle. Use `sbv agent instance create|replace|delete|default|migrate|recover mixed --json --yes --expected-revision N` for Mixed; standalone SOCKS, HTTP, Shadowsocks, Trojan, VMess, Hysteria2, Hysteria v1, AnyTLS, Snell, TUIC, NaiveProxy and ShadowTLS support the same operations except `migrate`, which is rejected because they have no legacy `.env` migration path. Existing live SOCKS/HTTP/Shadowsocks/Trojan/VMess configuration uses takeover; Hysteria2 and AnyTLS takeover accepts only the typed manual-TLS subset and preserves ACME/provider legacy state when that subset is not lossless; Hysteria v1 takeover accepts only the typed manual-TLS QUIC subset; Snell takeover accepts only its typed v5/v6 fields; TUIC takeover accepts only the typed manual-TLS QUIC subset; NaiveProxy takeover accepts only the typed manual-TLS TCP/UDP subset; ShadowTLS takeover accepts only the typed composite outer-plus-loopback-Mixed subset. Create/replace require a complete private `--file` record and delete/default require `--id`. Do not hand-edit stores or treat file rollback as a complete service/resource transaction; lifecycle writes use the managed-state snapshot, configuration publication, listener/resource checks and persistent recovery boundaries. See the [implementation record](../superpowers/plans/2026-09-06-unified-protocol-management.md) for the evidence boundary and its limits.

Client export includes Mixed and standalone SOCKS as SOCKS5 outbounds with explicit UoT v2, HTTP CONNECT as documented in its own section, and Shadowsocks as full JSON preserving its network/authentication fields. It preserves stored authentication mode and credentials; missing or invalid port/authentication state aborts the whole export without rotating the existing file or backup. `nodes.client_exportable` and `capabilities` reflect this. Export responses include a plaintext transport warning where applicable: SOCKS5 credentials and unencrypted application traffic are exposed on the proxy hop without TLS, so use a trusted network or protected tunnel. UoT encapsulates UDP over TCP, does not encrypt it, and requires no additional fixed server UDP listener. Standalone SOCKS has no HTTP/TLS surface or SubMan sync; its lifecycle/runtime/export paths passed the final gate, while public native UDP remains unverified. The final Shadowsocks export/runtime evidence covers its typed full-JSON path and documented warnings; it does not imply unsupported fields.

Managed server candidates and typed stores now check fixed listener conflicts by canonical address, address family, TCP/UDP, port and inbound tag. Cleanup of a removed listener uses the previous config backup and remaining listeners: it retains any transport/port still referenced and does not delete unrelated transports. An absent/unmodelled inventory blocks cleanup; a backend failure returns nonzero and explicitly reports possibly partial external changes. Do not infer a firewall ownership ledger, other-process port availability, dynamic SOCKS UDP/ACME resource coverage, or full service/resource rollback from this preflight. Existing `agent check` still means the core check, not a port reservation.

The resource contract is `managed_listener_plan <config_file>`: it emits a JSON listener array with `owner` (inbound tag), `protocol` (registered state ID), canonical `address`, `family` (`ipv4`/`ipv6`), `transport` (`tcp`/`udp`), `port`, and `dual_stack`. The registered `listen_networks` for Mixed, standalone SOCKS, HTTP, Shadowsocks and Trojan drive transport projection; IPv6 `::` canonicalizes to the all-zero IPv6 address and is marked dual-stack. Unknown inbound types and `netns`, `bind_interface` or `reuse_addr` listeners are rejected. The plan is a resource preflight, not proof that an existing broad firewall rule belongs to this instance. Trojan projects its actual listener from the typed transport (TCP for native/HTTP/WS/gRPC, UDP for TLS QUIC), not from the registry's possible-network union.

Opening rules now uses the entire committed listener plan without migrating state, and opens only actual registered listening transports. Full removal requires a successful service stop and confirmed inactive state before clearing the config/index; failed stop restores managed files and leaves firewall rules unchanged. A post-publication opening error reports `config_committed`, `firewall_may_be_partial`, and `service_restart_not_attempted`. It is not a successful rollback; inspect the service and external resources manually.

REALITY takeover matches live inbound tags to existing managed instance identities. It preserves their display names, upload/download QoS and default instance while rebuilding connection parameters from the live configuration. The saved public key is reusable only with a matching private key. Ambiguous identity mappings stop reconstruction; a state-write failure restores the previous protocol state tree. These metadata guarantees do not establish lossless handling of arbitrary custom sing-box fields or external system resources.

- Treat `install.sh` as the single runtime source of truth.
- Read `AGENTS.md` and `README.md` before changing repository behavior.
- Use `sing-box-test` for test VPS validation.
- Use `sing-box-prod` for production VPS operations.
- Remote verification runs in Docker locally, auto-building the sing-box-vps-verify image. No external SSH target required.
- Preserve secrets. Do not print private keys, passwords, tokens, full proxy links, or QR payloads unless the user explicitly requests them and the context is safe.
- Back up runtime config before changing it.
- Run `sing-box check` after generating or modifying any sing-box server or client config.
- Treat client exports, full link JSON, and SubMan sync payloads as sensitive connection material.

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

Remote verification runs via Docker locally.

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

Use the complete staged Bootstrap in `README.md`. It downloads to a `mktemp`
file, validates the script before execution, and must not be replaced with
`curl | bash` or process substitution.

Post-install checks:

```bash
command -v sbv
systemctl status sing-box --no-pager
sing-box check -c /root/sing-box-vps/config.json
```

If the install generates or displays credentials, summarize that credentials were generated without pasting secrets into logs.

## Complete Capability Map

Keep historical functions in scope when planning or documenting a change:

| Area | Current capability | Agent route |
|---|---|---|
| Protocols | VLESS REALITY, Mixed HTTP/SOCKS, standalone SOCKS, standalone HTTP, Shadowsocks, Trojan, VMess, Hysteria2, Hysteria v1, AnyTLS, Snell, TUIC, NaiveProxy, ShadowTLS; protocols can coexist | Discover with `capabilities`; summaries with `nodes`; general installation uses menus; typed Mixed/SOCKS/HTTP/Shadowsocks/Trojan/VMess/Hysteria2/Hysteria v1/AnyTLS/Snell/TUIC/NaiveProxy/ShadowTLS have Agent instance create/replace/delete/default/recover commands (Mixed additionally supports migrate) |
| REALITY | Multiple instances, independent ports/ShortID/names, per-instance outbound policy and optional upload/download QoS | Read with `nodes`; mutate through the interactive protocol menu |
| TLS | Hysteria2/AnyTLS ACME HTTP-01, Cloudflare DNS-01, or manual certificate paths; Hysteria v1, NaiveProxy, standalone HTTP, Trojan and TUIC use manual certificate paths; Trojan/TUIC/Hysteria v1/NaiveProxy explicitly select certificate or system client trust | Read warnings/check output; mutate interactively |
| Warp | Account registration, enable/disable, all/selective routing, built-in/custom domains, local/remote rule sets | Read with `warp`; mutate through menu 13 |
| Network/system | IPv4/IPv6/dual inbound stack, outbound/DNS strategy, BBR | Read config/doctor; mutate through menu 14 |
| Node material | Links/QR, bare-core client export, dual-stack labels | `nodes` is log-safe; `links` and `export-client` are sensitive |
| SubMan | Idempotent VLESS/Hysteria2 sync; Trojan and VMess sync only losslessly representable TLS/system-trust users and report per-user skips; revision/error/retry semantics; only encrypted dual-network Shadowsocks entries use the dedicated path, while single-network and `none` entries are skipped; Hysteria v1, Snell, TUIC, NaiveProxy, AnyTLS and ShadowTLS remain explicitly unsupported | `subman-sync` is sensitive and externally mutating; same-snapshot mock passed for VMess (`synced=3`, `skipped=1`, `failed=0`), and no unauthorized real sync |
| Lifecycle | start/stop/restart/status/logs, managed-instance takeover/repair, core/script upgrade, two uninstall scopes | Status/check/doctor are read-only; restart, fixed core upgrade and typed Mixed/SOCKS/HTTP/Shadowsocks/Trojan/VMess/Hysteria2/Hysteria v1/AnyTLS/Snell/TUIC/NaiveProxy/ShadowTLS instance mutations are guarded Agent mutations |
| Verification | VMess: native 1.13.18/1.14.0 generated none/http/ws/grpc/quic two-user exports and server/client checks; Hysteria2: typed multi-user lifecycle, independent bandwidth, Agent/share/client-export and SubMan contract; Hysteria v1: typed multi-user manual-TLS QUIC lifecycle, independent bandwidth/obfs, Agent redaction/share and outbound JSON contract; AnyTLS: typed multi-instance lifecycle, Agent credential-safe summary/share and client-export contract; Snell: typed v5/v6 lifecycle, takeover, Agent summary/share and outbound JSON contract; TUIC: typed multi-user manual-TLS QUIC lifecycle, Agent redaction/share and per-user outbound JSON contract; NaiveProxy: typed multi-user manual-TLS TCP/UDP lifecycle, Agent redaction/share and per-user outbound JSON contract with libcronet warning; ShadowTLS: typed composite outer/loopback-detour lifecycle, v1/v2/v3 validation, Agent redaction/share and per-user outbound JSON contract; focused takeover/lifecycle/Agent/share/SubMan/probe tests passed; Docker fresh-install and coexistence evidence is run below | Local VMess/Hysteria2/Hysteria v1/AnyTLS/Snell/TUIC/NaiveProxy/ShadowTLS tests pass, with Hysteria v1/Snell/TUIC/NaiveProxy/ShadowTLS target-core check when configured; SubMan is mock-only, no production or real SubMan sync proof |

Do not invent non-interactive mutations for features marked interactive-only. Use the menu after the appropriate safety gate or stop and ask for operator approval.

## Upgrade Existing VPS

For production, use the plan gate first.

First update only the management command, start a new invocation, and verify the new Agent surface:

```bash
sbv update sbv
sbv agent capabilities --json
```

For automation, use a fixed target and preserve the preflight JSON:

```bash
sbv agent upgrade-check --json 1.14.0
sbv agent upgrade --json 1.14.0 --yes
```

Require `ready=true` and an empty `blockers` array. The read-only preflight validates the currently installed core and reports known schema warnings without reconciling or migrating protocol state, but intentionally does not download the target binary. The guarded upgrade creates a root-only persistent backup, installs the target, runs the target core's `sing-box check` before restart, verifies the exact version/config hash/service, and attempts to restore the old binary and previous service activity on any failed invariant. `SHA256SUMS` covers every regular file in the copied runtime tree plus the binary, `sbv`, service unit, and metadata. `transaction-result.json` is written atomically beside that manifest and records the transaction ID, versions, status history, manifest hash, and rollback result. It never rewrites the server config for migration.

The ordinary operator path `sbv update sing-box [latest|x.y.z]` remains available, but Agent automation should use the fixed-version guarded command. Both paths only operate on a healthy managed instance and return nonzero when the target rejects the config. If the instance is incomplete or missing, enter the interactive `sbv` menu for repair/takeover instead of forcing an upgrade.

After upgrade:

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
sbv agent status --json
sbv agent nodes --json
sbv agent check --json
sbv agent doctor --json
systemctl status sing-box --no-pager
journalctl -u sing-box --no-pager -n 200
sing-box check -c /root/sing-box-vps/config.json
ls -la /root/sing-box-vps /root/sing-box-vps/protocols
```

Use the non-interactive Agent interface when automation needs stable output:

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
sbv agent instance create mixed|socks|http|shadowsocks|trojan|vmess|hy2|hysteria|anytls|snell|tuic --json --yes --expected-revision N --file record.json
sbv agent instance replace mixed|socks|http|shadowsocks|trojan|vmess|hy2|hysteria|anytls|snell|tuic --json --yes --expected-revision N --file record.json
sbv agent instance delete mixed|socks|http|shadowsocks|trojan|vmess|hy2|hysteria|anytls|snell|tuic --json --yes --expected-revision N --id ID
sbv agent instance default mixed|socks|http|shadowsocks|trojan|vmess|hy2|hysteria|anytls|snell|tuic --json --yes --expected-revision N --id ID
sbv agent instance migrate mixed --json --yes --expected-revision N
sbv agent instance recover mixed|socks|http|shadowsocks|trojan|vmess|hy2|hysteria|anytls|snell|tuic --json --yes --expected-revision N
sbv update sbv
sbv update sing-box latest
```

- `status --json` is safe for routine diagnostics. It reports script/core/service/path/protocol state plus inbound/outbound stack modes, BBR, REALITY instance/QoS counts, and whether client export/SubMan files exist; it does not return credentials.
- `capabilities --json` is read-only and returns the supported protocol/feature matrix plus safety labels. `upgrade-check --json 1.14.0` is read-only and must precede an upgrade; require `ready=true` and `blockers=[]`. Its `target_binary_validation.performed=false` means target validation is deferred to the guarded apply transaction, not that compatibility was already proven.
- `nodes --json` is safe for ordinary logs. It reports every protocol and every REALITY/Mixed/SOCKS/HTTP/Shadowsocks/Trojan/VMess/Hysteria2/Hysteria v1/AnyTLS/Snell/TUIC/NaiveProxy/ShadowTLS instance, including names, ports, instance revisions, server names, rate limits, outbound policy, and exportability without UUIDs, keys, full share links, or passwords. For Shadowsocks, VMess, Hysteria2, Hysteria v1, AnyTLS, Snell, TUIC, NaiveProxy, and ShadowTLS, authentication/network-specific summaries expose only bounded metadata; server PSKs, UUIDs, `auth_str`, AnyTLS passwords, Snell PSKs/user keys, TUIC UUIDs, Naive usernames/passwords, ShadowTLS passwords, and user passwords never appear.
- `links --json` returns full connection material for every protocol and every REALITY/Mixed/SOCKS/HTTP/Shadowsocks/Trojan/VMess/Hysteria2/Hysteria v1/AnyTLS/Snell/TUIC/NaiveProxy/ShadowTLS instance. Treat its output as sensitive and avoid pasting it into public logs. A Shadowsocks response has `links: {"<stable-outbound-tag>": "<uri>"}`, `outbounds: [...]` and `warnings: [...]`; VMess responses contain `vmess://` links plus matching outbounds; AnyTLS returns per-user outbound JSON, `links:{}`, and `warnings[].code=anytls_standard_uri_unavailable` because no standard URI can carry the complete configuration. Snell returns per-user outbound JSON, `links:{}`, and `warnings[].code=snell_standard_uri_unavailable` because version, obfs/shaping and user keys have no lossless standard URI. TUIC returns per-user outbound JSON, `links:{}`, and `warnings[].code=tuic_standard_uri_unavailable` because no standard URI carries its QUIC and user fields. Hysteria v1 returns per-user outbound JSON, `links:{}`, and `warnings[].code=hysteria_standard_uri_unavailable`; NaiveProxy returns per-user outbound JSON, `links:{}`, `warnings[].code=naive_standard_uri_unavailable` and `naive_libcronet_required`; ShadowTLS returns per-user outbound JSON, `links:{}`, and `warnings[].code=shadowtls_standard_uri_unavailable`; Hysteria2 returns per-user `hy2://` links when system trust is selected, full outbounds for certificate trust, and explicit warnings for unrepresentable options; manual Ed25519 certificates include `warnings[].code=hy2_ed25519_share_link_requires_client_override` because the share URI cannot carry the required 1.14+ client option.
- `export-client --json` generates `/root/sing-box-vps/client/sing-box-client.json`, validates it with `sing-box check`, and returns the path plus config JSON. It writes the client export file but does not change the running server config or restart services. Mixed and standalone SOCKS export SOCKS5 + UoT v2 with preserved authentication and no TLS/HTTP surface. Shadowsocks uses the full JSON export to preserve its network restriction and method/authentication; Trojan, VMess, ordinary VLESS, Hysteria2, Hysteria v1, AnyTLS, Snell, TUIC, NaiveProxy, and ShadowTLS export one full outbound per user, preserving transport and explicit public-certificate/system trust where applicable. Hysteria v1 preserves `auth_str`, bandwidth, obfs and QUIC fields; AnyTLS sets `client_metadata` to an empty string and embeds only the public certificate when `client_trust=certificate`; Snell maps inbound v5 to outbound v4 and inbound v6 to outbound v6, preserving v5 obfs host and v6 shaping; TUIC preserves congestion control, heartbeat, zero-rtt and outbound-only relay/udp-over-stream; NaiveProxy preserves username/password, TLS, QUIC and stream-window options but requires a `with_naive_outbound` build and runtime `libcronet.so`; ShadowTLS preserves version, handshake, trust, and per-user credentials; none of them exports a server private key or disables verification. For a 1.14+ Hysteria2 Ed25519 target it sets top-level `disable_chrome_parrot: true` and returns `warnings[].code=hy2_ed25519_chrome_parrot_disabled`.
- `check --json` validates the server config with `sing-box check` and returns stdout, stderr, exit code, and pass/fail state.
- `doctor --json` is read-only. It returns status, path existence checks, protocol state, and embedded config-check output for first-pass agent diagnostics.
- `service restart --json --yes` is a guarded mutation. It validates config first and skips restart when validation fails.
- `warp --json` reports Cloudflare Warp state: enabled/disabled, route mode (`all` or `selective`), account registration health, and counts for custom domains, local rule sets, remote rule sets, and builtin AI/streaming domain rules. Safe for routine diagnostics.
- `subman-sync --json` pushes eligible nodes to SubMan without prompting. Missing SubMan config is reported as structured JSON. Shadowsocks uses its dedicated integration only for encrypted entries whose network is `["tcp","udp"]`; single-network entries are skipped with `shadowsocks_uri_network_omitted`, while `none` with an empty password is parser-rejected and skipped with `shadowsocks_subman_none_unsupported`. Trojan, VMess and Hysteria2 use dedicated multi-instance, per-user paths: only lossless TLS/system-trust URIs are eligible; plaintext, certificate trust, unrepresentable transport, partial options and oversized URIs retain explicit skipped counts/warnings, including when every user is skipped. Hysteria v1, Snell, AnyTLS, TUIC, NaiveProxy and ShadowTLS are explicitly unsupported and are never sent as SubMan `other`; use outbound JSON from `links` or `export-client`. Same-snapshot mock coverage passed for VMess (`synced=3`, `skipped=1`, `failed=0`) and Hysteria2 (`synced=2`, `skipped=0`, `failed=0`); do not perform real sync without explicit authorization.
- `update sbv` updates `/usr/local/bin/sbv` from the project main branch.
- `update sing-box [latest|x.y.z]` updates only the sing-box binary, preserves the current server config byte-for-byte, validates it with `sing-box check`, and restarts the service only after validation passes. The aliases are `sbv update-sbv` and `sbv update-sing-box [latest|x.y.z]`.
- `upgrade --json 1.14.0 --yes` is the auditable Hermes path: it is mutating and service-impacting, persists a backup under `/root/sing-box-vps-backups/`, preserves `config.json` byte-for-byte, validates before restart, and attempts automatic binary recovery on failure. For an actual change, require `transaction.result_persisted=true`, then retain the referenced root-only `transaction-result.json`; it records `backup_ready` plus the terminal `success`, `rolled_back`, or `rollback_failed` state, and terminal records include `failure_reason` plus `operation_exit_code` when applicable. If the target is already installed, the no-op response instead has `changed=false`, `transaction.status=not_attempted`, `transaction.reason=already_installed`, and no backup or result file. Recovery is complete only when both `rolled_back` and `rollback_ok` are true; `error=rollback_failed` plus `manual_intervention_required=true` is a hard stop. It never silently rewrites configuration for migration. All public Agent protocol IDs include `vless-reality`, `mixed`, `socks`, `http`, `shadowsocks`, `trojan`, `vmess`, `hysteria2`, `hysteria`, `anytls`, `snell`, `tuic`, `naive` and `shadowtls`; the internal Hysteria2 state filename remains `hy2.env`. `instance` mutations for Mixed, standalone SOCKS, HTTP, Shadowsocks, Trojan, VMess, Hysteria2, Hysteria v1, AnyTLS, Snell, TUIC, NaiveProxy and ShadowTLS require `--yes` and exact `--expected-revision`; `migrate shadowsocks`, `migrate vmess`, `migrate hy2`, `migrate hysteria`, `migrate anytls`, `migrate snell`, `migrate tuic`, `migrate naive` and `migrate shadowtls` are unsupported. `export-client` and `subman-sync` are also mutating; `links`, export, and SubMan output are sensitive. Installation, protocol edits, REALITY/QoS, Warp, BBR, media checks, takeover/repair, and uninstall remain interactive-only.

## sing-box 1.14 Compatibility

- Fresh installs and regenerated configs targeting 1.14+ use top-level ACME `certificate_providers`; Hysteria2 and AnyTLS inbounds reference them through `tls.certificate_provider`.
- Remote rule sets targeting 1.14+ use `http_client.detour`. Explicitly pinned or installed 1.13.x targets retain the legacy inline `tls.acme` and rule-set layout.
- A binary-only update never migrates or rewrites the server config. The target binary must accept the existing file via `sing-box check` before the service is restarted.
- Hysteria2 manual Ed25519 certificates are detected with OpenSSL. Generated 1.14+ client outbounds receive top-level `disable_chrome_parrot: true`; share links cannot encode this field, so human and Agent interfaces emit a warning.
- If the manual certificate algorithm cannot be inspected, Agent output uses `warnings[].code=hy2_certificate_algorithm_unknown`; operators should verify the certificate and client compatibility manually.
- Inline `tls.acme` and legacy `download_detour` are deprecated in 1.14 but remain accepted for compatibility; both are scheduled for removal in 1.16. A binary-only upgrade does not migrate them.

For the complete single-host rehearsal, including stop conditions, evidence requirements, and rollback assertions, use `docs/agents/sing-box-1.13-to-1.14-upgrade-test.md`.

Common paths:

- Runtime directory: `/root/sing-box-vps/`
- Main config: `/root/sing-box-vps/config.json`
- Protocol state: `/root/sing-box-vps/protocols/`
- VLESS REALITY instance state: `/root/sing-box-vps/protocols/vless-reality.d/`
- Mixed instance state: `/root/sing-box-vps/protocols/instances/mixed.json`
- Standalone SOCKS instance state: `/root/sing-box-vps/protocols/instances/socks.json` (active marker schema 2, JSON `schema_version: 1`; lifecycle/export/runtime passed the final verification gate)
- Standalone HTTP instance state: `/root/sing-box-vps/protocols/instances/http.json` (active marker schema 2, JSON `schema_version: 1`; use the typed Agent lifecycle and manual TLS contract below)
- Shadowsocks instance state: `/root/sing-box-vps/protocols/instances/shadowsocks.json` (active marker schema 2, JSON `schema_version: 1`; use the typed Agent lifecycle and bounded export contract below)
- Trojan instance state: `/root/sing-box-vps/protocols/instances/trojan.json` (active marker `/root/sing-box-vps/protocols/trojan.env`, schema 2; JSON `schema_version: 1`; management menu 21 and typed Agent lifecycle)
- VMess instance state: `/root/sing-box-vps/protocols/instances/vmess.json` (active marker `/root/sing-box-vps/protocols/vmess.env`, schema 2; JSON `schema_version: 1`; management menu 22 and typed Agent lifecycle)
- AnyTLS instance state: `/root/sing-box-vps/protocols/instances/anytls.json` (active marker `/root/sing-box-vps/protocols/anytls.env`, schema 2; JSON `schema_version: 1`; management menu 24 and typed Agent lifecycle for the manual-TLS subset)
- Hysteria2 instance state: `/root/sing-box-vps/protocols/instances/hy2.json` (active marker `/root/sing-box-vps/protocols/hy2.env`, schema 2; JSON `schema_version: 1`; management menu 25 and typed Agent lifecycle for the manual-TLS subset)
- Hysteria v1 instance state: `/root/sing-box-vps/protocols/instances/hysteria.json` (active marker `/root/sing-box-vps/protocols/hysteria.env`, schema 2; JSON `schema_version: 1`; management menu 28 and typed Agent lifecycle for the manual-TLS QUIC subset)
- NaiveProxy instance state: `/root/sing-box-vps/protocols/instances/naive.json` (active marker `/root/sing-box-vps/protocols/naive.env`, schema 2; JSON `schema_version: 1`; management menu 29 and typed Agent lifecycle for the manual-TLS TCP/UDP subset; outbound requires `with_naive_outbound` and runtime `libcronet.so`)
- ShadowTLS instance state: `/root/sing-box-vps/protocols/instances/shadowtls.json` (active marker `/root/sing-box-vps/protocols/shadowtls.env`, schema 2; JSON `schema_version: 1`; management menu 30 and typed Agent lifecycle for the composite outer/loopback-Mixed subset; no standard URI or SubMan path)
- Snell instance state: `/root/sing-box-vps/protocols/instances/snell.json` (active marker `/root/sing-box-vps/protocols/snell.env`, schema 2; JSON `schema_version: 1`; management menu 26; typed v5/v6 lifecycle and outbound JSON, no standard URI or SubMan path)
- TUIC instance state: `/root/sing-box-vps/protocols/instances/tuic.json` (active marker `/root/sing-box-vps/protocols/tuic.env`, schema 2; JSON `schema_version: 1`; management menu 27; typed manual-TLS QUIC lifecycle and outbound JSON, no standard URI or SubMan path)
- VLESS REALITY QoS state: `/root/sing-box-vps/reality-qos.filters`
- Client export: `/root/sing-box-vps/client/sing-box-client.json`. Trojan exports one full outbound per user, preserving transport and explicit public-certificate/system trust; never exports the private key or disables verification.
- SubMan config: `/root/sing-box-vps/subman.env`
- Warp domains: `/root/sing-box-vps/warp-domains.txt`
- Global command: `/usr/local/bin/sbv`
- Agent upgrade backups: `/root/sing-box-vps-backups/` (sensitive, root-only)
- systemd service: `sing-box`

For config problems, do not guess from symptoms alone. Run `sing-box check`, inspect the generated JSON, and compare protocol state files to the runtime config.

## VLESS REALITY Multi-Instance Notes

VLESS REALITY can be installed as multiple managed instances. Each instance may have a distinct port, ShortID, node name, and optional upload/download Mbps limit. Instance state is authoritative; do not hand-edit generated `config.json` to add or remove REALITY inbounds.

When more than one REALITY instance exists, the interactive removal flow asks whether to remove one instance or the entire VLESS REALITY protocol. Confirm the scope explicitly; successful removal regenerates and validates the config, refreshes QoS, restarts the service when protocols remain, and closes ports that are no longer managed.

When diagnosing REALITY:

```bash
sbv agent nodes --json
ls -la /root/sing-box-vps/protocols/vless-reality.d 2>/dev/null || true
cat /root/sing-box-vps/reality-qos.filters 2>/dev/null || true
sing-box check -c /root/sing-box-vps/config.json
```

Use `nodes --json` for log-safe summaries. Use `links --json` only in trusted contexts because it includes full share links. If QoS or instance membership changes on production, use the production gate before running the interactive menu or guarded service mutations.

## Standalone SOCKS Inbound

Mixed/SOCKS URI userinfo is percent-encoded, preserving reserved characters and UTF-8 bytes without changing stored credentials. HTTP Basic excludes colon-containing usernames and ASCII control characters ([RFC 7617, section 2](https://www.rfc-editor.org/rfc/rfc7617#section-2)); for such Mixed credentials, `links.http` is absent and `warnings[].code=mixed_http_auth_unrepresentable`. SOCKS5 remains available. The additive `socks5_uri_transport_options_omitted` warning means a SOCKS5 URI does not carry UoT v2 client options; use `export-client` JSON instead of treating a URI as a full configuration. Percent encoding is not encryption, and links remain sensitive.

Standalone SOCKS is the fifth protocol-registry preset (`state_id=socks`, `agent_id=socks`, menu order 5). It is separate from the Mixed HTTP/SOCKS preset: the server record describes only a SOCKS4/4a/5 inbound, its listen address/port, authentication and outbound policy; it does not add HTTP or TLS. It has no legacy `.env` migration operation; a pre-existing live SOCKS configuration is handled through takeover.

The shared plain-proxy adapter uses `build_socks_inbound_json`, `save_socks_state`, `load_plain_proxy_structured_instance`, and `apply_plain_proxy_instance_change`. Its active marker is schema 2 and its JSON store (`schema_version: 1`) is `/root/sing-box-vps/protocols/instances/socks.json`; there is no `migrate socks` operation. Public Agent mutations are:

```bash
sbv agent instance create socks --json --yes --expected-revision N --file record.json
sbv agent instance replace socks --json --yes --expected-revision N --file record.json
sbv agent instance delete socks --json --yes --expected-revision N --id ID
sbv agent instance default socks --json --yes --expected-revision N --id ID
sbv agent instance recover socks --json --yes --expected-revision N
```

Use `nodes --json` to discover `instance_id`, `tag`, listen fields and `instance_revision`; use `links --json` only in a trusted context. `create` and `replace` require a complete typed record through `--file`, while `delete` and `default` use `--id`; `recover` uses the original journal revision, not a guessed current revision. All writes use the shared file/config/listener/firewall/service transaction and persistent result/journal boundaries. Client export is SOCKS5 with UoT v2 and preserves authentication, but has no TLS and no HTTP surface.

Standalone SOCKS integration passed the final local/runtime verification gate. The six focused tests (`plain_proxy_structured_store.sh`, `socks_instance_lifecycle.sh`, `socks_instance_lifecycle_runtime.sh`, `socks_instance_menu.sh`, `socks_structured_takeover.sh`, and `socks_export_client.sh`), two-core check/runtime coverage, menu 5 selection, and final Docker/TCP gate passed. The implementation record documents the remaining boundaries: no TLS/HTTP/SubMan, public native UDP unverified, and the full protocol goal unfinished.

## Shadowsocks Inbound

Shadowsocks is the registry/menu preset 7 with public protocol and Agent ID `shadowsocks`; `ss` is its public alias. This section is the `2026090802` contract for the integrated surface. Final evidence covers two core targets, all 9 methods in config checks, and four native Bash/Bash 4.2 runtime groups across 1.13.18 and 1.14, each with 7 TCP plus 7 UDP cases, including long-PSK derivation. The Docker rerun recorded 12/12 scenarios, 18/18 TCP probes, `rolled_back` and `success` rollback outcomes, and matching script/container hashes. Its active marker is `CONFIG_SCHEMA_VERSION=2`, while the typed JSON store remains `schema_version: 1` at `/root/sing-box-vps/protocols/instances/shadowsocks.json`. A live pre-existing inbound is handled by takeover; `migrate shadowsocks` is deliberately unsupported and must be rejected rather than routed through the Mixed legacy path.

The public Agent lifecycle is revision/CAS guarded and uses the same transaction boundaries as the other typed plain-proxy stores:

```bash
sbv agent instance create shadowsocks --json --yes --expected-revision N --file record.json
sbv agent instance replace shadowsocks --json --yes --expected-revision N --file record.json
sbv agent instance delete shadowsocks --json --yes --expected-revision N --id ID
sbv agent instance default shadowsocks --json --yes --expected-revision N --id ID
sbv agent instance recover shadowsocks --json --yes --expected-revision N
```

`create` and `replace` require a complete private typed record; `delete` and `default` require `--id`; `recover` uses the original journal revision. There is no `migrate shadowsocks` operation. The minimum record shape is:

```json
{
  "id": "main",
  "name": "Shadowsocks main",
  "tag": "ss-in",
  "listen": {
    "address": "127.0.0.1",
    "port": 8388,
    "network": ["tcp", "udp"]
  },
  "authentication": {
    "method": "2022-blake3-aes-128-gcm",
    "password": "<server-psk>",
    "users": [{"name": "user-1", "password": "<user-psk>"}]
  },
  "outbound_policy": "default",
  "dependencies": []
}
```

`listen.network` is a nonempty canonical subset of `tcp` and `udp`: use exactly `["tcp"]`, `["udp"]` or `["tcp","udp"]`; it is part of the inbound identity/resource plan. The default address is loopback (`127.0.0.1`). A non-loopback create/replace requires `--allow-public`; interactive management asks for the corresponding public-exposure consent. `none` is permitted only as an explicitly acknowledged plaintext transport and returns warning code `shadowsocks_plaintext_transport`.

Authentication supports classic AEAD methods (`aes-128-gcm`, `aes-192-gcm`, `aes-256-gcm`, `chacha20-ietf-poly1305`, `xchacha20-ietf-poly1305`) with one or multiple users, and 2022 AES methods (`2022-blake3-aes-128-gcm`, `2022-blake3-aes-256-gcm`) with server and user keys. `none` and `2022-blake3-chacha20-poly1305` do not support multiple users. The server/user key inputs must meet the core's method minimum (16 bytes for AES-128, 32 bytes for AES-256 or 2022 chacha); longer values are allowed and may be derived by the core. A long 2022 PSK is preserved byte-for-byte in the typed store; the client uses the equivalent fixed-length SHA-256-derived key and emits `warnings[].code=shadowsocks_2022_psk_derived`. Interactive defaults are not a schema maximum. Do not add or imply relay, mux or plugin support; fields outside this typed contract are unsupported/rejected.

`nodes --json` must keep Shadowsocks summaries credential-free: the SS authentication/network details are only `method`, `user_count`, `network` and the instance `revision` (serialized as `instance_revision` in the Agent payload, alongside generic non-secret identity); server PSKs and user passwords/keys are never returned. `links --json` is sensitive and returns the SS object shape `{"links":{"<stable-outbound-tag>":"<uri>"},"outbounds":[...],"warnings":[...]}`. A SIP002 URI cannot express a single-network restriction. For `["tcp"]` or `["udp"]`, emit `warnings[].code=shadowsocks_uri_network_omitted` and use the complete JSON client export when the restriction must be preserved. The `none` warning is also carried in the link response where applicable.

Shadowsocks has a dedicated SubMan path for encrypted SIP002-representable dual-network entries. Single-network entries are skipped with the `shadowsocks_uri_network_omitted` warning because the restriction cannot be encoded. `none` with an empty password is rejected by the current SubMan parser and skipped with `shadowsocks_subman_none_unsupported`. Same-snapshot mock coverage passed with `synced=2`, `skipped=2`, `failed=0`; this is local mock evidence, not a real authorized synchronization.

Protocol-wide removal already short-circuits an active schema-2 Shadowsocks store in `remove_protocol_menu` to `shadowsocks_instance_management_menu delete`; the bulk legacy `PORT`/`close_firewall_port` cleanup is therefore not entered for active SS. Preserve this guard for HTTP/SOCKS/SS and keep instance create/replace/delete/default/recover on the plan-aware `apply_plain_proxy_instance_change` transaction. The remaining old port-only cleanup applies only to non-structured legacy paths; it is not a precise ownership ledger.

Recorded verification boundary: final script hash `8d24fa6e`; the focused two-core/9-method checks and four native Bash/Bash 4.2 runtime groups (7 TCP plus 7 UDP per group) passed, including long-PSK derivation. The Docker rerun at `dev/verification-runs/20260908055118` used `VERIFY_SKIP_LOCAL_TESTS=1` and passed 12/12 scenarios and 18/18 TCP probes, with rollback outcomes `rolled_back` and `success` and matching script/container hashes. The default first gate stopped on an old test assertion; the ordinary 182-item run then fixed five failures and reran affected tests, with 16 framework items passing, but no complete 182-item rerun followed the local SubMan fix. Same-snapshot SubMan mock coverage passed with `synced=2`, `skipped=2`, `failed=0`; real synchronization still requires explicit authorization. The [implementation record](../superpowers/plans/2026-09-06-unified-protocol-management.md) documents these evidence limits. This is not a new full local 85-test pass and does not imply unsupported relay, mux, plugin or other unmodeled fields.

## Standalone HTTP Inbound

`http` is registry preset 6 and management menu 19, separate from Mixed and SOCKS. Its schema-2 marker references `protocols/instances/http.json` (`schema_version:1`). Use the same `instance create|replace|delete|default|recover http --json --yes --expected-revision N` contract; create/replace require `--file`, delete/default require `--id`. No legacy `migrate http` exists. Takeover preserves supported live HTTP authentication, tags, listener, policy and TLS references, and rejects unsupported fields rather than discarding them.

The complete record has the common instance fields plus a required `tls` object. Plain example:

```json
{
  "id": "main", "name": "Private HTTP", "tag": "http-in",
  "listen": {"address": "127.0.0.1", "port": 18080},
  "authentication": {"enabled": true, "username": "proxy-user", "password": "replace-with-a-secret"},
  "tls": {"enabled": false},
  "outbound_policy": "default", "dependencies": []
}
```

For TLS replace the entire `tls` value with `{"enabled":true,"server_name":"proxy.example.com","certificate_path":"/etc/proxy/server.crt","key_path":"/etc/proxy/server.key"}`. Supply valid existing certificate/key files; this preset does not issue ACME certificates, mutate the files, or delete them when an instance is removed. Unsupported TLS/provider/transport fields are rejected. Validate referenced files with the target core before publication. Non-loopback writes still require `--allow-public`; new interactive instances default to loopback and authentication. HTTP Basic rejects colons in usernames and ASCII controls in either credential; it does not impose SOCKS's 255-byte credential limit.

The client uses `type:http`, HTTP CONNECT and TCP only, not SOCKS/UoT. Entry TLS is independent of a destination website using HTTPS. TLS export embeds only public certificate trust and server name, never the server private key. Plain links use encoded `http://` userinfo and return `http_plaintext_transport`: use only trusted networks or protected tunnels. TLS trust cannot be carried faithfully in that URI, so TLS links are omitted with `http_tls_uri_unrepresentable` and callers should use `export-client`; TLS node summaries have `shareable=false` and `client_exportable=true`. HTTP is not synchronized to SubMan. `nodes` remains a credential-free summary; `links` and client exports are sensitive. This HTTP preset does not claim all upstream HTTP options or completion of the full protocol goal.

## WARP Operations

WARP state can be inspected non-interactively:

```bash
sbv agent warp --json
```

This returns `enabled`, `route_mode`, account registration health, and routing asset counts (custom domains, local/remote rule sets, builtin AI/streaming rules) plus related file paths.

`status --json` also includes a `warp` block with `enabled` and `route_mode`.

To change WARP state (enable/disable, mode switch, re-register, add domains or rule sets), use the interactive menu:

```bash
sbv
# Navigate: 13 -> Cloudflare Warp
```

On production, WARP mutations are production-changing operations. Use the production gate first.

## Client Export And SubMan

Use client export when an agent or client needs a full sing-box bare-core config:

```bash
sbv agent export-client --json
```

The command writes `/root/sing-box-vps/client/sing-box-client.json`, creates a `.bak` when replacing an existing export, and validates the generated config before returning success. Treat the returned JSON as sensitive because it contains usable connection credentials.

Use SubMan sync only when `/root/sing-box-vps/subman.env` is configured and the output context is trusted:

```bash
sbv agent subman-sync --json
```

SubMan sync is non-interactive for agents and pushes VLESS REALITY and Hysteria2 nodes idempotently, plus SIP002-representable encrypted Shadowsocks dual-network entries through its dedicated path; single-network entries are skipped and `none` with an empty password returns `shadowsocks_subman_none_unsupported`. Missing API configuration is reported as structured JSON rather than prompting. Same-snapshot mock coverage passed with `synced=2`, `skipped=2`, `failed=0`; real synchronization still requires explicit authorization.

## Rollback And Recovery

The guarded Agent upgrade attempts to restore the old binary automatically when its target validation or postconditions fail. First inspect `error`, `failure_reason`, `rollback_attempted`, `rolled_back`, `rollback_ok`, `manual_intervention_required`, `installed`, `config_preserved`, `service`, the exact `backup` path, and `transaction.{id,result_path,status,result_persisted,manifest,rollback}` in its JSON result. Agent `--json` responses use `schema_version: "1.0"` while retaining top-level `schema: "1"` compatibility. For an actual change, a false `transaction.result_persisted` is a failed operation even if the runtime postconditions otherwise succeeded; an already-installed no-op is the explicit exception described above.

Manual recovery is only for `rollback_ok=false`. Validate the returned path prefix and its manifest before copying anything; on production, present these exact commands in a new plan and wait for approval:

```bash
systemctl stop sing-box
backup=/root/sing-box-vps-backups/upgrade-EXACT-DIRECTORY-FROM-JSON
case "${backup}" in /root/sing-box-vps-backups/upgrade-*) ;; *) exit 1 ;; esac
(cd "${backup}" && sha256sum -c SHA256SUMS)
install -m 0755 "${backup}/sing-box" /usr/local/bin/sing-box
install -m 0644 "${backup}/sing-box.service" /etc/systemd/system/sing-box.service
install -m 0600 "${backup}/runtime/config.json" /root/sing-box-vps/config.json
systemctl daemon-reload
/usr/local/bin/sing-box check -c /root/sing-box-vps/config.json
systemctl start sing-box
systemctl status sing-box --no-pager
```

## Trojan typed instance contract

Trojan uses public/state ID `trojan`, preset 8, management menu 21 and the shared instance transaction. It is separate from VMess and the legacy VLESS REALITY alias. The store is `protocols/instances/trojan.json` (`schema_version:1`) with the standard active `CONFIG_SCHEMA_VERSION=2` marker. There is no legacy Trojan migration operation; unsupported live fields must block lossy takeover. Generic edit/remove menus route Trojan through this same instance transaction, never the legacy singleton rewrite path.

```bash
sbv agent instance create trojan --json --yes --expected-revision 0 --file record.json
sbv agent instance replace trojan --json --yes --expected-revision N --file record.json
sbv agent instance default trojan --json --yes --expected-revision N --id main
sbv agent instance delete trojan --json --yes --expected-revision N --id main
sbv agent instance recover trojan --json --yes --expected-revision N
```

Use a private record file, for example:

```json
{
  "id": "main",
  "name": "Trojan main",
  "tag": "trojan-in",
  "listen": {"address": "127.0.0.1", "port": 8443},
  "authentication": {"users": [{"name": "first", "password": "replace-with-a-private-password"}]},
  "tls": {
    "enabled": true,
    "server_name": "proxy.example.com",
    "certificate_path": "/etc/ssl/certs/proxy.pem",
    "key_path": "/etc/ssl/private/proxy.key"
  },
  "client_trust": "certificate",
  "transport": {"type": "none"},
  "outbound_policy": "default",
  "dependencies": []
}
```

Authentication contains 1–128 users with unique names and passwords. Names are stable user identities; editing unrelated fields must not rotate credentials. TLS uses administrator-provided certificate/key references. `client_trust:"certificate"` embeds only the public certificate in client exports; `"system"` explicitly chooses the client's system trust store and must not be inferred from a certificate filename. Disabled TLS requires `client_trust:"system"` and is not encrypted; non-loopback changes require the public-exposure confirmation.

Managed transport types are internal `none` (omitted from core JSON), HTTP, WebSocket without early data, gRPC and TLS-only QUIC. QUIC owns a UDP listener; other transports own TCP listeners, while both can carry TCP/UDP business traffic. Plaintext client JSON omits `tls` entirely: the pinned Trojan cores must not receive an explicit disabled TLS object, which can create an invalid TLS dialer despite passing `check`. HTTPUpgrade and WebSocket early data remain blocked by the previously reproduced runtime defects. REALITY, Vision, fallback and multiplex are not silently accepted as generic Trojan options. Takeover accepts only ALPN matching the managed transport profile; arbitrary ALPN is not discarded.

`nodes`/`status` are safe summaries, not complete transport records: authentication secrets and custom request headers must not leak. `links` and `export-client` are sensitive. Client exports are per-user complete outbounds with stable tags, matching transport/ALPN and strict trust; server private keys are never copied. Share/SubMan candidates require enabled TLS, explicit system trust and losslessly expressible transport fields. Plaintext, certificate-trust exports, custom headers and unsupported transport options return explicit warnings/skips instead of incomplete URIs. This is a local/mock integration contract, not proof of production reachability or an authorized real SubMan synchronization.

## VMess typed instance contract

VMess uses public/state ID `vmess`, preset 9, management menu 22 and the shared instance transaction. It is separate from the legacy VLESS REALITY alias. The store is `protocols/instances/vmess.json` (`schema_version:1`) with the active `CONFIG_SCHEMA_VERSION=2` marker in `vmess.env`; there is no legacy VMess migration operation. Unsupported live fields block takeover rather than being discarded.

```bash
sbv agent instance create vmess --json --yes --expected-revision 0 --file record.json
sbv agent instance replace vmess --json --yes --expected-revision N --file record.json
sbv agent instance default vmess --json --yes --expected-revision N --id main
sbv agent instance delete vmess --json --yes --expected-revision N --id main
sbv agent instance recover vmess --json --yes --expected-revision N
```

The private typed record contains the common `id`, `name`, `tag`, `listen`, `outbound_policy` and `dependencies` fields plus VMess-specific authentication, TLS and transport:

```json
{
  "id": "main",
  "name": "VMess main",
  "tag": "vmess-in",
  "listen": {"address": "127.0.0.1", "port": 1085},
  "authentication": {
    "users": [{"name": "first", "uuid": "replace-with-a-private-uuid", "alter_id": 0, "security": "auto"}]
  },
  "tls": {"enabled": true, "server_name": "proxy.example.com", "certificate_path": "/etc/ssl/certs/proxy.pem", "key_path": "/etc/ssl/private/proxy.key"},
  "client_trust": "certificate",
  "transport": {"type": "none"},
  "outbound_policy": "default",
  "dependencies": []
}
```

Authentication accepts 1–128 users with unique names and UUIDs. `security` is one of `auto`, `none`, `zero`, `aes-128-cfb`, `aes-128-gcm` or `chacha20-poly1305`; `alter_id` is an integer from 0 through 65535 and is rendered as core field `alterId`. Managed transports are `none`, HTTP, WebSocket without early data, gRPC and TLS-only QUIC. QUIC owns a UDP listener; the other transports own TCP listeners while the VMess business network remains TCP/UDP. HTTPUpgrade and WebSocket early data stay blocked by the known runtime guards.

TLS is explicit. `client_trust:"certificate"` embeds only the public certificate in client exports; `"system"` uses the client's system trust store. Plaintext exports omit `tls`, and no path ever copies the server private key or disables verification. VMess links use standard `vmess://` JSON with only losslessly representable transport fields; unsupported HTTP headers, methods, early data or oversized values fail closed. `nodes` remains credential-free, while `links` and `export-client` are sensitive.

SubMan synchronization is a dedicated per-instance/per-user path. Only enabled TLS with explicit system trust and a losslessly representable URI is synchronized; plaintext, certificate trust, unsupported transport and oversized URI entries are returned as structured skips. Focused native 1.13.18/1.14.0 check/export coverage and local lifecycle/takeover/Agent/share/SubMan/probe tests passed; this is local/mock evidence, not proof of public reachability or an authorized real SubMan synchronization.

## AnyTLS typed instance contract

AnyTLS uses public/state ID `anytls`, preset 4 and management menu 24. Its active marker is `protocols/anytls.env` with `CONFIG_SCHEMA_VERSION=2`; the typed store is `protocols/instances/anytls.json` with `schema_version:1`. The legacy schema-1 state remains available for ACME HTTP-01, Cloudflare DNS-01 and manual certificate generation. Typed instance takeover is intentionally limited to a lossless manual-TLS representation; an ACME/provider inbound is rejected and left untouched rather than flattened into an incomplete record.

```bash
sbv agent instance create anytls --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance replace anytls --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance default anytls --json --yes --expected-revision N --id main
sbv agent instance delete anytls --json --yes --expected-revision N --id main
sbv agent instance recover anytls --json --yes --expected-revision N
```

The private record contains the common `id`, `name`, `tag`, `listen`, `outbound_policy` and `dependencies` fields plus AnyTLS authentication, TLS and client trust:

```json
{
  "id": "main",
  "name": "AnyTLS main",
  "tag": "anytls-in",
  "listen": {"address": "127.0.0.1", "port": 8443},
  "authentication": {"users": [{"name": "first", "password": "replace-with-a-private-password"}]},
  "tls": {
    "enabled": true,
    "server_name": "proxy.example.com",
    "certificate_path": "/etc/ssl/certs/proxy.pem",
    "key_path": "/etc/ssl/private/proxy.key"
  },
  "client_trust": "certificate",
  "outbound_policy": "default",
  "dependencies": []
}
```

Authentication accepts 1–128 users with unique names and passwords. TLS is always enabled in the typed record and must use exactly `server_name`, `certificate_path` and `key_path`; the files are administrator-owned and are never issued, copied into the client export, or deleted by lifecycle operations. The AnyTLS listener is TCP; UDP business traffic uses the client/server UoT adapter rather than a native UDP listener. `client_trust:"certificate"` embeds only the public PEM in each client outbound, while `"system"` uses the client system trust store. AnyTLS has no standard share URI: `nodes` is credential-free, and `links` returns `links:{}`, per-user outbound JSON, and `warnings[].code=anytls_standard_uri_unavailable`. Client outbounds set `client_metadata` to an empty string, preserve the password, and never disable verification or include a private key. Non-loopback writes require `--allow-public`; lifecycle, export and Agent tests are local/mock evidence and do not prove public reachability or real SubMan synchronization.

## Hysteria2 typed instance contract

Hysteria2 uses public Agent ID `hysteria2`, internal/state ID `hy2`, preset 3 and management menu 25. Its active marker is `protocols/hy2.env` with `CONFIG_SCHEMA_VERSION=2`; the typed store is `protocols/instances/hy2.json` with `schema_version:1`. Legacy schema-1 Hysteria2 remains available for ACME HTTP-01, Cloudflare DNS-01 and certificate-provider configurations. Takeover preserves that legacy path; the typed store is used only when the live inbound is a lossless manual-TLS representation or when multiple Hysteria2 inbounds require structured identity.

```bash
sbv agent instance create hy2 --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance replace hy2 --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance default hy2 --json --yes --expected-revision N --id main
sbv agent instance delete hy2 --json --yes --expected-revision N --id main
sbv agent instance recover hy2 --json --yes --expected-revision N
```

The private record contains the common `id`, `name`, `tag`, `listen`, `outbound_policy` and `dependencies` fields plus Hysteria2 authentication, manual TLS, client trust, bandwidth, obfuscation and masquerade:

```json
{
  "id": "main",
  "name": "Hysteria2 main",
  "tag": "hy2-in",
  "listen": {"address": "127.0.0.1", "port": 8443},
  "authentication": {"users": [{"name": "first", "password": "replace-with-a-private-password"}]},
  "tls": {
    "enabled": true,
    "server_name": "proxy.example.com",
    "certificate_path": "/etc/ssl/certs/proxy.pem",
    "key_path": "/etc/ssl/private/proxy.key"
  },
  "client_trust": "system",
  "bandwidth": {"up_mbps": 100, "down_mbps": null},
  "obfs": {"enabled": true, "type": "salamander", "password": "replace-with-an-obfs-password"},
  "masquerade": "https://example.com",
  "outbound_policy": "default",
  "dependencies": []
}
```

Authentication accepts 1–128 unique names and passwords. TLS is always enabled and manual in schema 2; certificate paths remain administrator-owned and are never copied into a URI, issued, or deleted by lifecycle operations. `up_mbps` and `down_mbps` are independently optional positive integers. `obfs` is either disabled with empty fields or enabled as Salamander. The typed renderer emits UDP Hysteria2 inbounds with `alpn:["h3"]` and preserves bandwidth, obfs and masquerade.

Client exports contain one Hysteria2 outbound per user. `client_trust:"certificate"` embeds only the public certificate; `system` uses system trust. On 1.14+ an Ed25519 manual certificate adds `disable_chrome_parrot:true` to the client outbound and returns a structured compatibility warning for share links. Standard `hy2://` links are generated per user when system trust is selected; certificate trust, oversized URIs, and options that a standard URI cannot fully carry are reported as explicit warnings. `nodes` is credential-free, while `links`, `export-client` and SubMan payloads are sensitive.

SubMan synchronization is a dedicated per-instance/per-user path. Only system-trust users with a representable URI are pushed; certificate-trust users are skipped with a stable reason. Bandwidth and masquerade remain in the client JSON but produce a partial-URI warning. Non-loopback writes require `--allow-public`; lifecycle, export, Agent and SubMan tests are local/mock evidence and do not prove public reachability or an authorized real SubMan synchronization.

## Hysteria typed instance contract

Hysteria v1 uses public/state/Agent ID `hysteria`, registry preset 13 and management menu 28. Its active marker is `protocols/hysteria.env` with `CONFIG_SCHEMA_VERSION=2`; the typed store is `protocols/instances/hysteria.json` with `schema_version:1`. There is no legacy Hysteria `.env` migration path, so `migrate hysteria` is rejected; existing live Hysteria configuration is accepted only when every modeled field is losslessly representable by the typed manual-TLS QUIC record. Hysteria v1 is separate from Hysteria2: its users use `auth_str`, its obfs is a string password, and it does not use Hysteria2's `masquerade` or Salamander object.

```bash
sbv agent instance create hysteria --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance replace hysteria --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance default hysteria --json --yes --expected-revision N --id main
sbv agent instance delete hysteria --json --yes --expected-revision N --id main
sbv agent instance recover hysteria --json --yes --expected-revision N
```

The private record contains the common `id`, `name`, `tag`, `listen`, `outbound_policy` and `dependencies` fields plus Hysteria authentication, manual TLS, client trust, bandwidth, obfs and QUIC options:

```json
{
  "id": "main",
  "name": "Hysteria main",
  "tag": "hysteria-in",
  "listen": {"address": "127.0.0.1", "port": 8443},
  "authentication": {"users": [{"name": "first", "auth_str": "replace-with-a-private-auth-string"}]},
  "tls": {
    "enabled": true,
    "server_name": "proxy.example.com",
    "certificate_path": "/etc/ssl/certs/proxy.pem",
    "key_path": "/etc/ssl/private/proxy.key"
  },
  "client_trust": "system",
  "bandwidth": {"up_mbps": 100, "down_mbps": 200},
  "obfs": {"enabled": false, "password": ""},
  "hysteria": {
    "connection_receive_window": "",
    "disable_path_mtu_discovery": false,
    "initial_packet_size": 0,
    "max_concurrent_streams": 0,
    "stream_receive_window": ""
  },
  "outbound_policy": "default",
  "dependencies": []
}
```

Authentication accepts 1–128 unique names and `auth_str` values. TLS is always enabled and manual in schema 2; certificate paths remain administrator-owned and are never issued, copied into a client outbound, or deleted by lifecycle operations. `up_mbps` and `down_mbps` are required positive integers. When enabled, `obfs` renders as the Hysteria v1 password string; disabled obfs is omitted. The typed renderer emits a UDP/QUIC `type:"hysteria"` inbound with `alpn:["h3"]`, users, bandwidth and only non-default QUIC fields. Window values are bounded strings with an optional byte unit (`B`, `KB`, `MB` or `GB`); pure numeric strings are rejected so they are not confused with the core's integer form. `client_trust:"certificate"` embeds only the public certificate in each client outbound, while `system` uses the client system trust store.

Client export contains one Hysteria outbound per user with `auth_str`, bandwidth, optional obfs password and typed QUIC fields. `nodes` never exposes auth strings. Hysteria v1 has no lossless standard share URI or QR representation: `links` returns `links:{}`, complete outbound JSON and `warnings[].code=hysteria_standard_uri_unavailable`. Hysteria is not advertised to SubMan and is skipped rather than sent as `other`. Non-loopback writes require `--allow-public`; the focused lifecycle test uses local/mock service and firewall boundaries plus an optional sing-box 1.14 target `check`, so it does not prove public UDP reachability, UDP data-plane behavior, production deployment or real SubMan synchronization.

## NaiveProxy typed instance contract

NaiveProxy uses public/state/Agent ID `naive`, registry preset 14 and management menu 29. Its active marker is `protocols/naive.env` with `CONFIG_SCHEMA_VERSION=2`; the typed store is `protocols/instances/naive.json` with `schema_version:1`. There is no legacy NaiveProxy `.env` migration path, so `migrate naive` is rejected; existing live Naive configuration is accepted only when every modeled field is losslessly representable by the typed manual-TLS TCP/UDP record. The server and client roles are deliberately separate: Naive inbound needs TLS, while Naive outbound additionally requires an official build with `with_naive_outbound` and the `libcronet.so` runtime library.

```bash
sbv agent instance create naive --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance replace naive --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance default naive --json --yes --expected-revision N --id main
sbv agent instance delete naive --json --yes --expected-revision N --id main
sbv agent instance recover naive --json --yes --expected-revision N
```

The private record contains the common `id`, `name`, `tag`, `listen`, `outbound_policy` and `dependencies` fields plus Naive authentication, manual TLS, client trust, listener network and client-only options:

```json
{
  "id": "main",
  "name": "NaiveProxy main",
  "tag": "naive-in",
  "listen": {"address": "127.0.0.1", "port": 8443, "network": ["tcp", "udp"]},
  "authentication": {"users": [{"name": "first", "username": "proxy-user", "password": "replace-with-a-private-password"}]},
  "tls": {
    "enabled": true,
    "server_name": "proxy.example.com",
    "certificate_path": "/etc/ssl/certs/proxy.pem",
    "key_path": "/etc/ssl/private/proxy.key"
  },
  "client_trust": "system",
  "naive": {
    "quic_congestion_control": "bbr",
    "quic": false,
    "insecure_concurrency": 0,
    "stream_receive_window": "",
    "quic_session_receive_window": "",
    "extra_headers": {}
  },
  "outbound_policy": "default",
  "dependencies": []
}
```

Authentication accepts 1–128 unique `username`/`password` pairs. TLS is always enabled and manual in schema 2; certificate paths remain administrator-owned and are never issued, copied into an outbound, or deleted by lifecycle operations. `listen.network` is the canonical nonempty subset `["tcp"]`, `["udp"]` or `["tcp","udp"]`; a single-network inbound renders the sing-box scalar `network` field, while both networks omit it. `quic_congestion_control` accepts `bbr`, `cubic` or `reno`; `quic` and the receive-window/concurrency/header options are retained for client export. `client_trust:"certificate"` embeds only the public certificate in each client outbound, while `system` uses the client trust store.

Client export contains one Naive outbound per user with server, port, username/password, TLS trust and the stored Naive/QUIC options. `nodes` never exposes usernames or passwords. NaiveProxy has no lossless standard share URI or QR representation: `links` returns `links:{}`, complete outbound JSON and `warnings[].code=naive_standard_uri_unavailable`, plus `naive_libcronet_required` to make the optional runtime dependency explicit. The installer stages the official archive's `libcronet.so` atomically at `/usr/local/lib/libcronet.so`, records its SHA-256 under the managed project directory and refreshes the loader cache; core-upgrade backups include the library and marker and restore them with the binary when config/check/service validation fails. An unowned existing library is preserved and uninstall removes only a hash-matching managed copy. NaiveProxy is not advertised to SubMan and is skipped rather than sent as `other`. Non-loopback writes require `--allow-public`. Docker run `20260912014158` proved a single TCP Naive instance through the fixed 1.14.0 server/client `check`, official `libcronet.so`, TLS/HTTP2, loopback SOCKS and an exact HTTP marker; strict rendered-config and library-hash assertions were re-run in `20260912022837`. The focused lifecycle test and this probe do not prove Naive UDP/HTTP3, public reachability, production deployment or real SubMan synchronization.

## ShadowTLS typed instance contract

ShadowTLS uses public/state/Agent ID `shadowtls`, registry preset 15 and management menu 30 with a schema-1 JSON store and schema-2 active marker. It is a composite inbound: each typed instance renders one `type:"shadowtls"` outer listener and one private loopback `type:"mixed"` detour whose tag is `shadowtls-inner-<id>`. The typed lifecycle supports `create`/`replace`/`delete`/`default`/`recover` with exact revision CAS; `migrate shadowtls` is rejected because there is no legacy singleton state path.

```bash
sbv agent instance create shadowtls --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance replace shadowtls --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance default shadowtls --json --yes --expected-revision N --id main
sbv agent instance delete shadowtls --json --yes --expected-revision N --id main
sbv agent instance recover shadowtls --json --yes --expected-revision N
```

The private record contains common `id`, `name`, `tag`, `listen`, `outbound_policy` and `dependencies` fields plus ShadowTLS authentication, handshake and client settings:

```json
{
  "id": "main",
  "name": "ShadowTLS main",
  "tag": "shadowtls-in",
  "listen": {"address": "127.0.0.1", "port": 8443},
  "version": 3,
  "authentication": {"password": "", "users": [{"name": "first", "password": "replace-with-a-private-password"}]},
  "handshake": {"server": "www.apple.com", "server_port": 443},
  "handshake_for_server_name": {},
  "strict_mode": false,
  "wildcard_sni": "off",
  "detour": {"tag": "shadowtls-inner-main", "listen": {"address": "127.0.0.1", "port": 9443}},
  "dependencies": ["shadowtls-inner-main"],
  "client_trust": "system",
  "client_tls": {"server_name": "www.apple.com", "certificate_path": ""},
  "outbound_policy": "default"
}
```

Client export contains a two-part chain per user: a ShadowTLS transport outbound for the outer listener and an HTTP primary outbound whose `detour` points to that transport while targeting the loopback Mixed listener. `build_singbox_client_config` and Agent links retain both outbounds, but selector/tag projections expose only the HTTP primary tag; the transport dependency is never silently dropped. `nodes` never exposes usernames or passwords. Version 1 has no password or users, version 2 has one password, and version 3 has 1–128 unique name/password users. Version 2/3 may carry SNI-specific handshake mappings; version 3 additionally carries `strict_mode` and `wildcard_sni` (`off`, `authed`, `all`). The detour is always loopback and must use a distinct TCP port. `client_trust:"certificate"` embeds only the public certificate in each client outbound; `system` uses the client trust store. ShadowTLS has no lossless standard URI or QR representation: `links` returns `links:{}`, complete per-user transport-plus-HTTP outbound JSON, `primary_outbound_tags`, and `warnings[].code=shadowtls_standard_uri_unavailable`; it is not sent to SubMan. Docker run `20260912001650` proved the generated chain with fixed 1.14.0 `check`, a temporary SAN TLS cover, the outer ShadowTLS listener, loopback Mixed detour and an exact HTTP marker in both `multi_protocol_coexistence` and `runtime_smoke`; the evidence is limited to an isolated container/loopback and does not prove public reachability, an external handshake service, production deployment or real SubMan synchronization.

## TUIC typed instance contract

TUIC uses public/state/Agent ID `tuic`, registry preset 12 and management menu 27. Its active marker is `protocols/tuic.env` with `CONFIG_SCHEMA_VERSION=2`; the typed store is `protocols/instances/tuic.json` with `schema_version:1`. There is no legacy TUIC `.env` migration path, so `migrate tuic` is rejected; existing live TUIC configuration is accepted only when every modeled field is losslessly representable by the typed manual-TLS QUIC record.

```bash
sbv agent instance create tuic --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance replace tuic --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance default tuic --json --yes --expected-revision N --id main
sbv agent instance delete tuic --json --yes --expected-revision N --id main
sbv agent instance recover tuic --json --yes --expected-revision N
```

The private record contains the common `id`, `name`, `tag`, `listen`, `outbound_policy` and `dependencies` fields plus TUIC authentication, manual TLS, client trust and QUIC options:

```json
{
  "id": "main",
  "name": "TUIC main",
  "tag": "tuic-in",
  "listen": {"address": "127.0.0.1", "port": 8443},
  "authentication": {"users": [{"name": "first", "uuid": "replace-with-a-private-uuid", "password": "replace-with-a-private-password"}]},
  "tls": {
    "enabled": true,
    "server_name": "proxy.example.com",
    "certificate_path": "/etc/ssl/certs/proxy.pem",
    "key_path": "/etc/ssl/private/proxy.key"
  },
  "client_trust": "system",
  "tuic": {
    "auth_timeout_seconds": 3,
    "congestion_control": "bbr",
    "heartbeat_seconds": 10,
    "udp_over_stream": false,
    "udp_relay_mode": "native",
    "zero_rtt_handshake": false
  },
  "outbound_policy": "default",
  "dependencies": []
}
```

Authentication accepts 1–128 unique names and UUID/password pairs. TLS is always enabled and manual in schema 2; certificate paths remain administrator-owned and are never issued, copied into a client outbound, or deleted by lifecycle operations. The server renderer emits a TUIC UDP/QUIC inbound with `alpn:["h3"]`, users, congestion control, `auth_timeout`, `heartbeat` and `zero_rtt_handshake`. `udp_relay_mode` and `udp_over_stream` are outbound-only sing-box fields and are deliberately not rendered in the inbound; retaining them in the typed record allows faithful client export. `client_trust:"certificate"` embeds only the public certificate in each client outbound, while `system` uses the client system trust store.

Client export contains one TUIC outbound per user with `network:["tcp","udp"]`, UUID/password, congestion control, heartbeat, zero-rtt and the selected outbound-only `udp_relay_mode` or `udp_over_stream`; the exporter also emits `tls.alpn:["h3"]` to match the server renderer. `nodes` never exposes UUIDs or passwords. TUIC has no standard share URI or QR representation: `links` returns `links:{}`, complete outbound JSON and `warnings[].code=tuic_standard_uri_unavailable`. TUIC is not advertised to SubMan and is skipped rather than sent as `other`. Non-loopback writes require `--allow-public`; the focused lifecycle test and Docker run `dev/verification-runs/20260911164148` cover target-core checks plus a container-local SOCKS5 UDP marker round trip, but do not prove public UDP reachability, production deployment or real SubMan synchronization.

## Snell typed instance contract

Snell uses public/state/Agent ID `snell`, registry preset 11 and management menu 26. Its active marker is `protocols/snell.env` with `CONFIG_SCHEMA_VERSION=2`; the typed store is `protocols/instances/snell.json` with `schema_version:1`. Snell is a sing-box 1.14-only inbound in this project: the listener is TCP, and UDP proxy traffic relies on Snell's packet API over the TCP session. There is no legacy Snell `.env` migration path, so `migrate snell` is rejected; existing live Snell configuration is accepted only when every field is losslessly representable by the typed record.

```bash
sbv agent instance create snell --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance replace snell --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance default snell --json --yes --expected-revision N --id main
sbv agent instance delete snell --json --yes --expected-revision N --id main
sbv agent instance recover snell --json --yes --expected-revision N
```

The private record contains the common `id`, `name`, `tag`, `listen`, `outbound_policy` and `dependencies` fields plus Snell version, PSK, optional users, and version-specific shaping:

```json
{
  "id": "main",
  "name": "Snell main",
  "tag": "snell-in",
  "listen": {"address": "127.0.0.1", "port": 8443},
  "version": 6,
  "authentication": {
    "psk": "replace-with-a-private-psk",
    "users": [{"name": "first", "userkey": "replace-with-a-private-user-key"}]
  },
  "obfs_mode": "",
  "obfs_host": "",
  "mode": "default",
  "outbound_policy": "default",
  "dependencies": []
}
```

`version` is `5` or `6`. Version 5 uses `obfs_mode:"none"` or `"http"`; HTTP mode keeps an `obfs_host` hint for client export, while the inbound renderer emits only fields accepted by the Snell server. Version 6 clears v5 fields and uses `mode:"default"`, `"unshaped"` or `"unsafe-raw"`; its PSK must be 12–255 UTF-8 bytes. Authentication accepts zero to 128 unique `name`/`userkey` pairs; with no users, the PSK itself is used by the exported client. Client export maps inbound v5 to outbound v4 and inbound v6 to outbound v6, emits explicit `network:["tcp","udp"]` and preserves each user key. `nodes` never exposes PSKs or user keys. Snell has no lossless standard share URI, so `links` returns `links:{}`, full outbound JSON and `warnings[].code=snell_standard_uri_unavailable`; SubMan deliberately does not advertise Snell as `other`. Non-loopback writes require `--allow-public`. The focused lifecycle test uses mock service/firewall boundaries and an optional target-core `check`; Docker now separately exercises both v6 and v5 UDP packet API paths through the authenticated TCP session, but neither path proves public reachability or real SubMan synchronization.

## 2026-09-11：Hysteria v1/Hysteria2 Docker 数据面探针

`fresh_install_hysteria` 远程场景现在生成持久于验证容器生命周期的自签名 SAN 证书，安装 Hysteria v1 后用受管状态导出单用户客户端；导出器保留 `auth_str`、`up_mbps/down_mbps`、公开证书（不含私钥）和显式 `h3` ALPN。固定 1.14.0 核心的服务端 UDP listener、客户端 SOCKS listener、HTTP marker 与 SOCKS5 UDP ASSOCIATE marker 均在 Docker 回环内通过；`multi_protocol_coexistence` 对 Hysteria2、SS2022、Trojan QUIC、TUIC 与 VMess QUIC 也完成同一 UDP marker 回环，TUIC/VMess 客户端 exporter 的 `h3` ALPN 与服务端协商保持一致，同时 VMess/VLESS QUIC exporter 保留 `tcp+udp` proxy network。`fresh_install_vless_plain` 还验证同一受管实例从 TCP/none 替换为 TLS QUIC、协议索引保持 `vless-plain`，并完成 UDP marker 回环。完整 run `dev/verification-runs/20260911215408` 记录 15/15 场景、24 个常规协议探针结果（23/23 可执行探针成功，1 个既有 TUIC 结果为 `unsupported`），七个 `udp.result.env` 均为 `RESULT=success`，精确 payload 保存在对应 `udp-response.txt`。QUIC 选项输入允许 `0` 表示上游默认；这些结果仍只证明隔离容器/回环业务路径，不证明公网、生产、外部控制面或全协议目标完成。
## 2026-09-11：Snell v6 TCP 数据面探针

`multi_protocol_coexistence` 现在在 VMess 之后创建受管 Snell v6 typed instance（PSK、单用户 key、`mode:"default"`、TCP listener），并把 `snell` 加入 live protocol index 与配置类型断言。远程 entrypoint 先要求活动 schema-2 marker 和 schema-1 Snell store，严格核对选中的 tag、监听端口、版本、认证和 shaping 字段，再调用生产 `build_client_snell_outbounds` 生成探针副本；固定 1.14.0 客户端通过 `sing-box check` 后，经本地 SOCKS listener 访问 HTTP marker，`client.json` 保持 600 权限且不携带服务端私钥。

完整 Docker run `dev/verification-runs/20260911230518` 记录 15/15 场景、25 个常规 protocol result，其中 24/24 可执行探针成功，既有 TUIC 常规结果仍为 `unsupported`；共存场景的 Snell `result.env`、`client.check.txt`、精确 `http-response.txt` 和 typed index/store 均通过。七个既有 Hysteria/Hysteria2/SS2022/Trojan/TUIC/VMess/普通 VLESS UDP artifact 仍为成功；Snell 的 UDP packet API 本轮未单独宣称原生 UDP marker。证据限定在固定 1.14.0 核心、隔离 Docker 与回环业务路径，不代表公网可达、生产部署、外部认证、SubMan 或全协议目标完成。

## 2026-09-14：Snell UDP packet API 数据面探针

在 TCP 切片基础上，`multi_protocol_coexistence` 现在也调用共享 `verification_execute_protocol_udp_probe snell`。探针只接受活动 schema-2 marker、schema-1 store 和当前 v6 tag，复用生产 exporter 的 `network:["tcp","udp"]`，先执行固定 1.14.0 client `check`，再经 SOCKS5 UDP ASSOCIATE 发送精确 marker；Snell v6 listener 仍只有 TCP，UDP 语义由该认证 TCP 会话的 packet API 承载。

定向 Docker run `dev/verification-runs/20260914153908` 的 `multi_protocol_coexistence` 与 `runtime_smoke` 均成功；共存 artifact 中 `protocol-probes/snell/result.env`、`udp.result.env` 均为 `RESULT=success`，并保留 TCP/UDP 精确响应、client check、渲染配置与 journal 的 packet-connection 行。该证据只覆盖固定核心、隔离 Docker/回环和受管 exporter，不把 packet API 误写成原生 UDP listener，也不代表公网、生产、外部认证、SubMan 或完整协议目标完成。

在此基础上，定向 Docker run `dev/verification-runs/20260914185411` 的共存场景先保存 v6 的 `protocol-probes/snell-v6/` artifact，再以 `agent instance replace snell --expected-revision 1` 将同一 typed instance 替换为 v5 HTTP-obfs 记录；`snell-v5-replace.json` 报告 `revision:2`、`transaction.status:"success"` 与 `phase:"committed"`。固定 1.14.0 `snell-v5-check.txt` 和渲染配置通过，受管 store 保留 `obfs_host`，客户端 exporter 映射为 version 4、`obfs_mode:"http"`、`network:["tcp","udp"]`；v5 TCP 与 packet-API UDP 的 `result.env`、精确 marker、client check 和 journal 均成功。该证据仍限于隔离 Docker/回环，不把服务端 v5 renderer 的 host 元数据误写进核心配置，不宣称原生 UDP listener、公网、生产、外部认证、SubMan 或完整协议目标完成。

## 2026-09-14：AnyTLS UoT UDP 数据面探针

在既有 AnyTLS TCP marker 之上，`multi_protocol_coexistence` 新增共享
`verification_execute_protocol_udp_probe anytls`。探针由受管 AnyTLS marker/state
生成客户端 outbound，先执行 client `sing-box check`，并确认生成 JSON 不含
可配置的 `network`、`transport` 或 `multiplex` 字段；随后通过 SOCKS5 UDP
ASSOCIATE 发送精确 marker，经 AnyTLS UoT adapter 回到一次性 loopback UDP
echo，保留 `udp.result.env`、`udp-response.txt`、client check 与 stderr。

AnyTLS listener 仍是 TCP，UDP 结果表示 UoT adapter 的业务路径而非原生 UDP
监听。定向 Docker run `dev/verification-runs/20260914165733` 的共存场景与
runtime smoke 均成功，并保留 `inbound UoT connection` journal 行。该验证只
覆盖固定 1.14.0、隔离 Docker/loopback 和受管客户端导出，不能推出公网可达、
生产部署、外部认证、SubMan 或完整协议目标完成。

## External Documentation

When current `sing-box` configuration syntax, migration behavior, or version compatibility is needed, use Context7 first. If Context7 cannot provide enough detail, use official `sing-box` documentation or the official repository before relying on third-party posts.
