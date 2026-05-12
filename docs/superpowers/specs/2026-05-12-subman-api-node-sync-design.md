# SubMan API Node Sync Design

**Date:** 2026-05-12

**Goal**

Add a SubMan integration to `sing-box-vps` so the current VPS node information can be pushed to an already deployed SubMan Server API.

The first version should sync individual node share links into SubMan's node library. It should not edit SubMan workspace files directly, manage aggregate rules, or publish subscription targets.

## Context

`sing-box-vps` already generates protocol state and connection information for installed protocols. The node information menu currently supports:

- Viewing links, QR codes, and protocol summaries.
- Exporting a complete `sing-box` bare-core client config.

SubMan exposes an owner-operated Server API intended for backend automation. The recommended endpoint for `sing-box-vps` is:

```http
PUT /api/nodes/by-key/:externalKey
```

The request body requires:

- `name`
- `type`
- `raw`

It also accepts:

- `enabled`
- `tags`
- `source`

The endpoint is idempotent. Reusing the same `externalKey` updates the existing SubMan node instead of creating duplicates.

## Approved Scope

### 1. Use SubMan Server API only

The integration should call the deployed SubMan API with `curl`. It should not depend on the SubMan repository being present on the VPS and should not write directly to GitHub Gist or SubMan workspace JSON.

This keeps `sing-box-vps` responsible for producing node data and keeps SubMan responsible for storage, aggregation, and publishing.

### 2. Add a node information submenu action

The existing node information submenu should gain a third action:

- `1. 查看连接链接 / 二维码`
- `2. 导出 sing-box 裸核客户端配置`
- `3. 推送节点到 SubMan`
- `0. 返回`

The action belongs under node information because it publishes the same connection data that the user can already view manually.

### 3. Store SubMan API settings locally

Use a root-owned local config file:

```text
/root/sing-box-vps/subman.env
```

Initial fields:

```bash
SUBMAN_API_URL=https://subman.example.com
SUBMAN_API_TOKEN=...
SUBMAN_NODE_PREFIX=
```

`SUBMAN_API_URL` should be normalized by trimming trailing slashes before API calls.

`SUBMAN_NODE_PREFIX` is optional. If it is empty, default to the current hostname. The prefix is used for SubMan node names and external keys.

The file should be written with mode `600`. Logs must not print the token or full Authorization header.

### 4. Prompt for missing settings

When the user chooses `推送节点到 SubMan` and the config file is missing or incomplete, the script should prompt for:

- SubMan API URL.
- SubMan API token.
- Optional node prefix.

The prompt should validate that URL and token are non-empty. It should allow empty prefix and then use hostname as the default.

### 5. Sync only protocols that have stable share links

First-version protocol mapping:

| Runtime protocol | SubMan type | Raw value | Behavior |
| --- | --- | --- | --- |
| `vless+reality` / state `vless-reality` | `vless` | `vless://...` from existing link builder | Sync |
| `hy2` | `hysteria2` | `hy2://...` from existing link builder | Sync |
| `mixed` | none | none | Skip |
| `anytls` | `anytls` only if a standard raw URI exists | `anytls://...` when available | Otherwise skip with a clear warning |

Do not send a complete `sing-box` outbound JSON as SubMan `raw` for AnyTLS. SubMan's aggregation model treats `raw` as subscription line content, so pushing JSON would make the resulting subscription ambiguous.

### 6. Use stable external keys

Generate external keys in this format:

```text
sing-box-vps:<prefix>:<protocol>
```

Examples:

```text
sing-box-vps:hk-vps-01:vless-reality
sing-box-vps:hk-vps-01:hy2
```

This allows repeated script runs, port changes, and credential rotations to update the same SubMan node.

### 7. Payload shape

Each synced node should use this payload shape:

```json
{
  "name": "hk-vps-01 vless-reality",
  "type": "vless",
  "raw": "vless://...",
  "enabled": true,
  "tags": ["sing-box-vps", "hk-vps-01"],
  "source": "single"
}
```

Names should be readable and stable. Prefer the saved protocol `NODE_NAME` when it exists, with the prefix as fallback context. Tags should make it easy for SubMan aggregate rules to select or filter nodes created by this project.

## Architecture

Keep the first implementation inside `install.sh`, following the project's single-entrypoint architecture.

Suggested function boundaries:

- `subman_config_file_path()`
  - Returns `/root/sing-box-vps/subman.env`.
- `normalize_subman_api_url <url>`
  - Trims whitespace and trailing slashes.
- `load_subman_config()`
  - Loads config values from `subman.env` if present.
- `prompt_subman_config_if_needed()`
  - Prompts and persists missing values.
- `write_subman_config()`
  - Writes `subman.env` with `600` permissions.
- `subman_type_for_protocol <protocol>`
  - Maps supported runtime or state protocol names to SubMan node types.
- `build_subman_raw_for_protocol <protocol> <public_ip>`
  - Returns a raw subscription line for supported protocols.
- `build_subman_node_payload <protocol> <public_ip>`
  - Builds the JSON payload with `jq`.
- `subman_external_key_for_protocol <protocol>`
  - Builds the stable external key.
- `push_subman_node <external_key> <payload_json>`
  - Calls the API with `curl`.
- `push_nodes_to_subman()`
  - Orchestrates config loading, protocol iteration, skipped protocol reporting, and summary output.

Existing link builders should be reused for VLESS and Hysteria2 instead of duplicating URI construction.

## Data Flow

1. User opens node information menu.
2. User selects `推送节点到 SubMan`.
3. Script loads current config state.
4. Script loads or prompts for SubMan settings.
5. Script lists installed protocols.
6. For each installed protocol:
   - Load protocol state.
   - Skip unsupported protocols with a concise warning.
   - Build raw share link for supported protocols.
   - Build SubMan node JSON payload.
   - Call `PUT /api/nodes/by-key/:externalKey`.
7. Script prints a summary:
   - Synced count.
   - Skipped count.
   - Failed count.

If all supported nodes fail to sync, return non-zero from the action. The menu may keep running by calling it with `|| true`, matching the current export action style.

## Error Handling

- Missing API URL or token: prompt and persist before syncing.
- Empty installed protocol list: warn that no nodes are available.
- Mixed-only installation: warn that `mixed` is skipped and no SubMan nodes were synced.
- Unsupported AnyTLS raw URI: warn that AnyTLS cannot be pushed until a standard raw URI is available.
- `curl` missing: install dependency flow should already require curl; still fail with a clear error if unavailable.
- HTTP non-2xx response: print the status code and response body if available, without printing secrets.
- JSON payload build failure: skip that node and continue with remaining protocols.
- Public IP detection failure: reuse current fallback behavior where possible; if no address is available, skip affected nodes.

## Security

- Store `SUBMAN_API_TOKEN` only in `subman.env`.
- Set `subman.env` permissions to `600`.
- Never echo the token back after entry.
- Do not include the Authorization header in logs.
- Do not print full raw node links in sync summary by default; the existing view action remains the explicit path for showing node secrets.

## Testing

Add focused shell tests around the new behavior:

1. Node information menu renders the new SubMan action.
2. Missing SubMan settings trigger the config prompt and write `subman.env` with expected fields.
3. VLESS payload maps to `type: vless` and contains the expected raw `vless://` prefix.
4. Hysteria2 payload maps to `type: hysteria2` and contains the expected raw `hy2://` prefix.
5. Mixed-only installation reports no syncable SubMan nodes.
6. SubMan API URL normalization removes trailing slashes.
7. API failure returns non-zero and reports the HTTP status without leaking the token.

Because this changes `install.sh`, the implementation turn must also:

- Bump `SCRIPT_VERSION` once using `YYYYMMDDXX`.
- Update the README script version.
- Run `bash dev/verification/run.sh` by default after implementation.

## Non-Goals

- Creating or editing SubMan aggregate rules.
- Publishing SubMan Gist outputs.
- Pulling nodes from SubMan into `sing-box-vps`.
- Managing SubMan deployment, Worker secrets, or GitHub tokens.
- Directly editing SubMan workspace JSON or Gist files.
- Syncing the generated complete `sing-box` bare-core client config as a SubMan node.

