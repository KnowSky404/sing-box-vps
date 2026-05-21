# Unified Node Display Names Design

## Goal

Unify user-facing node names across connection viewing, sing-box client export, SubMan sync, and agent JSON output while keeping the node name entered during creation as the stable base name.

## Current Behavior

The script persists a per-protocol or per-instance `SB_NODE_NAME` during creation. For VLESS REALITY, several paths already append rate-limit and network-stack suffixes, but the behavior is not applied consistently across all consumers. Hysteria2 has bandwidth fields but currently does not include them in display names. Client export, SubMan sync, terminal link display, and agent JSON each partially build names in their own way.

VLESS REALITY is currently the only protocol that supports adding multiple nodes of the same protocol type. Hy2, AnyTLS, and Mixed are single-instance protocol entries in the protocol index.

## Naming Rule

All display-oriented node names should use this format:

```text
{node_base_name}[-{protocol_bandwidth_limit}]-{v4|v6}
```

`node_base_name` is the saved creation-time node name:

- If the user accepts the prompt default, keep the current default.
- If the user enters a custom name, preserve that custom name.
- Existing `normalize_node_name` compatibility behavior should still apply where state is loaded or user input is accepted.

`protocol_bandwidth_limit` is optional:

- Omit it when both upload and download limits are empty.
- Use `U{value}M` when upload is set.
- Use `D{value}M` when download is set.
- Use `U{up}M-D{down}M` when both are set.

`v4` or `v6` is optional:

- Append `v4` when rendering or exporting for an IPv4 address.
- Append `v6` when rendering or exporting for an IPv6 address.
- Omit the suffix when the address family is unknown or irrelevant.

Examples:

```text
hk-vps-vless-v4
hk-vps-vless-U40M-v6
hk-vps-hy2-U40M-D100M-v4
custom-anytls-v6
```

## Protocol Mapping

VLESS REALITY:

- Base name: the selected instance `SB_NODE_NAME`.
- Bandwidth: `SB_VLESS_RATE_LIMIT_UP_MBPS` and `SB_VLESS_RATE_LIMIT_DOWN_MBPS`.
- Network stack suffix: use the current address label from connection rendering or address detection.

Hysteria2:

- Base name: `SB_NODE_NAME`.
- Bandwidth: `SB_HY2_UP_MBPS` and `SB_HY2_DOWN_MBPS`.
- Network stack suffix: use the current address label when available.

AnyTLS:

- Base name: `SB_NODE_NAME`.
- No bandwidth suffix because no protocol bandwidth fields exist today.
- Network stack suffix: use the current address label when available.

Mixed:

- Base name: `SB_NODE_NAME`.
- No bandwidth suffix because no protocol bandwidth fields exist today.
- Network stack suffix: only apply where a shareable address-specific node name is needed.

## Consumers

The following consumers must use the same display-name helper instead of locally composing names:

- Terminal connection link output.
- Terminal QR-code link payloads.
- sing-box bare-core client export outbound `tag`.
- SubMan payload `name`.
- Agent JSON `nodes` and `links` output.

For VLESS REALITY multi-instance export, tag uniqueness must still be preserved. The base tag should be the unified display name. If two tags collide after applying the naming rule, the existing uniqueness fallback can append instance ID, port, or a counter.

## Duplicate Protocol Bandwidth Validation

When creating an additional VLESS REALITY instance, the script must reject a new instance if another existing VLESS REALITY instance has the same bandwidth tuple:

```text
protocol_type = vless-reality
upload_mbps = new_upload_mbps
download_mbps = new_download_mbps
```

Both empty values count as equal, so a second unlimited VLESS REALITY instance is rejected.

The validation should happen after the user enters the new bandwidth values and before credentials/state files are generated or saved. If a duplicate is found, print a clear warning that a VLESS REALITY node with the same bandwidth configuration already exists and cancel this create action without changing persisted state.

This rule intentionally ignores node name, port, SNI, UUID, and ShortID because the requested uniqueness boundary is protocol type plus bandwidth configuration.

Hy2, AnyTLS, and Mixed do not need new duplicate checks in this change because the current installer already prevents adding a second protocol state for those protocol types.

## Compatibility

This change should not rewrite existing state files. Existing node base names remain valid. The new display names are computed at render/export/sync time.

Existing SubMan external keys should not change. Only the SubMan node payload `name` should use the unified display name, so repeated syncs keep updating the same remote node.

## Testing

Focused tests should cover:

- Bandwidth suffix formatting for upload-only, download-only, both, and unlimited.
- Unified display names for VLESS REALITY, Hy2, AnyTLS, and Mixed.
- Address suffix behavior for IPv4, IPv6, and unknown address labels.
- VLESS REALITY duplicate bandwidth detection, including the unlimited/unlimited case.
- Client export and SubMan payloads using the unified display name.
- Agent JSON names matching the same helper behavior.

Because the change touches `install.sh`, the development verification workflow must run before completion:

```bash
bash dev/verification/run.sh
```
