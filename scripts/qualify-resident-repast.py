#!/usr/bin/env python3
"""One controller owns the dedicated Runtime and all native sessions to cleanup.

Requires a freshly acquired CCNativeMcpLease. No native work starts on a busy or
released gate. The caller waits outside GT for the released gate before joining.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import time
import uuid

HERE = Path(__file__).resolve().parent
module = importlib.util.spec_from_file_location("resident", HERE / "repast-resident.py")
resident = importlib.util.module_from_spec(module)
module.loader.exec_module(resident)


def main():
    parser = argparse.ArgumentParser()
    for name in ("project", "bvc", "output", "executable", "lease-release"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--ranks", type=int, nargs="+", choices=(1, 2, 4), default=[1, 2, 4])
    parser.add_argument("--typed-source-fixtures", type=Path)
    args = parser.parse_args()
    gate = args.lease_release.parent
    assert json.loads((gate / "active.json").read_text())["active"] is True
    assert not (gate / "gt-mcp-gate.json").exists() and not args.lease_release.exists()
    args.output.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, GEMSTONE_STONE_NAME="bvc_simulator_native", CS_REPAST_MODE="resident", CS_DROP_TARGET="6",
               CS_P3_SOURCE=str(HERE.parent / "src"))
    report = dict(passed=False, cases=[], stone="bvc_simulator_native", docker=False)
    fixtures = json.loads((HERE.parent / "conformance/results/repast-p2-macos-2026-10-30/fixtures.json").read_text())["cases"]
    fixture = next(case for case in fixtures if case["name"] == "conditional-graph")
    registry = json.loads((HERE.parent / "contracts/graph-1/fixtures.json").read_text())["registry"]
    sequence, active, spools = 0, None, []

    def save():
        (args.output / "qualification.json").write_text(json.dumps(report, indent=2) + "\n")

    def run(command, label, extra=None):
        nonlocal sequence
        sequence += 1
        result = subprocess.run(list(map(str, command)), cwd=args.project, env=dict(env, **(extra or {})),
                                capture_output=True, text=True, timeout=360)
        (args.output / f"{sequence:03}-{label}.log").write_text(result.stdout + result.stderr)
        assert result.returncode == 0, (label, result.returncode)
        return result.stdout

    def lifecycle(action, *extra):
        result = json.loads(run([args.bvc, "runtime", action, active, *extra], action))
        report.setdefault("lifecycle", []).append(dict(runtime=active, action=action, observation=result))
        return result

    def wait(predicate, timeout=45):
        deadline = time.monotonic() + timeout
        while not predicate():
            assert time.monotonic() < deadline, "Resident qualification deadline"
            time.sleep(.05)

    def phase(name):
        run([args.bvc, "topaz", "bvc_simulator_native", "--script", HERE / "qualify-live-repast.topaz"],
            f"r{ranks}-{name}", dict(CS_LIVE_PHASE=name))
        value = json.loads((directory / (name + ".json")).read_text())
        assert value["passed"]
        case["phases"][name] = value
        save()
        print(f"ranks={ranks} {name}: passed", flush=True)

    def sessions(spool):
        return [(path.parent, json.loads(path.read_text())) for path in (spool / "sessions").glob("*/claim.json")]

    def ready_session(spool, generation):
        matches = [path for path, claim in sessions(spool) if claim["session"]["generation"] == generation]
        if len(matches) != 1:
            return None
        path = matches[0]
        if (path / "finished.json").exists():
            raise AssertionError(("Resident ended before ready", path, (path / "finished.json").read_text()))
        return path if (path / "state.json").exists() else None

    def native_state(path):
        return json.loads((path / "state.json").read_text())["native"]

    def receipts(spool):
        return [dict(json.loads(path.read_text()), path=str(path.parent.relative_to(args.output)))
                for path in (spool / "jobs").glob("*/result.json")]

    def shutdown(spool):
        resident.shutdown(spool)
        wait(lambda: all((path / "finished.json").exists() for path, claim in sessions(spool)), 150)
        assert all(json.loads((path / "finished.json").read_text())["nativeReaped"] for path, claim in sessions(spool))

    def protocol_probe(ranks):
        """16-entity P2 contention fixture, actual resident continuation, not a GS authority test."""
        sample = next(case for case in fixtures if case["name"] == "cross-rank")
        spool = args.output / f"protocol-r{ranks}"
        run([HERE / "repast-resident.py", "--spool", spool, "--initialize"], "protocol-spool")
        spools.append(spool)
        checkpoint = resident.decode(sample["initial"])
        results = []
        pids = None
        for revision, target in enumerate((1, 2, 4, 8, 12), 1):
            raw = resident.encode(checkpoint)
            checkpoint_digest = resident.digest(raw)
            batch_id = resident.digest(resident.encode(["protocol", ranks, revision, checkpoint_digest, target]))
            binding = dict(version=1, world="a" * 32, group="b" * 32, generation=1, owner="c" * 32,
                           modelDigest=checkpoint["modelDigest"], checkpointDigest=checkpoint_digest,
                           fromTick=checkpoint["tick"], targetTick=target, batch=batch_id, inputDigest=batch_id)
            request = dict(action="ensure", spec=dict(binding=binding, checkpoint=checkpoint, registry=registry),
                           executable=str(args.executable), mpi="/opt/homebrew/bin/mpirun", ranks=ranks, acceptedRevision=revision)
            observed = {}

            def complete():
                nonlocal observed
                observed = resident.handle(spool, request)
                return observed["state"] == "complete"

            wait(complete)
            checkpoint = observed["checkpoint"]
            assert resident.encode(checkpoint) == sample["checkpoints"][str(target)]
            native = observed["native"]
            if pids is None:
                pids = native["pids"]
            assert native["pids"] == pids and native["restores"] == native["graphCompilations"] == 1
            assert native["snapshots"] == revision + 1
            results.append(dict(target=target, checkpointDigest=observed["checkpointDigest"], native=native))
        shutdown(spool)
        assert len(sessions(spool)) == 1
        return dict(ranks=ranks, entities=16, samples=results)

    try:
        run([args.bvc, "topaz", "bvc_simulator_native", "--script", HERE / "prepare-live-repast.topaz"],
            "install", dict(CS_P3_PREPARE_REPORT=str(args.output / "native-tests.json")))
        run([args.bvc, "topaz", "bvc_simulator_native", "--script", HERE / "verify-live-repast-source.topaz"],
            "verify-source", dict(CS_LIVE_SOURCE_REPORT=str(args.output / "source-native.json")))
        run([args.executable.parent / "catalyst_value_tests"], "native-values")
        if args.typed_source_fixtures:
            root = "CSTypedSource" + uuid.uuid4().hex
            report["typedSourceRoundTrip"] = {}
            for stage in ("build", "verify"):
                output = args.output / ("typed-source-" + stage + ".json")
                run([args.bvc, "topaz", "bvc_simulator_native", "--script", HERE / "qualify-typed-source.topaz"],
                    "typed-source-" + stage, dict(CS_TYPED_FIXTURE=str(args.typed_source_fixtures),
                        CS_TYPED_SOURCE_ROOT=root, CS_TYPED_SOURCE_PHASE=stage, CS_TYPED_SOURCE_REPORT=str(output)))
                report["typedSourceRoundTrip"][stage] = json.loads(output.read_text())
                assert report["typedSourceRoundTrip"][stage]["passed"]
        for ranks in args.ranks:
            active = "simulation_resident_" + uuid.uuid4().hex[:12]
            directory = args.output / f"r{ranks}"
            directory.mkdir()
            spool = directory / "spool"
            spools.append(spool)
            case = dict(ranks=ranks, runtime=active, phases={})
            report["cases"].append(case)
            (directory / "oracle-0.canon").write_text(fixture["initial"])
            for tick in range(1, 13):
                (directory / f"oracle-{tick}.canon").write_text(fixture["checkpoints"][str(tick)])
            wrapper = directory / "drop-reply.py"
            wrapper.write_text('#!/usr/bin/env python3\n' +
                'import importlib.util,json,pathlib\n' +
                f'spec=importlib.util.spec_from_file_location("resident",{str(HERE / "repast-resident.py")!r})\n' +
                'r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)\n' +
                'p=r.argparse.ArgumentParser();p.add_argument("--spool",type=pathlib.Path);p.add_argument("--request");a=p.parse_args()\n' +
                'request=json.loads(a.request);reply=r.handle(a.spool,request)\n' +
                'if request["action"] in ("ensure","query") and request["spec"]["binding"]["targetTick"]==6 and (a.spool.parent/"hold-reply").exists() and reply["state"]=="complete":\n' +
                ' (a.spool.parent/"reply-dropped").touch();reply={"state":"uncertain"}\n' +
                'print(json.dumps(reply,separators=(",",":")))\n')
            wrapper.chmod(0o700)
            run([HERE / "repast-resident.py", "--spool", spool, "--initialize"], "spool")
            env.update(CS_P3_RUNTIME=active, CS_P3_DIRECTORY=str(directory), CS_LIVE_RANKS=str(ranks),
                       CS_LIVE_LAUNCHER=str(wrapper), CS_LIVE_EXECUTABLE=str(args.executable))
            phase("configure")
            assert lifecycle("configure", directory / "runtime.ston")["state"] == "stopped"
            lifecycle("start")
            wait(lambda: lifecycle("status")["state"] == "running")
            for name in ("create", "advance1", "external1", "run3", "run4"):
                phase(name)
            first = ready_session(spool, 2)
            assert first is not None
            original = native_state(first)
            (directory / "hold-reply").touch()
            phase("run6")
            wait(lambda: (directory / "reply-dropped").exists())
            phase("read-held")
            assert lifecycle("stop")["state"] == "stopped"
            lifecycle("start")
            wait(lambda: lifecycle("status")["state"] == "running")
            phase("read-restarted")
            assert native_state(first)["pids"] == original["pids"]
            case["sameProcessAcrossRuntimeRestart"] = True
            phase("recover")
            phase("stale-result")
            (directory / "hold-reply").unlink()
            phase("accepted6")
            wait(lambda: ready_session(spool, 3) is not None)
            second = ready_session(spool, 3)
            phase("run8")
            wait(lambda: not native_state(second)["awaitingAcceptance"])
            victim = native_state(second)["pids"][0]
            command = subprocess.check_output(["ps", "-p", str(victim), "-o", "command="], text=True)
            assert str(second / "native") in command and args.executable.name in command
            os.kill(victim, signal.SIGKILL)
            wait(lambda: (second / "finished.json").exists())
            assert json.loads((second / "finished.json").read_text())["state"] == "failed"
            phase("read-crashed")
            assert len(sessions(spool)) == 2  # No implicit relaunch of the failed placement.
            case["killedRank"] = victim
            phase("recover-idle")
            wait(lambda: ready_session(spool, 4) is not None)
            current_session = ready_session(spool, 4)
            original_work = next(json.loads(path.read_text()) for path in (spool / "jobs").glob("*/claim.json")
                                 if json.loads(path.read_text())["spec"]["binding"]["targetTick"] == 6)
            stale = dict(action="query", spec=original_work["spec"], acceptedRevision=1,
                         executable=str(args.executable), mpi="/opt/homebrew/bin/mpirun", ranks=ranks)
            assert resident.handle(spool, stale)["state"] == "complete"
            stale["action"] = "retire"
            assert resident.handle(spool, stale)["state"] == "fenced"
            stale["action"] = "ensure"
            assert resident.handle(spool, stale)["state"] == "fenced"
            assert not (current_session / "stop").exists()
            case["transportFencing"] = dict(oldReceiptQueryable=True, staleRetirementRejected=True, staleLaunchRejected=True)
            phase("drive10")
            phase("local2")
            phase("advance12")
            shutdown(spool)
            case["receipts"] = receipts(spool)
            assert len(case["receipts"]) == 6
            assert len(sessions(spool)) == 3
            primary = [r for r in case["receipts"] if r["binding"]["generation"] == 2]
            assert len(primary) == 4 and all(r["native"]["pids"] == original["pids"] for r in primary)
            assert all(r["native"]["restores"] == r["native"]["graphCompilations"] == 1 for r in case["receipts"])
            case["protocol"] = protocol_probe(ranks)
            # Regression: the original batch entry point still produces exact bytes.
            batch_directory = directory / "batch-regression"
            (directory / "registry.canon").write_text(resident.encode(registry))
            (directory / "model.canon").write_text(resident.encode(resident.decode(fixture["initial"])["model"]))
            run(["/opt/homebrew/bin/mpirun", "--oversubscribe", "--bind-to", "none", "-n", ranks, args.executable,
                 "--registry", directory / "registry.canon", "--model", directory / "model.canon", "--input", directory / "oracle-0.canon",
                 "--output", batch_directory, "--steps", 4], "batch-regression")
            assert (batch_directory / "accepted.canon").read_text() == fixture["checkpoints"]["4"]
            assert lifecycle("stop")["state"] == "stopped"
            phase("cleanup")
            assert lifecycle("remove")["state"] == "removed"
            active = None
            save()
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
                report["runtimeCleanupError"] = repr(error)
        cleanup_confirmed = True
        for spool in spools:
            if (spool / "identity").exists():
                try:
                    shutdown(spool)
                except BaseException as error:
                    cleanup_confirmed = False
                    report["nativeCleanupError"] = repr(error)
        report["nativeCleanupConfirmed"] = cleanup_confirmed
        save()
        if cleanup_confirmed:
            args.lease_release.touch()
        else:
            raise RuntimeError("Owned native resources remain uncertain; isolation retained")


if __name__ == "__main__":
    main()
