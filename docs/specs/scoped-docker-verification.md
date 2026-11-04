# Scoped Docker verification contract

[简体中文](scoped-docker-verification.zh-CN.md) · [SPEC index](README.md)

Status: Stage 1 implemented with scoped local/Docker acceptance. Stage 1 introduces three
independently selectable component scenarios. The roadmap below is not a claim
that every coexistence test has been decomposed. Local/mock, real Docker,
external-network and delivery evidence must be recorded separately.

## Problem and baseline

Baseline `4aa3b27` has a 3,536-line `multi_protocol_coexistence.sh` scenario. It
installs 13 protocol families, runs TCP and UDP probes, exercises transparent
host policy and multiple component adapters, then uses the real Tor network.
Its final smoke probes all installed protocols again. A change to one HTTP
outbound therefore has a much smaller required scope than this aggregate.

The component store uses one revision sequence: HTTP outbound starts at 0,
SOCKS UDP finishes at 35, and the final rule-set lifecycle finishes at 42.
Individual protocol stores have separate revisions. Conditional blocks that
skip unrelated tests would invalidate the aggregate's hard-coded component
revisions and resource assumptions. Decomposition must establish prerequisites,
not remove assertions or rely on state left by a previous verification run.

The Tor block permits up to 120 seconds of listener waiting and 24 requests with
15-second timeouts and one-second intervals: about 8 minutes 24 seconds of
configured waiting alone. Installation, downloads and other startup work are
additional. This is a static cost analysis, not a measured successful-run time.

## Invariants

- Keep `multi_protocol_coexistence` as the compatibility/full-coverage entrypoint
  with its existing protocol combination and cross-protocol assertions.
- Add explicit leaf scenarios for small changes. They retain real core checks,
  activation, data-plane assertions, transaction/CAS checks and cleanup evidence.
- Ordinary component choices must not implicitly select Tor, the complete
  coexistence scenario, upgrades or unrelated protocol fixtures.
- A real external-service test remains external evidence. A mock, configuration
  check, open listener or local marker cannot stand in for a working Tor circuit.
- Reuse the existing serial Docker transport and artifact envelope. New scenes
  remain local disposable-container checks; they do not authorize production
  changes, real SubMan writes or unrelated host operations.
- Passing scoped checks does not establish complete protocol acceptance. Follow
  [AGENTS.md section 4.2](../../AGENTS.md#42-测试边界与执行策略) for the required scope.

## Stage 1: finite implementation scope

| Scenario ID | Required baseline | Assertions and evidence |
| --- | --- | --- |
| `component_http_outbound` | Fresh SOCKS installation; empty component registry at revision 0 | Create a typed HTTP outbound and owned route, validate the live configuration, restart/activation, authenticated SOCKS-to-HTTP-proxy loopback marker, observed proxy authorization and header, then delete and prove the route/outbound are absent. Component revision 0→1→2. |
| `component_rule_sets` | Fresh SOCKS installation; empty component registry at revision 0 | Create/replace inline, local and remote rule sets; real core check and successful localhost HTTP fetch; delete all three and prove rule-set removal while preserving the source file. Seven component mutations, revision 0→7. |
| `component_tor_outbound` | Fresh SOCKS installation; empty component registry at revision 0; usable Tor executable and outbound network | Create a typed Tor outbound and ingress-scoped route, core check and activation, request `https://check.torproject.org/` through authenticated SOCKS, assert its Tor marker, capture diagnostics, then delete and prove route/outbound removal. Component revision 0→1→2. |

`fresh_install_socks` is the shared baseline scenario, not an instruction to
install every protocol. Its ordinary baseline assertions remain visible in the
plan and artifacts. The final `runtime_smoke` follows all mutations and probes
the final SOCKS installation. No new production `sbv` operation or operation
catalog descriptor is introduced by this developer-only selection surface.

### Composition and state

Each leaf selection must receive a fresh SOCKS baseline, including when several
leaf scenarios are requested in one invocation. The scheduler may perform this
reset before every leaf, or run each leaf in a separate fresh container. Stage 1
uses the existing baseline/reset mechanism; it must not infer readiness merely
because another scenario installed SOCKS earlier.

Deleting the last component leaves an empty registry with a monotonically
increased revision. An empty registry after the HTTP test has revision 2, not
revision 0; after the rule-set test it has revision 7. Consequently, reusing that
post-test state as a new revision-0 baseline is invalid even when its config
contains no component projection. Do not conceal this with opportunistic
revision reads or retries that bypass the intended CAS assertions.

For example, a combined HTTP/rule-set selection has this order:

```text
fresh_install_socks
component_http_outbound
fresh_install_socks
component_rule_sets
runtime_smoke
```

Duplicate requested leaves are deduplicated under the existing request rules;
necessary baseline resets are not deduplicated across different leaf tests.
A previous HTTP installation, upgraded core, aggregate run or deleted component
must not suppress the reset. Invalid selections fail before executing work.

### Selection and compatibility

The help/available-scenario surface lists the three leaf IDs. The full suite
continues to select the original 17 registered scenarios and obtains these
assertions through the unchanged aggregate; it must not also execute the three
new leaves and duplicate that coverage. Keep the selectable registry and the
full-suite registry distinct, and test that distinction explicitly.

Changes to a local HTTP/rule-set leaf file select that leaf and its required
baseline. Changes to shared coexistence helpers, the aggregate, the dispatcher
or the external Tor leaf do not silently
select a large runtime matrix: preserve `needs_scope` until the operator assigns
an explicit impact-based scope. A shared helper is not itself an executable
scenario. Planning remains read-only and produces the exact execution order.

```bash
bash dev/verification/run.sh --plan --base origin/main \
  --scenario component_http_outbound

bash dev/verification/run.sh --plan --base origin/main \
  --scenario component_rule_sets

# Explicit external-network acceptance; never an implicit dependency.
bash dev/verification/run.sh --plan --base origin/main \
  --scenario component_tor_outbound
```

Remove `--plan` only after checking that the selected tests, prerequisites and
scenario list cover the actual change. A development run does not automatically
become full-release acceptance.

## Further decomposition roadmap

The line ranges refer to the baseline scenario and are design references, not
runtime extraction offsets. Shared fixture resources must be separated from the
component whose test originally created them.

| Unit | Baseline lines | Minimal dependencies / retained boundary | Stage |
| --- | --- | --- | --- |
| Shared HTTP marker and UDP echo | 743–949 | Extract pure marker processes separately from Direct inbound assertions; reused by Selector, URLTest, Direct, Block, VLESS, Shadowsocks and SOCKS UDP. | Later |
| Shared TLS cover/certificate | 275–289, 441–479 | Owned local certificate and port 1090 cover, child cleanup; ShadowTLS outbound does not require a ShadowTLS inbound installation. | Later |
| Pure protocol/TLS coexistence | 291–500, 1700–1765 | Preserve 13-protocol inventory, exported authentication/trust and listener checks; omit unrelated component adapters only in a new dedicated scene. | Later |
| Per-protocol TCP/UDP probes | 1767–1894 | One protocol baseline and its generated client/core checks; distinguish native UDP, XUDP and UoT. | Later |
| Naive TCP UoT / HTTP3 transition | 1776–1871 | libcronet, certificate, saved pre-replacement artifacts, protocol CAS 1→2; HTTP3 negotiation is separate from UoT UDP payload. | Later |
| Snell v6/v5 transition | 1895–1959 | Save v6 evidence before protocol CAS 1→2 replacement; retain v5→v4 export mapping and TCP/packet-API UDP checks. | Later |
| Direct inbound TCP/UDP | 739–949 | Pure TCP/UDP markers, independent owned component create/delete and resource cleanup. | Later |
| Redirect / TProxy / namespace policy | 950–1111 | Disposable root container, veth/netns, iptables and policy routes; preserve replace/recovery and deletion of owned chains, marks, rules and routes. | Later |
| HTTP outbound | 501–738 | SOCKS ingress, independent authenticated local proxy/marker; add deletion assertion in leaf. | Stage 1 |
| SSH outbound | 1112–1282 | SOCKS ingress, temporary sshd/user/key and its own marker. | Later |
| SOCKS outbound TCP | 1283–1536 | SOCKS ingress, independent upstream SOCKS server and marker. | Later |
| Selector / URLTest | 1537–1699 | SOCKS ingress, pure HTTP marker; URLTest must execute a real health probe. | Later |
| Shadowsocks outbound TCP/UDP | 1960–2056, 2967–3153 | SOCKS ingress, SS2022 inbound, TCP marker/UDP echo, route-loop prevention and encrypted upstream evidence. | Later |
| Direct / Block outbound | 2057–2341 | SOCKS ingress and markers; Direct UDP must prove destination override, Block must assert rejection rather than fallback success. | Later |
| VLESS outbound TCP/XUDP | 2342–2637 | SOCKS ingress, markers and owned upstream/client processes; retain real handshake and XUDP payload. | Later |
| Tor outbound | 2638–2746 | SOCKS ingress, Tor executable and real public circuit; explicit external-network cost. | Stage 1 |
| ShadowTLS outbound | 2747–2966 | SOCKS ingress, pure TLS cover, owned upstream/inner listener and HTTP detour; four CAS mutations. | Later |
| SOCKS outbound UDP | 3154–3534 | SOCKS ingress, authenticated UDP-associate upstream and echo; inspect actual upstream request. | Later |
| Managed rule sets | 47–242, call at 3535 | Local HTTP file service, typed create/replace/delete, fetch and final removal assertions. | Stage 1 |

Later extraction should let aggregate and leaf scenes share assertion bodies,
with explicit revision bases and fixture contracts, so two implementations do
not drift. It must not replace runtime assertions with static string checks.
Stage 1 does not promise that every later unit already has an independent ID.

## Acceptance and evidence record

1. **Local/static and mocks:** verify leaf selection, fresh-baseline ordering for
   independent/combined requests, final smoke, duplicate requests, invalid IDs,
   the original full list without repeated leaves, read-only planning, dispatcher
   routing, cleanup and preserved failure/artifact outcomes. Validate syntax,
   generated installer/version consistency, documentation links and real diff.
2. **Real Docker:** execute HTTP outbound and rule-set leaves on clean disposable
   baselines. Preserve core checks, service state, payload/fetch markers, exact
   CAS outcomes, deletion checks and artifact extraction. Report measured time
   and actual selected prerequisites; these checks are not public acceptance.
3. **External Tor:** only a successful explicit real-network execution establishes
   Tor acceptance. If not executed, record it as unexecuted; local/mock coverage
   cannot substitute for it.
4. **Legacy aggregate/full:** preserved code and dispatch/selection checks do not
   mean the aggregate or complete suite ran. Record any unexecuted aggregate/full
   acceptance separately; do not run it merely because this SPEC or a PR changed.

| Evidence boundary | Result / retained evidence |
| --- | --- |
| Local/static and mock selection/dispatch checks | Passed: 19 selected host checks; changed syntax, version/build sync and diff checks. Planner/atomic checks reran after the final scope-policy adjustment. |
| Real Docker HTTP outbound leaf | Passed: run `20261104042431`, real authenticated marker and CAS 0→1→2 cleanup. |
| Real Docker rule-set leaf | Passed: same run, real localhost HTTP fetch, CAS 0→7 and removal. |
| Explicit real-network Tor leaf | Passed: explicitly selected in the same run; real Tor page marker, create/delete, core checks and final SOCKS smoke. |
| Original aggregate / registered full suite | Not executed by default; unchanged aggregate coverage remains a separate boundary. |
| Current-head reviews, PR merge and Wiki publication | See the implementation PR and separate Wiki commit; these gates are independent of the test evidence. |

On this VPS, the three-leaf Docker run took about 601 seconds including three
fresh SOCKS baselines, final smoke and artifact transfer. Scenario artifact
start/result timestamps give about 59 seconds for HTTP, 350 for rule sets, 66 for
Tor and 7 for final smoke; these leaf times exclude their installation baselines.
Tor timing varies with public circuits. This is one scoped run, not a benchmark
against the old full suite. The 19 host checks took roughly two minutes, dominated
by the existing artifact mock (93 seconds). Results are in the run directory;
local resumptions after fixing an old full-manifest count assumption are retained
separately. No old aggregate/full Docker or production-host acceptance is claimed.
