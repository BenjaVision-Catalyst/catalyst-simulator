#!/usr/bin/env python3
"""Offline verification of committed live native integration evidence."""
import hashlib
import json
from pathlib import Path
import sys
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "conformance"))
from check_probe import decode, encode

HERE = Path(__file__).resolve().parents[1]
DIRECTORY = HERE / "conformance/results/live-repast-2026-10-30"


def digest(raw):
    return hashlib.sha256(raw.encode("ascii")).hexdigest()


def main():
    for filename, expected in json.loads((DIRECTORY / "SHA256.json").read_text()).items():
        assert hashlib.sha256((DIRECTORY / filename).read_bytes()).hexdigest() == expected
    qualification = json.loads((DIRECTORY / "qualification.json").read_text())
    assert qualification["passed"] and qualification["docker"] is False
    assert qualification["stone"] == "bvc_simulator_native"
    assert json.loads((DIRECTORY / "native-tests.json").read_text())["passed"] == 48
    assert json.loads((DIRECTORY / "gt.json").read_text())["passed"] == 57
    assert json.loads((DIRECTORY / "transport-tests.json").read_text())["passed"] == 7
    source = json.loads((DIRECTORY / "source-native.json").read_text())
    assert source["passed"] and source["definitions"] == 401
    for name in ("gt-mcp-gate.json", "source-mcp-gate.json", "scheduled-mcp-gate.json"):
        gate = json.loads((DIRECTORY / name).read_text())
        assert gate["state"] == "released" and gate["originalRegistriesRestored"]
    fixture = next(case for case in json.loads((HERE /
        "conformance/results/repast-p2-macos-2026-10-30/fixtures.json").read_text())["cases"]
        if case["name"] == "conditional-graph")
    finals = set()
    with zipfile.ZipFile(DIRECTORY / "artifacts.zip") as archive:
        for case in qualification["cases"]:
            ranks, phases = case["ranks"], case["phases"]
            assert ranks in (1, 2, 4) and len(case["jobs"]) == 4
            for phase in phases.values():
                assert phase["passed"]
                if "view" in phase:
                    assert phase["runtimeEndpoint"]
            for phase, tick in (("advance1", 1), ("external1", 1), ("run4", 4), ("local1", 4),
                                ("advance6", 6), ("external2", 6), ("run8", 6), ("read-held", 6),
                                ("recover", 6), ("stale-result", 6), ("accepted8", 8),
                                ("local2", 8), ("advance12", 12)):
                assert phases[phase]["view"]["checkpointDigest"] == digest(fixture["checkpoints"][str(tick)])
            assert phases["recover"]["view"]["phase"] == "reconciling"
            assert phases["recover"]["view"]["pending"] == phases["read-held"]["view"]["pending"]
            assert phases["stale-result"]["fencedResultRejected"]
            assert phases["stale-result"]["view"] == phases["recover"]["view"]
            assert phases["advance12"]["view"]["backend"] == "smalltalk"
            finals.add(phases["advance12"]["view"]["checkpointDigest"])
            for job in case["jobs"]:
                prefix = f"r{ranks}/spool/{job['batch']}/"
                claim = json.loads(archive.read(prefix + "claim.json"))
                result = json.loads(archive.read(prefix + "result.json"))
                finished = json.loads(archive.read(prefix + "finished.json"))
                assert finished["nativeReaped"]
                assert result["state"] == "complete" and result["ranks"] == ranks
                assert result["binding"] == claim["spec"]["binding"] == job["binding"]
                raw = archive.read(prefix + "result.canon").decode("ascii")
                assert raw == fixture["checkpoints"][str(job["binding"]["targetTick"])]
                assert digest(raw) == result["checkpointDigest"] == job["checkpointDigest"]
                assert digest(encode(claim["spec"])) == claim["specDigest"]
                execution = decode(archive.read(prefix + "native/execution.canon").decode("ascii"))
                assert execution["ranks"] == ranks
                assert sum(execution["localCounts"]) == len(claim["spec"]["checkpoint"]["entities"])
    assert len(qualification["cases"]) == 3 and len(finals) == 1
    scheduled = json.loads((DIRECTORY / "scheduled.json").read_text())
    assert scheduled["passed"] and scheduled["interruptedRuntimeRemoved"]
    case = scheduled["cases"][0]
    assert case["ranks"] == 2 and len(case["jobs"]) == 4
    for phase, tick in (("drive4", 4), ("drive12", 12)):
        observation = case["phases"][phase]
        assert observation["scheduledProgression"] and observation["runtimeEndpoint"]
        assert observation["view"]["checkpointDigest"] == digest(fixture["checkpoints"][str(tick)])
    with zipfile.ZipFile(DIRECTORY / "scheduled-artifacts.zip") as archive:
        for job in case["jobs"]:
            prefix = f"r2/spool/{job['batch']}/"
            assert json.loads(archive.read(prefix + "finished.json"))["nativeReaped"]
            raw = archive.read(prefix + "result.canon").decode("ascii")
            assert raw == fixture["checkpoints"][str(job["binding"]["targetTick"])]
    print("Live Repast evidence passed: 1/2/4 ranks, recovery, scheduled local/external progression, 16 qualified jobs")


if __name__ == "__main__":
    main()
