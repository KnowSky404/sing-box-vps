# Default dual-stack listeners

[简体中文](default-dual-stack-listeners.zh-CN.md) · [SPEC index](README.md)

This contract defines new server-listener defaults. Verification requirements
below are acceptance criteria; this document does not record completed testing,
review, merge, Wiki publication or production changes.

## Creation and preservation

New structured Mixed, SOCKS, HTTP, Shadowsocks, Trojan, VMess, VLESS plain,
AnyTLS, Hysteria2, Snell, TUIC, Hysteria, NaiveProxy and ShadowTLS outer
instances default to `listen.address:"::"` in creation and additional-install
menus. Fresh-install defaults for all 15 protocol presets use the same address.
On Linux, the project's sing-box TCP/UDP dual-stack socket model uses a single
`::` listener to accept IPv4 and IPv6, equivalent to accepting both IPv4 wildcard
`0.0.0.0` and IPv6 wildcard `::`. Do not add a second `0.0.0.0` listener on the
same port; the sockets can conflict.

REALITY and legacy singleton renderers still derive their actual listener from
the global inbound stack. A fresh dual-stack host defaults to `dual_stack`;
existing explicit modes and single-stack host fallback retain their behavior.
Changing a new-instance default does not migrate existing state or broaden an
existing listener.

Editing an instance preserves its stored address when the address input is
blank. Explicit IPv4, IPv6 and loopback input remains authoritative. Agent
`create`/`replace` requires a complete private typed record and preserves its
explicit `listen.address`; it does not fill missing fields from interactive
defaults. Capability metadata describes the new default. Public-exposure
confirmation and `--allow-public` requirements remain in force.

ShadowTLS's private Mixed detour, client-local proxy listeners, local management
APIs and advanced-component defaults keep their existing loopback semantics.
No core version, state schema, credential, port or TLS migration is introduced.

## SubMan and acceptance

[SubMan address selection](../wiki/SubMan-Address-Selection.md) continues to
follow each effective listener. For supported protocols, `::` can produce separate
IPv4 and IPv6 candidates when each family is successfully detected; explicit
`0.0.0.0` remains IPv4-only. HY2 keeps the configured domain as SNI while connecting
to the selected IP. Listener defaults add no SubMan protocol support, do not
delete remote nodes and do not certify public reachability.

Required acceptance covers creation defaults for all structured protocols and
fresh preset defaults, explicit-address and replacement preservation, capability
metadata, SubMan family selection, ShadowTLS detour and client-loopback
preservation. Generated server/client outputs must pass target-core
`sing-box check`. Isolated Linux runtime probes must cover IPv4 and IPv6 against
representative TCP and UDP listeners. Follow AGENTS.md section 4.2 for the
smallest sufficient local and Docker scope. Record local/mock, core check, Docker,
real SubMan, public-network and production evidence separately; this change does
not authorize production mutation.
