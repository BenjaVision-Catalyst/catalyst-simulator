# Native Repast HPC feasibility

The same interpreter now also implements the optional
[`resident-1` session](../../contracts/resident-1/README.md). Batch behaviour is
retained; resident mode keeps the compiled graph and distributed agents across
advance windows. See [resident qualification](../../conformance/Resident-Repast.md).

P2 passes on macOS arm64 with the same normalized `graph-1` bundles used by GT
and GemStone. This directory contains an experimental execution adapter and a
bounded qualification controller. Ecosystem behaviour stays in CatalystEcosystem.
Runtime service integration and one-click placement are subsequent work.

The [qualified record](../../conformance/results/repast-p2-macos-2026-10-30/qualification.json)
contains 24 runs: four initial states × 1/2/4 ranks × two ownership layouts.
Every boundary from tick 1 through 12 matches the live GT export and independent
Python interpreter byte for byte. Twelve restarts change ranks 1→2, 2→4 and
4→1 at tick 6 and match through tick 12. There are 372 archived MPI boundaries.

The fourth state uses the unchanged `conditional-graph` model digest, 16 agents, negative
coordinates, fractional motion and a shared resource with only three units.
The committed GemStone tick-1 checkpoint still holds all three units and no
requests. At tick 2, timers activate all 16 agents in Repast and each requests
two units. The smallest Catalyst ID wins even though it belongs to another rank
in layout zero. In the 11 distributed steps, the two-rank
and four-rank cases each record 176 actual ownership migrations.
Final ownership counts are 8/8 and 4/4/4/4. Root receives requests from other
ranks; this exercises exchanged interaction rather than independent replicas.

## Execution

- Real Repast `RepastProcess`, `SharedContext`, `ScheduleRunner`, agent packages
  and `synchronizeAgentStatus` drive the distributed run.
- Each rank owns only its assigned agent rows and executes their entity nodes.
  The initial input is broadcast for partition construction. Replicated metadata,
  root event draining and root resource arbitration are explicit P2 simplifications.
- All 16 graph-1 operations are interpreted from the bundle. Stages have immutable
  reads; ordered dependencies determine effects. Integer motion uses widened exact
  arithmetic, checked signed results and floor division. Addressed Philox uses
  Catalyst ID, seed, stream and draw index.
- Full 128-bit Catalyst IDs remain authoritative. Repast IDs use the canonical
  initial population ordinal with starting rank zero; current rank changes during
  migration. No rank or memory address enters persistent state or model identity.
  Dynamic population membership is outside this probe.
- Rank ownership is `floor(x / 1 mm) + layout modulo ranks`. Small cells deliberately
  force migration. The scheduler uses bounded relative steps; checkpoint ticks stay
  exact signed integers.
- At each boundary, root gathers unique owned rows, validates the complete
  checkpoint and atomically renames its output files. This is local file
  publication, without a production Runtime acceptance protocol.
- Six capability fixtures reject before launch with matching issue codes and
  paths. Corrupt digests reject before publication. A collective arithmetic failure
  leaves the previous accepted checkpoint intact.

## Native build

The qualified toolchain is Apple clang 21.0.0, Open MPI 5.0.11, Boost and
Boost.MPI 1.92.0, OpenSSL 3.6.5 on macOS 26.6.1 arm64.
[build.json](../../conformance/results/repast-p2-macos-2026-10-30/build.json)
records the SDK, CMake cache, source hashes, installed dependency receipts,
binary identities and linked-library hashes. This records an exact tested
installation; it is not a hermetic SDK/dependency distribution.

Provision the corresponding native dependencies:

```sh
brew install open-mpi boost boost-mpi openssl@3 cmake ninja
```

From the component checkout, with the pinned workspace reference available:

```sh
cmake -S native/p2 -B /private/tmp/catalyst-repast-build -G Ninja \
  -DREPAST_SOURCE="$PWD/../References/repast.hpc" \
  -DCMAKE_PREFIX_PATH='/opt/homebrew/opt/boost;/opt/homebrew/opt/openssl@3' \
  -DOPENSSL_ROOT_DIR=/opt/homebrew/opt/openssl@3 -DCMAKE_BUILD_TYPE=Release
cmake --build /private/tmp/catalyst-repast-build -j6
```

CMake requires upstream commit `a96c15f99589d15352523a0a710362af8997852a`.
It builds 28 upstream core translation units, omitting the two NetCDF recorder
units. OpenMP is disabled; each MPI rank uses one simulation thread. No upstream
source is modified. The libc++ compatibility definition restores the old
`unary_function`/`binary_function` bases used by Repast. Homebrew splits
Boost.MPI into a separate prefix; the adapter links its matching library directly
because its packaged CMake config references a missing adjacent helper.

Repast retains its upstream licence in the pinned reference. MPI, Boost and
OpenSSL retain their respective licences; no upstream implementation is vendored
here. Philox is independently implemented against the portable contract and
Random123 known-answer vectors.

## Qualification and ownership

Use the live GT image to evaluate `export-fixtures.st` through GT MCP. Optionally
set `CSRepastP2FixtureDirectory` to an output directory and remove it afterward;
the default is `FileLocator temp / 'catalyst-repast-p2-input'`. This runs the 32
Smalltalk tests and exports models, registry and all reference boundaries. It
does not edit shared kernel classes. The committed fixture export can also be
used for replay when freshly exporting GT is unnecessary.

All native execution must be inside `CCNativeMcpLease`, owned by one independent
controller through subprocess and GemStone cleanup. No Runtime service is started
for this file/checkpoint experiment. Start an asynchronous `CCNativeInteropRun`
through GT MCP with this shape, replacing the absolute lease directory with a
fresh directory:

```smalltalk
| run |
run := CCNativeInteropRun new start: [| lease deadline |
 lease := CCNativeMcpLease forRunningServers.
 [lease during: [
  CRPlatform current writeConnectEvidence:
   (Dictionary new at: 'active' put: true; yourself)
   to: '/absolute/lease/lease-active.json'.
  deadline := CRPlatform current currentMillis + 1800000.
  [('/absolute/lease/release-lease' asFileReference exists)
   or: [CRPlatform current currentMillis >= deadline]]
    whileFalse: [(Delay forMilliseconds: 10) wait]]]
 ensure: [CRPlatform current writeConnectEvidence: lease snapshot
  to: '/absolute/lease/gt-mcp-gate.json']].
Smalltalk globals at: #CSRepastP2Owner put: run.
run snapshot
```

Wait outside GT for `lease-active.json`, then launch the single controller:

```sh
python3 native/p2/qualify.py \
  --manifest /absolute/input/manifest.json \
  --binary /private/tmp/catalyst-repast-build/catalyst_repast \
  --output /absolute/fresh-run-directory \
  --project /absolute/project-containing-native-deployment \
  --bvc /absolute/bvc/bin/bvc \
  --deployment bvc_simulator_native \
  --lease-directory /absolute/lease
```

The manifest's sibling `registry.canon` is required. The controller checks the
active lease marker, bounds each command, owns the MPI process groups and creates
a unique persistent GemStone root. A failed launch still requires releasing the
lease; never leave an owner unattended until its safety deadline.

The Topaz scripts use the installed Core/Tests in `bvc_simulator_native`; they
do not load source, rebuild a stone or use Rowan. GemStone runs all 32 tests,
restores each GT initial state, advances to tick 1, commits and exports its exact
bundle/checkpoint. Repast resumes those bytes. For every rank/layout combination,
GemStone imports tick 4, continues through the pending tick-5 timer to tick 6,
commits, and verifies the results in a fresh Topaz session. Event cancellation
history, identities, draw state, remainders and resource outcomes are included in
the byte comparison.

The controller also kills an owned four-rank job after tick 2 is prepared but
before publication. The file remains at tick 1; a fresh GemStone session verifies
the committed source is unchanged. In all outcomes the controller reaps its jobs,
removes its temporary GemStone root, then writes `release-lease`.

Wait **outside GT** for `gt-mcp-gate.json` with `state = released` and
`originalRegistriesRestored = true`. Only then use GT MCP to join the owner with
`waitForMillis:`, inspect its snapshot and remove its global. Do not bypass a busy
lease using another MCP client.

The [archived evidence](../../conformance/results/repast-p2-macos-2026-10-30)
includes raw canonical traces and Topaz/MPI logs in `artifacts.zip`, the live GT
fixture export, qualification report, lease release and build provenance.
Verify it offline without starting native code:

```sh
python3 native/p2/verify-evidence.py conformance/results/repast-p2-macos-2026-10-30
```

## Decision and remaining gates

Repast is feasible as the first external adapter for this bounded portable
profile. Keep the same bundle/checkpoint boundary and the Simulator/Ecosystem
split. No kernel source or model-specific C++ translation was necessary.

This proves correctness on one host and small populations. It does not qualify
100,000 creatures, a cluster, ecological interactions, NPC reservations, automation
networks, dynamic births/deaths or production deployment. The current graph-1
capacity limits remain unchanged. P6/P8 must replace root arbitration/gather with
bounded distributed protocols and partitioned durable checkpoints, qualify ghost
neighbours and distributed interactions, and measure throughput/memory/latency.
The generic boxed `Value` representation favours inspectable correctness; a
production adapter needs packed component storage and bounded typed message
buffers behind the same model/state contracts.

P3 must supply GemStone-backed accepted revisions, placement fencing, idempotent
commands, durable state/projection acceptance and crash recovery. Runtime remains
the client endpoint and must serve accepted external read views without mirroring
every agent. P7 then binds the lifecycle into the GT one-click switch. The killed
speculative job establishes a P2 boundary property; it is not a distributed
transaction or production failover test.
