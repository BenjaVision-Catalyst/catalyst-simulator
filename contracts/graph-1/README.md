# Portable graph profile 1

`simulation-portable-1/graph-1` extends the local kernel with a bounded typed
dataflow graph, versioned operation declarations, content identity and target
compatibility reports. The three models in `fixtures.json` execute unchanged in
GT and native GemStone. Repast remains a future execution adapter.

This profile retains probe-1's integer units, addressed Philox, canonical codec,
entity/resource records, event generations and acceptance rules. It supports
generic mechanisms; ecosystem behaviour and species/habitat builders belong in
CatalystEcosystem. NPC/automation policies likewise compose operations above the
kernel. The primitive vocabulary has no ecosystem or Unreal types.

## Authoring and immutable bundles

`CSModelBuilder named:` creates an authoring object. `node:operation:stage:scope:
type:inputs:after:parameters:` adds a version 1 description; `addNode:` accepts an
explicit versioned node. Both detach supplied collections. Tick duration and
capacity setters configure the bundle; `build` validates and freezes it.

The bundle retains the six-field layout:

```
[profile, modelId, tickMilliseconds, entityLimit, eventLimit, graph]
```

The first five fields have the probe-1 bounds. The graph is a dictionary with
exactly `version` (integer 1), `nodes` (array), and `maxNodeEvaluations` (integer
1..1,000,000). A node has exactly these fields:

| Field | Contract |
| --- | --- |
| `id` | Unique 1..64 character lowercase ASCII letter/digit/hyphen name |
| `operation`, `version` | Stable operation name (1..128 characters), integer version 1..65535 |
| `stage` | `events`, `decide`, `motion`, `resolve` or `random` |
| `scope` | `world` or `entity` |
| `type` | `void`, `i64`, `u32`, `bool`, `string` or `vec3` |
| `inputs` | Ordered node IDs supplying typed values |
| `after` | Additional node IDs imposing execution order without supplying values |
| `parameters` | Data-only dictionary, at most eight keys |

The graph allows 1..128 nodes, at most 32 inputs and 32 `after` references per
node, and at most 1024 references overall. Duplicate node IDs, missing references,
cycles, backward-stage dependencies, void inputs and entity-to-world value edges
are rejected during construction. A repeated value input is permitted (for
example adding the same quantity twice); duplicate `after` entries are rejected.
There are no loops, selector/class references, arbitrary source or closures.

World values broadcast to entity nodes. Entity values are addressed to the same
stable entity ID; reductions and arbitrary cross-entity lookups are not part of
this profile. Typed components beyond the fixed nine-field entity record remain
a later profile extension.

## Operation registry

`CSOperationRegistry portable` supplies the trusted catalog. `supporting:` selects
a backend capability subset and rejects unknown registrations. The registry
stores immutable canonical declarations, never executable bindings. Implementing
a primitive requires trusted host code, a versioned contract and conformance
evidence on each backend. A model cannot register code by naming an operation.

Each declaration is `[version, scope, stage, inputTypes, outputType,
parameterTypes]`, keyed by operation name. All current operations use version 1:

| Operation | Scope / stage | Inputs → output | Parameters |
| --- | --- | --- | --- |
| `core.constant` | either / any | none → declared non-void type | `value` matching that type |
| `core.tick` | world / any | none → i64 | none |
| `core.entity.field` | entity / any | none → field type | `field` from the fixed entity schema |
| `core.i64.add` | either / any | i64, i64 → i64 | none; checked overflow |
| `core.i64.less` | either / any | i64, i64 → bool | none |
| `core.select.i64` | either / any | bool, i64, i64 → i64 | none |
| `core.string.equal` | either / any | string, string → bool | none |
| `core.bool.and` | either / any | bool, bool → bool | none |
| `core.bool.not` | either / any | bool → bool | none |
| `core.events.apply` | world / events | none → void | none |
| `core.velocity.set` | entity / decide | bool, vec3 → void | none |
| `core.mode.set` | entity / decide | bool, string → void | none |
| `core.resource.request` | entity / decide | bool, string, i64 → void | none; active quantity must be nonnegative |
| `core.motion.integrate` | entity / motion | bool → void | none |
| `core.resource.resolve` | world / resolve | none → void | none |
| `core.random.draw` | entity / random | bool → void | unsigned 32-bit `stream` |

`either` and `any` are declaration constraints; nodes always select a concrete
scope/stage. Types use probe-1 numeric bounds. Strings remain bounded printable
ASCII; vec3 is three signed 64-bit coordinates. Entity field names, in record
order, are `id`, `position`, `velocity`, `requestedResource`, `requestedQuantity`,
`mode`, `drawIndex`, `sample`, `motionRemainders`.

Exactly one event drain is required. Motion integration, resource resolution and
random drawing each permit at most one node. Other stages/effects are optional.
This restriction avoids duplicate integration/resolution/draw semantics in the
first profile. Multiple mode/velocity/request writes execute in the declared
deterministic order; use `after` when the order is part of the model's intent.

## Execution semantics and bounds

Stages execute in the order above. Within them, Kahn topological scheduling
chooses the earliest stage and then the lowest ASCII node ID among eligible
nodes. Every entity-scoped node evaluates over ascending stable entity IDs.
Input argument order is preserved, and world inputs broadcast without changing
their type. All value nodes evaluate eagerly; a false effect guard or unselected
`select` branch does not suppress earlier value-node evaluation or overflow.

Each stage captures an immutable read view. `core.entity.field` reads that view,
including when an `after` edge places it after a write in the same stage. Effects
update detached candidate state in plan order and become visible to reads in the
next stage. Resource requests from `decide` resolve together at `resolve` using
canonical entity ID. Outcomes clear at the beginning of each step, including
models without a resolver. Timers run before decisions; motion sees velocities
chosen during decisions. `core.tick` reads the proposed new tick.

Static compatibility requires `worldNodeCount + entityNodeCount * entityLimit`
to fit `maxNodeEvaluations`. Execution also checks the actual count. Existing
codec, event, entity and run-until budgets remain in force. Model headers cache
immutable scalar values so integration does not decode the graph per coordinate.
Graph values, stage copies and full candidate publication remain intended for
the initial local implementation, with allocation/partition work still required
before scale claims.

Compatibility also bounds the worst-case canonical encoding of retained node
values to 64 MiB before launch. The bound includes 16 root bytes, 100 bytes per
non-void node for its key/container, and the typed payload: bool 1, i64/u32 22,
string 4102, vec3 69 bytes. Entity outputs include another 36 bytes per stable-ID
key and multiply by `entityLimit`. This is deliberately conservative and excludes
VM object/header overhead; it is a payload budget, not a heap-size guarantee.
An unused value node still counts because evaluation is eager.

Random effects use the declared stream and the entity's current draw index, then
increment that index with checked u32 exhaustion. False guards leave both index
and sample unchanged. The checkpoint carries that address state. Execution rank,
wall time and host object identities never enter it.

Any execution/validation failure discards the whole candidate, including time,
timer effects, grants, graph writes and draws. Runtime transaction ownership and
distributed fencing remain separate P3 work.

## Canonical identity and compatibility

Graph normalization sorts nodes by ASCII ID and each `after` array by ID. Input
order remains significant. All dictionaries use the canonical codec's key order.
Redundant/transitive edges are retained: digests identify the declaration, not
every mathematically equivalent graph.

`CSModelBundle>>canonicalBytes` returns the normalized six-field encoding.
`digest` is lowercase 64-character SHA-256 hex over ASCII:

```
"CatalystSimulation-Model-1:" + canonicalBytes
```

The registry digest uses `"CatalystSimulation-Registry-1:" + canonicalRegistry`.
`CSSha256` implements [SHA-256 from FIPS 180-4](https://csrc.nist.gov/pubs/fips/180-4/upd1/final)
with exact integer arithmetic, independent of dialect crypto libraries. Known
answers and Python hashlib independently check it. Model identity includes the
profile, model ID, limits, graph, parameters and operation versions. Seed, entity
state and backend capability supersets are outside the model digest. Registry
digests identify declarations, not executable binaries or an authorization grant;
implementations must preserve the specified operation-version semantics.

`compatibilityReportFor:` returns `profile`, `modelDigest`, `registryDigest`,
`compatible` and an ordered `issues` array. Issues contain `path`, `code` and
`message`. Unsupported operations/versions, scope/stage mismatches, input arity or
type errors, output/parameter mismatches, missing event drains, duplicate effects
and evaluation budget failures identify the affected requirement. Structurally
invalid graphs fail construction; structurally valid unsupported models can be
inspected without launching them. Backend creation and checkpoint restore both
reject incompatible models before accepting state. The existing
`compatibilityIssues` helper retains its path/message-pair API.

## Checkpoints and rollout

Graph checkpoints use version 2 and add exactly `modelDigest` to the probe-1 key
set. Restore reconstructs and normalizes the bundle, validates compatibility,
requires the stored model to be normalized, checks its digest and validates all
state before publication. Registry digests are not pinned into checkpoints:
another compatible capability superset may resume the same model. A digest is
content identity; independent expected model/world authority belongs to Runtime.

Probe-1 checkpoint bytes and version 1 restore remain supported. They are not
silently upgraded into graph-1. `fixtures.json` contains graph-probe,
conditional-graph and expression-graph models, their tick 0/1/2/6 checkpoints, the
registry declaration/digest and six negative compatibility cases. These are
neutral conformance models, not production ecosystem behaviours.
