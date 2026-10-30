#!/usr/bin/env python3
"""Resident transport boundaries without native process allocation."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
module = importlib.util.spec_from_file_location("resident", HERE / "repast-resident.py")
resident = importlib.util.module_from_spec(module)
module.loader.exec_module(resident)


class ResidentTransportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.spool = Path(self.temporary.name)
        for name in ("sessions", "jobs", "placements"):
            (self.spool / name).mkdir()
        (self.spool / "identity").write_text(resident.MARKER)
        fixture = json.loads((HERE.parent / "contracts/graph-1/fixtures.json").read_text())
        checkpoint = resident.decode(fixture["models"][0]["initial"])
        b = dict(version=1, world="0" * 32, group="1" * 32, generation=1, owner="2" * 32,
                 modelDigest=checkpoint["modelDigest"], batch="a" * 64, inputDigest="a" * 64,
                 checkpointDigest=resident.digest(resident.encode(checkpoint)), fromTick=0, targetTick=1)
        self.request = dict(action="ensure", spec=dict(binding=b, checkpoint=checkpoint, registry=fixture["registry"]),
                            executable="/usr/bin/true", mpi="/usr/bin/true", ranks=2, acceptedRevision=1)
        self.session = self.spool / "sessions" / resident.session_key(b)
        self.job = self.spool / "jobs" / b["batch"]

    def call(self):
        return resident.handle(self.spool, self.request)

    def test_multiple_windows_share_one_claimed_session(self):
        with patch.object(resident.subprocess, "Popen") as launch:
            self.assertEqual(self.call()["state"], "uncertain")
            self.assertEqual(self.call()["state"], "uncertain")
            self.request["spec"]["binding"].update(batch="b" * 64, inputDigest="b" * 64, targetTick=2)
            self.assertEqual(self.call()["state"], "uncertain")
            self.assertEqual(launch.call_count, 1)
        self.assertEqual(len(list((self.spool / "sessions").iterdir())), 1)

    def test_recovery_query_missing_never_creates_a_session(self):
        self.request["action"] = "query"
        with patch.object(resident.subprocess, "Popen") as launch:
            self.assertEqual(self.call()["state"], "missing")
            launch.assert_not_called()
        self.assertFalse(self.session.exists())

    def test_incomplete_session_claim_is_never_relaunched(self):
        self.session.mkdir()
        with patch.object(resident.subprocess, "Popen") as launch:
            self.assertEqual(self.call()["state"], "unknown")
            launch.assert_not_called()

    def test_failed_incarnation_is_not_relaunched(self):
        with patch.object(resident.subprocess, "Popen"):
            self.call()
        resident.publish(self.session / "finished.json", dict(nativeReaped=True))
        with patch.object(resident.subprocess, "Popen") as launch:
            self.assertEqual(self.call()["state"], "failed")
            launch.assert_not_called()

    def test_retire_waits_for_native_reaping(self):
        with patch.object(resident.subprocess, "Popen"):
            self.call()
        self.request["action"] = "retire"
        self.request["spec"]["binding"]["generation"] = 2
        self.assertEqual(self.call()["state"], "retiring")
        self.assertTrue((self.session / "stop").exists())
        resident.publish(self.session / "finished.json", dict(nativeReaped=True))
        self.assertEqual(self.call()["state"], "retired")

    def test_new_generation_waits_for_previous_incarnation_to_stop(self):
        with patch.object(resident.subprocess, "Popen"):
            self.call()
        self.request["action"] = "synchronize"
        self.request["spec"]["binding"]["generation"] = 2
        with patch.object(resident.subprocess, "Popen") as launch:
            self.assertEqual(self.call()["state"], "retiring")
            launch.assert_not_called()

    def test_idle_synchronization_has_no_batch_claim(self):
        self.request["action"] = "synchronize"
        with patch.object(resident.subprocess, "Popen"):
            self.assertEqual(self.call()["state"], "resident")
        self.assertEqual(read := resident.read(self.session / "accepted.json"),
                         dict(checkpointDigest=self.request["spec"]["binding"]["checkpointDigest"], revision=1))
        self.assertFalse(self.job.exists())

    def test_binding_reuse_and_result_corruption_are_rejected(self):
        with patch.object(resident.subprocess, "Popen"):
            self.call()
        altered = copy.deepcopy(self.request)
        altered["spec"]["binding"]["owner"] = "3" * 32
        with self.assertRaises(ValueError):
            resident.handle(self.spool, altered)
        resident.publish(self.job / "result.json", dict(state="complete", binding=self.request["spec"]["binding"], checkpointDigest="0" * 64))
        (self.job / "result.canon").write_text("n")
        with self.assertRaises(ValueError):
            self.call()

    def test_spool_loss_fails_closed(self):
        (self.spool / "identity").unlink()
        with self.assertRaises(FileNotFoundError):
            self.call()

    def test_stale_retirement_cannot_stop_newer_incarnation(self):
        self.request["action"] = "synchronize"
        self.request["spec"]["binding"]["generation"] = 2
        current = self.spool / "sessions" / resident.session_key(self.request["spec"]["binding"])
        with patch.object(resident.subprocess, "Popen"):
            self.call()
        self.request["action"] = "retire"
        self.request["spec"]["binding"]["generation"] = 1
        self.assertEqual(self.call()["state"], "fenced")
        self.assertFalse((current / "stop").exists())

    def test_stale_first_launch_is_blocked_after_local_retirement(self):
        self.request["action"] = "retire"
        self.request["spec"]["binding"]["generation"] = 2
        self.assertEqual(self.call()["state"], "retired")
        self.request["action"] = "ensure"
        self.request["spec"]["binding"]["generation"] = 1
        with patch.object(resident.subprocess, "Popen") as launch:
            self.assertEqual(self.call()["state"], "fenced")
            launch.assert_not_called()

    def test_native_controller_requires_its_own_lease(self):
        output = self.spool / 'unstarted'
        result = subprocess.run([sys.executable, str(HERE / 'qualify-resident-repast.py'),
            '--project', str(self.spool), '--bvc', '/usr/bin/false', '--executable', '/usr/bin/false',
            '--output', str(output), '--lease-release', str(self.spool / 'release')], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
