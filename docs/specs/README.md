# Specification status

[简体中文](README.zh-CN.md)

Inventory checked against repository baseline `f498234` on 2026-10-30. The two
`unified-node-naming` documents describe one feature in English and Chinese;
they are maintained contracts, not two unfinished implementation plans. The
address-selection contract is maintained in the Wiki source instead of duplicated
here.

| Contract or goal | Implementation status | Evidence and remaining boundary |
| --- | --- | --- |
| [Unified node naming](unified-node-naming.md) ([中文](unified-node-naming.zh-CN.md)) | Implemented and accepted within the recorded scope | Section 9 preserves the original local/core evidence. Section 10 adds the actual SubMan application/storage integration (30 nodes across five protocols) and owner-authorized production VMess API/Gist acceptance (six test candidates and one test aggregate), with identity/membership preservation and cleanup. This is not production proxy-VPS or every-protocol public-connectivity acceptance. |
| [SubMan address selection](../wiki/SubMan-Address-Selection.md) | Implemented and accepted within the recorded scope | Isolated family/failure regressions and the application/storage integration cover IPv4, IPv6 and concrete listener cases. Naming section 10 records the representative production VMess test separately; address selection does not certify public proxy connectivity. |
| [Full protocol/component acceptance](full-protocol-completion.md) ([中文](full-protocol-completion.zh-CN.md)) | 15 presets and 38 component adapters implemented; FP-01–FP-11 scoped acceptance complete | The finite FP-01–FP-11 matrix records local component/group, authorized Cloudflare and controlled Headscale/ocserv acceptance, plus namespace build restrictions. Original lifecycle and data-plane evidence remains in the [upstream matrix](../wiki/Protocol-Coverage.md); public and production acceptance remain separate. |
| [Runtime transactions](runtime-transactions.md) ([中文](runtime-transactions.zh-CN.md)) | RT-01–RT-04 implementation and scoped acceptance complete | The runtime contract records bounded binary download/update, WARP registration and latest-version lookup behavior, failure/rollback tests and the corresponding isolated runtime evidence. External accounts and production proxy-host changes remain separate. |

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
