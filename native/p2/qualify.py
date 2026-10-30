#!/usr/bin/env python3
"""One bounded controller. Start through GT MCP under CCNativeMcpLease.

The controller never talks to MCP. Its caller must wait for gt-mcp-gate.json
outside GT before joining the GT owner. All MPI children and the temporary
GemStone root are cleaned before releasing the lease, including on failure.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import uuid

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / "conformance"))
from check_probe import decode, encode
from check_graph import step, digest


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser()
    for arg in ("manifest", "binary", "output", "project", "bvc", "lease-directory"):
        parser.add_argument("--" + arg, type=Path, required=True)
    parser.add_argument("--deployment", default="bvc_simulator_native", choices=["bvc_simulator_native"])
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    lease = args.lease_directory.resolve()
    assert json.loads((lease / "lease-active.json").read_text())["active"]
    assert not (lease / "gt-mcp-gate.json").exists()
    env = dict(os.environ, BVC_P2_MANIFEST=str(args.manifest.resolve()),
               BVC_P2_OUTPUT=str(out), BVC_P2_ROOT="CSRepastP2_" + uuid.uuid4().hex)
    report = dict(passed=False, stone=args.deployment, runs=[], restarts=[], negatives=[])
    children = []
    root_may_exist = False
    serial = 0

    def stop(process):
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(5)

    def run(command, name, expected=0, cwd=None, extra_env=None, timeout=90):
        nonlocal serial
        serial += 1
        with (out / f"{serial:03}-{name}.log").open("w") as log:
            process = subprocess.Popen(list(map(str, command)), cwd=cwd,
                                       env=dict(env, **(extra_env or {})), stdout=log,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            children.append(process)
            try:
                code = process.wait(timeout)
            finally:
                stop(process)
        assert (code == 0) if expected == 0 else (code != 0), (name, code)
        return code

    def topaz(name, extra_env=None):
        return run([args.bvc, "topaz", args.deployment, "--script", HERE / "gemstone" / (name + ".topaz")],
                   "gemstone-" + name, cwd=args.project, extra_env=extra_env)

    def mpi(ranks, model, checkpoint, directory, steps, layout=0, options=()):
        return ["/opt/homebrew/bin/mpirun", "--oversubscribe", "-n", ranks, args.binary,
                "--registry", args.manifest.parent / "registry.canon", "--model", model,
                "--input", checkpoint, "--output", directory, "--steps", steps, "--layout", layout, *options]

    try:
        data = json.loads(args.manifest.read_text())
        report["gtTests"] = data["gtTests"]
        cases = {r["name"]: r for r in data["cases"]}
        # Independently calculate every GT boundary before starting native runs.
        for record in cases.values():
            state = decode(record["initial"])
            for tick in range(1, 13):
                state = step(state)
                assert encode(state) == record["checkpoints"][str(tick)], (record["name"], tick, "Python vs GT")
        report["oracleBoundaries"] = len(cases) * 13
        run([args.binary.parent / "catalyst_value_tests"], "native-value-tests")
        root_may_exist = True
        topaz("prepare")
        report["gemstonePrepare"] = json.loads((out / "prepare.json").read_text())
        returns = []
        for name, record in cases.items():
            assert (out / (name + ".model")).read_text() == record["model"]
            assert (out / (name + ".checkpoint")).read_text() == record["checkpoints"]["1"]
            for ranks in (1, 2, 4):
                for layout in (0, 1):
                    key = f"{name}-r{ranks}-l{layout}"
                    directory = out / key
                    run(mpi(ranks, out / (name + ".model"), out / (name + ".checkpoint"), directory, 11, layout), key)
                    boundaries = {}
                    for tick in range(1, 13):
                        raw = (directory / f"tick-{tick}.canon").read_text()
                        assert raw == record["checkpoints"][str(tick)], (key, tick)
                        boundaries[str(tick)] = hashlib.sha256(raw.encode("ascii")).hexdigest()
                    assert (directory / "accepted.canon").read_text() == record["checkpoints"]["12"]
                    stats = decode((directory / "execution.canon").read_text())
                    if name == "cross-rank" and ranks > 1:
                        assert stats["migrations"] > 0 and stats["remoteRequests"] > 0
                        assert stats["localCounts"] == [16 // ranks] * ranks
                    report["runs"].append(dict(key=key, boundaries=boundaries, **stats))
                    returns.append(dict(key=key, name=name, checkpoint=str(directory / "tick-4.canon")))
            # Resume accepted MPI snapshots with a different partition count and layout.
            for before, after in ((1, 2), (2, 4), (4, 1)):
                key = f"{name}-restart-{before}-{after}"
                directory = out / key
                checkpoint = out / f"{name}-r{before}-l0" / "tick-6.canon"
                run(mpi(after, out / (name + ".model"), checkpoint, directory, 6, 1), key)
                for tick in range(6, 13):
                    assert (directory / f"tick-{tick}.canon").read_text() == record["checkpoints"][str(tick)]
                report["restarts"].append(dict(key=key, matchedTicks=list(range(6, 13))))
        # The globally first requester initially resides away from rank zero.
        first = decode(cases["cross-rank"]["checkpoints"]["2"])["outcomes"]
        assert first == [[2, "charge", "0" * 32, 2]]
        for record in data["compatibility"]:
            path = out / ("incompatible-" + record["name"] + ".model")
            path.write_text(record["model"])
            extra = ["--disable-operation", "core.random.draw"] if record["name"] == "missing-operation" else []
            run(mpi(2, path, out / "graph-probe.checkpoint", out / "never-published", 0,
                    options=["--validate-only", "true", *extra]), "negative-" + record["name"], expected=2)
            log = sorted(out.glob("*-negative-" + record["name"] + ".log"))[-1].read_text()
            issue = record["report"]["issues"][0]
            assert issue["code"] in log and issue["path"] in log
            report["negatives"].append(record["name"])
        # Invalid digest rejected before initial publication.
        bad = decode(cases["graph-probe"]["checkpoints"]["1"])
        bad["modelDigest"] = "0" * 64
        (out / "bad-digest.checkpoint").write_text(encode(bad))
        run(mpi(4, out / "graph-probe.model", out / "bad-digest.checkpoint", out / "bad-digest", 1), "bad-digest", expected=2)
        assert not (out / "bad-digest" / "accepted.canon").exists()
        # A collective arithmetic failure preserves the previous boundary on disk.
        bad = decode(cases["conditional-graph"]["initial"])
        for node in bad["model"][5]["nodes"]:
            if node["id"] == "one":
                node["parameters"]["value"] = (1 << 63) - 1
        bundle = encode(bad["model"])
        bad["modelDigest"] = digest("CatalystSimulation-Model-1:", bundle)
        (out / "overflow.model").write_text(bundle)
        (out / "overflow.checkpoint").write_text(encode(bad))
        run(mpi(4, out / "overflow.model", out / "overflow.checkpoint", out / "overflow", 1), "overflow", expected=2)
        assert (out / "overflow" / "accepted.canon").read_text() == encode(bad)
        assert not (out / "overflow" / "tick-1.canon").exists()
        # Kill a fully prepared speculative tick, before publication or migration.
        directory = out / "killed"
        with (out / "killed.log").open("w") as log:
            process = subprocess.Popen(list(map(str, mpi(4, out / "cross-rank.model", out / "cross-rank.checkpoint",
                directory, 3, options=["--hold-tick", 2]))), env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            children.append(process)
            deadline = time.monotonic() + 45
            while not (directory / "speculative-ready").exists():
                assert process.poll() is None and time.monotonic() < deadline, "Speculative marker timeout"
                time.sleep(.05)
            stop(process)
        assert (directory / "accepted.canon").read_text() == cases["cross-rank"]["checkpoints"]["1"]
        assert not (directory / "tick-2.canon").exists()
        topaz("verify", dict(BVC_P2_EXPECT_RETURNS="0"))
        report["speculativeKill"] = dict(unpublished=True, gemstoneSourceUnchanged=True, ranks=4)
        write(out / "returns.json", returns)
        topaz("return")
        topaz("verify", dict(BVC_P2_EXPECT_RETURNS=str(len(returns))))
        report["gemstoneReturn"] = json.loads((out / "return.json").read_text())
        report["gemstoneFreshSession"] = json.loads((out / f"verify-{len(returns)}.json").read_text())
        report["passed"] = True
    except BaseException as error:
        report["error"] = repr(error)
        raise
    finally:
        for process in reversed(children):
            stop(process)
        try:
            if root_may_exist:
                topaz("cleanup")
                report["gemstoneRootRemoved"] = True
        finally:
            write(out / "qualification.json", report)
            (lease / "release-lease").touch()
    print(json.dumps(dict(passed=True, runs=len(report["runs"]), restarts=len(report["restarts"]),
                          gemstoneRoundTrips=report["gemstoneReturn"]["returned"])))


if __name__ == "__main__":
    main()
