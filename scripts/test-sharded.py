#!/usr/bin/env python3
"""Artifact/transport integrity without allocating native simulator processes."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("sharded", HERE / "repast-sharded.py")
sharded = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sharded)


class ShardedTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.spool = Path(self.temporary.name)
        for name in ("objects", "control", "sessions", "jobs", "placements"):
            (self.spool / name).mkdir()
        (self.spool / "identity").write_text(sharded.MARKER)
        fixtures = json.loads((HERE.parent / "conformance/results/repast-p2-macos-2026-10-30/fixtures.json").read_text())["cases"]
        self.sample = next(case for case in fixtures if case["name"] == "conditional-graph")
        self.checkpoint = sharded.decode(self.sample["initial"])
        self.store = sharded.codec.Store(self.spool / "objects")
        self.root = self.store.checkpoint(self.checkpoint)
        b = dict(version=1, world="0" * 32, group="1" * 32, generation=1, owner="2" * 32,
                 modelDigest=self.checkpoint["modelDigest"], checkpointDigest=self.root,
                 fromTick=0, targetTick=1, batch="a" * 64, inputDigest="a" * 64)
        self.request = dict(action="ensure", spec=dict(root=self.root, binding=b), ranks=2,
                            executable="/usr/bin/true", mpi="/usr/bin/true", acceptedRevision=1)

    def test_gt_canonical_root_and_round_trip(self):
        self.assertEqual(self.root, "589473510e942cb810d309c34d0c3c5412e83f5c52f9946a5154762a3ce0f93f")
        self.assertEqual(self.store.materialize(self.root), self.checkpoint)
        self.assertTrue(all(len(self.store.raw(key)) <= 16384 for key in self.store.closure(self.root)))

    def test_metadata_splits_and_nested_single_entry(self):
        value = dict(single=[["x" * 100 for _ in range(500)]])
        root = self.store.value(value)
        self.assertEqual(self.store.read_value(root), value)

    def test_projection_reuses_pages_when_only_random_counter_changes(self):
        old = self.store.get(self.root)
        changed = copy.deepcopy(self.checkpoint)
        next(iter(changed["entities"].values()))[6] += 1
        root = self.store.checkpoint(changed)
        self.assertNotEqual(root, self.root)
        self.assertEqual(self.store.get(root)["projection"], old["projection"])

    def test_incremental_import_and_missing_child(self):
        target = sharded.codec.Store(self.spool / "other")
        self.assertEqual(sharded.missing(target, self.root, 4), [self.root])
        target.put_raw(self.root, self.store.raw(self.root))
        self.assertTrue(sharded.missing(target, self.root, 4))
        while needed := sharded.missing(target, self.root, 4):
            for key in needed:
                target.put_raw(key, self.store.raw(key))
        self.assertEqual(target.materialize(self.root), self.checkpoint)

    def test_corruption_never_overwrites_a_content_address(self):
        before = self.store.raw(self.root)
        with self.assertRaises(AssertionError):
            self.store.put_raw(self.root, "n")
        self.assertEqual(self.store.raw(self.root), before)
        (self.store.directory / (self.root + ".canon")).write_text("n")
        with self.assertRaises(AssertionError):
            self.store.get(self.root)

    def test_availability_reuses_closed_subtrees_across_process_calls(self):
        path = self.spool / "availability.sqlite3"
        with sharded.codec.Availability(path) as available:
            self.assertEqual(available.missing(self.store, self.root, 32), [])
            self.assertGreater(available.stats["readObjects"], 0)
        with sharded.codec.Availability(path) as available:
            self.assertEqual(available.missing(self.store, self.root, 32), [])
            self.assertEqual(available.stats["readObjects"], 0)
        path.unlink()
        with sharded.codec.Availability(path) as available:
            self.assertEqual(available.missing(self.store, self.root, 32), [])
            self.assertGreater(available.stats["readObjects"], 0)

    def test_availability_does_not_cache_absence_or_hide_corrupt_reads(self):
        target = sharded.codec.Store(self.spool / "import")
        path = self.spool / "availability.sqlite3"
        with sharded.codec.Availability(path) as available:
            self.assertEqual(available.missing(target, self.root, 32), [self.root])
        for key in self.store.closure(self.root):
            target.put_raw(key, self.store.raw(key))
        with sharded.codec.Availability(path) as available:
            self.assertEqual(available.missing(target, self.root, 32), [])
        (target.directory / (self.root + ".canon")).write_text("n")
        with self.assertRaises(AssertionError):
            target.get(self.root)

    def test_cached_subtree_height_still_enforces_the_whole_path_limit(self):
        leaf = self.store.value([])
        root = leaf
        for _ in range(64):
            root = self.store.put(dict(kind="array", left=root, right=leaf))
        path = self.spool / "availability.sqlite3"
        with sharded.codec.Availability(path) as available:
            self.assertEqual(available.missing(self.store, root, 32), [])
        parent = self.store.put(dict(kind="array", left=root, right=leaf))
        with self.assertRaises(AssertionError):
            with sharded.codec.Availability(path) as available:
                available.missing(self.store, parent, 32)

    def test_artifact_fetch_and_offer_budgets(self):
        with self.assertRaises(ValueError):
            sharded.handle(self.spool, dict(action="getObjects", hashes=[self.root] * 5))
        result = sharded.handle(self.spool, dict(action="getObjects", hashes=[self.root]))
        self.assertEqual(result["objects"][0]["hash"], self.root)
        self.assertLessEqual(len(json.dumps(result)), 196608)

    def test_query_never_launches_or_replays(self):
        self.request["action"] = "query"
        with patch.object(sharded.subprocess, "Popen") as launch:
            self.assertEqual(sharded.handle(self.spool, self.request)["state"], "missing")
            launch.assert_not_called()
        self.assertFalse(list((self.spool / "sessions").iterdir()))

    def test_large_fetch_is_shortened_to_the_wire_byte_budget(self):
        keys = [self.store.value([str(i), '"' * 4096, '"' * 4096, '"' * 4096]) for i in range(32)]
        result = sharded.handle(self.spool, dict(action="getObjects", hashes=keys))
        self.assertGreater(len(result["objects"]), 0)
        self.assertLess(len(result["objects"]), len(keys))
        self.assertLessEqual(len(json.dumps(result, separators=(",", ":"))), 160000)
        self.assertEqual([obj["hash"] for obj in result["objects"]], keys[:len(result["objects"])])

    def test_offer_rejects_oversized_control_before_writing(self):
        objects = self.store.objects([self.root]) * 32
        objects[0]["parts"] = ['"' * 4096] * 4
        with self.assertRaises(ValueError):
            sharded.handle(self.spool, dict(action="putObjects", objects=objects))

    def test_repeated_windows_reuse_the_claimed_incarnation(self):
        with patch.object(sharded.subprocess, "Popen") as launch:
            self.assertEqual(sharded.handle(self.spool, self.request)["state"], "uncertain")
            self.request["spec"]["binding"].update(batch="b" * 64, inputDigest="b" * 64, targetTick=2)
            sharded.handle(self.spool, self.request)
            self.assertEqual(launch.call_count, 1)
        self.assertLess(len(sharded.encode(self.request)), 2048)
        self.assertNotIn("checkpoint", self.request["spec"])

    def test_old_generation_cannot_retire_or_launch_newer_workers(self):
        self.request["action"] = "synchronize"
        self.request["spec"]["binding"]["generation"] = 2
        with patch.object(sharded.subprocess, "Popen"):
            sharded.handle(self.spool, self.request)
        current = self.spool / "sessions" / sharded.session_key(self.request["spec"]["binding"])
        self.request["spec"]["binding"]["generation"] = 1
        for action in ("retire", "ensure"):
            self.request["action"] = action
            with patch.object(sharded.subprocess, "Popen") as launch:
                self.assertEqual(sharded.handle(self.spool, self.request)["state"], "fenced")
                launch.assert_not_called()
        self.assertFalse((current / "stop").exists())

    def test_request_file_is_consumed_without_native_processes(self):
        path = self.spool / "control/test.json"
        path.write_text(json.dumps(dict(action="getObjects", hashes=[self.root])))
        result = subprocess.run([sys.executable, str(HERE / "repast-sharded.py"), "--spool", str(self.spool), "--request-file", str(path)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(path.exists())
        self.assertEqual(json.loads(result.stdout)["objects"][0]["hash"], self.root)

    def test_spool_loss_fails_closed(self):
        (self.spool / "identity").unlink()
        with self.assertRaises(FileNotFoundError):
            sharded.handle(self.spool, self.request)

    def test_controller_refuses_native_work_without_its_own_lease(self):
        for script in ("qualify-sharded.py", "qualify-typed.py"):
            output = self.spool / (script + "-not-started")
            result = subprocess.run([sys.executable, str(HERE / script), "--project", str(self.spool),
                "--bvc", "/usr/bin/false", "--executable", "/usr/bin/false", "--fixtures", str(self.spool),
                "--output", str(output), "--lease-release", str(self.spool / "release")], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
