# Specification status

[简体中文](README.zh-CN.md)

Inventory checked against repository baseline `c652169` on 2026-10-30. The two
`unified-node-naming` documents describe one feature in English and Chinese;
they are maintained contracts, not two unfinished implementation plans. The
address-selection contract is maintained in the Wiki source instead of duplicated
here.

| Contract or goal | Implementation status | Evidence and remaining boundary |
| --- | --- | --- |
| [Unified node naming](unified-node-naming.md) ([中文](unified-node-naming.zh-CN.md)) | Implemented, including review fixes | Section 9 records the selected local/mock suite, affected follow-up checks and real sing-box 1.14.2 configuration checks. Its final runtime SHA-256 matches the baseline `install.sh`. Real SubMan node-ID/aggregate preservation and production acceptance were not performed by that suite. |
| [SubMan address selection](../wiki/SubMan-Address-Selection.md) | Implemented; the listener/address-family contract remains active | `public_ip_detection.sh`, `subman_address_selection.sh` and affected SubMan payload/API/orchestration tests cover isolated inputs and failures. Naming section 9 includes historical SubMan regression results. Candidate selection does not prove public connectivity or real SubMan synchronization. |
| [Full protocol/component goal](../wiki/Protocol-Coverage.md) | Partially verified; no blanket completion claim | Lifecycle and data-plane evidence is recorded per row and dated slice. Tailscale/OpenConnect and other external-control-plane paths retain their authentication and runtime prerequisites; public and production acceptance remain separate. |
| [Transaction follow-ups](../wiki/Transactions.md#后续迁移清单) | Some paths remain to be unified | Binary-download bounds and error context, WARP operation boundaries and remaining failure classification must be assessed against their current callers before further changes. Existing implemented protections are not pending work. |

Keep the naming SPEC because it defines identity preservation, snapshot consistency,
collision handling and error propagation that future changes must preserve. Old
implementation steps and intermediate hashes in section 9 are historical evidence;
they are not the current script version or a request to repeat the entire suite.
The current version is in the root [README](../../README.md), and command support
comes from `sbv agent capabilities --json`.

Completion records have separate scopes: local/mock tests, real-core configuration
checks, isolated Docker probes, real external-service writes, public connectivity,
production acceptance, current-head reviews/merge, and Wiki publication. A result
from one scope does not complete another. Review/merge evidence belongs in the
associated PR; Wiki publication has its own repository commit. Documentation
cleanup does not authorize production changes or real SubMan writes.
