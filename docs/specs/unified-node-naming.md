# Unified instance and node naming specification

[简体中文](unified-node-naming.zh-CN.md)

Status: implementation contract for the unified naming change. This document defines
expected behavior and acceptance criteria; a completed implementation or successful
production synchronization must be recorded separately.

## 1. Problem and outcome

The original display path uses a stored node name with bandwidth and address-family
suffixes. New structured multi-user protocols independently construct SubMan names
from a machine prefix, protocol, instance ID and user digest. Local share links can
append a technical outbound tag instead. Consequently, editing an instance name can
leave its SubMan name unchanged, and the same candidate can have different names in
local sharing and synchronization.

Use the stored instance name as the human-readable base. Share and SubMan candidate
names must come from one formatter and the same captured instance data. Keep naming
separate from identity so a display-name edit can update an existing remote node.

## 2. Scope and identity boundaries

| Value | Responsibility | Compatibility rule |
| --- | --- | --- |
| Instance `id` | Select and update a local instance | Preserve existing values |
| Instance `name` | Human-readable base name | Preserve existing values; editable through existing instance management |
| Authentication user name | Stable user identity | Preserve; never use display normalization to rename a user |
| Inbound/client outbound `tag` | Configuration identity and references | Preserve existing values and construction rules |
| Link-map key | Associate share material with an outbound | Preserve technical keys |
| Candidate display name | Distinguish exported user/address candidates | Derive from the captured instance |
| SubMan `externalKey` | Update the same remote node | Preserve all existing protocol-specific formats |

Naming applies to local instances across supported protocols. SubMan synchronization
continues to follow the protocol registry: naming work does not add new URI formats,
change sharing eligibility, or make an unsupported protocol synchronizable.

There is no authentication-user alias field, instance-state migration, automatic
remote-node deletion, production-host change or automatic subscription republishing
in this change. Existing generated configuration tags and their references remain
stable.

## 3. New instance defaults

New interactive instances use:

```text
<host-label>-<canonical-protocol>-<ordinal>
```

Examples: `fra-01-vless-reality-01`, `fra-01-vless-plain-01`,
`fra-01-hy2-01`, `fra-01-trojan-01`.

1. Use the canonical registry protocol ID. In particular, distinguish
   `vless-reality` from `vless-plain`; the legacy CLI alias `vless` remains unchanged.
2. Choose the first unused generated name from the captured protocol inventory,
   starting at ordinal 1 and formatting it with at least two digits.
3. Persist the selected or user-supplied name at creation. Do not recalculate saved
   names when the host label, hostname, default instance, or inventory order changes.
4. Deleting an instance does not renumber surviving names. A free name may be reused
   by a later new instance; names are not an identity-allocation ledger.
5. Leave existing names, existing ID allocation, and legacy recovery/migration
   fallback names unchanged. User-supplied names are not parsed to infer IDs.

The optional `/root/sing-box-vps/node-naming.json` setting has this shape:

```json
{"host_label":"fra-01"}
```

The object accepts only the `host_label` field. The host label is trimmed,
nonempty UTF-8, contains no control characters and fits 128 UTF-8 bytes. If no setting exists, use the current hostname. A present malformed
or unsafe setting must produce an explicit failure, rather than silently choosing a
new default. A fresh installation with neither this file nor an existing inventory
must compute its first default name using the shell and hostname only; it must not
require `jq` before the existing dependency-installation stage. Reading an existing
JSON preference or inventory explicitly requires `jq`, with a clear dependency
error when it is unavailable. This feature does not reorder dependency installation. Main menu **11 → 5** exposes **设置新实例的主机显示标签** independently
of SubMan connection settings at **11 → 4**.

Saving the setting stages and validates JSON, backs up an existing file as `.bak`,
and atomically replaces it with private permissions. Failure leaves the previous
setting usable. Changing it affects only defaults for future instances; it does not
rewrite existing instances, restart the core, or contact SubMan.

## 4. Shared candidate formatter

The shared structured formatter receives explicit inputs:

```text
structured_node_display_name(protocol, snapshot_json, instance_id, user_name, address_label[, prepared_context])
```

The snapshot is the immutable, validated inventory already captured by its caller.
The formatter must not reread mutable stores per user, load another instance, or use
unrelated `SB_*` globals to obtain structured bandwidth values. An optional sixth
argument carries a prepared naming context derived from that same snapshot and
selected instance. Prepare the user-digest map once and reuse it for all candidates
in the instance; do not rehash every sibling in each per-user loop. The context
keeps identity and normalization data explicit, introduces no mutable global cache,
and must not be reused with a different snapshot or instance.

Compose fields in this order:

```text
<instance-name>[-i-<instance-digest>][-u-<user-digest>][-U<up>M][-D<down>M][-v4|-v6]
```

- **Base:** derive the base from the saved instance `name`, trimming only its
  leading and trailing ECMAScript `String.prototype.trim()` whitespace, matching
  SubMan. Trim before checking the remaining base for ASCII control characters.
  A saved `"\tCustom\t"` therefore renders as `Custom`; an interior tab still
  fails. Preserve interior characters of accepted names and the saved value.
  Reject a base that becomes empty. The exact trim set is U+0009–U+000D, U+0020, U+00A0, U+1680,
  U+2000–U+200A, U+2028, U+2029, U+202F, U+205F, U+3000 and U+FEFF; U+0085 is
  retained. Do not replace the base with the SubMan prefix, protocol label, ID or
  technical tag.
- **Duplicate base:** compare names after the same ECMAScript trim. When multiple
  instances in the same snapshot have the same normalized base, add `-i-` followed by the first 12 hexadecimal characters of SHA-256 of
  `<canonical-protocol>:<instance-id>` to each affected candidate.
- **User:** add `-u-` followed by at least the first 12 hexadecimal SHA-256
  characters of the user name only when the instance has multiple configured
  logical credentials. If configured sibling users share a shortened prefix,
  extend the candidate's digest by four hexadecimal characters at a time until
  it is distinct within that instance; fail if the complete digests collide.
  Shadowsocks with no per-user entries has one logical credential. Do not show
  `single-<digest>` for a single credential. Count configured users, including a
  sibling skipped by URI eligibility, so export filtering does not rename another
  candidate. User ordering does not affect the digest.
- **Bandwidth:** retain the existing `U...M` / `D...M` syntax for configured REALITY
  rate limits and HY2 bandwidth metadata. For structured HY2, read both values from
  the captured instance. These fields keep their protocol-specific meaning; HY2
  bandwidth metadata is not relabeled as a guaranteed traffic rate limit.
- **Address:** use the existing candidate label conversion for `IPv4` / `IPv6`.
  A concrete-bound listener uses its existing listener-address label and therefore
  has no extra family suffix. Do not infer a new external-key suffix from the IP.

The same candidate must use the same display name in the URI fragment (or VMess
`ps`) and SubMan payload `name`. Local share entrypoints and dedicated SubMan paths
share only formatting; retain each path's existing trust, lossless-representation,
size, warning and skip rules. Where an existing share producer cannot consume the
captured snapshot directly, recheck its captured inventory before accepting output
and fail closed when concurrent changes would mix names with other credentials.

An instance summary still describes an instance, rather than one of its potentially
many user/address candidates. Keep that distinction in menus and Agent summaries;
actual share material exposes candidate names. Technical link-map keys and client
outbound tags do not become display names.

## 5. Length and collision behavior

The final candidate name must fit **256 UTF-8 bytes**, including all suffixes.
Compute suffixes first. If the complete candidate is too long, shorten only the
rendered base at a Unicode code-point boundary and add `-n-<digest>` before the
suffixes. The digest is the first 12 SHA-256 hexadecimal characters of the complete
unshortened candidate. Reserve its bytes and all suffix bytes before shortening.
Do not modify the saved base, remove distinguishing suffixes, or truncate an
`externalKey`.

Digest shortening provides practical deterministic distinction, not a mathematical
guarantee of uniqueness. Remote names already used by another protocol, machine or
manually maintained node are outside the local snapshot's collision inventory.
Existing SubMan conflict handling and returned names remain authoritative; do not
claim local formatting prevents every remote collision.

## 6. SubMan settings and update behavior

Keep the stored `SUBMAN_NODE_PREFIX` field and its current values. Label it
**同步身份前缀** in the UI, with an explanation that changing it changes external keys
and leaves old nodes in place. It is independent of the host display label.

A display-name change must preserve the candidate's existing external key. The next
explicit synchronization updates an existing node through by-key PUT when that node
exists; it does not delete and recreate it. Preserve the existing Workspace checks,
119-byte external-key limit, conditional operations and uncertain-write readback.
Existing remote-node IDs and aggregate references must be checked in integration
verification rather than inferred from a mocked name comparison.

Saving display or connection settings does not push nodes. Node API synchronization
does not automatically republish previously generated subscription/client outputs.

## 7. Implementation order

1. Add the pure shared formatter, bounded rendering, new-default helper and optional
   host-label setting. Retain legacy fallback behavior and identity functions.
2. Connect structured local shares and all current SubMan push paths to captured
   snapshot naming. Keep technical tags and URI eligibility unchanged.
3. Update new-instance defaults and settings labels, document the operator flow,
   and complete focused compatibility tests.
4. Synchronize the script version once for this delivery, perform current-HEAD local
   review, then create the PR. Merge only after the required current-head remote
   security review and repository gates pass.

## 8. Acceptance and verification

Required assertions:

- New-instance defaults distinguish protocol and instance and use the host label.
- Fresh defaults without a preference or inventory work before `jq` is installed;
  an existing JSON preference/inventory explicitly reports a missing parser.
- Prepared digest context is reused across a 128-user instance, preserves the
  unprepared formatter's output, and avoids repeated per-candidate sibling hashing.
- Changing the host label changes future defaults only; missing configuration uses
  hostname, invalid configuration fails, and failed saves preserve the previous file.
- Existing custom names become the base of actual local share and SubMan names.
- Single-user, configured multi-user, reordered users and skipped siblings behave
  as specified; Shadowsocks' zero-user credential has no meaningless user suffix.
- Leading/trailing ECMAScript whitespace is trimmed only in rendered bases;
  U+FEFF trims, U+0085 remains, whitespace-only bases fail, and normalized duplicate
  snapshot names receive deterministic instance suffixes.
- A shortened user-digest collision expands deterministically without changing
  external keys or depending on user order.
- Structured HY2 bandwidth comes from the captured instance, not stale globals.
- IPv4, IPv6 and concrete listener labels retain current address/key semantics.
- Chinese/emoji names remain valid UTF-8 and final names fit 256 bytes; overflow
  leaves saved names unchanged and keeps distinguishing suffixes.
- A base-name edit preserves instance/user IDs, external keys, technical tags,
  link-map keys, credentials and generated configuration references.
- URI remarks/VMess `ps` match payload names for the same captured candidate.
- Sharing trust/skip behavior, API failure handling and snapshot isolation remain
  covered by their existing regressions.

Run the new formatter/default/settings tests, changed interaction tests, actual
structured share entrypoint tests, bounded SubMan payload/API/orchestration tests,
and documentation/version/syntax checks. If affected generated configuration content
changes, execute the target `sing-box check` on those outputs. If implementation
changes installation control flow, service/network or lifecycle behavior, add the
corresponding Docker scenario under AGENTS.md section 4.2. Naming alone does not
require an unrelated protocol matrix or full release acceptance.

Record local/mock results, real core checks, Docker, real SubMan integration,
production acceptance and Wiki publication separately. This SPEC is not evidence
that any of those checks or remote operations have completed.

## 9. Implementation and verification record

Implemented in script version `2026103003`, based on `061bc8e8f3c68b574b3ee6ad902abaa2b8761077`.
Previously verified runtime SHA-256: `93eeb20a4869e089fb3b9db4f904c337f4b04600cf6748a96db5e250851df465`.
Final post-review runtime SHA-256: `ac37a4caf8cc242937e3dafd2626d6110f57a175567897b9c1fc911b7041d556`.

The selected local suite passed **35/35** checks (608 seconds):

| Scope | Completed checks |
| --- | --- |
| Naming contract and integration | `node_naming_contract.sh`, `node_naming_settings.sh`, `node_naming_creation_defaults.sh`, `node_naming_share_subman_parity.sh`, `node_naming_generic_payload.sh` |
| Existing defaults and display | `default_node_names_follow_hostname_protocol_format.sh`, `vless_reality_new_instance_default_node_name.sh`, `install_prompts_include_protocol_name.sh`, `node_info_action_menu_renders.sh`, `unified_node_display_names.sh` |
| Affected creation menus | Mixed, SOCKS, HTTP, Shadowsocks and Trojan `*_instance_menu.sh`, plus `hy2_instance_acme_menu.sh` |
| Existing actual share callers | Trojan, VMess, plain VLESS and Shadowsocks `*_agent_share.sh`, plus `structured_hy2_instance_management.sh` |
| SubMan | All ten `tests/subman_*.sh`: address selection, API, config, payload, reconfiguration, Shadowsocks, orchestration, Trojan, plain VLESS and VMess |
| Core/config boundary | `export_client_config_1_14_compatibility.sh` with actual sing-box **1.14.2** checking the generated legacy HY2 client configuration; structured serializers and technical tag construction remain unchanged, with long legacy tag preservation checked separately |
| Documentation/version | `wiki_documentation.sh`, `readme_mentions_current_versions.sh`, `version_metadata_is_consistent.sh`; `bash -n install.sh` |

The suite initially covered runtime SHA-256
`bc957b86801f7510d821ebb78c273ea1eb7f05785e746e8128b69e30c4322673`.
Before review, a settings-only correction rejected nonregular configuration/backup
targets and reported an invalid stored label when generating a default. The contract,
settings and creation-default tests passed again against the previously verified
runtime above. At that stage, other results were reused because their affected
naming/share/API code and dependencies had not changed. The existing prompt fixture lacked its final
masquerade response on the base branch too; the fixture now supplies that response.

Docker runtime, real SubMan writes, preservation of actual remote node IDs and
aggregate memberships, production acceptance and automatic republishing were not
performed. No listener, credential, service-lifecycle or state-migration behavior
was changed. Local/mock and core-check results do not establish those boundaries.

Record the exact-HEAD local review, remote security review and merge in the
associated PR, and Wiki publication in its own commit. Those gate records remain
separate from this behavioral evidence so recording a reviewed commit's SHA does
not itself change the reviewed head.

### Local-review follow-up verification

The local review of `ff125e9` identified three concrete findings: fresh Mixed
defaults before `jq` installation, repeated sibling hashing for 128-user instances,
and rejecting valid surrounding tabs before trimming. All three were fixed, then
**21 affected checks passed** against the final runtime hash above:

- The six `node_naming_*.sh` tests, including the new
  `node_naming_fresh_dependencies.sh`, plus five existing default/display/interaction
  tests and the three documentation/version checks passed in the parent run.
- `subman_shadowsocks_sync.sh`, `subman_trojan_sync.sh`, `subman_vmess_sync.sh`,
  `subman_vless_plain_sync.sh`, `subman_sync_orchestration.sh`,
  `shadowsocks_agent_share.sh` and `structured_hy2_instance_management.sh` passed
  in the independent focused run against the same frozen runtime.
- The 128-user contract counts exactly 128 raw-user digest computations during
  preparation and zero additional raw-user computations across 128 candidate
  renders. It checks unique names, reordered users and invalid context rejection.
- Actual four-protocol generic share/payload fixtures preserve saved tab-wrapped
  names while rendering trimmed names; NUL and interior controls remain rejected.
- A separate name-only synthetic benchmark produced 128 unique names with 256 SHA
  calls total: 128 user hashes and 128 final display hashes. Preparation plus
  rendering took **10.539 seconds**, compared with approximately **110 seconds**
  in the review reproduction. This is not end-to-end synchronization timing.

The earlier core-check result is reused: these fixes change default computation,
display-name preparation and whitespace handling, with no changes to client JSON
serializers or technical tag construction. Local review must be rerun for the final
HEAD before push; its result and the remote security gate are recorded in the PR.
