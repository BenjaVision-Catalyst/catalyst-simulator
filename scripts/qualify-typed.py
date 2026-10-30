#!/usr/bin/env python3
"""Typed 100,000-entity native and Runtime switching / recovery qualification on native macOS."""
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
module = importlib.util.spec_from_file_location("sharded", HERE / "repast-sharded.py")
sharded = importlib.util.module_from_spec(module)
module.loader.exec_module(sharded)


def main():
    parser = argparse.ArgumentParser()
    for name in ("project", "bvc", "output", "executable", "fixtures", "lease-release"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--ranks", type=int, nargs="+", choices=(1, 2, 4), default=[4])
    parser.add_argument("--cases", nargs="+", choices=("typed100k",), default=["typed100k"])
    parser.add_argument("--cleanup-from", type=Path)
    parser.add_argument("--protocol-evidence-from", type=Path)
    args = parser.parse_args()
    gate = args.lease_release.parent
    assert json.loads((gate / "active.json").read_text())["active"] is True
    assert not (gate / "gt-mcp-gate.json").exists() and not args.lease_release.exists()
    args.output.mkdir(parents=True, exist_ok=False)
    fixtures = json.loads((args.fixtures / "fixtures.json").read_text())
    for fixture in fixtures:
        (args.fixtures / fixture["name"] / "record.json").write_text(json.dumps(fixture))
    env = dict(os.environ, GEMSTONE_STONE_NAME="bvc_simulator_native", CS_P3_SOURCE=str(HERE.parent / "src"))
    report = dict(passed=False, cases=[], protocol=[], docker=False, stone="bvc_simulator_native", lifecycle=[])
    active, sequence, spools = None, 0, []

    def save():
        (args.output / "qualification.json").write_text(json.dumps(report, indent=2) + "\n")

    def run(command, label, extra=None):
        nonlocal sequence
        sequence += 1
        result = subprocess.run(list(map(str, command)), cwd=args.project, env=dict(env, **(extra or {})),
                                capture_output=True, text=True, timeout=1800)
        (args.output / f"{sequence:03}-{label}.log").write_text(result.stdout + result.stderr)
        assert result.returncode == 0, (label, result.returncode)
        return result.stdout

    def lifecycle(action, *extra):
        result = json.loads(run([args.bvc, "runtime", action, active, *extra], action))
        report["lifecycle"].append(dict(runtime=active, action=action, result=result))
        save()
        return result

    def wait(predicate, timeout=300):
        deadline = time.monotonic() + timeout
        while not predicate():
            assert time.monotonic() < deadline, "Sharded native deadline"
            time.sleep(.05)

    def phase(name):
        started = time.monotonic()
        run([args.bvc, "topaz", "bvc_simulator_native", "--script", HERE / "qualify-typed.topaz"],
            f"{fixture['name']}-r{ranks}-{name}", dict(CS_SHARD_PHASE=name))
        result = json.loads((directory / (name + ".json")).read_text())
        assert result["passed"]
        case["phases"][name] = result
        case.setdefault("phaseElapsedSeconds", {})[name] = time.monotonic() - started
        if "view" in result:
            assert result["view"]["checkpointDigest"] == fixture["roots"][str(result["view"]["tick"])]
        save()
        print(f"{fixture['name']} ranks={ranks} {name}: passed", flush=True)

    def sessions(spool):
        return [(path.parent, json.loads(path.read_text())) for path in (spool / "sessions").glob("*/claim.json")]

    def ready_session(spool, generation):
        found = [path for path, claim in sessions(spool) if claim["session"]["generation"] == generation]
        if len(found) != 1:
            return None
        path = found[0]
        if (path / "finished.json").exists():
            raise AssertionError((path, (path / "finished.json").read_text()))
        return path if (path / "state.json").exists() else None

    def native_state(path):
        return json.loads((path / "state.json").read_text())["native"]

    def shutdown(spool):
        sharded.resident.shutdown(spool)
        wait(lambda: all((path / "finished.json").exists() for path, claim in sessions(spool)), 150)
        assert all(json.loads((path / "finished.json").read_text())["nativeReaped"] for path, claim in sessions(spool))

    try:
        if args.cleanup_from:
            prior = json.loads((args.cleanup_from / "qualification.json").read_text())
            assert prior["nativeCleanupConfirmed"] and not prior["passed"]
            report["predecessorCleanup"] = []
            for previous in prior["cases"]:
                active = previous["runtime"]
                assert active.startswith("simulation_sharded_")
                assert lifecycle("status")["state"] == "stopped"
                previous_directory = args.cleanup_from / (previous["name"] + f'-r{previous["ranks"]}')
                run([args.bvc, "topaz", "bvc_simulator_native", "--script", HERE / "qualify-typed.topaz"],
                    "predecessor-fixture-cleanup", dict(CS_SHARD_PHASE="cleanup", CS_P3_RUNTIME=active,
                        CS_P3_DIRECTORY=str(previous_directory), CS_SHARD_FIXTURE=str(args.fixtures / previous["name"])))
                assert lifecycle("remove")["state"] == "removed"
                report["predecessorCleanup"].append(active)
                active = None
            save()
        run([args.bvc, "topaz", "bvc_simulator_native", "--script", HERE / "prepare-live-repast.topaz"],
            "install", dict(CS_P3_PREPARE_REPORT=str(args.output / "native-tests.json")))
        run([args.bvc, "topaz", "bvc_simulator_native", "--script", HERE / "verify-live-repast-source.topaz"],
            "verify-source", dict(CS_LIVE_SOURCE_REPORT=str(args.output / "source-native.json")))
        run([args.executable.parent / "catalyst_value_tests"], "native-values")
        if args.protocol_evidence_from:
            prior = json.loads((args.protocol_evidence_from / "qualification.json").read_text())
            assert prior["nativeCleanupConfirmed"]
            assert sorted(case["ranks"] for case in prior["protocol"]) == [1, 2, 4]
            assert len(prior["typedGraphRegression"]) == 2
            executable_digest = sharded.hashlib.sha256(args.executable.read_bytes()).hexdigest()
            for directory in list(args.protocol_evidence_from.glob("protocol-r*")) + list(args.protocol_evidence_from.glob("typed-*")):
                if not directory.is_dir(): continue
                for claim in (directory / "sessions").glob("*/claim.json"):
                    assert json.loads(claim.read_text())["executableDigest"] == executable_digest
                    assert json.loads((claim.parent / "finished.json").read_text())["nativeReaped"]
            report["protocol"] = prior["protocol"]
            report["typedGraphRegression"] = prior["typedGraphRegression"]
            report["reusedProtocolEvidenceFrom"] = str(args.protocol_evidence_from)
            save()
        else:
            sample = fixtures[0]
            initial_objects = json.loads((args.fixtures / sample["name"] / "initial-objects.json").read_text())
            for ranks in (1, 2, 4):
                spool = args.output / f"protocol-r{ranks}"
                run([HERE / "repast-sharded.py", "--spool", spool, "--initialize"], "protocol-spool")
                spools.append(spool)
                store = sharded.codec.Store(spool / "objects")
                for obj in initial_objects:
                    store.put_raw(obj["hash"], "".join(obj["parts"]))
                root, tick, pids, samples = sample["initialRoot"], 0, None, []
                for revision, target in enumerate((1, 4, 8, 12), 1):
                    batch = sharded.digest(sharded.encode(["typed-protocol", ranks, revision, root, target]))
                    binding = dict(version=1, world="a" * 32, group="b" * 32, generation=1, owner="c" * 32,
                        modelDigest=sample["modelDigest"], checkpointDigest=root, fromTick=tick, targetTick=target,
                        batch=batch, inputDigest=batch)
                    request = dict(action="ensure", spec=dict(binding=binding, root=root), ranks=ranks,
                        executable=str(args.executable), mpi="/opt/homebrew/bin/mpirun", acceptedRevision=revision)
                    observed = {}
                    def complete():
                        nonlocal observed
                        observed = sharded.handle(spool, request)
                        assert observed["state"] not in ("failed", "fenced"), observed
                        return observed["state"] == "complete"
                    started = time.monotonic()
                    wait(complete)
                    assert observed["root"] == sample["roots"][str(target)]
                    native = observed["native"]
                    if pids is None: pids = native["pids"]
                    assert native["pids"] == pids and native["snapshots"] == native["rootEntityRowsGathered"] == 0
                    assert sum(native["population"]["localCounts"]) == 100000
                    assert native["population"]["persistentBoxedPopulationRows"] == 0
                    samples.append(dict(target=target, root=observed["root"], native=native, elapsedSeconds=time.monotonic()-started))
                    root, tick = observed["root"], target
                    print(f"100000 entities ranks={ranks} native tick={target}: passed", flush=True)
                shutdown(spool)
                report["protocol"].append(dict(ranks=ranks, entities=100000, samples=samples))
                save()
            # Converted GT/P2 conditional/contention checkpoints exercise every existing
            # state, timer, random, motion and contention mechanisms independently of scale motion.
            historical = json.loads((HERE.parent / "conformance/results/repast-p2-macos-2026-10-30/fixtures.json").read_text())["cases"]
            for sample_name in ("conditional-graph", "cross-rank"):
                sample = next(item for item in historical if item["name"] == sample_name)
                spool = args.output / ("typed-" + sample_name)
                run([HERE / "repast-sharded.py", "--spool", spool, "--initialize"], "typed-graph-spool")
                spools.append(spool)
                store = sharded.codec.Store(spool / "objects")
                references = {}
                for key, raw in dict(sample["checkpoints"], **{"0": sample["initial"]}).items():
                    state = sharded.decode(raw)
                    state["model"][0] = "simulation-portable-1/typed-1"
                    state["modelDigest"] = sharded.digest("CatalystSimulation-Model-1:" + sharded.encode(state["model"]))
                    references[int(key)] = store.checkpoint(state)
                tick, root, results = 0, references[0], []
                for revision, target in enumerate((1, 2, 4, 8, 12), 1):
                    batch = sharded.digest(sharded.encode([sample_name, revision, root, target]))
                    binding = dict(version=1, world="a"*32, group="b"*32, generation=1, owner="c"*32,
                        modelDigest=store.get(root)["modelDigest"], checkpointDigest=root,
                        fromTick=tick, targetTick=target, batch=batch, inputDigest=batch)
                    request = dict(action="ensure", spec=dict(root=root, binding=binding), executable=str(args.executable),
                        mpi="/opt/homebrew/bin/mpirun", ranks=4, acceptedRevision=revision)
                    observed = {}
                    def complete_small():
                        nonlocal observed
                        observed = sharded.handle(spool, request)
                        assert observed["state"] not in ("failed", "fenced"), observed
                        return observed["state"] == "complete"
                    wait(complete_small)
                    assert observed["root"] == references[target]
                    results.append(observed)
                    root, tick = observed["root"], target
                shutdown(spool)
                report.setdefault("typedGraphRegression", []).append(dict(name=sample_name, ranks=4, results=results))
                save()
        for fixture in fixtures:
            if fixture["name"] not in args.cases:
                continue
            for ranks in args.ranks:
                active = "simulation_sharded_" + uuid.uuid4().hex[:12]
                directory = args.output / (fixture["name"] + f"-r{ranks}")
                directory.mkdir()
                spool = directory / "spool"
                spools.append(spool)
                case = dict(name=fixture["name"], ranks=ranks, runtime=active, fixture=fixture, phases={})
                report["cases"].append(case)
                run([HERE / "repast-sharded.py", "--spool", spool, "--initialize"], "spool")
                store = sharded.codec.Store(spool / "objects")
                for obj in json.loads((args.fixtures / fixture["name"] / "initial-objects.json").read_text()):
                    store.put_raw(obj["hash"], "".join(obj["parts"]))
                wrapper = directory / "fault-transport.py"
                wrapper.write_text('#!/usr/bin/env python3\n' +
                    'import importlib.util,json,pathlib\n' +
                    f's=importlib.util.spec_from_file_location("sharded",{str(HERE / "repast-sharded.py")!r})\n' +
                    'r=importlib.util.module_from_spec(s);s.loader.exec_module(r)\n' +
                    'p=r.argparse.ArgumentParser();p.add_argument("--spool",type=pathlib.Path);p.add_argument("--request-file",type=pathlib.Path);a=p.parse_args()\n' +
                    'try:\n raw=a.request_file.read_text();q=json.loads(raw);reply=r.handle(a.spool,q)\n' +
                    'finally:\n a.request_file.unlink(missing_ok=True)\n' +
                    'base=a.spool.parent;hold=(base/"hold-import").exists();served=base/"artifact-served"\n' +
                    'if q["action"]=="getObjects" and hold: served.touch()\n' +
                    'if q["action"] in ("ensure","query") and q["spec"]["binding"]["targetTick"]==6 and hold and served.exists(): reply={"state":"uncertain"}\n' +
                    'encoded=json.dumps(reply,separators=(",",":"));path=base/"wire.json"\n' +
                    'stats=json.loads(path.read_text()) if path.exists() else {"requests":0,"maxInput":0,"maxOutput":0,"flatPayloads":0,"actions":{}}\n' +
                    'stats["requests"]+=1;stats["maxInput"]=max(stats["maxInput"],len(raw));stats["maxOutput"]=max(stats["maxOutput"],len(encoded));stats["flatPayloads"]+=int("checkpoint" in q.get("spec",{}));stats["actions"][q["action"]]=stats["actions"].get(q["action"],0)+1\n' +
                    'stats["availabilityReads"]=stats.get("availabilityReads",0)+reply.get("availability",{}).get("readObjects",0);stats["availabilityHits"]=stats.get("availabilityHits",0)+reply.get("availability",{}).get("cachedReferences",0)\n' +
                    'r.publish(path,stats);print(encoded)\n')
                wrapper.chmod(0o700)
                env.update(CS_P3_RUNTIME=active, CS_P3_DIRECTORY=str(directory), CS_SHARD_FIXTURE=str(args.fixtures / fixture["name"]),
                           CS_LIVE_RANKS=str(ranks), CS_LIVE_LAUNCHER=str(wrapper), CS_LIVE_EXECUTABLE=str(args.executable))
                phase("configure")
                assert lifecycle("configure", directory / "runtime.ston")["state"] == "stopped"
                lifecycle("start")
                wait(lambda: lifecycle("status")["state"] == "running")
                for name in ("upload", "create", "advance1", "external", "run3", "run4"):
                    phase(name)
                baseline = case["phases"]["external"]["materializations"]
                typed_baseline = case["phases"]["external"]["typedRestores"]
                first = ready_session(spool, 2)
                assert first is not None
                pids = native_state(first)["pids"]
                (directory / "hold-import").touch()
                phase("run6")
                wait(lambda: (directory / "artifact-served").exists())
                phase("staged")
                assert case["phases"]["staged"]["view"]["tick"] == 4
                assert lifecycle("stop")["state"] == "stopped"
                lifecycle("start")
                wait(lambda: lifecycle("status")["state"] == "running")
                phase("read-held")
                assert native_state(first)["pids"] == pids
                phase("recover")
                phase("stale-result")
                (directory / "hold-import").unlink()
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
                phase("read-crashed")
                phase("recover-idle")
                wait(lambda: ready_session(spool, 4) is not None)
                phase("drive10")
                for name in ("run3", "run4", "staged", "read-held", "recover", "accepted6", "run8", "read-crashed", "recover-idle", "drive10"):
                    assert case["phases"][name]["materializations"] == baseline == 0
                    assert case["phases"][name]["typedRestores"] == typed_baseline
                case["externalMaterializationsUnchanged"] = True
                phase("local")
                phase("advance12")
                phase("collect")
                shutdown(spool)
                receipts = []
                for path in sorted((spool / "jobs").glob("*/result.json")):
                    result = json.loads(path.read_text())
                    assert result["native"]["snapshots"] == result["native"]["rootEntityRowsGathered"] == 0
                    assert result["root"] == fixture["roots"][str(result["binding"]["targetTick"]) ]
                    assert not (spool / "sessions" / result["sessionKey"] / "native/candidate.canon").exists()
                    receipts.append(result)
                assert len(receipts) == 6 and len(sessions(spool)) == 3
                case["receipts"] = receipts
                case["wire"] = json.loads((directory / "wire.json").read_text())
                assert case["wire"]["flatPayloads"] == 0 and max(case["wire"]["maxInput"], case["wire"]["maxOutput"]) <= 196608
                assert lifecycle("stop")["state"] == "stopped"
                phase("cleanup")
                assert lifecycle("remove")["state"] == "removed"
                active = None
                save()
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
        confirmed = True
        for spool in spools:
            try:
                shutdown(spool)
            except BaseException as error:
                confirmed = False
                report["nativeCleanupError"] = repr(error)
        report["nativeCleanupConfirmed"] = confirmed
        save()
        if confirmed:
            args.lease_release.touch()
        else:
            raise RuntimeError("Owned native resources remain uncertain; isolation retained")


if __name__ == "__main__":
    main()
