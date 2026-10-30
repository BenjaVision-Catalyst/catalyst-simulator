#!/usr/bin/env python3
"""One controller owns one managed Runtime at a time, all MPI children and cleanup.

Run while CCNativeMcpLease is held. The controller always releases the lease;
the caller must wait for the outside-GT gate before joining the GT owner.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
import uuid

HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser()
    for name in ("project", "bvc", "output", "executable", "lease-release"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--ranks", type=int, nargs="+", choices=(1, 2, 4), default=[1, 2, 4])
    parser.add_argument("--scheduled", action="store_true")
    parser.add_argument("--cleanup-runtime")
    parser.add_argument("--cleanup-directory", type=Path)
    args = parser.parse_args()
    lease_directory = args.lease_release.parent
    assert json.loads((lease_directory / "active.json").read_text())["active"] is True, "Acquire this controller's lease first"
    assert not (lease_directory / "gt-mcp-gate.json").exists() and not args.lease_release.exists(), "Lease already released"
    args.output.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, GEMSTONE_STONE_NAME="bvc_simulator_native",
               CS_P3_SOURCE=str(HERE.parent / "src"))
    report = dict(passed=False, cases=[], stone="bvc_simulator_native", docker=False)
    fixture = next(case for case in json.loads((HERE.parent /
        "conformance/results/repast-p2-macos-2026-10-30/fixtures.json").read_text())["cases"]
        if case["name"] == "conditional-graph")
    sequence = 0
    active = None

    def save():
        (args.output / "qualification.json").write_text(json.dumps(report, indent=2) + "\n")

    def run(command, label, extra=None):
        nonlocal sequence
        sequence += 1
        result = subprocess.run(list(map(str, command)), cwd=args.project, env=dict(env, **(extra or {})),
                                capture_output=True, text=True, timeout=100)
        (args.output / f"{sequence:03}-{label}.log").write_text(result.stdout + result.stderr)
        assert result.returncode == 0, (label, result.returncode)
        return result.stdout

    def lifecycle(action, *extra):
        return json.loads(run([args.bvc, "runtime", action, active, *extra], action))

    def ready():
        deadline = time.monotonic() + 45
        while lifecycle("status")["state"] != "running":
            assert time.monotonic() < deadline
            time.sleep(.1)

    def wait(predicate):
        deadline = time.monotonic() + 45
        while not predicate():
            assert time.monotonic() < deadline, "Native batch barrier timeout"
            time.sleep(.05)

    def phase(name):
        run([args.bvc, "topaz", "bvc_simulator_native", "--script", HERE / "qualify-live-repast.topaz"],
            f"r{ranks}-{name}", dict(CS_LIVE_PHASE=name))
        value = json.loads((directory / (name + ".json")).read_text())
        assert value["passed"]
        case["phases"][name] = value
        save()
        print(f"ranks={ranks} {name}: passed", flush=True)

    try:
        if args.cleanup_runtime:
            assert args.cleanup_directory is not None
            active = args.cleanup_runtime
            env.update(CS_P3_RUNTIME=active, CS_P3_DIRECTORY=str(args.cleanup_directory))
            assert lifecycle("stop")["state"] == "stopped"
            run([args.bvc, "topaz", "bvc_simulator_native", "--script", HERE / "qualify-live-repast.topaz"],
                "interrupted-cleanup", dict(CS_LIVE_PHASE="cleanup"))
            assert lifecycle("remove")["state"] == "removed"
            report["interruptedRuntimeRemoved"] = active
            active = None
        run([args.bvc, "topaz", "bvc_simulator_native", "--script", HERE / "prepare-live-repast.topaz"],
            "install", dict(CS_P3_PREPARE_REPORT=str(args.output / "native-tests.json")))
        run([args.bvc, "topaz", "bvc_simulator_native", "--script", HERE / "verify-live-repast-source.topaz"],
            "verify-source", dict(CS_LIVE_SOURCE_REPORT=str(args.output / "source-native.json")))
        for ranks in args.ranks:
            active = "simulation_live_" + uuid.uuid4().hex[:12]
            directory = args.output / f"r{ranks}"
            directory.mkdir()
            case = dict(ranks=ranks, runtime=active, phases={})
            report["cases"].append(case)
            (directory / "oracle-0.canon").write_text(fixture["initial"])
            for tick in range(1, 13):
                (directory / f"oracle-{tick}.canon").write_text(fixture["checkpoints"][str(tick)])
            # Drop only replies to target tick 8. The real runner and durable result
            # still execute, and subsequent reads must show the old accepted state.
            wrapper = directory / "drop-reply.py"
            wrapper.write_text('#!/usr/bin/env python3\n' +
                'import importlib.util,json,pathlib,sys\n' +
                f'spec=importlib.util.spec_from_file_location("batch",{str(HERE / "repast-batch.py")!r})\n' +
                'batch=importlib.util.module_from_spec(spec);spec.loader.exec_module(batch)\n' +
                'p=batch.argparse.ArgumentParser();p.add_argument("--spool",type=pathlib.Path);p.add_argument("--request");a=p.parse_args()\n' +
                'request=json.loads(a.request);result=batch.handle(a.spool,request)\n' +
                'if request["spec"]["binding"]["targetTick"]==8 and (a.spool.parent/"hold-reply").exists() and result["state"]=="complete":\n' +
                ' (a.spool.parent/"reply-dropped").touch();result={"state":"uncertain"}\n' +
                'print(json.dumps(result,separators=(",",":")))\n')
            wrapper.chmod(0o700)
            run([HERE / "repast-batch.py", "--spool", directory / "spool", "--initialize"], "spool")
            env.update(CS_P3_RUNTIME=active, CS_P3_DIRECTORY=str(directory), CS_LIVE_RANKS=str(ranks),
                       CS_LIVE_LAUNCHER=str(wrapper), CS_LIVE_EXECUTABLE=str(args.executable))
            phase("configure")
            assert lifecycle("configure", directory / "runtime.ston")["state"] == "stopped"
            lifecycle("start"); ready()
            for name in ("create", "advance1", "external1", "run4", "local1", "advance6", "external2"):
                if name == "run4" and args.scheduled:
                    phase("drive4")
                    case["phases"]["run4"] = case["phases"]["drive4"]
                else:
                    phase(name)
            (directory / "hold-reply").touch()
            phase("run8")
            wait(lambda: (directory / "reply-dropped").exists())
            phase("read-held")
            held = case["phases"]["read-held"]["view"]
            assert held["pending"]["targetTick"] == 8
            assert lifecycle("stop")["state"] == "stopped"
            lifecycle("start"); ready()
            phase("recover")
            phase("stale-result")
            (directory / "hold-reply").unlink()
            for name in ("accepted8", "local2", "advance12"):
                if name == "advance12" and args.scheduled:
                    phase("drive12")
                    case["phases"]["advance12"] = case["phases"]["drive12"]
                else:
                    phase(name)
            jobs = []
            for path in sorted((directory / "spool").glob("*/claim.json")):
                claim = json.loads(path.read_text())
                result = json.loads((path.parent / "result.json").read_text())
                assert result["state"] == "complete"
                assert (path.parent / "started.json").exists()
                jobs.append(dict(batch=path.parent.name, binding=claim["spec"]["binding"],
                                 checkpointDigest=result["checkpointDigest"], ranks=result["ranks"]))
            assert len(jobs) == 4, jobs  # two paused restores, two actual advances
            case["jobs"] = jobs
            assert lifecycle("stop")["state"] == "stopped"
            phase("cleanup")
            assert lifecycle("remove")["state"] == "removed"
            active = None
            save()
        # Identical portable final frontier despite different rank counts and recovery.
        assert len({case["phases"]["advance12"]["view"]["checkpointDigest"] for case in report["cases"]}) == 1
        report["passed"] = True
    except BaseException as error:
        report["error"] = repr(error)
        raise
    finally:
        if active:
            try:
                lifecycle("stop")
            except BaseException as error:
                report["cleanupError"] = repr(error)
        # Every native job is bounded by its supervisor. Do not release GT isolation
        # while any owned supervisor is still running or its completion is uncertain.
        for claim in args.output.glob("r*/spool/*/claim.json"):
            deadline = time.monotonic() + 135
            while not (claim.parent / "finished.json").exists() and time.monotonic() < deadline:
                time.sleep(.1)
            if not (claim.parent / "finished.json").exists():
                report["cleanupError"] = "Uncertain native child: " + str(claim.parent)
                report["passed"] = False
        save()
        args.lease_release.touch()


if __name__ == "__main__":
    main()
