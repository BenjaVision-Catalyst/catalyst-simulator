# typed-1: typed population execution

`simulation-portable-1/typed-1` uses the six-field portable model bundle and the
same graph nodes, versioned operations, integer arithmetic, addressed random
streams and logical clock as `graph-1`. It is an explicit model profile; legacy
`probe-1` and `graph-1` capacity and whole-checkpoint limits remain unchanged.
Model identity includes the profile and declared capacity.

The typed profile admits entity capacities up to 1,000,000. This is an admission
bound, not a qualified capacity. The graph evaluation budget, retained expression
value budget and event bound still apply. In particular, declaring a large
capacity does not make every graph compatible: the existing worst-case retained
string-value budget can reject population-wide string expression results.

Author graphs with the existing `CSModelBuilder` node API and select `buildTyped`
after declaring the desired entity/event/evaluation limits. `build` continues to
produce the bounded legacy graph profile. Populate a `CSTypedPopulation`, then
construct `CSTypedSmalltalkBackend model:seed:population:`. Construction seals
membership and owns its copied data; public rows, IDs and borrowed label strings
cannot mutate an accepted population through aliases.

## Storage

GT and GemStone use `CSTypedPopulation`: fourteen packed numeric columns in
1,024-slot ByteArray chunks. Positions, velocities, request quantity and motion
remainders use checked signed 64-bit integers. Draw indices, samples and two
interned string indices use checked unsigned 32-bit integers. The columns occupy
96 bytes per allocated slot. Canonical entity IDs remain in a separate identity
index; shared label strings remain in an intern table. Neither their overhead nor
the database/VM overhead is included in the column byte count.

The native Repast adapter uses 112-byte typed records, including the complete
128-bit Catalyst ID. Repast agents retain those records rather than boxed
canonical value rows. Stage/candidate copies use typed records. Canonical row
arrays exist at shard and expression boundaries. Repast context/index overhead,
strings, graph scratch space, transport buffers and process memory are separate
from the record byte count and must be measured.

Native rank-local string codes are re-interned on migration. Slot ordinals,
string codes, chunk layout, native process IDs and memory statistics never enter
model identity, checkpoint hashes, random addressing or client entity identity.
Numeric identities compare in the same order as canonical fixed-width hexadecimal
IDs.

## Bounded artifact progression

The subsequent [`columnar-1`](../columnar-1/README.md) transport uses full typed
checkpoint frames for handover and field deltas for resident result import. It
reconstructs the same checkpoint-1 hashes with bounded transactional bulk staging.
The canonical page path and its limits below remain the fallback.

Artifact offers/fetches can contain up to 32 objects, with the existing 196,608-byte
control limit. Offers also cap their canonical object list at 60,000 bytes;
fetches cap encoded JSON at 160,000 bytes and can return a nonempty prefix of the
requested hashes. The driver verifies the returned subset and continues fetching
the remaining closure. Object size remains 16 KiB. Larger object-count limits do
not authorize larger messages.

Transactional upload/staging caches completeness and maximum height for immutable
subtrees as they arrive. Those proofs avoid rescanning downloaded leaves on each
fetch. They do not replace checkpoint, row, projection or lineage validation.
The per-group store still caps objects at 65,536, including locally produced
objects. Before idle local advancement or external prepare, a 49,152-object
watermark triggers collection retaining current/history roots. Pending work never
permits collection. Unresolved imports can still reach the quota and require
explicit recovery or operator action.

The native spool keeps a discardable SQLite completeness/height index, avoiding
repeated scans of already transferred immutable subtrees across control-process
calls. It never caches absence. Removing this index safely forces rediscovery;
it is separate from receipts and canonical objects. Artifact reads and native
restore still verify raw hashes, and acceptance still validates state in GemStone.
A completeness cache cannot authorize publication or declare a job absent.
Missing/corrupt spool objects still require recovery; retain the complete spool
while any outcome is uncertain.

## Execution and switching

Local candidate/stage copies preserve immutable graph reads without serializing
the whole population. Checked arithmetic failure leaves the accepted state
unchanged. Membership is sealed after construction; births/deaths remain a later
operation/profile extension.

The interchange format remains [`checkpoint-1`](../checkpoint-1/README.md).
Typed populations do not use the legacy flat canonical checkpoint API. Local
execution and return preflight reconstruct columns from bounded shards, rather
than passing a population-sized canonical value through the 8 MiB codec.
Metadata and individual shard/control-message budgets remain bounded.

Runtime remains the client endpoint and GemStone remains the acceptance authority.
Clients continue to use the same schema-2 accepted views and
[`projection-1`](../projection-1/README.md) pages. Placement generations, staged
result roots, receipt reconciliation and native retirement retain their existing
fencing rules. Storage diagnostics are operational evidence, not simulation input
or an alternate client endpoint.

The native supervisor allows a 300-second client lease for typed placements,
compared with 60 seconds for the legacy profile, so acceptance work can finish at
the qualified population size. The independent native supervisor heartbeat is
unchanged. Expiry reaps the owned incarnation; it never authorizes replay or
publication.

## Qualification boundary

The first target is 100,000 moving entities on one native macOS host. This is a
platform workload, not a production ecosystem or cluster capacity claim. Resource
arbitration and global metadata remain centralized, expressions can retain boxed
scratch values, and spatial AOI subscriptions and population lifecycle operations
remain separate work. Ecosystem behaviour/presentation stays in its own components;
NPCs and automation remain deferred.
