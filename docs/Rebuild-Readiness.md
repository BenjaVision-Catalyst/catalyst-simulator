# Simulation rebuild readiness

The graph increment is qualified in the existing GT image and GemStone stone.
Fresh GT/stone rebuild qualification is the next gate. Repast work has not started.

Shared Core, Tests and baseline source was compiled/exported through GT and every
exported class/method compared to its live package snapshot. Native qualification
loaded those same definitions in an independent checkout and compared every
installed definition. `conformance/source-sha256.json` pins the exported files.

For the rebuild:

1. Use the pushed workspace commit and its `Simulation/catalyst-simulator` gitlink.
   Clone/check out into fresh independent directories. Keep any running image and
   its registered checkouts intact until pending image edits have been recovered
   and verified through GT MCP. bvc's bundled project set now includes Simulator;
   its GT loader selects Tests, the Rowan installer selects Core, and the Seaside
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
4. For the fresh native stone, install the standard Tonel reader, Metacello/STON,
   SUnit and GsDeployer prerequisites first. Use the supplied
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

Do not treat direct Rowan installation as qualified by parsing its metadata.
Both Core/Tests Rowan specifications remain available, with native direct Rowan
loading awaiting a selected Rowan deployment. Record fresh build evidence
separately from the current-image qualification, retaining the pinned source
commit and manifest. After the fresh builds pass, the portable graph can become
the input to the early Repast feasibility adapter.
