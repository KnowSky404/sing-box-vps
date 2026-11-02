# Unified routing management

[简体中文](unified-routing-management.zh-CN.md)

## Scope and compatibility

Main menu 13 owns server routing/filtering, WARP accounts/assets, supported node
outbound overrides and full-client export preferences. Menus 1/2 edit protocol
connection parameters without asking about routing. New interactive nodes use
`outbound_policy=default`; edits retain the existing value. Explicit Agent records
remain authoritative. Node IDs, tags, credentials and existing store formats stay
unchanged. Legacy representations without a lossless independent-policy adapter
are listed as read-only rather than silently migrated.

No policy file means the existing server generation path. The first menu session
reads actual private-IP rejection and WARP state without creating files or treating
the old combined “advanced route” flag as advertising protection. Fresh installs
default to native egress, private-IP rejection and no advertising filtering; client
exports retain LAN/CN direct defaults. A bare installation needs no JSON parser
before its existing dependency preparation stage. Once dependencies and the core
are prepared, a fresh install seeds the policy before its first configuration.

## Policy and draft

`routing-policy.json` inside the private project directory is an optional additive
policy, not a migration of protocol or component state:

```json
{
  "schema_version": 1,
  "server": {
    "private_network_block": true,
    "adblock": false,
    "warp_ai": true,
    "warp_streaming": true,
    "rules": [],
    "rule_sets": []
  },
  "client": {"lan_direct": true, "cn_direct": true, "adblock": false},
  "adblock": {
    "url": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-ads-all.srs",
    "domains": [],
    "allow": []
  }
}
```

Rules have a unique `id`, `kind` (`domain`, `domain_suffix`, `ip_cidr`), `value`,
`action` (`direct`, `warp`, `reject`) and `enabled`. Rule-set records have a unique
`tag`, `type` (`remote`, `local`), `format` (`binary`, `source`), `url` or absolute
`path`, `update_interval`, `action` and `enabled`. Input is bounded inert JSON;
unknown fields, unsafe paths/URLs, duplicates and invalid types fail closed.
An empty ad URL permits a portable inline suffix list for operator-defined blocks
and isolated acceptance. Advertising exceptions exclude only ad rejection; they
do not force direct egress or bypass private-address controls.

WARP default enable/mode and existing domain/rule-set assets keep their current
state authorities. Node overrides stay in their existing per-instance records.
A private temporary draft combines these with the optional policy; editing,
listing and preview do not register an account, write live state or restart a
service. An input fingerprint rejects changes made outside the session.

## Routing behavior

With a saved policy, script-managed proxy tags receive sniffing before terminal
policy decisions, then private-address controls, advertising rejection, existing
node-specific egress, custom rules, AI/media presets and the default egress.
Protocol-required handling is preserved. Filtering applies to managed proxy
traffic, not every process on the VPS or unregistered/manual inbounds. Global
native egress does not remove a WARP endpoint still required by node/custom rules;
the overview lists these dependencies. Disabling an individual preset retains
the other preset and custom assets.

Private-address control resolves hostname destinations with `local-dns` before
matching IPs; any non-public address among the DNS answers is rejected, and the
original domain remains available to advertising/domain rules. With private
blocking disabled, enabled CIDR and potentially IP-based rule-set decisions
resolve destinations at their first IP-matching stage; earlier domain rules keep
their priority. IP routing/rejection therefore does not depend on the private
blocking switch. The supported
core behavior is established by the official [resolve implementation](https://github.com/SagerNet/sing-box/blob/v1.14.2/route/route.go)
and [private-IP matcher](https://github.com/SagerNet/sing-box/blob/v1.14.2/route/rule/rule_item_ip_is_private.go),
and by a loopback hostname/mixed-answer regression.

Existing configuration ownership and three-way merging remain mandatory. Managed
rule-set ownership requires an exact declared/generated object, never a broad
tag-prefix exemption. Manual values and their ordering are preserved. When that
ordering prevents the requested managed filtering precedence, application rejects
the ambiguity and restores state instead of silently moving operator rules.
Manual scope follows actual matcher semantics: missing, null or empty inbound
restrictions are global; inverted and logical conditions overlap managed traffic
unless a positive condition proves disjointness. Scope recognition is separate
from ownership, which still requires the exact generated object. Ownership does
not permit an early route/direct/bypass decision ahead of protection; overlapping
component decisions reject rather than move. Missing, null and empty legacy
actions are classified as routing decisions, matching the core. Advertising
exceptions use an inbound condition inside their logical AND; an accepted outer
field alone does not establish matching scope.
Typed projection recognizes bindings from trusted instance state, not from a
matching tag and shape alone. Unknown manual fallbacks remain in place or cause
a refusal; existing binding order must also be proved, including first-node
creation from an empty store. Source prechecks run before the legacy producer can
remove ambiguous target bindings. A preserved nonterminal prefix is not crossed.
Typed changes update the pure generation baseline in the same snapshot-protected
transaction, so a later global edit sees the committed scope. Pure generation
facts may reference operator-supplied objects. Baseline synchronization validates
a temporary merge with the complete, already-checked live context, requires
semantic equality with that live config, and saves only the pure facts; manual
objects are never imported into ownership. Existing REALITY
schema-1 migration stores its own backup inside the trusted rules journal,
leaving the external-file fingerprint protection unchanged; ordinary migration
keeps its established timestamp backup path. Legacy REALITY remains visible as
read-only before application and preview never migrates it. Takeover keeps live
configuration and generated facts unchanged; applying the routing draft explicitly
extends filtering to newly claimed tags, subject to the same ownership guards.

## Application and recovery

Application requires an installed, valid managed configuration and an exclusive
management lock. The pending-rules barrier is checked after acquiring, reusing
or upgrading the lock, with an explicit recovery exception. Rejection closes
only a descriptor opened by that attempt; inherited locks remain held. It
validates the draft/fingerprint, creates a private durable
`${SB_PROJECT_DIR}.rules-write.lock` journal and a whole-project snapshot, establishes
the prior generation baseline, stages policy/assets/node overrides, and generates
the complete candidate through existing graph/listener/core checks. Node policy
writes retain identity and use existing typed-store validation and revision checks.

Only a previously active service is restarted, once after the combined changes.
An inactive service stays inactive. The existing systemd unit and host firewall
are not rewritten. The snapshot is retained until service postchecks succeed.
Errors or INT/TERM/HUP restore project state and prior service activity; uncertain
recovery retains the journal and blocks other writes. Menu 13 exposes recovery
before reading partially written state. A committed previous snapshot is retained
privately outside the project directory for the explicit restore action, avoiding
recursive backups. Runtime purge or explicit project-config removal also removes
this private history; removing only the manager while keeping config retains it.
Restoring it refuses unrelated intervening configuration changes.
An existing policy's client-only edits validate/export preferences without server
regeneration or restart. Runtime logs are preserved separately on restoration;
concurrent changes to other manual/ACME files retain the journal instead of being
overwritten by automatic rollback.

WARP registration is an external action. A received result remains outside
project rollback until the outer rules transaction and service postchecks commit.
A failed application restores the old key and retains the received result for
reconciliation without another POST; committed recovery can finish receipt
cleanup. Restoring files does not claim to undo provider registration. Progress/errors omit private keys, tokens, full links and response
bodies.

## Client export

LAN direct, CN direct and advertising rejection are independent. CN disabling
removes matching route/DNS rules and unused CN rule sets while retaining the DNS
bootstrap needed to resolve proxy servers. Advertising rejection precedes CN
bypass. Client rule sets are portable remote/inline definitions, never VPS local
paths. Existing full-export validation, backup and atomic publication remain.
Preferences affect newly exported complete configs; sharing a URI or syncing a
SubMan node does not distribute routing preferences to a device.

## Verification and evidence

Required local checks cover no-prompt fresh/append/create/edit behavior, existing
overrides and no-jq dependency boundaries, policy validation and rule ordering,
precise ownership/manual coexistence, WARP dependency rendering, draft cancellation,
single application, failure/signal recovery, durable pending barriers and explicit
restore. Eight client switch combinations and representative server outputs must
pass the supported sing-box 1.14.2 core check. Real disposable Docker TCP/UDP paths
cover actual filtering/egress and service rollback; fixtures use owned local peers
and inline ad rules, not real WARP accounts or production credentials.

This is a bounded shared routing addition with explicit affected callers, not a
core-version or existing-state format migration. Tests follow AGENTS.md 4.2;
installation input fixtures are updated where their actual dialogue changes.
Local mocks, core checks, Docker, external providers, public connectivity and
production remain separate evidence.

### Scoped acceptance on 2026-11-02

- Host regressions cover prompts/default inheritance, menu drafts, exact ownership,
  manual ordering, typed-scope/baseline synchronization, rollback, signals and
  recovery. The `routing` group lists the focused checks explicitly.
- Real sing-box 1.14.2 checks pass for representative server candidates and all
  eight LAN/CN/advertising client combinations. Private-address probes cover
  hostname loopback and mixed public/private DNS answers.
- Disposable systemd Docker acceptance covers fresh HTTP installation, IP/domain
  private blocking, HTTP advertising rejection and fixed-direct overrides, typed
  HY2 append, one restart per server application, inactive application and explicit
  restore. The first run exposed stale typed generation facts; the corrected
  artifact `a980ad8b` passed a new fresh-to-restore replay. Its exact successful
  project output was then restored unchanged for HTTP and HY2 SOCKS5 UDP
  IP/domain echo and advertising-rejection probes. This latter result is an
  artifact data-plane check, not another fresh-install run.
- The earlier isolated restart-failure stage passed with real service rollback,
  restored config/state fingerprints and working filtering. Its later failed
  stage remains recorded as a failure; it is not reported as a passing full run.
- The final integrated artifact `0c1de022` passed a separate disposable Docker
  tail using the unchanged successful project output: actual systemd start-limit
  failure, client-only application while remaining failed with MainPID zero, and
  real full purge. Purge removes the project, private rule history, core, unit and
  manager while preserving an unrelated sibling marker. Host tests additionally
  cover script removal with/without config, unsafe history paths and pending
  journals. This tail does not repeat fresh installation or TCP/UDP acceptance.
- Follow-up local review found and corrected legacy migration self-backups
  being mistaken for concurrent files, and CIDR rules missing FQDN targets when
  private blocking was off. Real 1.14.2 probes cover CIDR/source/binary sets across
  direct/WARP/reject with literal, hostname, public and mixed DNS answers and
  domain-rule precedence (63 matrix probes). Public/WARP selections terminate
  at isolated block outbounds; they are matcher evidence, not external egress.
- The corrected artifact `42c2b18c` passed a new disposable schema-1 REALITY
  scenario: migration with one injected restart failure and real rollback, retry
  migration with one real restart, identical listener/inbound identity, private
  journal backup and unrelated manual HTTP marker preservation. Host checks cover
  indexed schema-1 and config-derived protocol state with existing key material,
  backup-write failure propagation and complete rollback without pending locks.
  Missing public-key material remains a protected refusal rather than key
  replacement. Ordinary migration backup behavior is covered separately.
- Subsequent precedence/concurrency review corrected empty inbound restrictions
  and legacy action defaults, component terminals ahead of filters, logical
  advertising scope, and pending journals appearing between the first check and
  lock acquisition. Real-core global/projector/application regressions preserve
  complete state on refusal; deterministic real-flock tests cover acquisition,
  inheritance, upgrades, recovery exceptions and descriptor cleanup.
- Artifact `83d20ed8` passed the complete representative Docker fixture in one
  run: fresh HTTP private blocking, operator-only HTTP coexistence, managed ads
  rejection and whitelist allowance, unchanged operator advertising traffic,
  fixed-direct protection, typed HY2 UDP ordinary/whitelist echo and ad rejection,
  real restart rollback, stopped restore, failed-unit client-only apply and purge.
  This whole-fixture result is the main routing runtime evidence.
- Artifact `2649d1a8` passed a separate actual-service manual-reference scenario:
  component API selector referencing a manual outbound, a preserved manual
  selector default, typed failure with real rollback, successful retry and later
  global private blocking. Pure baseline and backup stay free of manual objects;
  complete live graph/core checks and local marker traffic prove the context.
  The added listener remains active after global apply and manual traffic stays
  allowed. Its executed fixture and later equivalent listener/identity assertions
  are distinguished in the retained proof index.
- Final ownership revision `d3b4e5bb` passed the complete representative Docker
  fixture once: selector/manual-reference coexistence, HTTP manual fallback
  remaining after a custom rejection across HY2 creation and replacement,
  advertising scope/whitelist and UDP controls, actual rollback, stopped restore,
  failed-state client preferences and full purge. Nineteen real public-transaction
  cases separately cover trusted/missing/moved/duplicate bindings, empty-store
  activation, preserved nonterminal prefixes and rejected interleaving. Earlier
  unchanged protocol/CIDR results were reused; no protocol matrix was added.
- Mocked provider tests use the actual receipt/credential/outer-transaction code:
  successful registration followed by service failure preserves the received
  result, retry keeps the POST count at one, and committed recovery verifies
  key/receipt identity before cleanup. Ordinary registration regressions pass.

The unchanged `generate_config_commits_validated_candidate.sh` fixture also fails
on the original `14888ce` baseline: its `{"old":true}` live document triggers
`managed_config_conflict`. Ownership protection was retained; real generated
candidates and the Docker paths above provide the relevant generation evidence.
No full protocol matrix, real WARP registration, public-network or production
acceptance is claimed. Review/merge and Wiki publication are recorded separately
in the delivery PR.
