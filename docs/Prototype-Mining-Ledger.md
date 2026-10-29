# GT prototype adoption ledger

30 October 2026. Live source inspected through GT MCP. Original `CESim*`, `CE*`
and `BVC*` experiments remain in the image. This increment adopts concepts and
specifications, not a wholesale copy of the experimental packages.

| Prototype evidence | Classification | Implemented result |
| --- | --- | --- |
| `CESimPipeline>>runInContext:`; staged context/view/update design | Adapt | Fixed data-described `events/move/contend/random` probe stages, detached candidate state and acceptance after complete validation |
| `CESimEngine>>advancePartitionTick` advances time before pipeline validity/execution | Specification-only | Failure tests require accepted time and state to remain unchanged; `CSSmalltalkBackend>>advance` publishes once after successful stages |
| `CEStableId>>=` and entity/partition ID subclasses | Adapt | Canonical 128-bit lower-hex entity/event IDs; no class identity, OOP or partition rank in wire equality |
| `CESimInbox>>drain`, key block and `printString` tie-breaker | Adapt | Explicit typed lexicographic event tuples and canonical ASCII ID order for contention; no blocks in durable model/checkpoints |
| `CESimDedupingInbox`, key block and `seenKeys` | Defer | Bounded event cancellation generations are implemented separately; they do not claim durable command deduplication. Outcome replay/retention belongs with Runtime P3 |
| Inert command/envelope and operation families | Specification-only | Admission API is data-oriented and checkpoints reject executable values; production WorkUnits, permissions, outcomes and transaction routing remain P3 |
| `CESimCoreExamples` ordering/lifecycle/scan concepts | Adapt | New independent tests for stage effects, admission-order timers, cancellation, canonical ID contention, exact-radius spatial oracle and continuation |
| `CETransactionRunner>>inTransactionDo:`; null runner evaluates the block | Defer | No fake transaction adapter. GT publication is detached-state replacement. Native qualification separately tests real GemStone commit, new session and abort |
| `CESimPartitionMap>>partitionIdsForTransform:inContext:` first-partition placeholder | Defer | Derived local integer spatial grid only; no claim of distributed ownership, halo exchange or migration |
| Domain-named `CECreatureEntity`, `CESimPlayerEntity` in generic experimental core | Defer | No ecosystem entity class or behaviour enters the kernel; future rules belong in CatalystEcosystem |
| Empty registered ecosystem packages; empty `BVCSimulation`/`BVCCombatSimulation` roots | Defer | No usable behaviour to transplant; no guessed implementation from class names |

New `CS*` classes were checked for collisions, compiled in live GT, tested there,
then exported via GT's Tonel writer into this independent checkout. Every exported
class/method definition is compared against its live snapshot before adoption.
Native qualification loads the same exports and independently compares the
installed definitions. Source proofs and executable results live in
`conformance/`; they qualify the new probe, not the original experiments.

The workspace [inventory](https://github.com/BenjaVisionPro/catalyst-workspace/blob/main/Simulation/GT-Prototype-Mining-Inventory.md)
retains the original package/class inventory and inspected method findings.
