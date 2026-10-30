#!/usr/bin/env python3
"""Offline verifier for the committed resident execution / Runtime proof."""
import hashlib
import json
from pathlib import Path
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "conformance"))
from check_probe import decode, encode

DIRECTORY = ROOT / "conformance/results/resident-repast-2026-10-30"


def digest(raw):
    return hashlib.sha256(raw.encode("ascii")).hexdigest()


def main():
    for name, expected in json.loads((DIRECTORY / "SHA256.json").read_text()).items():
        assert hashlib.sha256((DIRECTORY / name).read_bytes()).hexdigest() == expected
    report = json.loads((DIRECTORY / "qualification.json").read_text())
    assert report["passed"] and report["nativeCleanupConfirmed"] and report["docker"] is False
    assert report["stone"] == "bvc_simulator_native"
    assert json.loads((DIRECTORY / "gt.json").read_text())["passed"] == 62
    assert json.loads((DIRECTORY / "native-tests.json").read_text())["passed"] == 53
    assert json.loads((DIRECTORY / "transport-tests.json").read_text())["passed"] == 19
    source = json.loads((DIRECTORY / "source-native.json").read_text())
    assert source["passed"] and source["definitions"] == 414
    gate = json.loads((DIRECTORY / "gt-mcp-gate.json").read_text())
    assert gate["state"] == "released" and gate["originalRegistriesRestored"]
    fixtures = json.loads((ROOT / "conformance/results/repast-p2-macos-2026-10-30/fixtures.json").read_text())["cases"]
    conditional = next(case for case in fixtures if case["name"] == "conditional-graph")
    contention = next(case for case in fixtures if case["name"] == "cross-rank")
    finals, sessions, windows = set(), 0, 0
    assert sorted(case["ranks"] for case in report["cases"]) == [1, 2, 4]
    with zipfile.ZipFile(DIRECTORY / "artifacts.zip") as archive:
        for case in report["cases"]:
            ranks, phases = case["ranks"], case["phases"]
            assert case["sameProcessAcrossRuntimeRestart"]
            assert all(case["transportFencing"].values())
            for phase in phases.values():
                assert phase["passed"]
                if "view" in phase:
                    assert phase["runtimeEndpoint"]
            for phase, tick in (("advance1", 1), ("external1", 1), ("run3", 3), ("run4", 4),
                                ("run6", 4), ("read-held", 4), ("read-restarted", 4), ("recover", 4),
                                ("stale-result", 4), ("accepted6", 6), ("run8", 8), ("read-crashed", 8),
                                ("recover-idle", 8), ("drive10", 10), ("local2", 10), ("advance12", 12)):
                assert phases[phase]["view"]["checkpointDigest"] == digest(conditional["checkpoints"][str(tick)])
            assert phases["recover"]["view"]["pending"] == phases["read-held"]["view"]["pending"]
            assert phases["stale-result"]["fencedResultRejected"]
            assert phases["drive10"]["scheduledProgression"]
            assert phases["advance12"]["view"]["backend"] == "smalltalk"
            finals.add(phases["advance12"]["view"]["checkpointDigest"])
            primary = []
            for receipt in case["receipts"]:
                prefix = receipt["path"] + "/"
                claim = json.loads(archive.read(prefix + "claim.json"))
                result = json.loads(archive.read(prefix + "result.json"))
                raw = archive.read(prefix + "result.canon").decode("ascii")
                b = receipt["binding"]
                assert result["binding"] == claim["spec"]["binding"] == b
                assert digest(encode(claim["spec"])) == claim["specDigest"]
                assert raw == conditional["checkpoints"][str(b["targetTick"])]
                assert digest(raw) == result["checkpointDigest"] == receipt["checkpointDigest"]
                assert result["native"]["restores"] == result["native"]["graphCompilations"] == 1
                assert len(result["native"]["pids"]) == ranks
                assert result["native"]["session"]["generation"] == b["generation"]
                if b["generation"] == 2:
                    primary.append(result)
                windows += 1
            primary.sort(key=lambda result: result["binding"]["targetTick"])
            assert [r["native"]["snapshots"] for r in primary] == [1, 2, 3, 4]
            assert len({tuple(r["native"]["pids"]) for r in primary}) == 1
            assert primary[-1]["native"]["advancedTicks"] == 5
            assert primary[-1]["native"]["awaitingAcceptance"]
            assert len(case["receipts"]) == 6
            for filename in archive.namelist():
                if filename.startswith(f"r{ranks}/spool/sessions/") and filename.endswith("/finished.json"):
                    finished = json.loads(archive.read(filename))
                    assert finished["nativeReaped"]
                    if finished["session"]["generation"] == 3:
                        assert finished["state"] == "failed"
                    sessions += 1
            samples = case["protocol"]["samples"]
            assert case["protocol"]["entities"] == 16
            assert [s["native"]["snapshots"] for s in samples] == [2, 3, 4, 5, 6]
            assert [s["native"]["number"] for s in samples] == [1, 3, 5, 7, 9]
            assert len({tuple(s["native"]["pids"]) for s in samples}) == 1
            for sample in samples:
                assert sample["checkpointDigest"] == digest(contention["checkpoints"][str(sample["target"])])
                assert sample["native"]["restores"] == sample["native"]["graphCompilations"] == 1
            assert samples[-1]["native"]["advancedTicks"] == 12
            assert archive.read(f"r{ranks}/batch-regression/accepted.canon").decode("ascii") == conditional["checkpoints"]["4"]
        # Every protocol incarnation was also reaped after its five windows.
        protocol_finished = [name for name in archive.namelist() if name.startswith("protocol-r") and name.endswith("/finished.json")]
        assert len(protocol_finished) == 3
        assert all(json.loads(archive.read(name))["nativeReaped"] for name in protocol_finished)
    assert len(finals) == 1 and sessions == 9 and windows == 18
    removed = [entry for entry in report["lifecycle"] if entry["action"] == "remove"]
    assert len(removed) == 3 and all(entry["observation"]["state"] == "removed" for entry in removed)
    print("Resident proof passed: 1/2/4 ranks, retained MPI/graph/agents, lost-reply and rank-failure recovery, GS return, native fencing")


if __name__ == "__main__":
    main()
