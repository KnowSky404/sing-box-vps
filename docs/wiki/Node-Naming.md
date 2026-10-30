# Instance and node naming

[简体中文](https://github.com/KnowSky404/sing-box-vps/wiki/Node-Naming.zh-CN)

An instance has one saved human-readable base name. Share material and SubMan use
that base to derive names for its user/address candidates. Instance IDs,
authentication user identities, internal/client tags, link-map keys and SubMan
external keys retain their existing roles.

## New instance defaults

New interactive instances default to:

```text
<host-label>-<canonical-protocol>-<ordinal>
```

For example, `fra-01-hy2-01` and `fra-01-vless-reality-01`. The ordinal has at least
two digits and selects a free generated name in the protocol's current inventory.
Deleting an instance does not renumber surviving names. The saved name can be
customized; existing names and legacy recovery defaults remain unchanged.

Main menu **11 → 5「设置新实例的主机显示标签」** sets the label used for future
instance defaults. The optional private setting is
`/root/sing-box-vps/node-naming.json`, with only `host_label`:

```json
{"host_label":"fra-01"}
```

The trimmed label must be nonempty, contain no control characters and fit 128
UTF-8 bytes. Without the file, defaults use the current hostname. An invalid
existing file is reported explicitly. Saving backs up the previous file as
`node-naming.json.bak` before atomic replacement. This setting does not rename
existing instances, restart sing-box, or push nodes to SubMan.

## Candidate names

For rendering, the saved base is trimmed at its ends using ECMAScript
`String.prototype.trim()` whitespace, matching SubMan. Interior characters and
the saved value are preserved. U+FEFF is trimmed; U+0085 is retained. A base that
becomes empty is rejected. The generated display name follows this order:

```text
<instance-name>[-i-<instance-digest>][-u-<user-digest>][-U<up>M][-D<down>M][-v4|-v6]
```

| Situation | Behavior |
| --- | --- |
| One logical credential | Omit the user digest, including single-credential Shadowsocks |
| Multiple configured users | Add `u-` plus at least 12 SHA-256 hex characters of the user identity; expand by four characters when a configured sibling shares that prefix |
| Duplicate instance base names after the same whitespace trim in one captured protocol inventory | Add `i-` plus the first 12 SHA-256 hex characters of `protocol:instance-id` |
| REALITY rate limits or HY2 bandwidth metadata | Preserve configured `U...M` and `D...M` fields and their protocol-specific meaning |
| IPv4/IPv6 wildcard-listener candidate | Append `v4` / `v6` using the existing address candidate label |
| Concrete listener address | Preserve the listener-address label behavior; no additional family suffix |

Configured users determine the suffix count even if one is skipped because its
share options cannot be represented. Reordering users does not change their
suffixes. An instance summary describes the instance; actual share material
contains its candidate names. A URI remark or VMess `ps` and the corresponding
SubMan payload use the same candidate name. Their technical mapping keys and
client configuration tags remain stable.

Examples:

```text
fra-01-hy2-01-v4
fra-01-hy2-01-U20M-D80M-v4
fra-01-hy2-01-u-2bd806c97f0e-v6
```

A final name is limited to 256 UTF-8 bytes. If suffixes make it longer, rendering
shortens the base at a Unicode character boundary and adds a stable `n-` digest,
while preserving suffixes. The saved instance name is unchanged. Local duplicate
handling is scoped to the captured protocol inventory; other protocols, machines
or manually maintained remote nodes can still conflict. SubMan's returned name is
authoritative when it applies its existing remote duplicate-name rules.

## Updating existing nodes

Use existing instance management to change an instance's base name. The next
explicit SubMan synchronization uses the original external key to update its node
when that node still exists. Do not delete and recreate nodes merely to rename
them: deletion can remove aggregate references.

Main menu **11 → 4** calls the saved `SUBMAN_NODE_PREFIX` setting **同步身份前缀**.
Its value and key format are preserved. Changing it changes remote identity and
leaves old nodes in place; the host display label is a separate setting. Saving
settings does not synchronize nodes. Node API writes do not automatically
republish previously generated subscription/client outputs.

Naming does not add protocol support, change sharing/trust requirements, or
contact production services. See [SubMan address selection](https://github.com/KnowSky404/sing-box-vps/wiki/SubMan-Address-Selection),
[interactive management](https://github.com/KnowSky404/sing-box-vps/wiki/Management)
and the [implementation SPEC](https://github.com/KnowSky404/sing-box-vps/blob/main/docs/specs/unified-node-naming.md)
([中文 SPEC](https://github.com/KnowSky404/sing-box-vps/blob/main/docs/specs/unified-node-naming.zh-CN.md)).
