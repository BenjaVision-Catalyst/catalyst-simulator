#!/usr/bin/env python3
"""Verify columnar frames against the existing GT canonical population oracle."""
from contextlib import ExitStack
import hashlib
import importlib.util
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / "conformance/results/columnar-2026-10-30"


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    c = load("columnar", "columnar-codec.py")
    typed = load("typed_evidence", "verify-typed-evidence.py")
    read = lambda name: json.loads((DIRECTORY / name).read_text())
    for name, digest in read("SHA256.json").items():
        assert hashlib.sha256((DIRECTORY/name).read_bytes()).hexdigest() == digest, name
    for name, digest in read("source-sha256.json").items():
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest() == digest, name
    reference = read("reference.json")
    previous = ROOT / reference["directory"]
    for name, digest in reference["files"].items():
        assert hashlib.sha256((previous/name).read_bytes()).hexdigest() == digest, name
    report = read("qualification.json")
    assert report["passed"] and report["nativeCleanupConfirmed"] and report["docker"] is False
    assert read("gt.json")["passed"] == 98 and read("native-tests.json")["passed"] == 88
    assert read("source-gt.json") == {"BVC-Simulator-Core":162,"BVC-Simulator-Authority":121,"BVC-Simulator-Runtime":168,
                                      "BVC-Simulator-Tests":50,"BVC-Simulator-Tests-Authority":76,"BVC-Simulator-Tests-Runtime":58}
    assert read("source-native.json")["passed"] and read("source-native.json")["definitions"] == 616
    assert read("runtime-source-native.json")["passed"] and read("runtime-source-native.json")["definitions"] == 615
    assert read("transport-tests.json")["passed"] == 46
    assert sum(run["passed"] for run in read("transport-tests.json")["runs"]) == 46
    assert all(run["returncode"] == 0 for run in read("transport-tests.json")["runs"])
    assert read("native-values.json") == dict(passed=True, checks=216)
    gate = read("gt-mcp-gate.json")
    assert gate["state"] == "released" and gate["originalRegistriesRestored"]
    gate = read("probe-gate.json")
    assert gate["state"] == "released" and gate["originalRegistriesRestored"]
    fixture = json.loads((previous/"fixtures.json").read_text())[0]
    case, = report["cases"]
    assert case["ranks"] == 4 and case["externalMaterializationsUnchanged"]
    with ExitStack() as stack:
        pools = {}
        for path in sorted(previous.glob("objects-*.zip")):
            archive = stack.enter_context(zipfile.ZipFile(path))
            for name in archive.namelist():
                digest = Path(name).stem
                assert digest not in pools
                pools[digest] = archive, name
        prior = stack.enter_context(zipfile.ZipFile(previous/"artifacts.zip"))
        store = typed.PoolStore(pools, json.loads(prior.read("gt/objects.json")))
        artifacts = stack.enter_context(zipfile.ZipFile(DIRECTORY/"artifacts.zip"))
        fields = json.loads(artifacts.read("all-fields.json"))
        field_probe = read("field-roundtrip.json")
        assert fields["passed"] and fields["fields"] == 14 and fields["entities"] == 300
        assert field_probe["passed"] and field_probe["cleaned"]
        assert field_probe["build"]["passed"] and field_probe["build"]["root"] == fields["target"]
        assert field_probe["verify"]["passed"] and field_probe["verify"]["population"]["entities"] == 300
        assert field_probe["verify"]["freshSessionVerified"] and field_probe["verify"]["root"] == fields["target"]
        assert field_probe["verify"]["materializations"] == 0
        class FixtureStore(c.cas.Store):
            def __init__(self):
                self.payloads = {obj["hash"]:"".join(obj["parts"]) for obj in fields["objects"]}
            def raw(self, key):
                raw = self.payloads[key]
                assert len(raw) <= c.cas.PAGE and c.cas.digest(raw) == key
                return raw
        field_store = FixtureStore()
        for frame in fields["frames"]:
            assert c.frame(field_store, frame["root"], frame["base"], frame["cursor"]) == frame
            scratch = c.reconstruct(field_store, frame, frame["base"], frame["cursor"])
            assert all(field_store.raw(key) == raw for key,raw in scratch.objects.items())
        frames, roots, expanded = 0, set(), 0
        cursors = {}
        for name in sorted(artifacts.namelist()):
            if not name.startswith("frames/"):
                continue
            frame = json.loads(artifacts.read(name))
            assert frame["base"] in fixture["roots"].values() and frame["root"] in fixture["roots"].values()
            assert c.frame(store, frame["root"], frame["base"], frame["cursor"]) == frame
            scratch = c.reconstruct(store, frame, frame["base"], frame["cursor"])
            for digest, raw in scratch.objects.items():
                assert store.raw(digest) == raw
            cursors.setdefault(frame["root"], {})[frame["cursor"]] = frame
            expanded += scratch.byte_count
            roots.add(frame["root"])
            frames += 1
        assert len(roots) == 5
        for root, stream in cursors.items():
            cursor = 0
            while cursor in stream:
                frame = stream[cursor]
                cursor = frame["next"]
            assert cursor == frame["total"] and len(stream) > 1
        membership = json.loads(artifacts.read("native/objects.json"))
        native_store = typed.PoolStore(pools, membership)
        for result in case["receipts"]:
            binding = result["binding"]
            assert result["root"] == fixture["roots"][str(binding["targetTick"])]
            assert result["executableDigest"] == read("build.json")["executableSha256"]
            assert result["native"]["snapshots"] == result["native"]["rootEntityRowsGathered"] == 0
            assert sum(result["native"]["population"]["localCounts"]) == 100000
            native_store.closure(result["root"])
        finished = [json.loads(artifacts.read(name)) for name in artifacts.namelist() if name.endswith("/finished.json")]
        assert len(finished) == 3 and all(record["nativeReaped"] for record in finished)
        assert sum(record["state"] == "failed" for record in finished) == 1
        for name, phase in case["phases"].items():
            if "view" not in phase:
                continue
            view = phase["view"]
            assert view["checkpointDigest"] == fixture["roots"][str(view["tick"])], name
            assert phase["runtimeEndpoint"] and phase["materializations"] == 0
            projection = phase["projection"]
            assert projection["root"] == view["checkpointDigest"] and projection["tick"] == view["tick"]
            node = store.get(view["checkpointDigest"])
            rows = store.read_rows(store.read_index(node["projection"])["00"])
            assert projection["entities"] == [rows[key] for key in sorted(rows)[:2]]
        phases = case["phases"]
        held = phases["staged"]["view"]
        assert held["tick"] == 4 and held["pending"]["columnarCursor"] > 0 and not held["pending"]["columnarComplete"]
        assert phases["read-held"]["view"]["pending"] == held["pending"]
        assert phases["recover"]["view"]["pending"] == held["pending"]
        assert phases["stale-result"]["fencedResultRejected"]
        assert phases["accepted6"]["view"]["tick"] == 6
        assert phases["drive10"]["scheduled"] and phases["drive10"]["view"]["tick"] == 10
        assert phases["advance12"]["view"]["backend"] == "smalltalk"
        baseline = phases["external"]["typedRestores"]
        for name in ("run3", "run4", "staged", "read-held", "recover", "accepted6", "run8", "read-crashed", "recover-idle", "drive10"):
            assert phases[name]["typedRestores"] == baseline
        assert phases["collect"]["objectsAfter"] < phases["collect"]["objectsBefore"] <= 65536
        wire = case["wire"]
        assert wire["flatPayloads"] == 0 and max(wire["maxInput"], wire["maxOutput"]) <= 196608
        assert wire["actions"].get("getColumnar", 0) > 0 and wire["actions"].get("putColumnar", 0) > 0
        assert wire["actions"].get("getObjects", 0) == wire["actions"].get("putObjects", 0) == 0
        metrics = phases["drive10"]["columnar"]
        assert metrics["deltaFrames"] == frames and metrics["rows"] == 500000
        comparison = read("comparison.json")
        for name in ("run3", "run4", "run8", "drive10"):
            assert comparison[name]["seconds"] == case["phaseElapsedSeconds"][name]
            assert comparison[name]["seconds"] < comparison[name]["baselineSeconds"]
    print(json.dumps(dict(passed=True, entities=100000, runtimeRanks=4, frames=frames, expandedBytes=expanded,
                         gtTests=98, gemstoneTests=88, nativeChecks=216)))


if __name__ == "__main__":
    main()
