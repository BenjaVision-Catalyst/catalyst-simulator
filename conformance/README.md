# Portable kernel qualification

30 October 2026: **32/32 GT tests and 32/32 native GemStone tests passed**
(18 probe contracts plus 14 graph contracts).
The tested hosts were Pharo 13.1.0SNAPSHOT in the connected GT image and GemStone
3.7.5 arm64 in `bvc_foundation_portable`. GT export and native snapshot comparisons
matched every class/method. The legacy probe and three graph models matched
canonical ticks 0/1 natively; a fresh native session matched continuation to tick
6, then proved real abort restoration and removed its disposable root. Model
and registry digests and six compatibility reports matched across platforms.
Independent Python oracles matched four legacy and twelve graph checkpoints,
three model digests, the registry digest, three Random123 vectors and the
full-width random-address vector. The same 32 contracts now pass after a fresh
GT rebuild and GemStone 3.7.5 `--with-seaside` rebuild; see the workspace
[fresh-load record](https://github.com/BenjaVisionPro/catalyst-workspace/blob/main/Simulation/evidence/rebuild-2026-10-30.md).
Current devkit stones do not use Rowan; that migration is deferred to GemStone 4
in 2027. This opening record describes P0/P1. Later P2/P3 evidence is linked below;
production external execution and scale remain open.

The GT image is authoritative for shared source. Author/compile/test through GT
MCP, then export with TonelWriter and compare every class/method definition with
the live package snapshot. Do not patch the exported `.st` files. Load that
verified independent checkout into GemStone for native qualification.

## GT

Load `BaselineOfCatalystSimulator` group `Core` for a headless kernel, or `Tests`
for its optional SUnit contracts. Default loads Core only. No Runtime, Connect,
GT UI, ecosystem, Unreal or MPI dependency is required by Core. Rowan Core/Tests
metadata is supplied separately; direct Rowan loading needs its own qualification.

Run `CSKernelExamples suite run` and `CSGraphExamples suite run` and require no
failures/errors. A small legacy world is `CSKernelExamples new probe`; a graph
world is `CSGraphExamples new worldFor: CSGraphExamples new conditionalModel`.
Send `advance`, `advanceThrough: 6`,
`snapshot`, `checkpoint` or `spatialGridWithWidth: 1000` to it. Restore with
`CSSmalltalkBackend fromCheckpoint: savedBytes`. `advanceThrough:` accepts at most
1000 future ticks per call, accepting each step separately.

`gt.json` records executed tests and export snapshot definition counts (including
the organization definition). Fixture canonical bytes are emitted by that tested
GT models at ticks 0, 1, 2 and 6. `check_probe.py` checks the legacy bytes with
independent integer arithmetic, event ordering and Philox. `check_graph.py`
interprets the same graph data independently and uses hashlib to check all model
and registry digests. Run:

```sh
python3 conformance/check_probe.py
python3 conformance/check_graph.py
```

These are conformance oracles rather than supported execution backends. P2 now
qualifies bounded native MPI rank-count independence in its separate record.

## Native GemStone

Use the workspace `gemstone-topaz` skill from the existing deployment's project
directory. Choose a unique qualification root and absolute output paths. Keep
login credentials in the existing bvc login configuration, never in these scripts.
The load script mutates only the new Simulator packages and its named fixture
root; do not run it concurrently with another Simulator source load.

For a fresh build, run `scripts/verify-installed-core.topaz` before the qualifier.
It loads no Simulator source and compares the already installed Core against all
three graph traces/digests and six compatibility cases. Set SOURCE as below and
`BVC_REBUILD_REPORT` to a fresh JSON output path. Its prerequisite flags record
whether Simulator test classes and Rowan were present before qualification.

Set these environment variables for `bvc topaz <deployment> --script
<simulator>/scripts/qualify-gemstone.topaz`:

- `BVC_SIMULATOR_SOURCE`: absolute path to this checkout's `src`.
- `BVC_SIMULATOR_ROOT`: fresh unique Smalltalk symbol name for the disposable root.
- `BVC_SIMULATOR_REPORT`: absolute output file for native test/source evidence.

The installed older Tonel port can read current Tonel snapshots but its Gofer
repository listing expects historical version metadata. The runner therefore
loads the unchanged snapshot definitions in superclass order through GsDeployer,
then verifies all native class/method definitions against the exported snapshots.
It requires the host's Tonel reader, SUnit, STON, Metacello and BaselineOf.

The runner executes both suites, matches canonical tick 0/1 model/state fixtures,
model/registry digests and all compatibility reports, then commits the four tick 1
backends under one qualification root. It also checks default load-group
selection and parses/checks Rowan metadata; this does not qualify direct Rowan
installation. If the run fails, inspect its logs and named root before retrying.
It never stops/reconfigures an existing Runtime or stone.

In a **new Topaz session**, retain SOURCE/ROOT and set
`BVC_SIMULATOR_RESUME_REPORT`, then run `scripts/resume-gemstone.topaz`. It checks
that every committed tick 1 survived logout/login, advances each to the GT tick 6
bytes, aborts and verifies restoration of every model to committed tick 1, then removes and commits
removal of its own root. Both process exit status and reports must pass. This
tests real repository persistence/abort separately from GT candidate publication.

`gemstone.json` and `gemstone-resume.json` record those separate native runs.
Definition counts there exclude organization definitions. The root name records
fixture ownership; it must be absent after successful cleanup. The scripts do not
claim multi-owner fencing, Runtime transactional delivery, stone-process restart,
production crash recovery, external migration or performance qualification.

The first probe qualification found two dialect assumptions: large negative
decimal parsing and the ninth ordinal accessor. The shared GT-authored source now
parses decimal digits explicitly and accesses that record field by index. No
GemStone-specific fork of the kernel was introduced.

The [rebuild record](../docs/Rebuild-Readiness.md) explains the next clean-load gate.

## Runtime acceptance and durability

The [P3 record and reproduction](P3-Runtime.md) cover the named Simulation service,
accepted revisions, retry windows, placement fencing and uncertain-batch recovery.
GT passes 52 tests; native portable qualification passes 43. A configured
`bvc_simulator_native` Runtime proves real routing, commit/rollback from another
Gem, scheduled transactional progression, restart/reconciliation and two
independent-session writer conflicts. Source exports and actual native bvc install
recipes match the running stone. P0/P1's older JSON/source-hash files remain
historical; the P3 directory records the current source set.

## Native Repast feasibility

The [P2 adapter and runner](../native/p2/README.md) execute the unchanged graph-1
bundles natively on macOS with 1/2/4 MPI ranks, actual Repast agent migration and
shared-resource contention. The dedicated `bvc_simulator_native` stone exports
committed checkpoints and accepts returned states for native continuation.

[The qualified record](results/repast-p2-macos-2026-10-30/qualification.json)
includes 24 rank/layout runs, 12 rank-count restarts, 24 durable GemStone returns,
negative capability/digest/overflow checks and speculative-job termination.
Raw canonical traces and logs, toolchain identities and the released GT MCP lease
are archived beside the report. Use `native/p2/verify-evidence.py` for offline
verification. This is P2 correctness evidence; production Runtime acceptance,
one-click migration and massive-scale qualification remain later gates.
