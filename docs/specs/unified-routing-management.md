# Unified routing management (superseded)

[简体中文](unified-routing-management.zh-CN.md)

The current contract and test plan are [Server-only network management](server-only-network.md).
The earlier client routing/export, advertising/private controls and fresh-install
policy defaults have been removed from the product. Valid old policies are read
only for compatibility until an explicit network apply; node operations preserve
their existing effective server behavior.

The original acceptance was recorded for the earlier implementation at `34c7140`.
Its local/client-filter and isolated runtime results are historical evidence,
not acceptance of the current contract. The original design and detailed results
remain available in Git history. Current review, external-provider and production
boundaries are recorded separately in the replacement contract and delivery PR.
