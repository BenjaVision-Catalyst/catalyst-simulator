# Live Runtime → Repast integration

This increment binds the P3 Simulation service to the actual native P2 Repast
executable. It uses the same portable graph bundles, operation catalog, integer
rules, Philox addresses and canonical checkpoints. No domain behaviour lives in
the adapter. CatalystEcosystem remains separate; Landform integration, NPCs and
automation are outside this increment.

## Execution and authority

`CSSimulationConfiguration` optionally selects absolute launcher, executable, MPI
and durable spool paths, with a qualified rank count of 1, 2 or 4. Empty paths keep
the existing Smalltalk service. The existing Runtime and RuntimeTests load groups
include the adapter; Core and Authority have no Runtime or native dependency.

Runtime-owned `CSSimulationDriveWork` performs I/O outside the GemStone
transaction. It observes committed execution-group state and enqueues an inert
`CSScheduledSimulationTransitionWorkUnit` addressed to the same named service.
That unit performs the authority operation in a subsequent Runtime-owned
transaction. Each queued transition carries the configuration policy digest,
expected revision, generation and owner. Superseded configuration or placement
cannot accept its result. No process, transport or executable service is persisted
in an execution group.

An external handover first runs a zero-step native restore. The checkpoint must
be byte-identical before Runtime enqueues activation. Local return reconstructs
the Smalltalk backend from the accepted checkpoint before activation.

For advancement, prepare records a content-addressed batch; dispatch durably marks
it uncertain. Only then may the nontransactional driver claim and launch it. The
native adapter starts MPI from that exact input and publishes a complete result
only after successful MPI exit. Intermediate `native/accepted.canon` files are
private candidates and never client views. Runtime validates binding, digest,
model, seed and frontier, then proposes acceptance through the usual service.

Reads during native execution and handover return the previous accepted view.
Clients keep the same Runtime Simulation endpoint, world/group identifiers and
revision contract throughout the switch. This qualification exercises actual
Runtime routing and accepted read work units; it does not introduce another
client listener or a direct client-to-MPI path.

## Durable transport and recovery

`scripts/repast-batch.py` is a native macOS, local filesystem transport. Initialize
a dedicated spool once with `--spool /absolute/path --initialize`. Retain it
across Runtime restarts. Runtime supplies trusted executable paths; model data
cannot select a shell command. Arguments are quoted at the GemStone boundary and
MPI launches use argument arrays without a shell. There is no Docker dependency.

The spool is evidence, **GemStone is the acceptance authority**. Exclusive claims,
atomic fsynced manifests and a per-job worker lock prevent repeated `ensure`
requests from executing the same job twice. A crash after claim and before
confirmed completion remains uncertain. Neither an incomplete claim nor a failed
job is automatically retried. Missing spool identity fails closed. Operators must
retain/restore the spool or explicitly reconcile lost evidence.

Each receipt binds world/group, model digest, original placement generation and
owner, batch/input digest, input checkpoint digest and logical interval. The
executable digest and rank count are retained as evidence. A completed result can
be queried repeatedly without starting MPI again.

After explicit placement recovery rotates the owner/generation, Runtime queries
the **original pending binding** and never launches from the reconciling state.
A verified complete receipt becomes a `confirmed-result` reconciliation proposal.
The same authority checks commit it under the current placement. Late results
submitted under the old placement are fenced. Missing, failed or unknown jobs
remain unresolved; the bridge does not infer confirmed absence or blindly replay.

## Bounds and remaining work

This is a bounded batch integration, not a resident population service or a
100,000-creature qualification. Each batch launches fresh MPI ranks and restores
the full checkpoint. It retains the P2 root gather/resource arbitration and boxed
values. The local bridge accepts at most 49,152 JSON request bytes, 192 KiB of
checkpoint bytes and 64 ticks per batch; service configuration can impose a lower
step limit. The subprocess supervisor bounds MPI execution to 120 seconds and
terminates only its own process group on timeout. Per-batch evidence is retained;
spool archival/retention policy is an operator responsibility for this increment.

Production gates remain resident/sharded execution, bounded accepted projections
and AOI streaming, remote authenticated transport, durable artifact storage,
read-view retention, deployment/version negotiation and a GT placement UI. A
filesystem receipt protects against lost replies and process restarts; it is not
a cryptographic proof of simulation correctness or a distributed consensus log.

## Qualified results, 30 October 2026

| Check | Result |
| --- | --- |
| GT kernel/authority/Runtime/batch tests | 57 passed |
| Native GemStone portable/batch tests | 48 passed |
| Transport failure/lease guard checks | 7 passed |
| Native source comparison | 401 definitions match the GT-verified checkout |
| Live switch and recovery | 1, 2 and 4 ranks passed |
| Native launches | Exactly 12: two paused restores and two advances per rank count |
| Scheduled progression recheck | 2 ranks; local and external automatic drive passed, with 4 additional jobs |
| Final accepted tick-12 digest | `483452a978d4439064b1143a9cc66fb727a61c4894c5d8d5a98a39ac4db019f0` for every rank count |

The live fixture is the existing two-entity conditional graph, including integer
motion, events, mode changes and addressed random draws. Repast's own execution
records confirm rank counts and agent migrations. Cross-rank contention on the
larger neutral fixture remains covered by the separate P2 proof; neither fixture
is an ecosystem or a population-scale benchmark.

[Committed evidence](results/live-repast-2026-10-30/qualification.json) includes
endpoint observations, native claims/receipts/checkpoints, MPI execution records,
source comparisons and released MCP gates. Verify it offline with
`python3 scripts/verify-live-repast-evidence.py`.

## Reproduction

Build the pinned native adapter as described in [P2](../native/p2/README.md).
Use the dedicated `bvc_simulator_native` devkit stone, without Rowan. Hold
`CCNativeMcpLease` around the controller and all native jobs; wait outside GT for
the released gate before inspecting/joining its owner.
The controller checks for its own `active.json` marker and refuses to invoke
Topaz if that lease was not acquired or has already released.

```sh
python3 scripts/test-repast-batch.py
python3 scripts/qualify-live-repast.py \
  --project /absolute/path/to/dedicated/bvc/project \
  --bvc /absolute/path/to/bvc/bin/bvc \
  --executable /absolute/path/to/catalyst_repast \
  --output /absolute/path/to/fresh/evidence \
  --lease-release /absolute/path/to/lease/release
```

The controller installs the GT-exported Runtime adapter in the dedicated stone,
runs portable/driver tests, then owns one uniquely named managed Runtime at a
time. For each rank count it exercises GS tick 1 → native restore → Repast tick 4
→ GS tick 6 → native restore → Repast tick 8 with its reply dropped → Runtime
restart → placement fencing/reconciliation → GS tick 12. Every accepted endpoint
read is compared with the GT/P2 canonical oracle. Exactly four native jobs per
rank count demonstrate that restart and repeated polling do not duplicate work.
The injected fault drops only the transport reply; real native execution and its
durable result remain intact. All runtimes and owned native jobs are cleaned up
before releasing the lease.
Use `--ranks 2 --scheduled` for the additional scheduled progression run. It
replaces the explicit tick-4 prepare and tick-12 local advance with Runtime policy
updates and waits for automatic transactional progress.
