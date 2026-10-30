#!/usr/bin/env python3
"""Offline verification of typed population, native rank and Runtime evidence."""
from contextlib import ExitStack
import hashlib
import importlib.util
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("codec", ROOT / "scripts/sharded-codec.py")
codec = importlib.util.module_from_spec(spec)
spec.loader.exec_module(codec)
DIRECTORY = ROOT / "conformance/results/typed-population-2026-10-30"


class PoolStore(codec.Store):
    def __init__(self, pools, allowed):
        self.pools, self.allowed = pools, set(allowed)
        self.verified = set()
        assert len(self.allowed) == len(allowed)
        assert all(codec.valid_hash(key) for key in self.allowed)

    def raw(self, key):
        assert key in self.allowed
        archive, name = self.pools[key]
        raw = archive.read(name).decode("ascii")
        assert len(raw) <= codec.PAGE and codec.digest(raw) == key
        return raw

    def get(self, key):
        raw = self.raw(key)
        node = codec.decode(raw)
        if key not in self.verified:
            assert codec.encode(node) == raw
            self.verified.add(key)
        return node


def motion_oracle(state):
    assert len(state["entities"]) == 100000
    assert state["model"][0] == "simulation-portable-1/typed-1"
    assert state["model"][3] == 100000
    assert state["modelDigest"] == codec.digest("CatalystSimulation-Model-1:" + codec.encode(state["model"]))
    assert state["seed"] == 42
    for ordinal in range(100000):
        identity = f"{ordinal:032x}"
        velocity = [1003 + ordinal % 7, -997, 13]
        initial = [ordinal * 5 - 250000, -ordinal, ordinal % 13]
        wide = [value * 100 * state["tick"] for value in velocity]
        assert state["entities"][identity] == [identity, [p + w // 1000 for p, w in zip(initial, wide)],
            velocity, "", 0, "neutral", 0, 0, [value % 1000 for value in wide]]


def main():
    read = lambda name: json.loads((DIRECTORY / name).read_text())
    for name, expected in read("SHA256.json").items():
        assert hashlib.sha256((DIRECTORY / name).read_bytes()).hexdigest() == expected, name
    report, fixture = read("qualification.json"), read("fixtures.json")[0]
    assert report["passed"] and report["nativeCleanupConfirmed"] and report["docker"] is False
    assert report["stone"] == "bvc_simulator_native"
    assert read("gt.json")["passed"] == 89 and read("native-tests.json")["passed"] == 79
    assert read("source-gt.json")["passed"]
    assert read("source-native.json")["passed"] and read("source-native.json")["definitions"] == 571
    assert read("transport-tests.json")["passed"] == 36
    assert read("native-values.json") == dict(passed=True, checks=216)
    gate = read("gt-mcp-gate.json")
    assert gate["state"] == "released" and gate["originalRegistriesRestored"]
    for name in ("protocol-gate.json", "legacy-gate.json"):
        gate = read(name)
        assert gate["state"] == "released" and gate["originalRegistriesRestored"]
    legacy = read("legacy-regression.json")
    assert legacy["passed"] and legacy["nativeCleanupConfirmed"]
    assert [case["ranks"] for case in legacy["cases"]] == [2]
    source_probe = legacy["typedSourceRoundTrip"]
    assert source_probe["build"]["root"] == source_probe["verify"]["root"] == fixture["roots"]["1"]
    assert source_probe["verify"]["freshSessionVerified"] and source_probe["verify"]["cleaned"]
    assert source_probe["verify"]["materializations"] == 0
    assert source_probe["verify"]["population"]["entities"] == 100000
    assert fixture["population"]["packedBytes"] == 9633792
    assert fixture["population"]["numericBytesPerSlot"] == 96
    assert fixture["population"]["idIndexEntries"] == fixture["population"]["entities"] == 100000
    build = read("build.json")
    native_windows, reaped, failures = 0, 0, 0
    with ExitStack() as stack:
        archive = stack.enter_context(zipfile.ZipFile(DIRECTORY / "artifacts.zip"))
        pools = {}
        for path in sorted(DIRECTORY.glob("objects-*.zip")):
            part = stack.enter_context(zipfile.ZipFile(path))
            for name in part.namelist():
                key = name.removesuffix(".canon")
                assert codec.valid_hash(key) and key not in pools
                pools[key] = part, name
        members = lambda prefix: json.loads(archive.read(prefix + "/objects.json"))
        reference = PoolStore(pools, members("gt"))
        # This checks every row against independent integer arithmetic, not just
        # agreement between the two interpreters or a population-count counter.
        for tick, root in fixture["roots"].items():
            reference.closure(root)
            state = reference.materialize(root)
            assert state["tick"] == int(tick)
            motion_oracle(state)
        assert sorted(item["ranks"] for item in report["protocol"]) == [1, 2, 4]
        for item in report["protocol"]:
            prefix = f'protocol-r{item["ranks"]}'
            store = PoolStore(pools, members(prefix))
            assert item["entities"] == 100000
            assert [sample["target"] for sample in item["samples"]] == [1, 4, 8, 12]
            pids = set()
            for index, sample in enumerate(item["samples"]):
                native = sample["native"]
                assert sample["root"] == fixture["roots"][str(sample["target"])]
                store.closure(sample["root"])
                assert native["profile"] == "checkpoint-1" and native["shardedSnapshots"] == index + 2
                assert native["snapshots"] == native["rootEntityRowsGathered"] == 0
                assert native["graphCompilations"] == native["restores"] == 1
                population = native["population"]
                assert population["layout"] == "typed-records-1" and population["rowBytes"] == 112
                assert population["persistentBoxedPopulationRows"] == 0
                assert sum(population["localCounts"]) == 100000
                assert len(native["pids"]) == item["ranks"]
                assert all(value > 0 for value in population["currentRssBytes"] + population["peakRssBytes"])
                pids.add(tuple(native["pids"]))
                native_windows += 1
            assert len(pids) == 1
        assert {item["name"] for item in report["typedGraphRegression"]} == {"conditional-graph", "cross-rank"}
        historical = json.loads((ROOT / "conformance/results/repast-p2-macos-2026-10-30/fixtures.json").read_text())["cases"]
        for item in report["typedGraphRegression"]:
            prefix = "typed-" + item["name"]
            store = PoolStore(pools, members(prefix))
            sample = next(value for value in historical if value["name"] == item["name"])
            assert len(item["results"]) == 5 and item["ranks"] == 4
            for result in item["results"]:
                state = codec.decode(sample["checkpoints"][str(result["binding"]["targetTick"])])
                state["model"][0] = "simulation-portable-1/typed-1"
                state["modelDigest"] = codec.digest("CatalystSimulation-Model-1:" + codec.encode(state["model"]))
                assert store.materialize(result["root"]) == state
                native_windows += 1
        assert len(report["cases"]) == 1 and report["cases"][0]["ranks"] == 4
        case = report["cases"][0]
        prefix, phases = "typed100k-r4/spool", case["phases"]
        store = PoolStore(pools, members(prefix))
        external = phases["external"]["typedRestores"]
        assert external == 1
        for name, phase in phases.items():
            assert phase["passed"]
            if "view" not in phase:
                continue
            view, page = phase["view"], phase["projection"]
            assert phase["runtimeEndpoint"] and view["entityCount"] == 100000
            assert phase["materializations"] == 0 and phase["objectCount"] <= 65536
            assert view["checkpointDigest"] == fixture["roots"][str(view["tick"])]
            assert page["root"] == view["checkpointDigest"]
            assert page["revision"] == view["dataRevision"] <= view["revision"]
            manifest = reference.get(page["root"])
            assert phase["manifest"]["manifest"] == manifest
            rows = reference.read_rows(reference.read_index(manifest["projection"])["00"])
            ids = sorted(rows)[:2]
            assert page["entities"] == [rows[key] for key in ids] and page["next"] == ids[-1]
            assert len(codec.encode(page["entities"])) <= 32768
            changes = phase["projectionChanges"]
            assert changes["root"] == page["root"] and changes["revision"] == page["revision"]
            for change in changes["changes"]:
                before = reference.read_index(reference.get(change["baseRoot"])["projection"])
                after = reference.read_index(reference.get(change["root"])["projection"])
                assert change["changedBuckets"] == sorted(key for key in set(before) | set(after)
                                                          if before.get(key) != after.get(key))
            if name in ("run3", "run4", "staged", "read-held", "recover", "accepted6", "run8",
                        "read-crashed", "recover-idle", "drive10"):
                assert phase["typedRestores"] == external
        assert phases["staged"]["unacceptedMissingObjects"] > 0
        for name in ("staged", "read-held", "recover", "stale-result"):
            assert phases[name]["view"]["tick"] == 4
            assert phases[name]["view"]["pending"]["resultRoot"] == fixture["roots"]["6"]
        assert phases["recover"]["view"]["pending"] == phases["read-held"]["view"]["pending"]
        assert phases["stale-result"]["fencedResultRejected"]
        assert phases["drive10"]["scheduled"]
        assert phases["advance12"]["view"]["backend"] == "smalltalk"
        assert phases["advance12"]["typedRestores"] == 3
        assert phases["collect"]["objectsAfter"] < phases["collect"]["objectsBefore"]
        assert phases["collect"]["projectionChanges"]["resnapshot"]
        assert case["externalMaterializationsUnchanged"]
        assert case["wire"]["flatPayloads"] == 0
        assert max(case["wire"]["maxInput"], case["wire"]["maxOutput"]) <= 196608
        assert len(case["receipts"]) == 6
        for result in case["receipts"]:
            assert result["executableDigest"] == build["executableDigest"]
            assert result["root"] == fixture["roots"][str(result["binding"]["targetTick"])]
            store.closure(result["root"])
            assert sum(result["native"]["population"]["localCounts"]) == 100000
            assert result["native"]["snapshots"] == result["native"]["rootEntityRowsGathered"] == 0
            native_windows += 1
        for name in archive.namelist():
            if name.endswith("/finished.json") and "/sessions/" in name and not name.startswith("legacy/"):
                finished = json.loads(archive.read(name))
                assert finished["nativeReaped"]
                reaped += 1
                failures += finished["state"] == "failed"
                if name.startswith("protocol-r"):
                    execution = codec.decode(archive.read(name.replace("finished.json", "native/execution.canon")).decode("ascii"))
                    if not name.startswith("protocol-r1/"):
                        assert execution["migrations"] > 0
        assert any(item["action"] == "remove" and item["result"]["state"] == "removed" for item in report["lifecycle"])
    assert (native_windows, reaped, failures) == (28, 8, 1)
    print(json.dumps(dict(passed=True, entities=100000, nativeRanks=[1, 2, 4], runtimeRanks=[4],
        resultWindows=native_windows, reapedSessions=reaped, gtTests=89, gemstoneTests=79)))


if __name__ == "__main__":
    main()
