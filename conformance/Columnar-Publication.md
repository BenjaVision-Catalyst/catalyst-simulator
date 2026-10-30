# Columnar transport and bulk publication

[`columnar-1`](../contracts/columnar-1/README.md) reduces control traffic and
transaction count for the existing 100,000-moving-entity workload. It preserves
the exact portable model, checkpoint-1 hashes, projection-1 pages, Runtime client
endpoint and GemStone acceptance authority. Ecosystem behaviour remains separate;
NPCs and automation remain deferred. Native execution uses macOS MPI without Docker.

## Implementation

`CSColumnarCodec` and the Python transport share a deterministic full-checkpoint
and field-delta format. Deltas reuse sorted accepted identities, omit unchanged
columns, and choose constant, palette or fixed-width representations. Projection
pages are derived from the reconstructed state, rather than sent a second time.
String data is split into parts within the existing 4,096-character atom limit.
The frame builder measures expanded object closures and reserves JSON escaping
space before selecting units. Oversized buckets use the canonical page path.

Runtime transfers full columnar checkpoints to the native spool during handover
and imports columnar deltas for resident results. It keeps the pending result
root, cursor and plan size in GemStone. Each imported frame reconstructs canonical
pages in an owned scratch store, verifies entity/projection hashes, checks
collisions and capacity, then merges the objects and cursor in one work delivery.
Locally constructed pages are encoded and hashed once; incoming raw metadata
still receives its existing integrity and node checks. The spool flushes file
bytes and syncs one directory per bounded frame.

Bulk staging does not publish a candidate. Existing acceptance checks still
validate the complete closure, model, seed, tick, fixed membership, resources,
events and projection/state agreement. The accepted checkpoint and data revision
stay unchanged during partial staging. Exact retry fingerprints, placement
generations, original receipt reconciliation, native retirement and return to
the packed GemStone backend remain in use.

## Qualification method

Use the same GT reference roots and moving population as
[typed population qualification](Typed-Population.md), with the unchanged native
Repast executable. The native rank-count proof remains the recorded 1/2/4-rank
execution qualification; this increment repeats the managed four-rank Runtime
scenario against the new transport. It measures the same accepted windows and
repeats partial import, Runtime restart, stale-owner rejection, rank failure,
scheduled progression, GemStone return, local continuation and collection.

The codec tests cover dense identity buckets, signed integer extremes, atom and
JSON budgets, sparse field changes, unchanged populations, corrupt hashes,
malformed palettes, wrong bases/cursors and atomic rejection. Python compares
frames byte-for-byte with a GT-produced fixture and exercises replay after a
partially flushed bulk write. Native GemStone loads the GT export and compares
every definition before running the same portable/authority contracts.

The evidence reuses the checked-in GT canonical object pool by hash, rather than
duplicating it. The offline verifier reconstructs each recorded delta into those
exact canonical bytes, checks native closure membership, client projections,
recovery cursors, cleanup, source hashes and measured publication timings.

## Qualified result — 30 October 2026

The managed 100,000-entity four-rank scenario passes through local GemStone tick
12, including partially staged restart, owner recovery, stale-result rejection,
rank failure, scheduled progression, native retirement and local continuation.
All three owned native incarnations are reaped, including the deliberately failed
one, and the owned Runtime and simulation fixtures are removed.

The load passes **98 GT tests, 88 native GemStone tests, 46 Python transport
checks and 216 native C++ checks**. The final definition comparison matches 616
definitions; the managed run matches 615 before the additional test-fixture
exporter is added. Production definitions are unchanged between those records.
A separate all-fields fixture compares GT/Python wire frames, then verifies
committed GemStone restoration in an independent session. It covers all fourteen
fields, signed integer extremes, distinct draw/sample values, escaped labels,
resource metadata, outcomes and an unsigned 64-bit seed.

The scale run uses 130 delta frames for five accepted results and 65 full frames
for initial handover. It makes 594 transport calls, compared with 3,989 previously.
There are no canonical page fallback calls for this workload. Peak control input
is 122,334 bytes and output is 52,291 bytes, below the unchanged 196,608-byte limit.
Flat materializations stay zero, and typed reconstruction remains unchanged during
external execution/recovery. Final collection reduces 52,270 objects to 43,559.

See [qualification](results/columnar-2026-10-30/qualification.json),
[comparison](results/columnar-2026-10-30/comparison.json) and
[archived evidence](results/columnar-2026-10-30). The archive references the preceding
GT canonical pool by checked hashes. It includes the new native membership,
receipts, frames, source comparisons, cleanup gates and all-fields round trip.

Run `python3 scripts/verify-columnar-evidence.py` from the repository for the
offline audit. Extract `artifacts.zip` to a fresh directory, then pass its
`gt-wire.json` and `all-fields.json` to `scripts/test-columnar.py` for wire tests.
Native reproduction follows the existing typed qualification controller and
`CCNativeMcpLease` workflow. Generate fixtures through GT MCP; the additional
`CSColumnarExamples>>writeAllFieldsFixturesTo:` helper and
`scripts/qualify-columnar-fields.topaz` exercise committed all-fields recovery.

## Measured publication costs

The same host, model, roots, native executable and controller phases allow a
comparison with the preceding typed-storage run. These are observed end-to-end
qualification timings, not isolated production throughput measurements.

| Phase | Previous seconds | Columnar seconds |
| --- | ---: | ---: |
| GemStone → resident Repast handover | 178.2 | 67.0 |
| Accepted tick 3 | 251.0 | 106.3 |
| Accepted tick 4 | 172.1 | 71.0 |
| Receipt reconciliation to tick 6 | 187.2 | 80.8 |
| Accepted tick 8 | 169.6 | 88.8 |
| Scheduled progression to tick 10 | 262.2 | 180.6 |

The ordinary resident result phases improve by approximately 48–59%. Scheduled
progression includes idle collection and configuration work; its measured
end-to-end improvement is approximately 31%. Handover improves by approximately
62%. Local return and local advancement retain their existing reconstruction and
checkpoint costs and are outside those publication improvements.

Each all-moving result uses 26 committed delta frames. Across five results, the
store reconstructs 146,323,037 canonical bytes from 2,820,614 canonical frame bytes,
with the existing per-page and control budgets intact. Runtime preserves accepted
client views while frames are incomplete. The same roots make the previous GT
integer-motion oracle and native 1/2/4-rank determinism proof directly reusable.

## Remaining costs

The transport retains canonical checkpoint storage and normal accepted-row
validation. Native checkpoint writing, GemStone canonical reconstruction,
durability and local checkpoint generation still cost time. Initial administrative
population uploads use the existing bounded upload endpoint. Columnar frames are
a transport optimization, not a change to the simulation model or a real-time
ecosystem capacity claim. Long-running ecology, lifecycle operations, spatial
interactions, remote clusters and UE presentation need separate qualifications.
