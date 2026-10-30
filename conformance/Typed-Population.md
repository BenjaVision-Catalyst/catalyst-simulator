# Typed population qualification

The subsequent [columnar publication increment](Columnar-Publication.md) retains
these model/checkpoint identities and addresses the publication cost measured
here. This record preserves the original typed-storage workload and timings.

The [`typed-1` profile](../contracts/typed-1/README.md) removes the legacy
10,000-entity admission limit through typed population execution and sharded
interchange. It keeps the existing portable graph operations and the Simulator /
Ecosystem boundary. Runtime remains the client endpoint and GemStone remains the
acceptance authority. NPCs and automation remain deferred.

## Implementation

`CSTypedPopulation` stores checked integers in fourteen packed, chunked ByteArray
columns, with separate canonical-ID and interned-string indices.
`CSTypedSmalltalkBackend` copies columns for candidates and immutable graph stages.
Population rows are temporary boundary values, not the persistent local layout.
Local arithmetic failure leaves the accepted columns unchanged.

The native `TypedProbe` interprets the same graph with typed records in Repast
agents and typed stage/candidate buffers. Complete 128-bit Catalyst identities
remain independent of Repast ordinals, current rank and local string codes.
Migration re-interns string labels at the receiving rank. The adapter exchanges
typed records to checkpoint bucket writers, which encode bounded canonical pages;
rank zero receives only descriptors.

Returning to GemStone reconstructs packed columns from shards during preflight.
Neither local advancement nor return uses a population-sized canonical value.
The schema-2 Runtime read endpoint, accepted projection pages, owner/generation
fences, staged result-root binding and receipt reconciliation remain in use.
Legacy graph/batch/resident modes retain their existing bounded representation.

Object acceptance and transfer must remain bounded as population size grows.
Typed storage does not justify raising the legacy canonical 8 MiB/atom limits or
turning off row, model, resource, event or projection validation.

The transport also caches immutable subtree completeness in a discardable SQLite
index. This avoids rescanning transferred leaves on every availability request.
Cache hits cannot replace raw-object hash checks, native restore verification or
GemStone acceptance. The index never establishes confirmed job absence. Tests
cover cache loss, incremental arrival, cached subtree depth and corrupt object reads.

## Workload and evidence layers

The scale workload has 100,000 distinct entities. Every entity moves in all three
axes, with negative coordinates/velocity and fractional motion remainders.
GT produces reference roots from the actual typed Smalltalk interpreter through
tick 12. A separate closed-form integer-motion oracle can verify every row.

Native 1/2/4-rank runs retain processes and graph state through several windows,
checking every boundary root against GT. Converted GT/P2 conditional and resource
contention checkpoints exercise the general typed engine separately from the
scale motion workload.

The managed four-rank Runtime case constructs an accepted GemStone placement,
advances locally, switches to resident Repast, stages an incomplete result,
restarts Runtime, rotates the owner, rejects a stale result and reconciles the
retained receipt. It then kills an owned rank, recovers from the accepted shards,
uses scheduled progress, returns to GemStone and advances locally again. Client
observations remain rooted in accepted GemStone data throughout.

These layers are distinct: native rank-count determinism is not itself a managed
Runtime durability test. The workload is a platform motion qualification, not a
complete ecosystem or a claim of real-time planetary simulation.

Full-population Runtime publication remains expensive: observed accepted windows
take minutes, despite native compute/checkpoint windows taking seconds. The
workload changes every entity at every step, so it transfers and validates the
entire changed population. Typed execution storage removes the admission/memory
barrier; it does not remove canonical-page, control-process, queue and GemStone
ingestion costs. Columnar checkpoint/delta transport and bulk durability work are
the next performance gate before claiming real-time 100,000-entity service.

## Qualified result — 30 October 2026

The 100,000-entity native runs match GT at ticks 1/4/8/12 on **1/2/4 ranks**.
The managed **four-rank** Runtime scenario matches through local tick 12, including
partially staged recovery, Runtime restart, stale-owner rejection, rank failure,
scheduled progression and return to GemStone. Independent integer arithmetic
checks every entity in all eight GT reference snapshots.

The local columns occupy **9,633,792 bytes** for 100,000 entities, including chunk
rounding; ID-index, intern-table and VM/database overhead is additional. Native
records occupy 112 bytes each, plus Repast/index/scratch/transport overhead.
Observed final-window peak RSS per rank is:

| Native ranks | Peak RSS per process, MiB |
| --- | --- |
| 1 | 161.9 |
| 2 | 141.5–155.1 |
| 4 | 87.8–89.3 |

RSS includes process overhead and shared mappings; summing process RSS does not
measure unique physical memory. These are observations on one host, not isolated
production performance limits. After startup, native motion/checkpoint windows
take roughly 1–4 seconds. Managed accepted windows take roughly 170–262 seconds
for this all-moving workload; that includes transfer, queueing, verification and
durability. Local accepted advancement also includes shard reconstruction and
publication, rather than only kernel compute.

External execution and recovery keep GemStone's flat-materialization counter at
zero and its typed-reconstruction counter unchanged. The latter increases only
for local execution and return preflight. Native full snapshots and root population
gathers remain zero. Idle collection keeps the 65,536-object quota intact; the
final explicit collection reduces 52,270 objects to 43,559. Control messages peak
at 59,427 input bytes and 126,894 output bytes, below the 196,608-byte limit.

The evidence contains 28 typed result windows across eight reaped incarnations,
including one intentional rank failure. Tests cover 89 GT examples, 79 native
GemStone examples, 36 transport checks and 216 native codec/storage checks.
The final source comparison includes 571 definitions. A final-source 100,000-row
GemStone checkpoint/restore probe and a two-rank legacy resident/batch regression
also validate the load and compatibility paths.

See [qualification](results/typed-population-2026-10-30/qualification.json) and
[archived evidence](results/typed-population-2026-10-30). Run
`python3 scripts/verify-typed-evidence.py` offline to verify canonical object hashes,
source/test records, all population rows, native memberships, client projections,
recovery boundaries and cleanup. Canonical objects are deduplicated across stores
and split into small ZIP parts; per-store hash membership preserves provenance.

## Reproduction

Use native macOS MPI and the existing pinned Repast/CMake project. Use the
dedicated `bvc_simulator_native` GemStone 3.7.5 devkit stone without Rowan, through
the repository's `gemstone-topaz` skill. Shared Smalltalk remains authoritative
in the live GT image and must be exported/compared through GT MCP.

Run `CSTypedPopulationExamples` and the existing portable/authority/Runtime
examples in GT. Its `writeScaleFixturesTo:` helper exports conformance data from
the live interpreter; it does not write class source. Native validation requires
a fresh `CCNativeMcpLease`, with one independent controller owning Runtime and
every simulator process through cleanup. Wait outside GT for the released and
restored `gt-mcp-gate.json` before joining the owner.

```sh
cmake --build /absolute/path/to/repast-build -j6
python3 scripts/test-sharded.py
python3 scripts/qualify-typed.py \
  --project /absolute/path/to/dedicated/bvc/project \
  --bvc /absolute/path/to/bvc/bin/bvc \
  --executable /absolute/path/to/repast-build/catalyst_repast \
  --fixtures /absolute/path/to/GT-exported/fixtures \
  --output /absolute/path/to/fresh/evidence \
  --lease-release /absolute/path/to/fresh/lease/release
```

## Remaining boundaries

The typed model's admission ceiling is separate from tested capacity. Existing
evaluation/retained-expression budgets still reject unsupported graphs. Events,
global metadata, resource arbitration, fixed membership, per-group artifacts and
retained history remain bounded. Native graph expression results can still use
boxed scratch values. Repast context/index overhead and database object/index
overhead remain in addition to packed field storage.

Cluster deployment, partition-local interactions, births/deaths, spatial AOI,
long-running ecosystem workloads, authenticated remote artifact storage and UE
presentation benchmarks require their own qualification. CatalystLandform and
ecosystem rules/presentation remain in their own components.
