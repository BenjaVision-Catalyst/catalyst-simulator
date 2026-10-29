# Simulation rebuild readiness

The graph increment is qualified in rebuilt GT and a fresh GemStone 3.7.5 devkit
stone. Both pass 32 tests. Core installation was verified before loading the
Simulator tests; model traces, digests, compatibility reports and real native
persistence/abort checks match. Repast work has not started.

For current development, build GemStone with `bvc start <name> --with-seaside`.
The current devkit stone has no Rowan. Rowan migration is deferred until
GemStone 4, planned for 2027; do not select the Rowan installer for current rebuilds.
The workspace preserves the [fresh-load evidence](https://github.com/BenjaVisionPro/catalyst-workspace/blob/main/Simulation/evidence/rebuild-2026-10-30.md).

Shared Core, Tests and baseline source was compiled/exported through GT and every
exported class/method compared to its live package snapshot. Native qualification
loaded those same definitions in an independent checkout and compared every
installed definition. `conformance/source-sha256.json` pins the exported files.

For the rebuild:

1. Use the pushed workspace commit and its `Simulation/catalyst-simulator` gitlink.
   Clone/check out into fresh independent directories. Keep any running image and
   its registered checkouts intact until pending image edits have been recovered
   and verified through GT MCP. bvc's bundled project set now includes Simulator;
   its GT loader selects Tests and the Seaside
   installer loads Core after Foundation. Use the updated bvc checkout and merge
   these entries into any project-local configuration overrides before rebuilding.
2. Load Metacello baseline `CatalystSimulator`, group `Core` (default) or `Tests`,
   from the pinned Simulator commit's `src`. In a clean GT build, use the repository
   URL `github://BenjaVision-Catalyst/catalyst-simulator:<component-commit>/src`.
   Core has no Runtime, Connect, GT UI, ecosystem or Unreal dependency. Tests need
   SUnit, and baseline loading needs the build's Metacello infrastructure.
3. Run both `CSKernelExamples suite run` and `CSGraphExamples suite run`: expect
   18 and 14 tests, respectively, with no failures or errors. Execute the fixture
   generators and compare the committed model bytes/digests and tick traces.
4. Build the fresh native devkit with `--with-seaside`; bvc provisions Tonel,
   Metacello/STON, SUnit and GsDeployer and installs Foundation and Simulator Core.
   Run `scripts/verify-installed-core.topaz` first, setting `BVC_SIMULATOR_SOURCE`
   and `BVC_REBUILD_REPORT`, to verify Core before any test-source load. Then use
   `scripts/qualify-gemstone.topaz` through `bvc topaz <deployment>` with an isolated
   root and fresh evidence output paths; follow `conformance/README.md`. This
   avoids the installed older Gofer version-metadata assumption. The runner loads
   Core and optional tests from the same source exports and checks load groups.
5. Run `scripts/resume-gemstone.topaz` in a new native session. Require matching
   legacy and three graph continuations, real abort restoration and successful
   cleanup of the runner's own root. Preserve logs and inspect any failed fixture
   rather than resetting the shared image/server or replaying uncertain work.
6. Run `python3 conformance/check_probe.py` and
   `python3 conformance/check_graph.py`. Require 4 legacy and 12 graph checkpoints,
   three model digests, the registry digest and six compatibility cases to pass.

Core/Tests Rowan specifications remain available for the later GemStone 4
migration; metadata parsing does not qualify that future installation route.
Retain source revisions, manifests and separate fresh-build evidence for each
subsequent kernel change. The current portable graph is now qualified as an input
to the early Repast feasibility adapter.
