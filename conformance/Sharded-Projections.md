# Incremental accepted projections and sharded checkpoints

The subsequent [typed population increment](Typed-Population.md) adds packed
execution storage and a separate 100,000-entity qualification. This record retains
the original sharded-profile scope, counts and remaining boundaries at that stage.

The optional `sharded` Runtime backend mode uses
[`checkpoint-1`](../contracts/checkpoint-1/README.md) immutable objects and
[`projection-1`](../contracts/projection-1/README.md) client pages. Runtime remains
the client endpoint and GemStone remains the acceptance authority. Portable model
semantics, Simulator/Ecosystem ownership and deferred NPC/automation scope remain
unchanged.

## Removed dependencies

The resident full-checkpoint mode gathered population rows at rank zero, sent a
complete checkpoint through the control path, rebuilt a Smalltalk backend to
validate it, and returned the full state in service reads. That imposed the
192 KiB acceptance and 49,152-character command limits even when native agents
were resident.

The new profile instead:

- Exchanges rows to canonical bucket writers and gathers only shard descriptors.
- Writes fsynced, immutable objects of at most 16 KiB; unchanged content is reused.
- Exchanges root references and missing objects in bounded control messages.
- Stages objects in GemStone without publishing candidate data.
- Validates new subtrees and changed row buckets against cached immutable proofs.
- Atomically publishes one root/data revision and its projection-change entry.
- Serves root-pinned, byte-bounded client pages from accepted GemStone objects.

All external/process I/O remains outside authority transactions. Upload, staging,
publication, placement fencing and reconciliation use actual Runtime WorkUnits.
The native process still waits for acceptance acknowledgment between advances.

## Data and authority

`CSArtifactStore` keeps canonical page strings, validation summaries and closure
heights. It does not persist executable native sessions or construct a live
Smalltalk agent per external entity. `CSShardedExecutionGroup` uses the same
single-slot copy-on-write guard, sequence/retry rules and generation fencing as
the bounded legacy authority. Legacy schema-1 groups and batch/resident modes
remain available.

Sharded groups expose a compact schema-2 view. `revision` covers authority
operations, including staging. `dataRevision` advances only when a new simulation
root publishes. Projection change entries compare the accepted pose/mode roots,
so random-counter changes alone do not force presentation-page updates.

Publication verifies object integrity and completeness, model and seed lineage,
target tick, entity identities and row shape, resource/event references, and exact
checkpoint/projection correspondence. The first result root is fixed in pending
state when staging begins. Recovery retains it and can finish the same import
under a new owner; old-owner publication remains rejected.

Cached subtrees carry verified maximum height. A new parent cannot conceal an
oversized graph behind a shared subtree. Unchanged row buckets reuse their
summaries. Validation diagnostics count newly visited objects and checked rows;
they are operational evidence, not simulation inputs.

## Local switching and retention

Local Smalltalk advancement and transfer preflight explicitly materialize a world
from the accepted shards. External prepare, stage, accept, read and recovery do
not do so. The local compatibility check runs before changing placement, so an
unsupported local reconstruction leaves external ownership intact. Native
retirement finishes before local activation.

Projection history is bounded by the configured retention count. Clients pin
reads to a retained root and resnapshot after a gap. Artifact collection is an
explicit idle operation: it retains current/history roots and removes unreachable
objects and cached proofs. Pending imports prevent collection. Native receipts
and their durable object spool have a separate operator retention responsibility.

## Qualification scope

Reference roots are produced through the live GT image for the existing
two-entity conditional graph and a neutral 4,096-entity sparse-motion model. The
latter has a 556,805-byte flat checkpoint, above the previous 192 KiB limit.
Six managed Runtime scenarios cover both models on 1/2/4 native macOS ranks.

Each scenario uploads bounded initial objects, creates a GemStone placement,
advances locally, switches to resident Repast, and advances through ticks 3/4.
At tick 6, fault injection allows one artifact fetch then suppresses the complete
receipt. The accepted view stays at tick 4 with an incomplete staged closure.
Runtime restarts, fences the owner, rejects a stale result, resumes the import
and reconciles tick 6. A rank is then killed after accepted tick 8; explicit
recovery restores from shards, scheduled progress reaches tick 10, and GemStone
continues to tick 12. Collection and slow-reader resnapshot checks follow.

The controller records actual endpoint projections, data revisions, bounded
wire sizes, native PIDs/counters and GemStone materialization counts. No complete
checkpoint is present in control specifications or native input/output files.
The native full-snapshot and root-population-gather counters remain zero.
GemStone's materialization count remains constant throughout external execution
and recovery, increasing only for explicit local execution/preflight.

The sparse model moves 16 entities. A changed accepted window produces 37 new
objects and checks 256 row records in the affected 16 ID buckets, reusing the
remaining verified subtrees. This is a structural/data-path qualification, not a
planetary throughput or memory benchmark.

Qualified on 30 October 2026: 81 GT examples, 71 native GemStone examples,
31 transport/lease checks and 210 native codec checks pass. All 519 exported
Simulator definitions match the dedicated stone. The six managed scenarios
produce 36 durable root receipts across 18 resident incarnations, including six
deliberately failed by rank kill. Every incarnation is reaped and every test
Runtime is removed. A separate 2-rank legacy resident/batch regression also passes.
Control messages peak at 18,979 input bytes and 18,957 output bytes for the sparse
fixture; those are observed sizes for this workload, not a throughput claim.

See the [committed qualification](results/sharded-projections-2026-10-30/qualification.json),
[test/build evidence](results/sharded-projections-2026-10-30) and archived canonical
objects. Run `python3 scripts/verify-sharded-evidence.py` to independently verify
object hashes/closures, GT/native root equality, client projections, changed
buckets, recovery boundaries and cleanup without starting any native process.

## Reproduction

Build the pinned native adapter with the existing `native/p2` CMake project.
Load the exported Core, Authority, Runtime and test packages into the dedicated
`bvc_simulator_native` devkit stone without Rowan. Use the repository's
`gemstone-topaz` workflow. Hold a fresh `CCNativeMcpLease`; one independent
controller owns Runtime and every native session through cleanup. Wait outside
GT for its released `gt-mcp-gate.json` before joining the owner.

The GT-only `CSRepastResidentExamples>>writeShardedFixturesTo:` exports reference
roots and bounded upload records. Then:

```sh
python3 scripts/test-sharded.py
python3 scripts/qualify-sharded.py \
  --project /absolute/path/to/dedicated/bvc/project \
  --bvc /absolute/path/to/bvc/bin/bvc \
  --executable /absolute/path/to/repast-build/catalyst_repast \
  --fixtures /absolute/path/to/GT-exported/fixtures \
  --output /absolute/path/to/fresh/evidence \
  --lease-release /absolute/path/to/fresh/lease/release
```

Production configuration selects `repastMode: 'sharded'` and
`repastLauncher: '/absolute/path/scripts/repast-sharded.py'`. Initialize a separate
spool with `--initialize`. Control payloads use unique request files, which the
launcher consumes, rather than embedding object contents in shell arguments.
The sharded mode has the same absolute executable/MPI/directory and rank settings
as the resident mode. A mode/rank/executable change requires resolving pending
work and fencing placement.

## Remaining scale gates

The old whole-checkpoint transport/acceptance ceiling is removed for this profile.
Individual objects, control frames, traversal depth, retained history and storage
quotas remain intentionally bounded. The existing `graph-1` 10,000-entity model
capacity and local canonical materialization budgets are unchanged; larger local
returns fail preflight rather than corrupt ownership.

Native execution still uses boxed values, replicated global metadata and root
resource arbitration. It computes checkpoint hashes across owned state at each
window. Spatial AOI subscriptions, typed/columnar population storage, partitioned
interactions, population lifecycle operations, remote authenticated object storage
and a 100,000+ population benchmark remain separate gates. No NPC or automation
vertical slice is introduced.
