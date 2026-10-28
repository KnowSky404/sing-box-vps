# 数据面验证

以下为各能力取得的历史验证证据及范围；不表示本轮重新执行。涉及本地开发工具的命令须在仓库根目录运行，先确认所需工具存在。

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

## URLTest group verification

The privileged Docker `multi_protocol_coexistence` scenario (run
`dev/verification-runs/20260915062630`) creates a typed URLTest group with one
built-in `direct` member. Its health URL is the existing loopback HTTP marker,
with `interval:"1s"`, bounded retry and `idle_timeout:"5s"`; the `localhost`
route must return the exact marker after the group completes a health probe.
Artifacts retain the target-core `check`, rendered URLTest configuration,
response, and revision-14 create/revision-15 delete envelopes. The result label
is `DATA_PLANE=urltest_direct_loopback` with `HEALTHCHECK=loopback_http`.

This proves only single-member URLTest health checking and route resolution in
an isolated container. It does not prove multi-member latency ordering or
failover, an external health URL, public reachability, production operation,
UDP, or SubMan synchronization; the marker and direct member are disposable
verification fixtures.

## Shadowsocks outbound TCP verification

The privileged Docker `multi_protocol_coexistence` scenario (run
`dev/verification-runs/20260915065946`) creates a typed
`shadowsocks-outbound-verification` component using
`2022-blake3-aes-128-gcm`, a 16-byte Base64 PSK and `network:["tcp"]`. The
synthetic domain is routed from the existing authenticated SOCKS5 inbound to
the managed outbound; a second rule on the existing SS2022 inbound overrides
that domain to the disposable direct loopback HTTP marker, preventing a
recursive route. Artifacts retain the target-core `check`, rendered outbound
and routes, exact marker response, `AUTHENTICATION=ss2022_psk`, and revision-16
create/revision-17 delete envelopes. The result label is
`DATA_PLANE=shadowsocks2022_connect_loopback`.

This proves only the managed SS2022 outbound/upstream TCP path in an isolated
container. The disposable SS2022 fixture, key and marker are not installer
resources; deletion asserts the component and both route references are gone.
It does not prove an external Shadowsocks service, UDP, public reachability,
production operation, SubMan synchronization or completion of the full
protocol goal.

## Shadowsocks outbound UDP verification

The same privileged Docker `multi_protocol_coexistence` scenario (run
`dev/verification-runs/20260915121419`) creates a second typed
`shadowsocks-outbound-udp-verification` component with the same SS2022
16-byte Base64 PSK and `network:["udp"]`. Its route is limited to the
existing authenticated SOCKS5 ingress and the existing SS2022 `ss-in` inbound
is the encrypted upstream. A real authenticated SOCKS5 UDP ASSOCIATE sends a
datagram to the disposable direct UDP echo marker and requires the exact
payload on return. Artifacts retain the target-core `check`, rendered config,
the `shadowsocks-outbound-udp-response.txt` payload, both
`outbound/shadowsocks[...]` and `inbound/shadowsocks[ss-in]` journal entries,
and the expected-revision-29 create (revision 30) / expected-revision-30 delete
(revision 31) envelopes. The result label is
`DATA_PLANE=shadowsocks2022_udp_loopback` with
`AUTHENTICATION=ss2022_psk`.

This proves only the managed SS2022 native UDP path through SOCKS5 UDP
ASSOCIATE in an isolated container. The SS2022 fixture, key and marker are
disposable and deletion asserts the component and route are gone; it does not
prove an external Shadowsocks service, public reachability, production
operation, SubMan synchronization or completion of the full protocol goal.

## SOCKS outbound native UDP verification

The same privileged Docker `multi_protocol_coexistence` scenario (run
`dev/verification-runs/20260915152726`) creates a typed
`socks-outbound-udp-verification` component with `network:["udp"]` and an
independent disposable username/password SOCKS5 upstream. That upstream
implements UDP ASSOCIATE and relays only the exact marker to the existing
direct UDP echo. The authenticated SOCKS5 ingress therefore traverses the
managed SOCKS outbound's native UDP path, while the upstream request log proves
authentication, UDP ASSOCIATE and the constrained destination/payload.

Artifacts retain the target-core `check`, rendered config, exact
`socks-outbound-udp-response.txt`, upstream request log, outbound journal and
expected-revision-31 create (revision 32) / expected-revision-32 delete
(revision 33) envelopes. The result label is
`DATA_PLANE=socks5_native_udp_loopback` with
`AUTHENTICATION=upstream_username_password`.

This proves only a SOCKS5 outbound native UDP relay in an isolated container.
The upstream, credentials and marker are disposable; deletion asserts the
component and route are gone. It does not prove an external proxy, public
reachability, production operation, SubMan synchronization or completion of
the full protocol goal.

## Direct and block outbound verification

The privileged Docker `multi_protocol_coexistence` scenario creates a typed
custom `direct-outbound-verification` component with an empty config and
TCP/UDP `route` rules owned by the existing authenticated SOCKS5 inbound. The
rules use sing-box 1.14 route options `override_address`/`override_port` to
send a synthetic TCP domain and a synthetic UDP target port to disposable
direct loopback markers; the UDP target port differs from the echo port so a
default direct fallback cannot return the marker. It then creates a typed
`block-outbound-verification` component with the same empty config and asserts
that its routed request fails instead of returning the marker.
Artifacts retain target-core `check`, rendered outbounds/routes, exact direct
TCP/UDP responses, expected block rejection, and CAS create/delete envelopes
(direct revision 17→18→19; block revision 19→20→21). Result labels are
`DATA_PLANE=direct_route_override_loopback`,
`DATA_PLANE=direct_udp_route_override_loopback` and
`DATA_PLANE=block_reject_loopback`.

This proves only custom direct route-option TCP+UDP forwarding and block
rejection in an isolated container. The direct and block components are
deleted before the scenario exits; no host policy or firewall ownership is
claimed. It does not prove public reachability, production operation, SubMan
synchronization or completion of the full protocol goal.

## VLESS outbound verification

The privileged Docker `multi_protocol_coexistence` scenario starts a disposable
plaintext VLESS upstream whose own route sends the synthetic destination to the
scenario's HTTP loopback marker. It then creates the typed
`vless-outbound-verification` component with `flow:""` and
`network:["tcp"]`, and accesses that destination through the existing
authenticated SOCKS5 inbound. The client and upstream configurations both pass
the target `sing-box 1.14.0 check`; the response must contain the exact marker
after a real VLESS client/server handshake. Artifacts retain the upstream
listener/check, rendered outbound/route, client response, and CAS envelopes
(expected revision 21 creates revision 22; expected revision 22 deletes revision
23). The result labels are `DATA_PLANE=vless_tcp_loopback` and
`UPSTREAM=vless_loopback_server`.

The captured TCP Docker run is `dev/verification-runs/20260915081600`.

### VLESS outbound UDP/XUDP closure

The same privileged `multi_protocol_coexistence` scenario also closes the
managed VLESS outbound UDP path. In Docker run
`dev/verification-runs/20260915235706`, the scenario extracts the rendered
`vless-outbound-verification` outbound, asserts `network:["tcp","udp"]`, and
builds a minimal local client without `packet_encoding`; the target core
therefore keeps its documented xudp default. The client passes
`sing-box check`, then a real no-auth SOCKS5 UDP ASSOCIATE sends an exact marker
through the VLESS client/server handshake. The disposable VLESS upstream routes
that UDP port to the loopback echo, and
`vless-outbound-udp.result.env` reports
`DATA_PLANE=vless_udp_xudp_loopback`, `UPSTREAM=vless_loopback_server`, and
`CLIENT_TRANSPORT=xudp`. The component is deleted afterward through the same
revision CAS lifecycle (21→23); the UDP response, client check, upstream check,
and cleanup steps remain in the scenario artifacts.

This is an isolated-container, loopback, plaintext VLESS TCP+UDP/XUDP proof
only. It does not prove external VLESS, TLS/REALITY, public reachability,
production operation, SubMan synchronization or completion of the full protocol
goal.

## TCP-listener inbound UDP business verification

The privileged Docker `multi_protocol_coexistence` gate in
`dev/verification-runs/20260916022721` runs the normal TCP probes first, then
executes `verification_execute_protocol_udp_probe` for `vless-reality`, `mixed`
and `socks`. Each probe reads the active listener/state, generates a disposable
SOCKS client, passes the target `sing-box 1.14.0 check`, sends one exact
SOCKS5 UDP ASSOCIATE marker and requires the matching loopback UDP echo. The
three `protocol-probes/<protocol>/udp.result.env` files report `RESULT=success`
and the response, client-check and cleanup artifacts are retained.

The VLESS REALITY generator preserves the stored Vision flow and omits
`network`/`packet_encoding`, exercising the core's default TCP+UDP and xudp
semantics through the REALITY/TCP listener. The Mixed generator uses a native
SOCKS UDP ASSOCIATE without UoT. The standalone SOCKS generator explicitly
uses `udp_over_tcp:{enabled:true,version:2}`, so its result is TCP-carried UoT
business rather than proof of a native UDP listener. This is fixed-core,
isolated-container/loopback evidence only: it does not prove public reachability,
external clients, host firewall policy, production operation, SubMan or full
protocol completion.

## Tor outbound verification

The privileged Docker `multi_protocol_coexistence` scenario uses the image's
`/usr/bin/tor` external executable and creates a typed
`tor-outbound-verification` component with `torrc.ClientOnly`. Through the
existing authenticated SOCKS5 inbound it requests `https://check.torproject.org/`
and requires the response text `This browser is configured to use Tor`, which
proves a real Tor circuit rather than only a target-core `check`. The component
uses expected revision 23 to create revision 24 and expected revision 24 to
delete revision 25; the captured run is recorded in
`dev/verification-runs/20260915090437`.

This is an external-network TCP proof from a disposable container. It does not
prove Tor network stability, anonymity guarantees, production configuration,
SubMan synchronization or completion of the full protocol goal.

## ShadowTLS outbound verification

ShadowTLS outbound is a transport rather than a standalone application proxy.
The privileged Docker `multi_protocol_coexistence` scenario therefore starts a
disposable ShadowTLS v3 server with a certificate cover and a Mixed inner
listener, creates `shadowtls-outbound-verification`, and creates a typed HTTP
outbound whose detour is the ShadowTLS component. Through the existing
authenticated SOCKS5 inbound it requests a synthetic loopback target and
requires the exact direct marker; the server stderr and `sing-box` journal
capture both sides of the v3 handshake and HTTP detour.

The evidence is captured in `dev/verification-runs/20260915104124`; inspect
`shadowtls-outbound.result.env`, `shadowtls-outbound-response.txt`,
`shadowtls-outbound-server.stderr.txt`, `shadowtls-outbound-journal.txt` and
`shadowtls-outbound-check.txt` under the scenario artifacts. The ShadowTLS
component uses expected revision 25 to create revision 26; the HTTP detour uses
26 to create 27, then deletes at 27→28 and 28→29. This proves the isolated
HTTP-over-ShadowTLS TCP combination only. It does not prove that ShadowTLS
alone carries arbitrary applications, external endpoints, UDP, production
configuration, SubMan synchronization or the full protocol goal.

## Direct inbound override data plane

Direct inbound component records may include the upstream `network` string (`tcp` or `udp`) and destination override fields `override_address`/`override_port`. The component validator rejects control characters, empty override addresses and ports outside 1-65535 while preserving the normal listen fields. A loopback direct record does not require `--allow-public`; non-loopback listeners still do.

The bounded Docker proof in `multi_protocol_coexistence` creates TCP and UDP direct components through the component CAS API, waits for service activity, runs the target `sing-box check`, and asserts their rendered listeners. Disposable loopback HTTP and UDP marker/echo fixtures receive requests only through the managed direct listeners' override destinations; exact responses are stored in `direct-inbound-response.txt` and `direct-inbound-udp-response.txt`, and the corresponding `direct-inbound.result.env` files report `RESULT=success`. Run `dev/verification-runs/20260912073323` contains the successful artifacts. This is fixed-core/loopback TCP+UDP evidence for direct forwarding only. It does not establish TUN/redirect/TProxy transparent routing, host firewall policy, public reachability, production deployment or full-protocol completion.

## TUN L3 payload verification

The privileged Docker `fresh_install_vless` scenario now runs
`verification_run_tun_l3_probe` after the managed TUN resource observation. The
probe creates a disposable veth pair and network namespace, starts HTTP and UDP
marker fixtures on the namespace peer, and sends exact TCP/UDP payloads through
the core-owned TUN configured with `auto_route`. It first runs the target ARM64
`sing-box 1.14.0 check`, captures route/resource snapshots, and removes marker
processes, veth devices and the namespace on both success and failure paths.

Run `dev/verification-runs/20260916064328` contains
`fresh_install_vless/tun-data-plane/`: `result.env` reports
`RESULT=success`, `DATA_PLANE=tun_l3_tcp_udp_netns`, `ROUTING=auto_route`,
`POLICY_SCOPE=verification_container_only` and `POLICY_OWNERSHIP=core_owned`;
`http-response.txt`/`udp-response.txt` hold the exact markers and
`http-client.stderr.txt`/`sing-box-journal.txt` retain bounded retry diagnostics
and the TUN route/outbound log;
`resources.before.txt`/`resources.with-tun.txt`/`resources.after-cleanup.txt`
show the route during the probe and disposable veth/namespace cleanup state;
the managed TUN is removed by the following component-delete step. Treat this as
`project-real-tun-l3-tcp+udp` evidence for a fixed core in an isolated
container. It does not prove host policy routing, DNS or firewall ownership,
public reachability, external control-plane authentication, production
deployment or the full protocol goal.

## Bridge outbound L3 payload verification

The privileged Docker `fresh_install_vless` scenario now exercises the managed
bridge outbound after the core-owned bridge resource check. It creates two
disposable veth/network namespaces, sends TCP and UDP marker traffic through
`tun-bridge-data-plane-verification` (`auto_route`) and a route action to
`bridge-l3-data-plane-verification`, then receives it on a synthetic address
through the bridge dynamic TUN/netfilter egress. Run
`dev/verification-runs/20260916071546` contains
`fresh_install_vless/bridge-data-plane/`; `result.env` reports
`RESULT=success`, `DATA_PLANE=bridge_l3_tcp_udp_netns`,
`ROUTING=auto_route_to_bridge`, `POLICY_SCOPE=verification_container_only` and
`POLICY_OWNERSHIP=core_owned`. The artifact set includes the target core check,
rendered config, bridge rule/table/link snapshots, exact TCP/UDP responses,
journal, diagnose, CAS deletion and final veth/namespace cleanup. This is
`project-real-bridge-l3-tcp+udp` evidence for fixed core/isolated namespaces
only; it does not prove host policy ownership, an external bridge interface,
public reachability or production deployment.

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

## OpenVPN system-device TCP+UDP payload closure

The historical privileged Docker gate `dev/verification-runs/20260916083525`
extends that resource-only slice with a managed direct inbound and a real TCP
payload. It starts the named `system:true` server/client pair, then sends the
direct inbound's request through the core-owned TUN interfaces to a marker
bound at `198.18.20.2` in a disposable veth/network namespace. Its artifact
bundle retains the target-core `sing-box check`, marker peer/host links, the
route to the marker, interface/address/MTU snapshots, `peer connected` and
`tunnel established` journal lines, endpoint/direct connection logs, and
`component diagnose`; the result is the historical
`project-real-openvpn-system-tcp` TCP-only proof.

The latest privileged Docker gate `dev/verification-runs/20260916104745`
preserves that TCP proof, then creates an independent UDP `system:true`
server/client pair (`sbv-ovpn-us`/`sbv-ovpn-uc`, server port `11997`) and a
managed direct UDP inbound on port `15095`, using the same disposable marker.
It retains target-core `check`, UDP listener and packet journal evidence,
interface/address/MTU/diagnose snapshots, exact TCP and UDP marker responses,
and the CAS delete results. The combined artifact result is
`project-real-openvpn-system-tcp+udp` with `SYSTEM_INTERFACE=true`,
`PAYLOAD=marker_round_trip`, `TCP_PAYLOAD=marker_round_trip`,
`UDP_PAYLOAD=marker_round_trip`, `RESOURCE_EVIDENCE=interface_and_tunnel`,
and `MARKER_NETWORK=disposable_netns_veth`. Proxy/client/server resources are
deleted in revision order, followed by both system interfaces and the marker
veth/network namespace; `after-delete.env` records
`RESOURCES=managed_system_interfaces_removed` and
`MARKER_RESOURCES=disposable_netns_veth_removed`.

This is fixed 1.14.0, isolated container/network-namespace evidence for the
core-owned system-interface TCP and UDP paths. It does not install host routes
or transparent policy, authenticate an external VPN control plane, or prove
public reachability, production operation, SubMan synchronization, or the full
protocol goal.

## WireGuard endpoint UDP closure

The privileged Docker `fresh_install_vless` scenario now creates a disposable
kernel WireGuard peer with the image's `wireguard-tools`, then manages a
`system:false`/gVisor WireGuard endpoint and a UDP-only direct inbound. The
peer's real handshake is observed with `wg latest-handshakes` and transfer
counters; the inbound sends an exact marker through the endpoint to a UDP
server bound only on the peer address. The target core `check`, rendered route
and endpoint (with private key redacted in artifacts), journal, marker response,
and endpoint/proxy/kernel-peer CAS cleanup are retained under
`fresh_install_vless/wireguard-endpoint/`. The successful result label is
`project-real-wireguard-udp`.

This proves only an isolated internal WireGuard UDP path and lifecycle. It does
not prove `system:true` interface creation, external peer or control-plane
authentication, public reachability, production operation, host routes or
SubMan synchronization.

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

Unknown state IDs or future schema versions block reconstruction while preserving those entries. Live inbound discovery is also all-or-nothing: unknown types, non-REALITY VLESS, duplicate single-instance protocols, and duplicate explicit tags block reconciliation, takeover, and regeneration before resource preparation. `status`, `nodes`, and `links` then return `live_inbound_inventory_untrusted` instead of presenting a partial protocol/node list as complete. All three commands require the normalized index to match the complete live protocol set exactly and require every base state to be present, recognized, canonical, and indexed; failures return `protocol_index_untrusted` or `protocol_state_untrusted`. `nodes` and `links` additionally capture and validate the complete REALITY instance list before public-address lookup, and discard all rendered nodes if any state load or final state restoration fails. This inventory check does not certify custom fields, outbounds, endpoints, or routes as losslessly managed. Restore a compatible script or reviewed backup to recover; do not remove unknown files or config components to bypass the guard. Track the full protocol expansion and evidence in [the implementation record](https://github.com/KnowSky404/sing-box-vps/wiki/Verification-History) and [the upstream matrix](https://github.com/KnowSky404/sing-box-vps/wiki/Protocol-Coverage).
