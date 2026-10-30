# checkpoint-1: sharded accepted simulation state

This profile removes the requirement to transmit or materialize a complete
`graph-1` checkpoint on every external advance. It preserves the existing model,
entity, random-address and logical-time semantics. Legacy `authority-1` groups
retain their full-checkpoint representation; new sharded groups identify
`schemaVersion: 2` and `profile: checkpoint-1` at the same Runtime endpoint.

## Immutable objects

Each object is canonical ASCII (`CSCanonicalCodec`), at most 16,384 bytes,
addressed by its raw SHA-256 hash. Object transport uses `{hash, parts}` with at
most four printable strings of at most 4,096 characters. Only primitive data is
decoded; model data cannot supply executable Smalltalk or native callbacks.

| Kind | Fields besides `kind` |
| --- | --- |
| `value` | `value`: a canonical primitive/container value |
| `array`, `map` | `left`, `right`: roots whose values concatenate or merge |
| `item`, `entry` | `value`: child root; `entry` also has a `key` |
| `index` | `entries`: two-digit entity-ID suffix → row-tree root |
| `indexBranch` | `left`, `right`: disjoint index roots |
| `entities`, `projection` | `suffix`, `rows`: at most 128 keyed records |
| `entitiesBranch`, `projectionBranch` | `suffix`, `children`: preceding hexadecimal digit → child root |
| `checkpoint` | Manifest fields below |

Value and index containers split at their sorted midpoint when their encoded
object would exceed the page budget. A single oversized container member is
represented through `item` or `entry`. Row tries extend the ID suffix one digit
at a time until each leaf fits both row and byte budgets. All traversal is
bounded to depth 64. The current per-group store bounds objects to 65,536;
collection must run before exhausting that quota.

The manifest has exactly `kind`, `version` (1), `model`, `modelDigest`, `tick`,
`seed`, `entities`, `projection`, `entityCount`, `resources`, `events`, `outcomes`.
`model/resources/events/outcomes` are value roots; `entities/projection` are index
roots. Metadata contains no population-sized inline array. Its hash is the
sharded group's `checkpointDigest`; it is distinct from the legacy flat-byte hash.

Checkpoint rows retain all nine `graph-1` fields. Projection rows contain only
`[id, position3, velocity3, mode]`. Their roots are independent, so changes to
random counters or resource bookkeeping do not invalidate unchanged presentation
pages. See [projection-1](../projection-1/README.md).

## Native construction and restore

Living agents remain spatially distributed in Repast. At a checkpoint boundary,
ranks exchange row copies to canonical ID-bucket owners with MPI all-to-all.
Those owners write immutable entity/projection pages. Rank zero gathers only
bucket descriptors and publishes a manifest after all shard writes are fsynced.
It never gathers a complete population checkpoint. Restore reads assigned buckets
and exchanges rows to their execution owners; no full-population input file or
command argument is required.

Object hashes and row ordering are independent of rank count and spatial
ownership. The native session retains its graph/agents and continues using the
acceptance acknowledgment and incarnation fencing of `resident-1`.

## GemStone publication

`CSUploadSimulationArtifactsWorkUnit` imports bounded objects for a not-yet-created
group. `CSCreateShardedSimulationWorkUnit` validates the complete initial closure
and creates the group from a root reference. Upload after creation is rejected.

After committed prepare/dispatch, the external result contains a root and its
original batch binding. Runtime fetches missing objects in bounded batches and
submits `CSStageSimulationArtifactsWorkUnit`. Staging is generation/revision fenced;
it does not change the accepted root or data revision. The first staged result
root is fixed for that pending batch, including across recovery.

Acceptance requires a complete verified closure, model/seed/target identity,
valid entity and event/resource references, and exact correspondence between
checkpoint and projection rows. Verified immutable subtrees are reused; only new
objects and changed row buckets are revalidated. Cached closure heights enforce
depth bounds even when subtrees are shared. Root, accepted data revision and the
projection-change entry publish in one copy-on-write GemStone transaction.

This first profile preserves fixed entity identities, matching the registered
`graph-1` operations. Population creation/deletion needs a later operation/profile
extension. A missing or corrupt object never authorizes publication, absence or
replay. Queries continue to serve the previous accepted root during staging.

## Durability and retention

GemStone stores immutable canonical pages, not a live object for each external
agent. No external I/O occurs inside an authority transaction. Runtime restarts
resume from committed staged objects and query the original immutable native
receipt. Reconciliation preserves the original batch binding while accepting
under the current placement fence.

`CSCollectSimulationArtifactsWorkUnit` is allowed only when no batch is pending.
It retains current and bounded projection-history roots, removes unreachable
objects and invalidates associated validation caches. Expired views require
resnapshot. The native spool retains receipts and objects separately; operators
must retain that complete spool until its uncertain work is resolved.

Local Smalltalk execution and preflight return to GemStone explicitly reconstruct
a world from shards. An unsupported local materialization fails before placement
changes; external execution remains recoverable. The existing `graph-1` model
capacity (10,000) and local canonical byte/atom budgets still apply. This removes
the old 192 KiB checkpoint/control-argument ceiling for the new profile; it is not
a 100,000-creature qualification.
