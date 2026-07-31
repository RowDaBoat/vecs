# VEP-3 - queryForRemoval Scan Copies T
**Status:** Open


## Bug
`queryForRemoval` scans with `Query[(Meta, T)]`, causing `buildAccessTuple` to copy `T` for every entity with `T`, even though `T` is never used during the scan — only `meta.operations` is inspected.

Resolving VEP-2 (plain `T` → `lent T`) would reduce this to a borrow rather than a copy, but the access still occurs for every entity regardless of pending removals.


## Fix
Drive the scan manually: call `world.updateQuery(ofType)` then iterate `ofType.matchedArchetypes` directly, accessing only `Meta` per entity. This preserves the archetype scope (only entities with `T`) while never touching `T` during the scan. `ofType.operations` must still be processed and cleared at the end, mirroring what `world.query` does today.


## References
- [VEP-1 - queryForRemoval Copies All Components](VEP-1%20-%20queryForRemoval%20Copies%20All%20Components.md): initial fix that reduced O(n) T-copies-into-seq to O(k) entity ID collection
- [VEP-2 - Read Access Copies Components](VEP-2%20-%20Read%20Access%20Copies%20Components.md): making plain read access zero-copy via `lent T`
