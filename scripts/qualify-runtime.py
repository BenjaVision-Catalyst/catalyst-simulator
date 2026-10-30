#!/usr/bin/env python3
"""Socket-free P3 qualification using one uniquely named managed Runtime.

Requires the GT-verified Simulator and Runtime sources installed in the dedicated
stone. No stone rebuild, Docker or external simulator is launched. Actual Repast
checkpoint bytes come from the pinned P2 evidence. Failures retain their named
Runtime and repository for inspection; no application body is automatically
replayed and no uncertain delivery is deleted.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
import uuid
import zipfile

HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser()
    for name in ("project", "bvc", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--deployment", default="bvc_simulator_native", choices=["bvc_simulator_native"])
    args = parser.parse_args()
    directory = args.output.resolve()
    directory.mkdir(parents=True, exist_ok=False)
    runtime = "simulation_p3_" + uuid.uuid4().hex[:12]
    env = dict(os.environ, GEMSTONE_STONE_NAME=args.deployment, CS_P3_RUNTIME=runtime,
               CS_P3_REPOSITORY=runtime, CS_P3_DIRECTORY=str(directory))
    report = dict(runtime=runtime, stone=args.deployment, phases={}, conflicts=[], passed=False)
    sequence = 0

    def save():
        (directory / "qualification.json").write_text(json.dumps(report, indent=2) + "\n")

    def run(command, label, extra=None):
        nonlocal sequence
        sequence += 1
        result = subprocess.run(list(map(str, command)), cwd=args.project, env=dict(env, **(extra or {})),
                                capture_output=True, text=True, timeout=90)
        (directory / f"{sequence:03}-{label}.log").write_text(result.stdout + result.stderr)
        assert result.returncode == 0, (label, result.returncode)
        return result.stdout

    def phase(name):
        run([args.bvc, "topaz", args.deployment, "--script", HERE / "qualify-runtime.topaz"],
            name, dict(CS_P3_PHASE=name))
        report["phases"][name] = json.loads((directory / (name + ".json")).read_text())
        assert report["phases"][name]["passed"]
        save()
        print(name + ": passed", flush=True)

    def lifecycle(action, *extra):
        result = json.loads(run([args.bvc, "runtime", action, runtime, *extra], action))
        report[action + "-" + str(sequence)] = result
        save()
        return result

    def ready():
        deadline = time.monotonic() + 45
        while True:
            state = lifecycle("status")
            if state["state"] == "running":
                return state
            assert time.monotonic() < deadline, state
            time.sleep(.2)

    def conflict(round_number):
        children = []
        logs = []
        try:
            for role in ("A", "B"):
                log = (directory / f"writer-{round_number}-{role}.log").open("w")
                logs.append(log)
                process = subprocess.Popen(list(map(str, [args.bvc, "topaz", args.deployment,
                    "--script", HERE / "qualify-runtime-writer.topaz"])), cwd=args.project,
                    env=dict(env, CS_P3_WRITER=role, CS_P3_ROUND=str(round_number)),
                    stdout=log, stderr=subprocess.STDOUT)
                children.append(process)
            deadline = time.monotonic() + 45
            for role in ("A", "B"):
                while not (directory / f"writer-{round_number}-{role}-ready").exists():
                    assert all(p.poll() is None for p in children), "Writer failed before barrier"
                    assert time.monotonic() < deadline, "Writer preparation timeout"
                    time.sleep(.05)
            # A fresh Gem reads while both writer candidates are still private.
            phase("uncommitted-" + str(round_number))
            for role, process in zip(("A", "B"), children):
                (directory / f"writer-{round_number}-{role}-release").touch()
                assert process.wait(30) == 0
                observation = json.loads((directory / f"writer-{round_number}-{role}.json").read_text())
                assert observation["bodyExecutions"] == 1
                assert observation["committed"] == (role == "A"), observation
                if role == "B":
                    assert observation["writeWriteConflicts"] > 0, observation
                report["conflicts"].append(observation)
        finally:
            for role in ("A", "B"):
                (directory / f"writer-{round_number}-{role}-release").touch()
            for process in children:
                if process.poll() is None:
                    process.wait(70)
            for log in logs:
                log.close()
        save()

    p2 = HERE.parent / "conformance/results/repast-p2-macos-2026-10-30"
    fixture = next(r for r in json.loads((p2 / "fixtures.json").read_text())["cases"] if r["name"] == "conditional-graph")
    (directory / "oracle-0.canon").write_text(fixture["initial"])
    with zipfile.ZipFile(p2 / "artifacts.zip") as archive:
        for tick in range(1, 13):
            raw = archive.read(f"conditional-graph-r4-l0/tick-{tick}.canon")
            assert raw.decode("ascii") == fixture["checkpoints"][str(tick)]
            (directory / f"oracle-{tick}.canon").write_bytes(raw)
    save()
    try:
        phase("configure")
        assert lifecycle("configure", directory / "runtime.ston")["state"] == "stopped"
        lifecycle("start")
        ready()
        for name in ("create", "advance", "rollback"):
            phase(name)
        assert lifecycle("stop")["state"] == "stopped"
        lifecycle("start")
        ready()
        for name in ("recover-local", "enable-drive", "disable-drive", "obsolete",
                     "external", "activate", "prepare", "dispatch"):
            phase(name)
        assert lifecycle("stop")["state"] == "stopped"
        lifecycle("start")
        ready()
        for name in ("recover-external", "late-result", "reconcile", "local", "activate", "advance10"):
            phase(name)
        conflict(1)
        conflict(2)
        for name in ("activate", "advance12", "retention"):
            phase(name)
        assert lifecycle("stop")["state"] == "stopped"
        phase("cleanup")
        assert lifecycle("remove")["state"] == "removed"
        report["passed"] = True
        save()
    except BaseException as error:
        report["error"] = repr(error)
        save()
        raise
    print(json.dumps(dict(passed=True, runtime=runtime, conflicts=len(report["conflicts"]))), flush=True)


if __name__ == "__main__":
    main()
