#!/usr/bin/env python3
"""Verify the archived P3 receipts, source identities and checkpoint evidence."""
import hashlib
import json
from pathlib import Path
import sys
import zipfile


def main():
    root = Path(sys.argv[1])
    for name, digest in json.loads((root / "SHA256.json").read_text()).items():
        assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, name
    report = json.loads((root / "qualification.json").read_text())
    assert report["passed"] and report["stone"] == "bvc_simulator_native"
    assert json.loads((root / "gt.json").read_text())["passed"] == 52
    assert json.loads((root / "native-tests.json").read_text())["passed"] == 43
    assert json.loads((root / "source-native.json").read_text())["passed"]
    loading = json.loads((root / "loading.json").read_text())
    assert loading["passed"] and loading["defaultPackages"] == ["BVC-Simulator-Core"]
    assert loading["runtimeLoadsBeforeSimulator"] and not loading["directRowanLoadQualified"]
    phases = report["phases"]
    expected_ticks = {"create": 0, "advance": 2, "rollback": 2, "recover-local": 2,
                      "enable-drive": 6, "disable-drive": 6, "obsolete": 6, "external": 6,
                      "prepare": 6, "dispatch": 6, "recover-external": 6, "late-result": 6,
                      "reconcile": 8, "local": 8, "advance10": 10,
                      "uncommitted-1": 10, "uncommitted-2": 11, "advance12": 12, "retention": 12}
    with zipfile.ZipFile(root / "artifacts.zip") as archive:
        for phase, tick in expected_ticks.items():
            assert phases[phase]["passed"]
            expected = hashlib.sha256(archive.read(f"run/oracle-{tick}.canon")).hexdigest()
            assert phases[phase]["view"]["checkpointDigest"] == expected, phase
        assert phases["rollback"]["view"] == phases["advance"]["view"]
        assert phases["late-result"]["view"] == phases["recover-external"]["view"]
        assert phases["recover-external"]["view"]["pending"] == phases["dispatch"]["view"]["pending"]
        assert phases["enable-drive"]["scheduledNativeTransaction"]
        assert phases["external"]["view"]["backend"] == "external"
        assert phases["local"]["view"]["backend"] == "smalltalk"
        assert phases["cleanup"]["fixtureRemoved"]
        assert archive.read("bvc-cli-tests.log").rstrip().endswith(b"OK")
        for name, digest in json.loads((root / "source-sha256.json").read_text()).items():
            assert hashlib.sha256(archive.read("source/" + name)).hexdigest() == digest, name
    assert len(report["conflicts"]) == 4
    for observation in report["conflicts"]:
        assert observation["bodyExecutions"] == 1
        assert observation["committed"] == (observation["role"] == "A")
        if observation["role"] == "B":
            assert observation["writeWriteConflicts"] > 0
    assert any(k.startswith("remove-") and v["state"] == "removed" for k, v in report.items())
    print(json.dumps(dict(passed=True, gtTests=52, nativeTests=43,
                          conflictingWriters=4, checkedFrontiers=len(expected_ticks))))


if __name__ == "__main__":
    main()
