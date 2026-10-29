# Portable kernel probe 1

This is a bounded implementation of selected P0/P1 semantics, identified as
`simulation-portable-1/probe-1`. It is a feasibility profile, not the complete
`simulation-portable-1` contract. The next backend must implement these semantics
and pass the same fixtures before accepting this profile. No Repast backend is
implemented or qualified yet.

The kernel contains generic mechanisms. Species, predation, metabolism and
habitat rules belong in CatalystEcosystem; appearance belongs in its UE plugin.
NPC and automation model packages will compose kernel operations separately.

## Numeric and ordering rules

- Entity and event identities are exactly 32 lowercase hexadecimal ASCII
  characters, representing unsigned 128-bit values. They contain no OOP, pointer
  or partition/rank identity. World IDs and model digests remain a later gate.
- Logical time is a nonnegative signed 64-bit tick. The model declares an integer
  tick duration of 1..1000 milliseconds. Wall time never advances simulation time.
- Coordinates are signed 64-bit millimetres; velocities are signed 64-bit
  millimetres/second. Each axis retains a remainder in 0..999. For each step,
  `wide = velocity * tickMilliseconds + remainder`, `delta = floor(wide / 1000)`,
  `remainder = wide - delta * 1000`. Negative movement therefore retains its
  fractional displacement exactly. Intermediates use exact widened integers;
  out-of-range published results reject the entire step. C++ must avoid signed
  overflow and implement floor division explicitly.
- Resource quantities are nonnegative signed 64-bit integers. All-or-nothing
  requests resolve by canonical entity ID. A fulfilled request clears; an
  unfulfilled request remains pending. This probe has one request per entity,
  no multi-resource reservations and no consumption/reproduction policy.
- The stages are exactly `events`, `move`, `contend`, `random`. Unknown/reordered
  stages produce a compatibility issue at `model/stages`. The bundle is data,
  never a closure or serialized Smalltalk class graph. An arbitrary operation
  graph and a registered operation vocabulary remain P0/P1 work.
- Due events order lexicographically by tick, phase (0), priority (0), entity ID,
  admission sequence, event ID, generation and mode. Sequence starts at 1.
  Cancellation/rescheduling increments the event identity generation. Superseded
  events do not execute. The generation table is bounded and retained in the
  checkpoint; exceeding its capacity rejects admission rather than silently
  forgetting cancellation history. Past/current-tick admission is rejected.

## Randomness

`CSPhilox` implements Philox4x32-10 with unsigned 32-bit words. It uses the
algorithm and three known-answer vectors from Random123's `tests/kat_vectors`.
There is no linked Random123 dependency or copied source. The ten-round multiply,
high/low split, XOR and Weyl increments use exact integers and explicit masks.

For unsigned world seed `S`, entity integer `E`, unsigned 32-bit stream `T` and
draw index `D`:

```
counter = [D, T, E[31:0], E[63:32]]
key     = [E[95:64] XOR S[31:0], E[127:96] XOR S[63:32]]
sample  = Philox4x32-10(counter, key)[0]
```

The probe draws once per entity per accepted tick on stream 0. The next draw
counter and sample are checkpointed. Counter exhaustion rejects the step.
Randomness depends on identity and draw address, never iteration order or MPI
rank. Rank-count independence is specified here; only a future distributed
conformance run can qualify it.

The independent address-mapping vector is entity
`0123456789abcdeffedcba9876543210`, seed `0xFEDCBA9876543210`, stream
`0x13579BDF`, draw `0x2468ACE0`: sample `697764476`. This exercises all entity
and seed words, beyond the small IDs in the progression fixture.

## Canonical data format

ASCII bytes only, no whitespace between values. Strings contain printable ASCII
32..126, length at most 4096. Decimal integers have no leading zero or plus sign;
zero is `0`, never `-0`. Allowed integer range is -2^63..2^64-1; schemas constrain
individual fields further.

| Value | Encoding |
| --- | --- |
| nil, true, false | `n`, `t`, `f` |
| integer | `i` + decimal + `;` |
| string | `s` + byte length + `:` + bytes |
| array | `a` + element count + `:` + values |
| dictionary | `d` + pair count + `:` + key/value pairs |

Dictionary keys are unique strings ordered by ascending ASCII bytes. Symbols,
floats, executable objects and other collections are rejected. Limits: 8 MiB per
document, depth 16, 500,000 values, 100,000 entries per container. Decode validates
the full input and requires exact canonical re-encoding. This is an initial
interchange/test codec, not the eventual high-throughput UE binary projection
protocol. Runtime must never serve this whole-world checkpoint per client frame.

## Bundle and checkpoint schema

A bundle is the six-element array:

```
[profile, modelId, tickMilliseconds, entityLimit, eventLimit, stageNames]
```

Limits are 1..10,000; defaults are 10,000. These are validation budgets, not
measured capacity claims. The immutable bundle stores canonical text and returns
detached data. Backend creation rejects unsupported stages before creating a world.

A checkpoint is a dictionary with exactly these keys:

| Key | Value |
| --- | --- |
| `version` | integer 1 |
| `model` | bundle array |
| `tick`, `seed` | nonnegative signed 64-bit tick, unsigned 64-bit seed |
| `entities` | entity ID to nine-element record |
| `resources` | nonempty resource string to nonnegative quantity |
| `events` | `[sortedEvents, identityGenerations, lastSequence, eventLimit]` |
| `outcomes` | resource grants from the latest step, each `[tick, resource, entityId, quantity]` |

An entity record is `[id, position3, velocity3, requestedResource,
requestedQuantity, mode, nextDrawIndex, lastSample, motionRemainders3]`.
An event is `[tick, phase, priority, entityId, sequence, eventId, generation, mode]`.
Restore checks schema, bounds, identities, references, future events and model
compatibility. No schema upgrade is implicit.

## Execution and read boundary

`CSSmalltalkBackend` is a synchronous single-owner backend. Admission and each
advance work on detached candidate state; publication replaces accepted state
only after all stages and validation succeed. Any failure preserves accepted
state and tick. The advancing guard prevents re-entry; it is not a multi-process
ownership/fencing protocol. GemStone must still serialize transactional access
through the later Runtime adapter. No Runtime queue or external I/O occurs here.

`snapshot`, `model` and `checkpoint` expose detached accepted data. Spatial grids
are derived from accepted positions and rebuilt after restore; they are never
checkpointed. Queries use integer floor cells, exact squared distances and sorted
IDs, and reject more than 4096 intersected cells. Region/AOI projections and
versioned backend detail reads remain later service contracts. Runtime will stay
the client endpoint when execution is external.

The full-copy candidate design intentionally starts with a simple failure
boundary. It is not a scale solution for 100,000 agents. P1 performance work must
measure allocation/commit costs and introduce bounded partitions or transactional
write sets without changing accepted semantics.
