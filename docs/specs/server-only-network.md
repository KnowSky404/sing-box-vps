# Server-only network management

[简体中文](server-only-network.zh-CN.md)

Status: implemented; scoped acceptance and evidence boundaries are recorded below. This contract supersedes
the client-routing, advertising, private-address filtering and installation
defaults in [Unified routing management](unified-routing-management.md).

## 1. Findings and scope

Baseline: `34c7140`. The old network menu mixes server policy with device LAN/CN
bypass and client advertising preferences. Full client exports are exposed in
the node menu, Agent CLI, status and protocol capabilities. Fresh installation
seeds a policy with private-address rejection, installation saves WARP settings,
and config generation creates WARP assets and may register an account. Hiding
menu entries alone does not remove those side effects.

The project manages a VPS server. Client interaction is limited to node sharing
(URI/QR where supported) and SubMan synchronization. Internal node outbound
builders remain for SubMan, node connection materials and isolated protocol
probes; they do not generate a complete client configuration or client routing.

## 2. Menu and ownership

Keep deployment/service controls, then expose these independent functions:

- **11 Node sharing and subscription**: share links/QR, SubMan, node display label.
- **12 Network and routing**: Block CN, WARP, node outbound selection,
  AI/streaming selection and egress/media diagnostics.
- **13 System settings**: BBR and inbound/outbound stack controls.
- **14/15 Script maintenance**: update/remove the management script.

The network menu has three policy areas: Block CN, WARP (including node
overrides and compatible advanced sources), and AI/streaming. Preview/apply/
restore and diagnostics are operations, not additional routing features.
Remove advertising, LAN access control, client bypass and complete client
configuration export. Remove `sbv agent export-client --json`, its discovery
and status fields, and obsolete full-export tests. Existing exported files are
not deleted as a side effect of upgrading the script.

Media checks must not register/re-register WARP, change routes, or modify node
credentials. WARP checks require already prepared valid account material. Running
diagnostics after editing a draft must preserve pending choices. Only proven
diagnostic-cache changes may refresh private draft fingerprints; an already stale
draft or any unrelated concurrent change must retain the normal CAS rejection.

## 3. Installation and lifecycle isolation

Fresh installation asks only for core/node/connection parameters. Defaults:
native egress, Block CN off, WARP off, no advertising/private-address policy.
Do not create a routing policy, WARP key/settings/domain/source files or WARP
asset directory merely to install a node. Retain ordinary node, service,
certificate and listener preparation.

New nodes inherit current server policy. Editing preserves the existing node
override. Node creation/edit/removal may update the exact managed listener tag
membership in already applied policy rules so the same policy still applies.
They must not change the policy choices, WARP settings/key/assets, other nodes'
overrides, operator DNS/routes/outbounds, or register/repair a WARP account.
Missing required WARP credentials cause a clear failure and rollback; repair
belongs to an explicit network operation. Config rendering reads assets only.

## 4. Server policy

Clean policy format:

```json
{
  "schema_version": 2,
  "server": {
    "block_cn": false,
    "warp_ai": true,
    "warp_streaming": true,
    "rules": [],
    "rule_sets": []
  }
}
```

The two collections preserve existing explicit server rules and allow bounded
advanced WARP customization without a separate general-purpose top-level menu.
Strict field/type/size/path validation, source ownership and dependency checks
remain. No client, advertising or private-address setting is written in v2.

Block CN is disabled by default. When enabled, reject China domain and IP
rule-set matches for managed proxy listeners, including resolved domain targets.
Use maintained remote binary `geosite-cn`/`geoip-cn` sources and direct downloads;
preserve the target-core HTTP-client compatibility boundary. Ordering is:
required protocol processing/sniff → Block CN → node override → explicit
server rule/source → AI/streaming WARP presets → global default. Block CN
therefore also applies to a node fixed to direct or WARP. This is outbound
destination filtering, not source-IP firewalling or host-wide routing.

Configuration references (retrieved through Context7, then checked with the
actual target core): [route resolve/reject actions](https://github.com/SagerNet/sing-box/blob/v1.14.2/docs/configuration/route/rule_action.md)
and [remote rule-set HTTP clients](https://github.com/SagerNet/sing-box/blob/v1.14.2/docs/configuration/rule-set/index.md).

WARP supports native default, selective AI/streaming/custom routing and full
managed proxy traffic. Global native/off does not remove WARP still required by
a node or explicit rule. Per-node choices are inherit/direct/WARP. Node and
global controls share one transactional network apply; no node credential,
identity, listener or SubMan object changes are implied.

## 5. Existing installations and transactions

Read valid v1 policy without changing files. Node operations preserve its
existing effective server policy until the owner explicitly applies network
settings. Draft creation converts v1 to v2 in memory and marks this cleanup as
pending even if no toggle is changed. Application removes only old rules proven
to belong to the script by the generated baseline and exact policy projection.
When the live config is absent, a trusted generated baseline still carries its
existing restrictions through recovery; neutral fresh defaults must not erase
them. Do not claim operator rules by their shape, protocol or tag prefix. Preserve
unknown/manual rules or refuse a conflicting/lossy application.

Opening, previewing, cancelling or leaving the network menu does not write state.
Apply uses existing lock/fingerprint checks, private snapshots, staged candidate
validation, backups, atomic publication, one restart only if originally active,
postchecks, rollback and interrupted-transaction recovery. Explicit restore
restores prior policy and config together, including v1 if that was the snapshot.
WARP registration is allowed only as part of an explicit network operation;
registration receipts and unavoidable external side effects remain documented.

## 6. Test plan

Because this changes persisted policy format and shared config rendering, run
the explicit full host-test manifest and registered Docker scenario set from
`bash dev/verification/run.sh --plan --base origin/main --full`. Inspect and save
the expanded names; this is not every file under `tests/`. Container-only
fixtures require dedicated disposable containers and are not host tests.

Required focused coverage before the full pass:

| Area | Assertions |
| --- | --- |
| Menus and Agent | Three network policy areas, diagnostics nested, no client/ad/LAN UI, no export command/capability/status; URI/QR/SubMan remain |
| Install/edit | No routing questions; neutral fresh defaults; policy/key/env/domain/source fingerprints unchanged; no implicit WARP registration |
| Policy | Strict v1/v2 validation, v1 read preservation, explicit v2 cleanup, Block CN domain/IP ordering and managed-listener scope |
| Lifecycle | New-node inheritance, retained overrides, typed/global baseline continuity, manual-config preservation/refusal |
| Transactions | Cancel/no-op, stale draft/lock, edit → diagnose → apply without lost choices, cache-only refresh with race checks, apply once, stopped/failed service, explicit legacy WARP repair, validation/restart failure and signal rollback, recovery/restore |
| Sharing | SubMan payload/mock/orchestration and URI/QR regressions; internal per-node builders/probes retained |
| Real core/runtime | sing-box 1.14.2 check, fresh install, Block CN TCP/UDP rejection with isolated local rule fixtures, non-CN allowance, install-after-policy isolation and legacy cleanup/rollback |

Use deterministic local China rule fixtures for filtering probes. Such probes
prove rendering/routing behavior, not public rule-source availability or real
Cloudflare WARP handshake/egress. Actual SubMan writes, real account registration,
public connectivity, production rollout, local review, remote security review,
merge and Wiki publication are separate evidence boundaries.

Estimate time from the selected manifest before execution. The full host and
registered Docker runs include large existing component matrices and can exceed
one hour in this environment, in addition to protocol/core/certificate setup.
Inspect specific slow/failing cases before retrying. Reuse unchanged passing
results and rerun only failures and tests affected by repairs.

## 7. Delivery evidence

Completed isolated acceptance uses sing-box 1.14.2 and disposable systemd
containers with external networking disabled:

- `routing_policy_runtime.sh`: fresh installation, CN domain/IP TCP and UDP
  filtering, node inheritance, fixed-direct precedence, network fingerprints,
  restart-failure rollback, v1 preservation/cleanup and explicit restore passed.
  Artifacts: `/tmp/sbv-routing-runtime-20261102T074735Z.OfxddhlN`.
- `routing_policy_legacy_runtime.sh`: old REALITY state, actual first migration,
  failure rollback and retry passed. Artifacts:
  `/tmp/sbv-server-only-legacy-runtime-20261102T075319Z.q2p797QX`.
- `routing_policy_manual_references_runtime.sh`: manual outbound/selector
  references, typed failure/retry and subsequent global policy apply passed;
  operator listener traffic remained usable. Artifacts:
  `/tmp/sbv-server-only-manual-references-runtime-20261102T075805Z.w14PRfeo`.

Local review found two additional edges: absent live config could inherit the old
private-block initial default, and absent policy/baseline could claim a manual
private rejection by shape. Both are fixed in the neutral default/common ownership
projection and have targeted actual-core regressions with negative controls.

Follow-up review fixes cover explicit legacy WARP credential repair before
baseline generation, retention of operator endpoint options, and media diagnostic
cache changes within an open draft. Scoped WARP dependency removal and component
generation preserve the correct old-state inventory context. Dedicated regressions exercise provider
receipts/retries, exact rollback, ordinary node/diagnostic isolation, and CAS
rejection of concurrent non-cache changes.

The 199-entry full host manifest completed, including scoped repairs and valid
result reuse; the reconciled record is
`/tmp/sbv-server-only-delivery/host-results.json`. The registered Docker scope is
all 16 scenarios; per-scenario results, artifact bundles, current-head reviews and
merge status belong to the delivery PR. No merge is allowed while a required
scenario or the exact-head security review remains incomplete.

The planner deliberately reports `needs_scope` for edited container-only fixtures.
Its complete host/scenario lists are executed directly alongside the dedicated
fixtures above, without omitting changed files or pretending `--full` runs those
fixtures. The slow registered scenarios include their existing component matrices;
passing unchanged paths are reused rather than restarted after an unrelated fix.

Passing earlier results are reused only for unchanged executed branches. The
initial full artifact was `73fe2b5a`; the CN runtime used `03db0201` before the
unused preset constant removal and stricter WARP preparation guard (its exercised
WARP-dependency condition is false in both versions). Later neutral-default and
unproven-baseline fixes are covered separately. This is not a claim that every
result ran on one byte-identical artifact, nor external-service/production
acceptance.
