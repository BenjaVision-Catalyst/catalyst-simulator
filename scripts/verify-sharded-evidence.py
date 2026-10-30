#!/usr/bin/env python3
"""Verify the committed sharded proof offline, without GT, GemStone or MPI."""
import hashlib
import importlib.util
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("codec", ROOT / "scripts/sharded-codec.py")
codec = importlib.util.module_from_spec(spec)
spec.loader.exec_module(codec)
DIRECTORY = ROOT / "conformance/results/sharded-projections-2026-10-30"


class ArchiveStore(codec.Store):
    def __init__(self, archive, prefix):
        self.archive, self.prefix = archive, prefix

    def raw(self, key):
        assert codec.valid_hash(key)
        raw = self.archive.read(self.prefix + key + ".canon").decode("ascii")
        assert len(raw) <= codec.PAGE and codec.digest(raw) == key
        assert codec.encode(codec.decode(raw)) == raw
        return raw


def main():
    read = lambda name: json.loads((DIRECTORY / name).read_text())
    for name, expected in read("SHA256.json").items():
        assert hashlib.sha256((DIRECTORY / name).read_bytes()).hexdigest() == expected, name
    report = read("qualification.json")
    assert report["passed"] and report["nativeCleanupConfirmed"] and report["docker"] is False
    assert report["stone"] == "bvc_simulator_native"
    assert read("gt.json")["passed"] == 81
    assert read("native-tests.json")["passed"] == 71
    assert read("transport-tests.json")["passed"] == 31
    assert read("source-native.json")["definitions"] == 519
    assert read("source-native.json")["passed"] and read("source-gt.json")["passed"]
    for name in ("gt-mcp-gate.json", "legacy-gate.json"):
        gate = read(name)
        assert gate["state"] == "released" and gate["originalRegistriesRestored"]
    regression = read("legacy-regression.json")
    assert regression["passed"] and regression["nativeCleanupConfirmed"]
    assert [case["ranks"] for case in regression["cases"]] == [2]
    assert read("native-values.json")["passed"] and read("native-values.json")["checks"] > 40
    assert sorted((c["name"], c["ranks"]) for c in report["cases"]) == [
        (name, ranks) for name in ("conditional", "sparse") for ranks in (1, 2, 4)]
    assert sum(item["action"] == "remove" and item["result"]["state"] == "removed"
               for item in report["lifecycle"]) == 6
    windows, sessions, failures = 0, 0, 0
    with zipfile.ZipFile(DIRECTORY / "artifacts.zip") as archive:
        names = archive.namelist()
        for case in report["cases"]:
            fixture, phases = case["fixture"], case["phases"]
            prefix = f'{case["name"]}-r{case["ranks"]}/spool/'
            reference = ArchiveStore(archive, f'gt/{case["name"]}/')
            native = ArchiveStore(archive, prefix + "objects/")
            for root in fixture["roots"].values():
                reference.closure(root)
            for phase in phases.values():
                assert phase["passed"]
                if "view" not in phase:
                    continue
                view, page, changes = phase["view"], phase["projection"], phase["projectionChanges"]
                root = fixture["roots"][str(view["tick"])]
                assert phase["runtimeEndpoint"] and view["checkpointDigest"] == root
                assert page["root"] == changes["root"] == phase["manifest"]["root"] == root
                assert page["revision"] == changes["revision"] == view["dataRevision"]
                assert page["revision"] <= view["revision"]
                manifest = reference.get(root)
                assert phase["manifest"]["manifest"] == manifest
                assert view["projectionRoot"] == manifest["projection"]
                assert page["tick"] == view["tick"] and len(codec.encode(page["entities"])) <= 32768
                buckets = reference.read_index(manifest["projection"])
                bucket = "00" if case["name"] == "sparse" else sorted(buckets)[0]
                rows = reference.read_rows(buckets[bucket])
                ids = sorted(rows)[:2]
                assert page["entities"] == [rows[key] for key in ids]
                assert page["next"] == (ids[-1] if len(rows) > len(ids) else None)
                for change in changes["changes"]:
                    assert change["revision"] > change["baseRevision"]
                    before = reference.read_index(reference.get(change["baseRoot"])["projection"])
                    after = reference.read_index(reference.get(change["root"])["projection"])
                    assert change["changedBuckets"] == sorted(key for key in set(before) | set(after)
                                                              if before.get(key) != after.get(key))
            assert phases["staged"]["unacceptedMissingObjects"] > 0
            for name in ("staged", "read-held", "recover", "stale-result"):
                assert phases[name]["view"]["tick"] == 4
                assert phases[name]["view"]["pending"]["resultRoot"] == fixture["roots"]["6"]
            assert phases["recover"]["view"]["pending"] == phases["read-held"]["view"]["pending"]
            assert phases["stale-result"]["fencedResultRejected"] and phases["drive10"]["scheduled"]
            assert phases["recover"]["view"]["generation"] > phases["read-held"]["view"]["generation"]
            baseline = phases["external"]["materializations"]
            assert baseline == 1 and case["externalMaterializationsUnchanged"]
            for name in ("run3", "run4", "staged", "read-held", "recover", "accepted6", "run8",
                         "read-crashed", "recover-idle", "drive10"):
                assert phases[name]["materializations"] == baseline
            assert phases["advance12"]["materializations"] > baseline
            assert phases["advance12"]["view"]["backend"] == "smalltalk"
            assert phases["collect"]["objectsAfter"] < phases["collect"]["objectsBefore"]
            assert phases["collect"]["projectionChanges"]["resnapshot"]
            assert case["wire"]["flatPayloads"] == 0
            assert max(case["wire"]["maxInput"], case["wire"]["maxOutput"]) <= 196608
            assert all(case["wire"]["actions"][action] > 0 for action in ("getObjects", "putObjects", "query"))
            if case["name"] == "sparse":
                assert fixture["flatBytes"] == 556805 > 196608
                assert phases["run4"]["validation"] == dict(newObjects=37, checkedRows=256, totalEntities=4096)
            job_results = [name for name in names if name.startswith(prefix + "jobs/") and name.endswith("/result.json")]
            assert len(job_results) == len(case["receipts"]) == 6
            primary = []
            for filename in job_results:
                result = json.loads(archive.read(filename))
                assert result in case["receipts"] and result["state"] == "complete"
                claim = json.loads(archive.read(filename.replace("result.json", "claim.json")))
                assert claim["specDigest"] == codec.digest(codec.encode(claim["spec"]))
                assert claim["spec"] == dict(binding=result["binding"], root=result["binding"]["checkpointDigest"])
                root = result["root"]
                assert root == fixture["roots"][str(result["binding"]["targetTick"])]
                native.closure(root)
                assert native.materialize(root) == reference.materialize(root)
                counters = result["native"]
                assert counters["profile"] == "checkpoint-1"
                assert counters["snapshots"] == counters["rootEntityRowsGathered"] == 0
                assert counters["restores"] == counters["graphCompilations"] == 1
                assert len(counters["pids"]) == case["ranks"]
                assert result["executableDigest"] == read("build.json")["executableDigest"]
                if result["binding"]["generation"] == 2:
                    primary.append(result)
                windows += 1
            primary.sort(key=lambda result: result["binding"]["targetTick"])
            assert [r["binding"]["targetTick"] for r in primary] == [1, 3, 4, 6]
            assert [r["native"]["shardedSnapshots"] for r in primary] == [1, 2, 3, 4]
            assert len({tuple(r["native"]["pids"]) for r in primary}) == 1
            finished_files = [name for name in names if name.startswith(prefix + "sessions/") and name.endswith("/finished.json")]
            assert len(finished_files) == 3
            for filename in finished_files:
                finished = json.loads(archive.read(filename))
                assert finished["nativeReaped"]
                if finished["session"]["generation"] == 3:
                    assert finished["state"] == "failed"
                    failures += 1
                sessions += 1
            assert not any(name.startswith(prefix) and name.endswith(("result.canon", "candidate.canon", "input.canon")) for name in names)
    assert (windows, sessions, failures) == (36, 18, 6)
    print(json.dumps(dict(passed=True, cases=6, resultWindows=windows, reapedSessions=sessions,
                          injectedRankFailures=failures, gtTests=81, gemstoneTests=71, transportTests=31)))


if __name__ == "__main__":
    main()
