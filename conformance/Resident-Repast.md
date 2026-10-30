# Resident Repast backend

The subsequent optional [sharded checkpoint/projection profile](Sharded-Projections.md)
removes this mode's whole-checkpoint transport and acceptance limits. This record
continues to describe and qualify the retained full-checkpoint resident mode.

The resident adapter retains a compiled portable model graph and Repast
`SharedContext` across accepted execution windows. Runtime still serves client
requests and GemStone still owns accepted revisions, checkpoints and placement
generations. CatalystEcosystem remains the first domain; no ecosystem behaviour,
NPC behaviour or automation behaviour is implemented in this adapter.

## Runtime binding

Set `CSSimulationConfiguration>>repastMode:` to `'resident'`, with the existing
absolute launcher/executable/MPI/spool paths and rank count. The launcher is
`scripts/repast-resident.py`; initialize its dedicated spool with `--initialize`.
The default mode is `'batch'`, and the original batch adapter remains available.
Mode participates in the queued-transition policy digest. Changing execution
mode, rank count or executable requires resolving pending work, fencing the old
placement and using the matching spool format.

The resident driver uses the existing data-only `prepare`, `dispatch`, `result`,
`transfer`, `activate`, `recover` and `reconcile` operations. It adds no domain or
native dependency to Core or Authority. All shared Smalltalk source is authored
and exported through GT, then compared against the independent native stone.

Runtime-owned nontransactional progress handles native I/O. Authority changes
still run in subsequent transactional WorkUnits with expected revision, owner,
generation and configuration-policy checks. A native reply alone never advances
the accepted GemStone frontier. Reads use the same named Runtime service in
every placement, including during execution, handover and recovery.

## Resident execution

Each world/group placement generation has one exclusively claimed incarnation.
Its identity includes world/group, owner, generation, model digest and a fresh
incarnation token. One supervisor owns the MPI process group through reaping.
An fsynced per-group generation fence rejects stale launches and retirements
before process effects; read-only queries of older receipts remain available.
The native process compiles the graph and restores the checkpoint once, then
waits for strictly sequenced commands:

1. `advance` must start at the current checkpoint digest and tick. A committed
   Runtime dispatch supplies the batch/input binding and a bounded target tick.
2. Agents migrate through Repast while ticks execute. The native process gathers
   a full checkpoint only at the requested boundary and waits for acceptance.
3. The supervisor fsyncs an immutable result checkpoint and receipt for that batch.
4. Runtime validates and accepts the result in GemStone. Its accepted digest and
   revision acknowledge the candidate. A subsequent window cannot execute before
   that acknowledgment.
5. `stop` ends the session; the supervisor waits for MPI exit before publishing
   `nativeReaped`. Local placement activation waits for that retirement evidence.

No per-tick full checkpoint files are written in resident mode. Graph compilation,
initial restore and process IDs remain unchanged between windows. A single inbox
slot identifies the current request, so the worker does not scan retained receipt
history during progression. Receipts remain available for duplicate queries and
reconciliation.

## Switching and failure recovery

An external handover restores the accepted GemStone checkpoint into a paused
resident session and requires byte equality before activation. An idle external
view synchronizes its accepted frontier with that session. Returning to GemStone
retires resident incarnations for the group and reconstructs the Smalltalk backend
from the accepted checkpoint before activation.

A Runtime service restart reattaches to the existing incarnation through the
durable spool. It does not start another MPI process. Lost replies return the
same immutable batch receipt. Placement recovery rotates the owner/generation
and queries the original pending binding; it never launches from reconciling
state. A verified retained result becomes an ordinary fenced reconciliation
proposal. The next placement starts from the recovered accepted checkpoint.

A failed MPI incarnation is never automatically relaunched or replayed. After an
idle failure, explicit Runtime recovery rotates placement and restores the last
accepted checkpoint. If failure leaves a dispatched batch without a complete
receipt, the pending batch stays uncertain: an operator must establish its outcome
or confirmed absence before another advance. A crash after computation but before
durable receipt publication is deliberately not treated as confirmed absence.

Runtime renews a 60-second client lease while observing the session. Supervisors
also pulse a separate native heartbeat; idle native command waits abort after
30 seconds without it. Native replies have bounded deadlines, and supervisors
terminate only their own MPI process group on failure. Operator shutdown uses
`scripts/repast-resident.py --spool /absolute/path --shutdown` after stopping
Runtime; poll until all
incarnations report `nativeReaped`. Stopping Runtime alone permits a brief restart
without losing the resident process; an abandoned session expires its client lease.

## Current scaling boundary

This removes per-window MPI startup, graph compilation, restore and per-tick
full-state gathering. It establishes resident execution; it does not qualify a
100,000-creature ecosystem. The current graph profile and full checkpoint/receipt
limits remain: 1/2/4 native macOS ranks, at most 64 ticks per window, 49,152 JSON
request bytes and 192 KiB checkpoint bytes. Runtime still materializes the full
accepted checkpoint. Repast retains the generic boxed-value interpreter,
replicated metadata and root resource arbitration from P2.

Next scaling gates are typed column storage, partition-local interaction/halo
exchange, incremental accepted projections and sharded checkpoint artifacts,
bounded receipt retention, remote authenticated transport and population/memory
benchmarks. Checkpoint limits must be replaced by those contracts before claiming
massive-scale Runtime serving. Changing accepted state with an external-idle
Smalltalk command currently requires placement recovery before the next resident
advance if its digest differs from the resident frontier; command streaming into
the resident session is a separate gate. Landform integration and ecosystem
behaviour remain in their own component and milestones.

## Qualification and reproduction

Qualified on 30 October 2026: 62 GT tests, 53 native GemStone tests, 19 transport
and lease checks, plus native codec/random and batch compatibility checks. All
414 exported Simulator definitions match the independent native stone.
The managed Runtime proof passes on 1/2/4 ranks with 18 durable result receipts
across nine resident incarnations, including three deliberately failed by rank
kill. Three additional resident incarnations run the 16-entity protocol fixture
through 15 result windows. Graph compilation and restore counts remain one per
incarnation; the protocol fixture reaches tick 12 with six full snapshot gathers
rather than one per tick. All incarnations and test Runtimes are cleaned up.

The final accepted checkpoint digest is identical for every rank count:
`483452a978d4439064b1143a9cc66fb727a61c4894c5d8d5a98a39ac4db019f0`.
See [committed proof](results/resident-repast-2026-10-30/qualification.json) and run
`python3 scripts/verify-resident-repast-evidence.py` for offline verification.

The qualification uses the dedicated `bvc_simulator_native` devkit stone, native
macOS MPI, the pinned Repast HPC source and the same portable model bundles. No
Docker or Rowan is used. Hold a fresh `CCNativeMcpLease`; the controller refuses
to invoke Topaz without its own active marker. One controller owns Runtime and
every native session through shutdown. Wait outside GT for the released
`gt-mcp-gate.json` before joining the owner.

```sh
cmake --build /absolute/path/to/repast-build -j6
python3 scripts/test-repast-resident.py
python3 scripts/test-repast-batch.py
python3 scripts/qualify-resident-repast.py \
  --project /absolute/path/to/dedicated/bvc/project \
  --bvc /absolute/path/to/bvc/bin/bvc \
  --executable /absolute/path/to/repast-build/catalyst_repast \
  --output /absolute/path/to/fresh/evidence \
  --lease-release /absolute/path/to/fresh/lease/release
```

For each rank count, the managed Runtime test runs GS tick 1 → resident ticks
3/4 → completed tick 6 with reply suppressed → Runtime restart with unchanged
rank PIDs → fenced recovery of tick 6 → resident tick 8 → injected rank kill →
recovery into a new incarnation → scheduled tick 10 → GemStone tick 12. Every
accepted read through Runtime is checked against the GT/P2 canonical oracle.

A separate native protocol probe continues the 16-entity cross-rank contention
fixture through ticks 1/2/4/8/12 in one incarnation, using each actual result as
the next input. It is a native determinism/continuation test, not a GemStone
authority or population benchmark. The original batch entry point and native
canonical/random tests also run under the same lease.
