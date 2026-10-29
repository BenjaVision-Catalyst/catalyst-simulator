# Kernel probe qualification

30 October 2026: **18/18 GT tests and 18/18 native GemStone tests passed**.
The tested hosts were Pharo 13.1.0SNAPSHOT in the connected GT image and GemStone
3.7.5 arm64 in `bvc_foundation_portable`. GT export and native snapshot comparisons
matched every class/method. Canonical ticks 0/1 matched natively; a fresh native
session matched continuation to tick 6, then proved real abort restoration and
removed its disposable root. The independent Python oracle matched four canonical
checkpoints, three Random123 vectors and the full-width random-address vector.
Direct Rowan installation, Repast, Runtime service routing and scale remain open.

The GT image is authoritative for shared source. Author/compile/test through GT
MCP, then export with TonelWriter and compare every class/method definition with
the live package snapshot. Do not patch the exported `.st` files. Load that
verified independent checkout into GemStone for native qualification.

## GT

Load `BaselineOfCatalystSimulator` group `Core` for a headless kernel, or `Tests`
for its optional SUnit contracts. Default loads Core only. No Runtime, Connect,
GT UI, ecosystem, Unreal or MPI dependency is required by Core. Rowan Core/Tests
metadata is supplied separately; direct Rowan loading needs its own qualification.

Run `CSKernelExamples suite run` and require no failures/errors. A small inspectable
world is `CSKernelExamples new probe`; send `advance`, `advanceThrough: 6`,
`snapshot`, `checkpoint` or `spatialGridWithWidth: 1000` to it. Restore with
`CSSmalltalkBackend fromCheckpoint: savedBytes`. `advanceThrough:` accepts at most
1000 future ticks per call, accepting each step separately.

`gt.json` records executed tests and export snapshot definition counts (including
the organization definition). Fixture canonical bytes are emitted by that tested
GT probe at ticks 0, 1, 2 and 6. `check_probe.py` independently checks the same
bytes with Python integer arithmetic, event ordering and Philox. Run:

```sh
python3 conformance/check_probe.py
```

This oracle covers the fixed probe and three upstream random vectors. It is not
an external backend, nor evidence of MPI rank-count independence.

## Native GemStone

Use the workspace `gemstone-topaz` skill from the existing deployment's project
directory. Choose a unique qualification root and absolute output paths. Keep
login credentials in the existing bvc login configuration, never in these scripts.
The load script mutates only the new Simulator packages and its named fixture
root; do not run it concurrently with another Simulator source load.

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

The runner executes the contracts, matches canonical tick 0/1 fixtures and commits
the tick 1 backend under the qualification root. It also checks default load-group
selection and parses/checks Rowan metadata; this does not qualify direct Rowan
installation. If the run fails, inspect its logs and named root before retrying.
It never stops/reconfigures an existing Runtime or stone.

In a **new Topaz session**, retain SOURCE/ROOT and set
`BVC_SIMULATOR_RESUME_REPORT`, then run `scripts/resume-gemstone.topaz`. It checks
that committed tick 1 survived logout/login, advances to the GT tick 6 bytes,
aborts and verifies restoration to committed tick 1, then removes and commits
removal of its own root. Both process exit status and reports must pass. This
tests real repository persistence/abort separately from GT candidate publication.

`gemstone.json` and `gemstone-resume.json` record those separate native runs.
Definition counts there exclude organization definitions. The root name records
fixture ownership; it must be absent after successful cleanup. The scripts do not
claim multi-owner fencing, Runtime transactional delivery, stone-process restart,
production crash recovery, external migration or performance qualification.

Native testing found two dialect assumptions before acceptance: large negative
decimal parsing and the ninth ordinal accessor. The shared GT-authored source now
parses decimal digits explicitly and accesses that record field by index. No
GemStone-specific fork of the kernel was introduced.
