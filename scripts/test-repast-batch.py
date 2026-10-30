#!/usr/bin/env python3
"""Transport failure semantics, without launching MPI."""
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
module = importlib.util.spec_from_file_location("batch", HERE / "repast-batch.py")
batch = importlib.util.module_from_spec(module)
module.loader.exec_module(batch)


class TransportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.spool = Path(self.temporary.name)
        (self.spool / "identity").write_text(batch.MARKER)
        fixture = json.loads((HERE.parent / "contracts/graph-1/fixtures.json").read_text())
        checkpoint = batch.decode(fixture["models"][0]["initial"])
        binding = dict(version=1, world="0" * 32, group="1" * 32, generation=1, owner="2" * 32,
                       modelDigest=checkpoint["modelDigest"], batch="a" * 64, inputDigest="a" * 64,
                       checkpointDigest=batch.digest(batch.encode(checkpoint)), fromTick=0, targetTick=1)
        self.spec = dict(binding=binding, checkpoint=checkpoint, registry=fixture["registry"])
        self.request = dict(action="ensure", spec=self.spec, executable="/usr/bin/true", mpi="/usr/bin/true", ranks=1)
        self.job = self.spool / binding["batch"]

    def test_duplicate_ensure_claims_once(self):
        with patch.object(batch.subprocess, "Popen") as launch:
            self.assertEqual(batch.handle(self.spool, self.request)["state"], "uncertain")
            self.assertEqual(batch.handle(self.spool, self.request)["state"], "uncertain")
            self.assertEqual(launch.call_count, 1)

    def test_query_never_launches_missing_job(self):
        self.request["action"] = "query"
        with patch.object(batch.subprocess, "Popen") as launch:
            self.assertEqual(batch.handle(self.spool, self.request)["state"], "missing")
            launch.assert_not_called()
        self.assertFalse(self.job.exists())

    def test_claim_crash_is_unknown_and_never_replayed(self):
        self.job.mkdir()
        with patch.object(batch.subprocess, "Popen") as launch:
            self.assertEqual(batch.handle(self.spool, self.request)["state"], "unknown")
            launch.assert_not_called()

    def test_job_identity_cannot_be_reused(self):
        with patch.object(batch.subprocess, "Popen"):
            batch.handle(self.spool, self.request)
        self.request["spec"] = copy.deepcopy(self.spec)
        self.request["spec"]["binding"]["generation"] += 1
        with self.assertRaises(AssertionError):
            batch.handle(self.spool, self.request)

    def test_checksum_corruption_rejects_result(self):
        with patch.object(batch.subprocess, "Popen"):
            batch.handle(self.spool, self.request)
        (self.job / "result.canon").write_text("n")
        batch.publish(self.job / "result.json", dict(state="complete", binding=self.spec["binding"], checkpointDigest="0" * 64))
        with self.assertRaises(AssertionError):
            batch.handle(self.spool, self.request)

    def test_lost_spool_cannot_initialize_itself(self):
        (self.spool / "identity").unlink()
        with self.assertRaises(FileNotFoundError):
            batch.handle(self.spool, self.request)

    def test_controller_requires_its_own_active_lease_before_topaz(self):
        output = self.spool / 'unstarted'
        result = subprocess.run([sys.executable, str(HERE / 'qualify-live-repast.py'),
            '--project', str(self.spool), '--bvc', '/usr/bin/false', '--executable', '/usr/bin/false',
            '--output', str(output), '--lease-release', str(self.spool / 'release')], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
