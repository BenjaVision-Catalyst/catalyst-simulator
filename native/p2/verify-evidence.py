#!/usr/bin/env python3
"""Offline verification of archived P2 bytes; does not execute native code."""
import hashlib
import json
from pathlib import Path
import sys
import zipfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / "conformance"))
from check_probe import decode, encode
from check_graph import step


def main():
    evidence = Path(sys.argv[1])
    inventory = json.loads((evidence / "SHA256.json").read_text())
    for name, expected in inventory.items():
        assert hashlib.sha256((evidence / name).read_bytes()).hexdigest() == expected, name
    report = json.loads((evidence / "qualification.json").read_text())
    fixtures = json.loads((evidence / "fixtures.json").read_text())
    cases = {r["name"]: r for r in fixtures["cases"]}
    committed = json.loads((HERE.parents[1] / "contracts/graph-1/fixtures.json").read_text())
    for record in committed["models"]:
        assert cases[record["name"]]["model"] == record["model"]
        assert cases[record["name"]]["initial"] == record["initial"]
        for tick, checkpoint in record["checkpoints"].items():
            assert cases[record["name"]]["checkpoints"][tick] == checkpoint
    assert report["passed"] and report["gtTests"] == 32 and report["gemstonePrepare"]["tests"] == 32
    assert report["gemstoneReturn"]["returned"] == report["gemstoneFreshSession"]["returned"] == 24
    assert report["gemstoneFreshSession"]["sourcesUnchanged"] and report["gemstoneRootRemoved"]
    assert len(report["runs"]) == 24 and len(report["restarts"]) == 12 and len(report["negatives"]) == 6
    source = decode(cases["cross-rank"]["checkpoints"]["1"])
    assert source["resources"] == {"charge": 3} and source["outcomes"] == []
    assert all(row[4] == 0 for row in source["entities"].values())
    assert source["entities"]["0" * 32][1][0] == -1
    assert decode(cases["cross-rank"]["checkpoints"]["2"])["outcomes"] == [[2, "charge", "0" * 32, 2]]
    count = 0
    with zipfile.ZipFile(evidence / "artifacts.zip") as archive:
        for name, record in cases.items():
            state = decode(record["initial"])
            for tick in range(1, 13):
                state = step(state)
                assert encode(state) == record["checkpoints"][str(tick)]
            for ranks in (1, 2, 4):
                for layout in (0, 1):
                    key = f"{name}-r{ranks}-l{layout}"
                    row = next(r for r in report["runs"] if r["key"] == key)
                    for tick in range(1, 13):
                        raw = archive.read(f"{key}/tick-{tick}.canon")
                        assert raw.decode("ascii") == record["checkpoints"][str(tick)]
                        assert hashlib.sha256(raw).hexdigest() == row["boundaries"][str(tick)]
                        count += 1
                    if name == "cross-rank" and ranks > 1:
                        assert row["migrations"] > 0 and row["remoteRequests"] > 0
                        assert row["localCounts"] == [16 // ranks] * ranks
            for before, after in ((1, 2), (2, 4), (4, 1)):
                for tick in range(6, 13):
                    assert archive.read(f"{name}-restart-{before}-{after}/tick-{tick}.canon").decode("ascii") == record["checkpoints"][str(tick)]
                    count += 1
        assert json.loads(archive.read("001-native-value-tests.log")) == {"passed": True, "checks": 29}
        assert archive.read("killed/accepted.canon").decode("ascii") == cases["cross-rank"]["checkpoints"]["1"]
        assert "killed/tick-2.canon" not in archive.namelist()
        assert "bad-digest/accepted.canon" not in archive.namelist()
        assert archive.read("overflow/accepted.canon") == archive.read("overflow.checkpoint")
        assert "overflow/tick-1.canon" not in archive.namelist()
    gate = json.loads((evidence / "gt-mcp-gate.json").read_text())
    assert gate["state"] == "released" and gate["originalRegistriesRestored"]
    build = json.loads((evidence / "build.json").read_text())
    assert build["repastRevision"] == "a96c15f99589d15352523a0a710362af8997852a" and not build["repastDirty"]
    print(json.dumps(dict(passed=True, archivedMpiBoundaries=count, gemstoneRoundTrips=24)))


if __name__ == "__main__":
    main()
