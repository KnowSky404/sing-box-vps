# Scoped Docker verification contract

[简体中文](scoped-docker-verification.zh-CN.md) · [SPEC index](README.md)

Status: Accepted within this SPEC's finite runtime scope. The complete decomposition
roadmap is implemented; all 32 independently selected Stage 2 scenes and the
aggregate compatibility run passed real Docker acceptance (33/33). Stage 1's
historical evidence is retained separately. The default 17-scenario full suite
and production acceptance are not claimed.

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

## Stage 1: original component leaves

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
reset before every leaf, or run each leaf in a separate fresh container. The
implementation uses the existing baseline/reset mechanism; it must not infer
readiness merely because another scenario installed SOCKS earlier.

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

## Stage 2: complete selectable scope

Every scenario below starts from its own `fresh_install_socks`. Component leaves
create only their required local upstreams, markers and component records. A
protocol leaf additionally installs only its target protocol; the SOCKS leaf
uses the baseline SOCKS instance. Shared HTTP/UDP marker and TLS-cover fixtures
own their child processes independently of the Direct or ShadowTLS components
that originally created them. Generated server and probe configurations still
require real core checks.

| Scenario ID | Retained runtime boundary |
| --- | --- |
| `component_ssh_outbound` | Temporary sshd, user/key and marker; authenticated outbound data plane, owned route and create/delete lifecycle. |
| `component_socks_outbound` | Independent authenticated upstream SOCKS server, TCP marker and observed upstream request. |
| `component_selector_outbound` | Marker through the selected owned outbound; selector projection and lifecycle. |
| `component_urltest_outbound` | Real URLTest health request and selected-path marker, followed by component removal. |
| `component_shadowsocks_outbound` | SS2022 upstream and real TCP marker, encrypted upstream and route-loop boundaries. |
| `component_shadowsocks_udp_outbound` | Independent SS2022 upstream, UDP echo and encrypted UDP data-plane evidence. |
| `component_direct_outbound` | TCP marker and UDP destination override; owned route and create/delete assertions. |
| `component_block_outbound` | Explicit rejection through Block; successful fallback cannot satisfy the assertion. |
| `component_vless_outbound` | Owned VLESS upstream/client fixtures, real TCP handshake and XUDP payload. |
| `component_shadowtls_outbound` | Local TLS cover and inner upstream, real HTTP detour and four CAS mutations; no unrelated ShadowTLS inbound installation. |
| `component_socks_udp_outbound` | Authenticated UDP-associate upstream and echo; inspect the real upstream request. |
| `component_direct_inbound` | Independent TCP and UDP Direct components, exact marker payloads, delete both components and prove listener/route removal; registry 0→4. |
| `component_redirect_inbound` | Redirect data plane and owned NAT chains; create/delete, fixture and listener cleanup; registry 0→2. |
| `component_tproxy_inbound` | Namespace/veth TCP and UDP probes, two managed replacements, diagnostics, deletion of owned chains, marks, policy rules and routes; registry 0→4. |
| `component_transparent_policy` | Redirect/TProxy combination and joint diagnostics without Direct components; registry 0→6 and complete owned-resource cleanup. |

All protocol probe IDs are explicit; `vless_reality` is the normalized scenario
suffix for the VLESS REALITY family.

| Protocol probe ID | Data plane / additional dependency |
| --- | --- |
| `protocol_probe_vless_reality` | TCP and UDP through the generated client; existing interactive-only test fixture and external `www.cloudflare.com` TLS cover. Explicit external selection. |
| `protocol_probe_mixed` | TCP and UDP. |
| `protocol_probe_hy2` | TCP and native UDP; target certificate/client checks. |
| `protocol_probe_anytls` | TCP and UDP via UoT. |
| `protocol_probe_socks` | TCP and UDP through the fresh SOCKS baseline. |
| `protocol_probe_http` | TCP only; no UDP claim. |
| `protocol_probe_shadowsocks` | TCP and UDP. |
| `protocol_probe_trojan` | TCP and UDP; target certificate/client checks. |
| `protocol_probe_tuic` | TCP and native UDP; target certificate/client checks. |
| `protocol_probe_vmess` | TCP and UDP through the generated client. |
| `protocol_probe_snell` | Snell v6 TCP and packet-API UDP; replacement is a separate scenario. |
| `protocol_probe_shadowtls` | Existing HTTP-over-ShadowTLS composite TCP probe; no UDP/UoT claim. |
| `protocol_probe_naive` | Initial TCP plus UDP via UoT; transition is a separate scenario. |
| `protocol_naive_transition` | Save TCP/UoT evidence, protocol CAS 1→2, then test UDP-only/HTTP3 transport carrying TCP; preserve libcronet and certificate prerequisites. |
| `protocol_snell_transition` | Save v6 TCP/UDP evidence, protocol CAS 1→2 to v5, retain v5→v4 client mapping and both TCP/packet-API UDP probes. |
| `protocol_coexistence` | All 13 protocol families, exported authentication/trust and listener checks plus their protocol probes; omit component adapters and the separately selectable transitions. Includes the explicit external REALITY cover boundary. |

The protocol fixtures preserve existing acceptance paths; their use does not add
new production operation-catalog capabilities or erase an existing
`interactive_only` limitation. Native UDP, XUDP, UoT and HTTP3 negotiation remain
distinct assertions. A TCP-only protocol cannot gain a UDP claim from a different
protocol's successful probe. Protocol probes and coexistence retain installed
configurations/certificates for final smoke; Naive and Snell transitions retain
their final UDP-only and v5 states respectively. Fixture cleanup removes owned
peers and temporary work trees without deleting that installed state.

### Selection and compatibility

The help and selectable registry expose all listed leaves. The default `--full`
set remains the original 17 scenarios, obtaining component and protocol coverage
through `multi_protocol_coexistence` rather than repeating the new leaves. The
aggregate and leaves share assertion bodies with explicit revision bases; the
aggregate retains its original component revision sequence and combination
assertions. A compatibility run must exercise this shared path, not merely check
that its ID remains selectable.

Ordinary local leaf changes may select that leaf and its baseline. Changes to
shared fixtures/assertions, aggregate, dispatcher or an external REALITY/Tor
scenario retain `needs_scope` until the operator assigns an impact-based scope.
A helper is not an executable scenario. Do not silently select every caller,
complete coexistence or external traffic to resolve unknown shared impact.
Planning remains read-only and prints the exact reset/probe/smoke order.

```bash
# Select the changed outbound, retaining full branch-diff checks.
bash dev/verification/run.sh --plan --base origin/main \
  --scenario component_vless_outbound

# A single protocol probe, rather than thirteen protocol installations.
bash dev/verification/run.sh --plan --base origin/main \
  --scenario protocol_probe_hy2

# Host-network policy without other component adapters.
bash dev/verification/run.sh --plan --base origin/main \
  --scenario component_tproxy_inbound

# Explicit external-network acceptance; never an implicit dependency.
bash dev/verification/run.sh --plan --base origin/main \
  --scenario protocol_probe_vless_reality
bash dev/verification/run.sh --plan --base origin/main \
  --scenario component_tor_outbound
```

Remove `--plan` only after checking that tests, prerequisites and scenarios cover
the actual change. A development run does not automatically become full-release
acceptance. Every selected leaf receives a fresh baseline; final `runtime_smoke`
executes once after all selected mutations and probes the final installed state.

## Implemented decomposition roadmap

The line ranges refer to the baseline scenario and are design references, not
runtime extraction offsets. Shared fixture resources must be separated from the
component whose test originally created them.

| Unit | Baseline lines | Minimal dependencies / retained boundary | Implementation / current acceptance |
| --- | --- | --- | --- |
| Shared HTTP marker and UDP echo | 743–949 | Extract pure marker processes separately from Direct inbound assertions; reused by Selector, URLTest, Direct, Block, VLESS, Shadowsocks and SOCKS UDP. | Implemented; scoped Docker passed (evidence below) |
| Shared TLS cover/certificate | 275–289, 441–479 | Owned local certificate and port 1090 cover, child cleanup; ShadowTLS outbound does not require a ShadowTLS inbound installation. | Implemented; scoped Docker passed (evidence below) |
| Pure protocol/TLS coexistence | 291–500, 1700–1765 | Preserve 13-protocol inventory, exported authentication/trust and listener checks; omit unrelated component adapters only in a new dedicated scene. | Implemented; scoped Docker passed (evidence below) |
| Per-protocol TCP/UDP probes | 1767–1894 | One protocol baseline and its generated client/core checks; distinguish native UDP, XUDP and UoT. | Implemented; scoped Docker passed (evidence below) |
| Naive TCP UoT / HTTP3 transition | 1776–1871 | libcronet, certificate, saved pre-replacement artifacts, protocol CAS 1→2; HTTP3 negotiation is separate from UoT UDP payload. | Implemented; scoped Docker passed (evidence below) |
| Snell v6/v5 transition | 1895–1959 | Save v6 evidence before protocol CAS 1→2 replacement; retain v5→v4 export mapping and TCP/packet-API UDP checks. | Implemented; scoped Docker passed (evidence below) |
| Direct inbound TCP/UDP | 739–949 | Pure TCP/UDP markers, independent owned component create/delete and resource cleanup. | Implemented; scoped Docker passed (evidence below) |
| Redirect / TProxy / namespace policy | 950–1111 | Disposable root container, veth/netns, iptables and policy routes; preserve managed replacement, failure cleanup and deletion of owned chains, marks, rules and routes. | Implemented; scoped Docker passed (evidence below) |
| HTTP outbound | 501–738 | SOCKS ingress, independent authenticated local proxy/marker; add deletion assertion in leaf. | Implemented; Stage 2 Docker revalidated (history also retained) |
| SSH outbound | 1112–1282 | SOCKS ingress, temporary sshd/user/key and its own marker. | Implemented; scoped Docker passed (evidence below) |
| SOCKS outbound TCP | 1283–1536 | SOCKS ingress, independent upstream SOCKS server and marker. | Implemented; scoped Docker passed (evidence below) |
| Selector / URLTest | 1537–1699 | SOCKS ingress, pure HTTP marker; URLTest must execute a real health probe. | Implemented; scoped Docker passed (evidence below) |
| Shadowsocks outbound TCP/UDP | 1960–2056, 2967–3153 | SOCKS ingress, SS2022 inbound, TCP marker/UDP echo, route-loop prevention and encrypted upstream evidence. | Implemented; scoped Docker passed (evidence below) |
| Direct / Block outbound | 2057–2341 | SOCKS ingress and markers; Direct UDP must prove destination override, Block must assert rejection rather than fallback success. | Implemented; scoped Docker passed (evidence below) |
| VLESS outbound TCP/XUDP | 2342–2637 | SOCKS ingress, markers and owned upstream/client processes; retain real handshake and XUDP payload. | Implemented; scoped Docker passed (evidence below) |
| Tor outbound | 2638–2746 | SOCKS ingress, Tor executable and real public circuit; explicit external-network cost. | Implemented; aggregate Docker passed; Stage 1 history retained |
| ShadowTLS outbound | 2747–2966 | SOCKS ingress, pure TLS cover, owned upstream/inner listener and HTTP detour; four CAS mutations. | Implemented; scoped Docker passed (evidence below) |
| SOCKS outbound UDP | 3154–3534 | SOCKS ingress, authenticated UDP-associate upstream and echo; inspect actual upstream request. | Implemented; scoped Docker passed (evidence below) |
| Managed rule sets | 47–242, call at 3535 | Local HTTP file service, typed create/replace/delete, fetch and final removal assertions. | Implemented; aggregate Docker passed; Stage 1 history retained |

Aggregate and leaves share assertion bodies with explicit revision bases and
fixture contracts. Static host contracts verify composition and failure cleanup;
they do not replace real data-plane or kernel-resource assertions. Existing
managed replacement/failure cleanup is distinct from an explicitly injected
`component recover` command test; record such recovery evidence separately.

## Acceptance and evidence record

1. **Local/static and mocks:** verify every leaf's selection and dispatch,
   fresh-baseline ordering for individual/combined requests, final smoke,
   duplicate/invalid requests, original full-list compatibility, read-only
   planning, explicit external boundaries, owned cleanup and failure/artifact
   propagation. Check syntax, version/build sync, links and the complete diff.
2. **Stage 2 real Docker:** execute every new outbound/policy/protocol leaf and
   both transition scenarios on clean disposable baselines. Retain server and
   client core checks, service state, exact payloads, CAS and deletion/cleanup
   evidence. Record actual prerequisites and per-scenario results and timings.
3. **External network:** REALITY probes/coexistence and Tor require explicit
   selection and successful real-network evidence; a local marker or mock
   cannot replace that boundary. Record unavailable external acceptance as
   incomplete rather than silently falling back to a different assertion.
4. **Aggregate compatibility:** actually run `multi_protocol_coexistence` after
   extracting its shared assertions, preserving the original inventory, CAS
   sequence and cross-protocol/component checks. This finite implementation
   acceptance does not require rerunning unrelated upgrade, uninstall and other
   original full-suite scenarios. An unexecuted default 17-scenario full set
   remains a separate evidence boundary.
5. **Completion:** this SPEC's complete decomposition is accepted only when all
   Stage 2 leaves and aggregate compatibility have real Docker results. Historical
   Stage 1 passes and host contracts alone cannot close the Stage 2 table.

### Stage 1 historical acceptance

The following results belong to run `20261104042431`; they are preserved evidence,
not claims that Stage 2 code has already passed the same checks.

| Evidence boundary | Result / retained evidence |
| --- | --- |
| Local/static and mock selection/dispatch checks | Passed: 19 selected host checks; changed syntax, version/build sync and diff checks. Planner/atomic checks reran after the final scope-policy adjustment. |
| Real Docker HTTP outbound leaf | Passed: run `20261104042431`, real authenticated marker and CAS 0→1→2 cleanup. |
| Real Docker rule-set leaf | Passed: same run, real localhost HTTP fetch, CAS 0→7 and removal. |
| Explicit real-network Tor leaf | Passed: explicitly selected in the same run; real Tor page marker, create/delete, core checks and final SOCKS smoke. |
| Original aggregate / registered full suite | Not executed during Stage 1; Stage 2 aggregate compatibility and the default full suite remain separate boundaries. |
| Current-head reviews, PR merge and Wiki publication | See the implementation PR and separate Wiki commit; these gates are independent of the test evidence. |

On this VPS, the three-leaf Docker run took about 601 seconds including three
fresh SOCKS baselines, final smoke and artifact transfer. Scenario artifact
start/result timestamps give about 59 seconds for HTTP, 350 for rule sets, 66 for
Tor and 7 for final smoke; these leaf times exclude their installation baselines.
Tor timing varies with public circuits. This is one scoped run, not a benchmark
against the old full suite. The 19 host checks took roughly two minutes, dominated
by the existing artifact mock (93 seconds). Results are in the run directory;
local resumptions after fixing an old full-manifest count assumption are retained
separately. No old aggregate/full Docker or production-host acceptance is claimed by this historical run.

### Stage 2 current acceptance

All 31 new leaves and the refactored HTTP leaf passed independently: 32 scenes
with fresh SOCKS baselines and their required fixtures. The aggregate compatibility
run also passed, closing this SPEC's runtime scope at 33/33. The table records
actual scenario artifact timestamps, not estimates: seconds exclude separately
scheduled `fresh_install_socks` baselines, final smoke and artifact transfer.
Installation work performed inside a scene is included: single-protocol leaves
install their target there, pure coexistence installs its remaining protocols,
and the aggregate includes its own 13-protocol installation. Do not compare these
scene timings with Stage 1's 601-second complete three-leaf run or claim a default
17-scenario full-suite speedup from them.

| Evidence boundary | Current result |
| --- | --- |
| Initial integrated host checks | Passed: 27 selected checks in `20261104073759`, including planning, dispatch, artifacts, leaf/fixture contracts and related documentation. Its `VERIFY_SKIP_REMOTE` result is host evidence only. |
| Targeted resumptions after fixes | Passed: Redirect partial-creation/ownership and TProxy invalid-registry cleanup, URLTest independent health requests, shared HTTP relocation and leaf selection. Repeated only affected contracts; retained earlier results for unchanged inputs. |
| Structured protocol probe checks | Passed: new `tests/verification_protocol_probe_structured_basics.sh`, existing HY2/AnyTLS probe and matrix checks; the new check also passed on the integrated archive-owner baseline. |
| Default original 17-scenario full set | Not executed or required for this finite decomposition acceptance; no full-suite pass claimed. |
| Current-head local/security reviews, PR merge and Wiki publication | Evidence is recorded in the implementation PR and Wiki history, separately from this runtime table. |

| Scene | Real Docker run | Scene seconds | Result |
| --- | --- | --- | --- |
| `component_http_outbound` | `20261104074232` | 59 | Passed |
| `component_block_outbound` | `20261104074232` | 59 | Passed |
| `component_direct_inbound` | `20261104075528` | 180 | Passed |
| `component_direct_outbound` | `20261104074232` | 59 | Passed |
| `component_redirect_inbound` | `20261104075528` | 83 | Passed |
| `component_selector_outbound` | `20261104074232` | 59 | Passed |
| `component_shadowsocks_outbound` | `20261104074232` | 93 | Passed |
| `component_shadowsocks_udp_outbound` | `20261104075528` | 93 | Passed |
| `component_shadowtls_outbound` | `20261104075528` | 160 | Passed |
| `component_socks_outbound` | `20261104074232` | 58 | Passed |
| `component_socks_udp_outbound` | `20261104075528` | 59 | Passed |
| `component_ssh_outbound` | `20261104074232` | 59 | Passed |
| `component_tproxy_inbound` | `20261104075528` | 236 | Passed |
| `component_transparent_policy` | `20261104075528` | 406 | Passed |
| `component_urltest_outbound` | `20261104074232` | 58 | Passed |
| `component_vless_outbound` | `20261104075528` | 64 | Passed |
| `protocol_coexistence` | `20261104083008` | 459 | Passed |
| `protocol_naive_transition` | `20261104083008` | 70 | Passed |
| `protocol_probe_anytls` | `20261104083008` | 31 | Passed |
| `protocol_probe_http` | `20261104083008` | 24 | Passed |
| `protocol_probe_hy2` | `20261104083008` | 32 | Passed |
| `protocol_probe_mixed` | `20261104083008` | 30 | Passed |
| `protocol_probe_naive` | `20261104083008` | 33 | Passed |
| `protocol_probe_shadowsocks` | `20261104083008` | 24 | Passed |
| `protocol_probe_shadowtls` | `20261104083008` | 29 | Passed |
| `protocol_probe_snell` | `20261104083008` | 29 | Passed |
| `protocol_probe_socks` | `20261104083008` | 1 | Passed |
| `protocol_probe_trojan` | `20261104083008` | 40 | Passed |
| `protocol_probe_tuic` | `20261104083008` | 33 | Passed |
| `protocol_probe_vless_reality` | `20261104082117` | 40 | Passed |
| `protocol_probe_vmess` | `20261104083008` | 40 | Passed |
| `protocol_snell_transition` | `20261104083008` | 67 | Passed |
| `multi_protocol_coexistence` compatibility | `20261104085357` | 6164 | Passed: original CAS 0→42 and complete shared protocol/component assertion orchestration. |

The ordinary outbound scenes took 58–93 seconds each. ShadowTLS outbound took
160 seconds; Direct inbound 180, TProxy 236, and combined transparent policy
406. Individual protocol probes took 1–40 seconds; Snell and Naive transitions
67 and 70 respectively; pure protocol coexistence 459. These are scene-only
measurements on this VPS, excluding only separately scheduled baselines, final
smoke and transfer; they are not task turnaround totals. In particular, the
6164-second aggregate includes its internal 13-protocol installation. Its following
final smoke passed in 50 seconds, and both remote execution and artifact extraction
returned 0. A single protocol plus its SOCKS baseline, an HTTP component leaf and
the complete aggregate exercise different scopes; these observations are not a
controlled performance comparison against the original 17-scenario full suite.

Run `20261104082117` passed explicit REALITY acceptance, then failed at the Mixed
probe because verification code still assumed legacy scalar authentication/state
for typed instances. Only the Mixed/HY2/AnyTLS verification probe extraction was
adapted to the existing production exporters. Run `20261104083008` resumed Mixed
and the remaining protocol/transition/coexistence scenes successfully; the already
passed REALITY result was reused because its tested path and dependencies did
not change. This was a focused recovery, not a restart of all passed leaves.

The first component batch, `20261104074232`, completed remotely with exit 0 and
a complete artifact bundle. A private-driver edit while it was running caused
local extraction status 2. The original bundle was recovered and extracted;
`summary.log` records `remote_status=success_from_recovered_complete_artifacts`
and `recovery=original_complete_bundle_extracted_without_rerunning_scenarios`.
The driver error is retained rather than reported as an initially clean run;
those successful scenes were not rerun.

HTTP fixture/assertion definitions were subsequently relocated without content
changes: `verification_atomic_http_fixture` retained SHA-256
`61b9d04a7b011fce6591185957cc664e03d5c273002b164b8cd0cb66fba77e4b`, and
`verification_case_http_outbound` retained
`3ad78ba263640756ad1f3de7fa2d4fb1d5612aed217b80cf3fe112802a1e6694`.
Focused host checks passed after relocation; the real HTTP result above is
reused. The delivery worktree integrates archive-owner baseline `1e0e781`:
its upstream historical-archive-only change does not reach these fresh-install
or component paths, their shared storage-gate predicates are unchanged, and the
core remains 1.14.2. That audited boundary permits reuse of the earlier passing
component evidence rather than rerunning it solely for a new worktree or hash.

The recorded aggregate pass closes this SPEC's finite runtime acceptance.
The existing Stage 1 Tor/rule-set history, explicit current REALITY evidence,
current standalone leaves, aggregate compatibility, full suite and production
remain separate proof boundaries.
