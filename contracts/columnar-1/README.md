# columnar-1: bounded checkpoint and field-delta transport

`columnar-1` transfers `typed-1` populations while preserving the exact
[`checkpoint-1`](../checkpoint-1/README.md) artifact hashes. It changes transport
and staging granularity, not model identity, execution, accepted client views or
placement fencing. Legacy models continue to use bounded canonical page transfer.

## Frame

Each frame contains exactly `profile`, `root`, `base`, `cursor`, `next`, `total`,
`buckets` and `objects`. `profile` is `columnar-1`; `root` is the candidate
checkpoint hash. `base` is either the accepted checkpoint hash for a delta or
null for a full checkpoint. Cursors count deterministic transfer units, not
entities or revisions. `next - cursor` equals the number of bucket packets plus
metadata objects in the frame.

The plan lists changed two-digit identity buckets in lexical order, followed by
sorted new metadata hashes. Metadata includes the checkpoint manifest, index
nodes and model/resources/events/outcomes closures. Population and projection
pages are reconstructed from bucket packets. Unchanged buckets and unchanged
metadata are omitted from a delta. A full checkpoint contains all population
buckets and metadata.

Budgets remain explicit:

| Budget | Maximum |
| --- | ---: |
| Canonical frame bytes | 131,072 |
| JSON control request/response bytes | 196,608 |
| Rows reconstructed per frame | 4,096 |
| Transfer units per frame | 128 |
| Expanded canonical bytes in owned scratch | 4,194,304 |
| Individual canonical artifact bytes | 16,384 |
| String part characters / parts per column | 4,096 / 32 |
| Per-group artifact count | 65,536 |

A sender measures expanded bucket closures before selecting a frame and reserves
space for JSON escaping. A bucket that cannot fit a frame uses the existing canonical page path. A
partially staged columnar transfer can finish through canonical pages; publication
still requires the complete verified candidate closure. Frame expansion never
authorizes larger canonical pages, whole-population values or unbounded messages.

## Bucket and column layout

A packet contains exactly `bucket`, `baseEntities`, `baseProjection`, `entities`,
`projection`, `count`, `ids` and `columns`. Base hashes must match the corresponding
bucket roots in the accepted base. The entity and projection hashes identify the
reconstructed target bucket roots. Full checkpoints carry concatenated sorted
32-character hexadecimal IDs, split into string parts of at most 4,096 characters.
Deltas reuse the sorted base membership and carry an empty `ids` array.
Population membership remains fixed.

Columns are numbered independently of VM and rank storage:

| Columns | Value |
| --- | --- |
| 1–3 | Position x/y/z |
| 4–6 | Velocity x/y/z |
| 7 | Resource request quantity |
| 8–9 | Random draw index and sample |
| 10–12 | Motion remainders x/y/z |
| 13–14 | Resource request name and mode label |

Each column packet is `[number, mode, encoding, values, data]`, in strictly
increasing column order. Full checkpoints include all fourteen columns. Deltas
omit unchanged columns. `set` replaces a field; numeric `add` applies a checked
signed-64-bit delta to a base field. An overflowing difference uses `set`.
Decoded results still undergo normal entity and checkpoint validation.

`data` is an array of string parts of at most 4,096 characters; it is joined only
inside the bounded decoder. `constant` contains one value and empty data. `palette8` contains 2–256 distinct
values and one two-character lowercase hexadecimal palette index per row.
`int64` contains no palette and sixteen lowercase hexadecimal digits per row,
encoding big-endian signed two's complement. `text` contains one printable ASCII
string per row and empty data. Text labels remain independent of local intern
codes. The sender chooses a smaller valid numeric add representation when useful.

## Bulk durability and recovery

GemStone reconstructs each frame into an owned bounded scratch store. It checks
the base, cursor, membership, encodings, expansion budget and exact reconstructed
entity/projection hashes before merging any objects. Locally constructed scratch
objects are encoded and hashed once; inbound raw metadata still receives its
normal integrity and node checks. Collision and total-capacity checks precede
the bulk merge. Runtime commits the objects and pending transfer cursor in the
same transactional work delivery.

Staged data does not change the accepted checkpoint or data revision. The pending
batch retains the pinned result root, cursor and plan size across Runtime restart
and owner recovery. Existing request fingerprints provide exact retry handling;
the journal retains frame digest/cursor evidence rather than repeated column
payloads. Result acceptance still validates the complete checkpoint, lineage,
target tick, seed, fixed population, resources, events and derived projections.
Neither a cursor nor the transport's completion claim authorizes publication.

The native spool preflights a bounded frame, flushes each new immutable file, then
syncs the containing directory once for the frame. A crash can leave immutable
orphans or an incomplete closure, never an accepted result. Full offers are
idempotent, including after loss of the sender's transient cursor. Repast restore
continues reading and verifying ordinary checkpoint-1 artifacts. The existing
supervisor, receipts, accepted acknowledgements and retirement protocol remain in
use. Runtime remains the client endpoint for both execution placements.

Canonical checkpoint construction, full changed-row acceptance validation and
database publication remain costs. This increment does not qualify real-time
ecosystem workloads, partition-local interactions, births/deaths, remote cluster
storage or UE presentation. Ecosystem behaviour remains separate; NPCs and
automation remain deferred.
