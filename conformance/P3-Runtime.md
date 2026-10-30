# P3 Runtime and GemStone durability

The [authority-1 contract](../contracts/authority-1/README.md) describes the service,
payloads, fencing, receipts, publication and recovery policy. The
[qualified record](results/runtime-p3-2026-10-30/qualification.json) preserves the
managed Runtime run, with raw logs/checkpoints in `artifacts.zip`.

## Proven in this record

- 52 GT tests pass, including the 32 unchanged portable kernel/graph contracts.
- 43 portable kernel/authority tests pass in native GemStone 3.7.5.
- Named, authoritative `CSSimulationService` starts through a configured native
  Runtime in `bvc_simulator_native`. Production WorkUnits use the real native
  route and default transaction-owning workers.
- Another Gem observes committed creation/advance, and verifies that a body
  failing after mutation leaves state, revision, sequence and receipt unchanged.
- Runtime stop/start preserves the frontier. Explicit recovery rotates the
  placement fence, and scheduled local progression submits a transactional
  WorkUnit through the existing same-worker Runtime route.
- Runtime accepts the exact P2 four-rank Repast checkpoint through external
  reconciliation, serves it through the same read/checkpoint API, switches back
  to local execution and continues identically to tick 12.
- A second stop/start retains the uncertain external batch. A late result with
  its old placement stamp is rejected; no uncertain application delivery or batch
  is deleted or automatically replayed.
- Two independent Gems prepare competing candidates at the same frontier. A
  fresh reader sees neither candidate. One commits and the other reports a real
  write/write conflict. The second round races placement transfer against advance.
  Both losing bodies execute once, with no automatic replay.
- Receipt expiry and slow-reader resnapshot gaps stay bounded. The managed
  Runtime and its task-owned repository/evidence are stopped and removed.

GT result-completion tests verify Simulation's after-finalization publication
and suppression after pipeline failure. Native Runtime owns after-commit
publication; this run separately proves native committed service reads. It does
not establish a new wire transport or client authentication protocol.

## Source and installation evidence

Smalltalk classes and methods were compiled and exported through the live GT
image into an independent component checkout, then round-trip compared as
Monticello definitions. No registered live-image checkout was externally changed.
The native source comparison covers 358 composed Simulator definitions and 2,688
composed Runtime definitions, including native overrides.

GemStone Monticello includes subpackages in a parent package's snapshot. The
checker therefore composes definitions by class/side/selector rather than
mistaking optional test packages for source drift. It excludes only
`CSSimulationRuntimeExamples`, whose direct GT worker fixture is replaced by
the managed native qualification. Native qualification utility WorkUnits are
included in the source comparison.

The bvc install paths now select Simulator Runtime after native Runtime, and
the GT startup selects `RuntimeTests` after loading Runtime. Both the actual
native Runtime recipe and Simulator Runtime recipe pass in the dedicated stone.
The bvc CLI's 54 contract tests pass, including ordered installation and retry
without recreating a stone. A sandbox-only first attempt could not inspect its
stub processes with `/bin/ps`; the passing run used the required process-inspection
permission. No real Rowan build is involved in these stub tests.

## Reproduce

Use macOS and the dedicated `bvc_simulator_native` deployment. This runner does
not create/rebuild/stop the stone or launch Docker/Repast. It creates its own
uniquely named Runtime and removes only that Runtime on success. Use an independent
source checkout exported/verified through GT, respecting live-image ownership.

1. Load the component's `RuntimeTests` group in GT and run the test methods in
   `CSKernelExamples`, `CSGraphExamples`, `CSAuthorityExamples` and
   `CSSimulationRuntimeExamples`. Export and compare the selected packages through
   GT MCP before loading their native versions.
2. Install the existing native Runtime prerequisites and Simulator production
   packages through bvc's `--with-seaside` path. For an already provisioned stone,
   run the native Runtime and Simulator recipes with their source/report
   environment variables. Set `BVC_SIMULATOR_LOAD_RUNTIME=1` for the Simulator
   recipe. The default standalone Simulator recipe still supports Core-only loads.
3. Load and run native test support with `bvc topaz`, from the deployment's project
   directory:

   ```sh
   CS_P3_SOURCE=/absolute/catalyst-simulator/src \
   CS_P3_PREPARE_REPORT=/absolute/evidence/native-tests.json \
     bvc topaz bvc_simulator_native \
       --script /absolute/catalyst-simulator/scripts/prepare-runtime-tests.topaz
   ```

4. Compare source with the running stone:

   ```sh
   CS_P3_SOURCE=/absolute/catalyst-simulator/src \
   CS_P3_RUNTIME_SOURCE=/absolute/CatalystRuntime/src \
   CS_P3_SOURCE_REPORT=/absolute/evidence/source-native.json \
     bvc topaz bvc_simulator_native \
       --script /absolute/catalyst-simulator/scripts/verify-runtime-source.topaz
   ```

5. Run the managed qualification against a fresh output directory:

   ```sh
   python3 scripts/qualify-runtime.py \
     --project /absolute/project-containing-native-deployment \
     --bvc /absolute/bvc/bin/bvc \
     --deployment bvc_simulator_native \
     --output /absolute/fresh-evidence-directory
   ```

The controller uses bounded subprocesses and uniquely named fixtures. Its oracle
files come from the committed P2 fixture/archive, with byte comparisons before use.
Verify the packaged receipts, source hashes, conflicts and checkpoint frontiers
offline with:

```sh
python3 scripts/verify-runtime-evidence.py conformance/results/runtime-p3-2026-10-30
```

This is a socket-free native GemStone test; it does not execute native C++/GT
interop. Any added C++/GT run still requires `CCNativeMcpLease` and the outside-GT
completion gate.

On failure, inspect the retained named Runtime, repository, native queue and logs.
Do not rerun a saved application body or delete an uncertain delivery. The first
development run exposed a harness-only queue-drain race after live configuration;
it was inspected, the task-owned Runtime was stopped/cleaned explicitly, and a
fresh full qualification passed after adding the drain wait.

## Remaining gates

The initial authority profile accepts bounded full graph-1 checkpoints. It is
not the eventual partitioned checkpoint/projection format for 100,000 agents.
External process management, authenticated readiness/result transport, executor
queries, accepted remote read handles and massive-scale projections remain P6/P8.
Connect transport binding and the one-click GT workflow require further
integration. The P3 APIs provide the accepted revision, placement and recovery
boundary those integrations must use.
