# 协议实例契约

New structured instances across all 14 proxy protocols default to a single `::` server listener in creation and additional-install menus. The Linux sing-box TCP/UDP dual-stack socket accepts IPv4 and IPv6; adding a second `0.0.0.0` listener on the same port can conflict. Existing-instance edits preserve the address on blank input, and explicit addresses in complete Agent records remain authoritative. Public-exposure confirmation is still required. REALITY and legacy singleton rendering retain the global inbound mode, including existing explicit settings and single-stack fallback. ShadowTLS inner detours and client-local listeners remain loopback. The explicit loopback examples below remain valid. See the [default-listener contract](https://github.com/KnowSky404/sing-box-vps/blob/main/docs/specs/default-dual-stack-listeners.md).

## Trojan typed instance contract

Trojan uses public/state ID `trojan`, preset 8, protocol management via main menu 2 and the shared instance transaction. It is separate from VMess and the legacy VLESS REALITY alias. The store is `protocols/instances/trojan.json` (`schema_version:1`) with the standard active `CONFIG_SCHEMA_VERSION=2` marker. There is no legacy Trojan migration operation; unsupported live fields must block lossy takeover. Generic edit/remove menus route Trojan through this same instance transaction, never the legacy singleton rewrite path.

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

Authentication contains 1–128 users with unique names and passwords. Names are stable user identities; editing unrelated fields must not rotate credentials. TLS uses administrator-provided certificate/key references. `client_trust:"certificate"` embeds only the public certificate in node connection materials; `"system"` explicitly chooses the client's system trust store and must not be inferred from a certificate filename. Disabled TLS requires `client_trust:"system"` and is not encrypted; non-loopback changes require the public-exposure confirmation.

Managed transport types are internal `none` (omitted from core JSON), HTTP, WebSocket without early data, gRPC and TLS-only QUIC. QUIC owns a UDP listener; other transports own TCP listeners, while both can carry TCP/UDP business traffic. Plaintext client JSON omits `tls` entirely: the pinned Trojan cores must not receive an explicit disabled TLS object, which can create an invalid TLS dialer despite passing `check`. HTTPUpgrade and WebSocket early data remain blocked by the previously reproduced runtime defects. REALITY, Vision, fallback and multiplex are not silently accepted as generic Trojan options. Takeover accepts only ALPN matching the managed transport profile; arbitrary ALPN is not discarded.

`nodes`/`status` are safe summaries, not complete transport records: authentication secrets and custom request headers must not leak. `links` are sensitive. Node connection materials are per-user complete outbounds with stable tags, matching transport/ALPN and strict trust; server private keys are never copied. Share/SubMan candidates require enabled TLS, explicit system trust and losslessly expressible transport fields. Plaintext, certificate-trust exports, custom headers and unsupported transport options return explicit warnings/skips instead of incomplete URIs. This is a local/mock integration contract, not proof of production reachability or an authorized real SubMan synchronization.

## VMess typed instance contract

VMess uses public/state ID `vmess`, preset 9, protocol management via main menu 2 and the shared instance transaction. It is separate from the legacy VLESS REALITY alias. The store is `protocols/instances/vmess.json` (`schema_version:1`) with the active `CONFIG_SCHEMA_VERSION=2` marker in `vmess.env`; there is no legacy VMess migration operation. Unsupported live fields block takeover rather than being discarded.

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

TLS is explicit. `client_trust:"certificate"` embeds only the public certificate in node connection materials; `"system"` uses the client's system trust store. Plaintext exports omit `tls`, and no path ever copies the server private key or disables verification. VMess links use standard `vmess://` JSON with only losslessly representable transport fields; unsupported HTTP headers, methods, early data or oversized values fail closed. `nodes` remains credential-free, while `links` are sensitive.

SubMan synchronization is a dedicated per-instance/per-user path. Only enabled TLS with explicit system trust and a losslessly representable URI is synchronized; plaintext, certificate trust, unsupported transport and oversized URI entries are returned as structured skips. Focused native 1.13.18/1.14.0 check/export coverage and local lifecycle/takeover/Agent/share/SubMan/probe tests passed; this is local/mock evidence, not proof of public reachability or an authorized real SubMan synchronization.

## AnyTLS typed instance contract

AnyTLS uses public/state ID `anytls`, preset 4 and protocol management via main menu 2. Its active marker is `protocols/anytls.env` with `CONFIG_SCHEMA_VERSION=2`; the typed store is `protocols/instances/anytls.json` with `schema_version:1`. The legacy schema-1 state remains available for ACME HTTP-01, Cloudflare DNS-01 and manual certificate generation. Typed instance takeover is intentionally limited to a lossless manual-TLS representation; an ACME/provider inbound is rejected and left untouched rather than flattened into an incomplete record.

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

Authentication accepts 1–128 users with unique names and passwords. TLS is always enabled in the typed record and must use exactly `server_name`, `certificate_path` and `key_path`; the files are administrator-owned and are never issued, copied into the node connection materials, or deleted by lifecycle operations. The AnyTLS listener is TCP; UDP business traffic uses the client/server UoT adapter rather than a native UDP listener. `client_trust:"certificate"` embeds only the public PEM in each client outbound, while `"system"` uses the client system trust store. AnyTLS has no standard share URI: `nodes` is credential-free, and `links` returns `links:{}`, per-user outbound JSON, and `warnings[].code=anytls_standard_uri_unavailable`. Client outbounds set `client_metadata` to an empty string, preserve the password, and never disable verification or include a private key. Non-loopback writes require `--allow-public`; lifecycle, export and Agent tests are local/mock evidence and do not prove public reachability or real SubMan synchronization.

## Hysteria2 typed instance contract

Hysteria2 uses public Agent ID `hysteria2`, internal/state ID `hy2`, preset 3 and protocol management via main menu 2. Its active marker is `protocols/hy2.env` with `CONFIG_SCHEMA_VERSION=2`; the typed store is `protocols/instances/hy2.json` with `schema_version:1`. Each typed instance supports manual TLS or ACME HTTP-01 / Cloudflare DNS-01. Legacy schema-1 nodes remain readable; creating an additional instance imports the existing bounded, losslessly representable ACME/provider options in the same CAS transaction. Unsupported fields, ambiguous provider references and orphaned stores abort the operation without changing the existing node.

Deleting the final managed Hysteria2 instance permits only its live listen-address drift when the requested ID and unique live tag/type still match and every other modeled field agrees. The transaction removes that target while preserving remaining live listeners, including unregistered Hysteria2 inbounds, and certificate caches. Other drift, another surviving managed instance, and non-delete operations remain blocked; see the [transaction contract](https://github.com/KnowSky404/sing-box-vps/blob/main/docs/specs/runtime-transactions.md#hysteria2-final-instance-deletion).

A valid active typed store or positive empty retained revision keeps unregistered custom-tag HY2 listeners outside the managed index, including when several remain after deletion. Listing protocols preserves that boundary, and creating another instance advances the retained revision without adopting those listeners. Reserved default tags and untrusted or legacy state retain their existing checks.

```bash
sbv agent instance create hy2 --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance replace hy2 --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance default hy2 --json --yes --expected-revision N --id main
sbv agent instance delete hy2 --json --yes --expected-revision N --id main
sbv agent instance recover hy2 --json --yes --expected-revision N
```

The private record contains the common `id`, `name`, `tag`, `listen`, `outbound_policy` and `dependencies` fields plus Hysteria2 authentication, TLS, client trust, bandwidth, obfuscation and masquerade:

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

Authentication accepts 1–128 unique names and passwords. TLS is always enabled. Manual certificate paths remain administrator-owned and are never copied into a URI or deleted by lifecycle operations. For automatic issuance, replace the entire `tls` object with the following, and use `client_trust:"system"`:

```json
{
  "enabled": true,
  "server_name": "proxy.example.com",
  "acme": {
    "domain": ["proxy.example.com"],
    "data_directory": "/root/.sing-box-vps/runtime/acme",
    "disable_http_challenge": false,
    "disable_tls_alpn_challenge": true
  }
}
```

The additional-install and instance-creation menus default to ACME and a single `::` listen address for IPv4/IPv6 clients; do not add a second `0.0.0.0` listener on the same port. Fresh legacy singleton rendering still follows the global inbound mode. Editing an existing instance keeps its current TLS mode and listen address by default. HTTP-01 needs the domain to resolve to this VPS and public TCP 80 available for validation and renewal. This port is separate from the HY2 UDP listener; the menu does not claim to verify provider firewalls or public reachability. For Cloudflare DNS-01, add `dns01_challenge:{"provider":"cloudflare","api_token":"replace-with-a-private-token"}` inside `acme`. This mode requires DNS edit permissions, does not require TCP 80 or A/AAAA records pointing to the VPS, and prompts for the token without echoing it. The optional `zone_token` is retained when supplied in an Agent record. Email is optional.

State stores ACME options per instance. Runtime rendering uses an inline `tls.certificate_provider` object on 1.14+ and inline `tls.acme` on 1.13.x, preserving certificate domains, storage, account and supported HTTP-client options. Shared provider references are resolved only when unique. Unknown or conflicting TLS/ACME fields are rejected. sing-box handles issuance, cache and renewal; deleting an instance retains its ACME cache. Config checks and an active service do not prove that a public CA issued a certificate.

`up_mbps` and `down_mbps` are independently optional positive integers. `obfs` is either disabled with empty fields or enabled as Salamander. The typed renderer emits UDP Hysteria2 inbounds with `alpn:["h3"]` and preserves bandwidth, obfs and masquerade.

Node connection materials contain one Hysteria2 outbound per user. `client_trust:"certificate"` embeds only the public certificate; `system` uses system trust. On 1.14+ an Ed25519 manual certificate adds `disable_chrome_parrot:true` to the client outbound and returns a structured compatibility warning for share links. Standard `hy2://` links are generated per user when system trust is selected; certificate trust, oversized URIs, and options that a standard URI cannot fully carry are reported as explicit warnings. `nodes` is credential-free, while `links` and SubMan payloads are sensitive.

SubMan synchronization is a dedicated per-instance/per-user path. Only system-trust users with a representable URI are pushed; certificate-trust users are skipped with a stable reason. Bandwidth and masquerade remain in the client JSON but produce a partial-URI warning. Non-loopback writes require `--allow-public`; lifecycle, export, Agent and SubMan tests are local/mock evidence and do not prove public reachability or an authorized real SubMan synchronization.

## Hysteria typed instance contract

Hysteria v1 uses public/state/Agent ID `hysteria`, registry preset 13 and protocol management via main menu 2. Its active marker is `protocols/hysteria.env` with `CONFIG_SCHEMA_VERSION=2`; the typed store is `protocols/instances/hysteria.json` with `schema_version:1`. There is no legacy Hysteria `.env` migration path, so `migrate hysteria` is rejected; existing live Hysteria configuration is accepted only when every modeled field is losslessly representable by the typed manual-TLS QUIC record. Hysteria v1 is separate from Hysteria2: its users use `auth_str`, its obfs is a string password, and it does not use Hysteria2's `masquerade` or Salamander object.

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

Node connection materials contains one Hysteria outbound per user with `auth_str`, bandwidth, optional obfs password and typed QUIC fields. `nodes` never exposes auth strings. Hysteria v1 has no lossless standard share URI or QR representation: `links` returns `links:{}`, complete outbound JSON and `warnings[].code=hysteria_standard_uri_unavailable`. Hysteria is not advertised to SubMan and is skipped rather than sent as `other`. Non-loopback writes require `--allow-public`; the focused lifecycle test uses local/mock service and firewall boundaries plus an optional sing-box 1.14 target `check`, so it does not prove public UDP reachability, UDP data-plane behavior, production deployment or real SubMan synchronization.

## NaiveProxy typed instance contract

NaiveProxy uses public/state/Agent ID `naive`, registry preset 14 and protocol management via main menu 2. Its active marker is `protocols/naive.env` with `CONFIG_SCHEMA_VERSION=2`; the typed store is `protocols/instances/naive.json` with `schema_version:1`. There is no legacy NaiveProxy `.env` migration path, so `migrate naive` is rejected; existing live Naive configuration is accepted only when every modeled field is losslessly representable by the typed manual-TLS TCP/UDP record. The server and client roles are deliberately separate: Naive inbound needs TLS, while Naive outbound additionally requires an official build with `with_naive_outbound` and the `libcronet.so` runtime library.

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

For Naive export, a TCP-capable `listen.network` (`["tcp"]` or `["tcp","udp"]`) adds
`udp_over_tcp:{enabled:true,version:2}` to each user outbound. A UDP-only listener omits
this TCP-only adapter and requires `quic:true` when the probe/client path uses Naive
HTTP/3 over QUIC.

Authentication accepts 1–128 unique `username`/`password` pairs. TLS is always enabled and manual in schema 2; certificate paths remain administrator-owned and are never issued, copied into an outbound, or deleted by lifecycle operations. `listen.network` is the canonical nonempty subset `["tcp"]`, `["udp"]` or `["tcp","udp"]`; a single-network inbound renders the sing-box scalar `network` field, while both networks omit it. `quic_congestion_control` accepts `bbr`, `cubic` or `reno`; `quic` and the receive-window/concurrency/header options are retained for node connection materials. `client_trust:"certificate"` embeds only the public certificate in each client outbound, while `system` uses the client trust store.

Node connection materials contains one Naive outbound per user with server, port, username/password, TLS trust and the stored Naive/QUIC options. `nodes` never exposes usernames or passwords. NaiveProxy has no lossless standard share URI or QR representation: `links` returns `links:{}`, complete outbound JSON and `warnings[].code=naive_standard_uri_unavailable`, plus `naive_libcronet_required` to make the optional runtime dependency explicit. The installer stages the official archive's `libcronet.so` atomically at `/usr/local/lib/libcronet.so`, records its SHA-256 under the managed project directory and refreshes the loader cache; core-upgrade backups include the library and marker and restore them with the binary when config/check/service validation fails. An unowned existing library is preserved and uninstall removes only a hash-matching managed copy. NaiveProxy is not advertised to SubMan and is skipped rather than sent as `other`. Non-loopback writes require `--allow-public`. Docker run `20260915184405` proved a TCP-capable Naive listener's HTTP/2 marker plus real UDP-over-TCP v2 payload through SOCKS5 UDP ASSOCIATE, then a CAS `1→2` replacement to a UDP-only listener whose authenticated client reached a TCP marker over Naive HTTP/3/QUIC (`protocol: quic/1+spdy/3`); artifacts are `protocol-probes/naive-tcp-uot`, `naive-udp-journal.txt`, `protocol-probes/naive-udp-http3` and `naive-http3-journal.txt`. This proves UoT UDP only when a TCP leg exists and HTTP/3 TCP transport for UDP-only, not native UDP payload on the UDP-only listener, public reachability, production deployment, external authentication or real SubMan synchronization.

## ShadowTLS typed instance contract

ShadowTLS uses public/state/Agent ID `shadowtls`, registry preset 15 and protocol management via main menu 2 with a schema-1 JSON store and schema-2 active marker. It is a composite inbound: each typed instance renders one `type:"shadowtls"` outer listener and one private loopback `type:"mixed"` detour whose tag is `shadowtls-inner-<id>`. The typed lifecycle supports `create`/`replace`/`delete`/`default`/`recover` with exact revision CAS; `migrate shadowtls` is rejected because there is no legacy singleton state path.

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

Node connection materials contains a two-part chain per user: a ShadowTLS transport outbound for the outer listener and an HTTP primary outbound whose `detour` points to that transport while targeting the loopback Mixed listener. Internal per-node builders and Agent links retain both outbounds, but selector/tag projections expose only the HTTP primary tag; the transport dependency is never silently dropped. `nodes` never exposes usernames or passwords. Version 1 has no password or users, version 2 has one password, and version 3 has 1–128 unique name/password users. Version 2/3 may carry SNI-specific handshake mappings; version 3 additionally carries `strict_mode` and `wildcard_sni` (`off`, `authed`, `all`). The detour is always loopback and must use a distinct TCP port. `client_trust:"certificate"` embeds only the public certificate in each client outbound; `system` uses the client trust store. ShadowTLS has no lossless standard URI or QR representation: `links` returns `links:{}`, complete per-user transport-plus-HTTP outbound JSON, `primary_outbound_tags`, and `warnings[].code=shadowtls_standard_uri_unavailable`; it is not sent to SubMan. Docker run `20260912001650` proved the generated chain with fixed 1.14.0 `check`, a temporary SAN TLS cover, the outer ShadowTLS listener, loopback Mixed detour and an exact HTTP marker in both `multi_protocol_coexistence` and `runtime_smoke`; the evidence is limited to an isolated container/loopback and does not prove public reachability, an external handshake service, production deployment or real SubMan synchronization.

## TUIC typed instance contract

TUIC uses public/state/Agent ID `tuic`, registry preset 12 and protocol management via main menu 2. Its active marker is `protocols/tuic.env` with `CONFIG_SCHEMA_VERSION=2`; the typed store is `protocols/instances/tuic.json` with `schema_version:1`. There is no legacy TUIC `.env` migration path, so `migrate tuic` is rejected; existing live TUIC configuration is accepted only when every modeled field is losslessly representable by the typed manual-TLS QUIC record.

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

Authentication accepts 1–128 unique names and UUID/password pairs. TLS is always enabled and manual in schema 2; certificate paths remain administrator-owned and are never issued, copied into a client outbound, or deleted by lifecycle operations. The server renderer emits a TUIC UDP/QUIC inbound with `alpn:["h3"]`, users, congestion control, `auth_timeout`, `heartbeat` and `zero_rtt_handshake`. `udp_relay_mode` and `udp_over_stream` are outbound-only sing-box fields and are deliberately not rendered in the inbound; retaining them in the typed record allows faithful node connection materials. `client_trust:"certificate"` embeds only the public certificate in each client outbound, while `system` uses the client system trust store.

Node connection materials contains one TUIC outbound per user with `network:["tcp","udp"]`, UUID/password, congestion control, heartbeat, zero-rtt and the selected outbound-only `udp_relay_mode` or `udp_over_stream`; the exporter also emits `tls.alpn:["h3"]` to match the server renderer. `nodes` never exposes UUIDs or passwords. TUIC has no standard share URI or QR representation: `links` returns `links:{}`, complete outbound JSON and `warnings[].code=tuic_standard_uri_unavailable`. TUIC is not advertised to SubMan and is skipped rather than sent as `other`. Non-loopback writes require `--allow-public`; the focused lifecycle test and Docker run `dev/verification-runs/20260911164148` cover target-core checks plus a container-local SOCKS5 UDP marker round trip, but do not prove public UDP reachability, production deployment or real SubMan synchronization.

## Snell typed instance contract

Snell uses public/state/Agent ID `snell`, registry preset 11 and protocol management via main menu 2. Its active marker is `protocols/snell.env` with `CONFIG_SCHEMA_VERSION=2`; the typed store is `protocols/instances/snell.json` with `schema_version:1`. Snell is a sing-box 1.14-only inbound in this project: the listener is TCP, and UDP proxy traffic relies on Snell's packet API over the TCP session. There is no legacy Snell `.env` migration path, so `migrate snell` is rejected; existing live Snell configuration is accepted only when every field is losslessly representable by the typed record.

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

`version` is `5` or `6`. Version 5 uses `obfs_mode:"none"` or `"http"`; HTTP mode keeps an `obfs_host` hint for node connection materials, while the inbound renderer emits only fields accepted by the Snell server. Version 6 clears v5 fields and uses `mode:"default"`, `"unshaped"` or `"unsafe-raw"`; its PSK must be 12–255 UTF-8 bytes. Authentication accepts zero to 128 unique `name`/`userkey` pairs; with no users, the PSK itself is used by the exported client. Node connection materials maps inbound v5 to outbound v4 and inbound v6 to outbound v6, emits explicit `network:["tcp","udp"]` and preserves each user key. `nodes` never exposes PSKs or user keys. Snell has no lossless standard share URI, so `links` returns `links:{}`, full outbound JSON and `warnings[].code=snell_standard_uri_unavailable`; SubMan deliberately does not advertise Snell as `other`. Non-loopback writes require `--allow-public`. The focused lifecycle test uses mock service/firewall boundaries and an optional target-core `check`; Docker now separately exercises both v6 and v5 UDP packet API paths through the authenticated TCP session, but neither path proves public reachability or real SubMan synchronization.


## TCP Fast Open and HY2 defaults

New TCP-capable protocol instances enable TCP Fast Open (TFO) by default:
Mixed, SOCKS, HTTP, Shadowsocks with TCP, Trojan/VMess/plain VLESS with a TCP
transport, VLESS REALITY, AnyTLS inbound, Snell, Naive inbound with TCP, and
ShadowTLS including its internal Mixed listener. UDP-only listeners, QUIC
transports, HY2, TUIC and Hysteria v1 do not receive a TFO default.
The generated sing-box client materials enable TFO on supported TCP adapters;
AnyTLS outbound is excluded because the core explicitly rejects it. Naive
QUIC materials remain unchanged.

Typed records accept optional boolean `listen.tcp_fast_open`; ShadowTLS also
accepts `detour.listen.tcp_fast_open`. On `instance create`, omission enables
TFO only for a TCP-capable listener. Explicit `false` is honored. On replace,
omission preserves the prior value, including legacy absence. Takeover/import
preserves the live field exactly; existing records are not migrated merely by
updating the script. VLESS REALITY keeps its existing per-instance switch.
TFO depends on kernel and peer support; this default does not modify host sysctl
settings or prove latency improvements.

Both HY2 installation and interactive instance creation default to Salamander
obfuscation and generate a password when blank. Replacement preserves the current
obfs state. Structured HY2 records retain their explicit `obfs` object and
`masquerade` string; operators can explicitly disable obfs. Use
`{"enabled":true,"type":"salamander","password":"<private-random-password>"}`
to match the menu default.

The existing URL prompt accepts `r1`, `r2`, etc. for installed or already
configured REALITY SNI candidates. A selected candidate becomes
`https://<SNI>`; it does not change HY2 TLS `server_name`, certificate or ACME
domain. New HTTP(S) input (and a fresh installation's default URL) is checked
with a bounded HEAD request: normal DNS resolution and certificate verification,
5-second connection timeout, 10-second total timeout, at most three redirects,
and a final 2xx/3xx response. Failure retries without writing configuration.
Replacement with blank input preserves the current URL without a network request.
Existing `file:` masquerade support is retained and bypasses HTTP checking.
This check establishes HTTP(S) reachability only; it does not prove HTTP/3
support, content suitability or a working HY2 data plane.

The equivalent read-only structured preflight is:

```bash
sbv hy2 masquerade-check --json
sbv hy2 masquerade-check --json --url https://www.example.com
```

The first command lists `.data.reality_candidates` without making network
requests. The second also reports `.data.http_available`; a failed probe returns
`.ok=false` and a nonzero exit code. Put the explicitly selected URL into the
private HY2 record's `masquerade` field before normal CAS-protected create/replace.
Those write commands do not make an implicit external probe.

[Upstream Hysteria documentation](https://v2.hysteria.network/docs/advanced/Full-Server-Config/#obfuscation)
states that enabling obfs prevents standard QUIC/HTTP/3 connections. A masquerade
URL can remain configured, but ordinary HTTP/3 browsers cannot reach that facade
while Salamander is enabled. HY2's certificate must still cover its own TLS name;
using a REALITY SNI as a website candidate supplies no certificate for that name.
