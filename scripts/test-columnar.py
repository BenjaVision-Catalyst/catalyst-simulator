#!/usr/bin/env python3
"""Columnar codec, bounded durability and GT/Python wire conformance checks."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import sys

spec = importlib.util.spec_from_file_location("columnar", Path(__file__).with_name("columnar-codec.py"))
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)
WIRE = Path(sys.argv.pop(1)) if len(sys.argv) > 1 and not sys.argv[1].startswith("-") else None
ALL_FIELDS = Path(sys.argv.pop(1)) if len(sys.argv) > 1 and not sys.argv[1].startswith("-") else None


class ColumnarTests(unittest.TestCase):
    def test_integer_encodings(self):
        for values in ([0] * 3, [1, -2, 1], [c.I64_MIN, c.I64_MAX] + list(range(257))):
            packet = c.pack(1, "set", values)
            self.assertEqual(c.unpack(packet, len(values), False)[2], values)

    def test_label_encodings(self):
        for values in (["neutral"] * 3, ["", "a", ""], [str(i) for i in range(257)]):
            packet = c.pack(14, "set", values)
            self.assertEqual(c.unpack(packet, len(values), False)[2], values)

    def test_atom_parts_and_json_budget(self):
        packet = c.pack(1, "set", list(range(600)))
        self.assertGreater(len(packet[4]), 1)
        self.assertEqual(c.cas.decode(c.cas.encode(packet)), packet)
        with self.assertRaises(ValueError):
            c.join_parts(["0" * 4097])
        self.assertFalse(c.wire_fits(['"' * 4096] * 25))
        self.assertTrue(c.wire_fits(['"' * 4096] * 20))

    def test_reject_invalid_columns(self):
        for packet, count, base in [
            ([1, "add", "constant", [1], []], 1, False),
            ([1, "set", "palette8", [0, 1], ["ff"]], 1, False),
            ([1, "set", "palette8", [0, 0], ["00"]], 1, False),
            ([1, "set", "int64", [], ["00"]], 1, False),
            ([1, "set", "constant", [True], []], 1, False),
            ([14, "add", "constant", ["a"], []], 1, True),
            ([14, "set", "constant", ["\n"], []], 1, False),
            ([15, "set", "constant", [0], []], 1, False),
        ]:
            with self.subTest(packet=packet), self.assertRaises(ValueError):
                c.unpack(packet, count, base)

    def test_bulk_preflight(self):
        with tempfile.TemporaryDirectory() as directory:
            store = c.cas.Store(directory)
            raw = c.cas.encode(dict(kind="value", value=42))
            with self.assertRaises(AssertionError):
                store.put_many_raw({c.cas.digest(raw): raw, "0"*64: raw})
            self.assertEqual(list(Path(directory).iterdir()), [])
            store.put_many_raw({c.cas.digest(raw): raw})
            store.put_many_raw({c.cas.digest(raw): raw})
            self.assertEqual(store.get(c.cas.digest(raw))["value"], 42)

    def test_interrupted_bulk_replay(self):
        with tempfile.TemporaryDirectory() as directory:
            store = c.cas.Store(directory)
            objects = {}
            for value in range(3):
                raw = c.cas.encode(dict(kind="value", value=value))
                objects[c.cas.digest(raw)] = raw
            fsync = c.cas.os.fsync
            calls = 0
            def interrupted(descriptor):
                nonlocal calls
                calls += 1
                if calls == 2:
                    raise OSError("injected frame interruption")
                fsync(descriptor)
            with patch.object(c.cas.os, "fsync", interrupted), self.assertRaises(OSError):
                store.put_many_raw(objects)
            self.assertEqual(len(list(Path(directory).glob("*.canon"))), 1)
            store.put_many_raw(objects)
            self.assertEqual({key: store.raw(key) for key in objects}, objects)

    @unittest.skipUnless(WIRE, "Pass the GT-produced gt-wire.json fixture")
    def test_gt_frames_and_roots(self):
        fixture = json.loads(WIRE.read_text())
        with tempfile.TemporaryDirectory() as directory:
            source, target = c.cas.Store(Path(directory)/"source"), c.cas.Store(Path(directory)/"target")
            for obj in fixture["objects"]:
                source.put_raw(obj["hash"], "".join(obj["parts"]))
            for frame in fixture["frames"]:
                self.assertEqual(c.frame(source, frame["root"], frame["base"], frame["cursor"]), frame)
                scratch = c.reconstruct(target, frame, frame["base"], frame["cursor"])
                target.put_many_raw(scratch.objects)
            self.assertEqual(target.materialize(fixture["target"]), source.materialize(fixture["target"]))
            self.assertEqual(source.closure(fixture["target"]), target.closure(fixture["target"]))
            frames = fixture["frames"]
            self.assertLess(sum(len(c.cas.encode(f)) for f in frames if f["base"]), sum(len(c.cas.encode(f)) for f in frames if not f["base"]))
            # Every malformed frame is decoded into scratch before the target is mutated.
            frame = next(f for f in frames if f["base"] and f["buckets"])
            baseline = sorted(path.name for path in target.directory.iterdir())
            for mutation in ("projection", "cursor", "base", "count", "column", "overflow", "ids"):
                bad = copy.deepcopy(frame)
                packet = bad["buckets"][0]
                if mutation == "projection": packet["projection"] = "0" * 64
                elif mutation == "cursor": bad["cursor"] += 1
                elif mutation == "base": bad["base"] = fixture["target"]
                elif mutation == "count": packet["count"] = 4097
                elif mutation == "column": packet["columns"] *= 2
                elif mutation == "overflow": packet["columns"] = [[1, "add", "constant", [c.I64_MIN], []]]
                elif mutation == "ids": packet["ids"] = "0"*32
                with self.subTest(mutation=mutation), self.assertRaises((ValueError, AssertionError)):
                    c.reconstruct(target, bad, frame["base"], frame["cursor"])
                self.assertEqual(sorted(path.name for path in target.directory.iterdir()), baseline)

    @unittest.skipUnless(WIRE, "Pass the GT-produced gt-wire.json fixture")
    def test_transport_full_offer_and_delta_fetch(self):
        spec = importlib.util.spec_from_file_location("sharded_transport", Path(__file__).with_name("repast-sharded.py"))
        transport = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(transport)
        fixture = json.loads(WIRE.read_text())
        with tempfile.TemporaryDirectory() as directory:
            spool = Path(directory)
            (spool / "identity").write_text(transport.MARKER)
            for name in ("objects", "control", "jobs", "sessions", "placements"):
                (spool/name).mkdir()
            for frame in fixture["frames"]:
                if frame["base"] is None:
                    request = dict(action="putColumnar", frame=frame)
                    reply = transport.handle(spool, request)
                    self.assertEqual(reply["next"], frame["next"])
                    # Replaying any complete frame is idempotent, including after
                    # loss of the sender's activation-local transfer cursor.
                    self.assertEqual(transport.handle(spool, request), reply)
            store = c.cas.Store(spool/"objects")
            for obj in fixture["objects"]:
                store.put_raw(obj["hash"], "".join(obj["parts"]))
            for frame in fixture["frames"]:
                if frame["base"]:
                    reply = transport.handle(spool, dict(action="getColumnar", root=frame["root"], base=frame["base"], cursor=frame["cursor"]))
                    self.assertEqual(reply, dict(state="frame", frame=frame))
                    self.assertLessEqual(len(json.dumps(reply, separators=(",", ":"))), 196608)
            before = sorted(path.name for path in store.directory.iterdir())
            bad = copy.deepcopy(fixture["frames"][0])
            bad["buckets"][-1]["projection"] = "0" * 64
            with self.assertRaises(ValueError):
                transport.handle(spool, dict(action="putColumnar", frame=bad))
            self.assertEqual(sorted(path.name for path in store.directory.iterdir()), before)

    @unittest.skipUnless(WIRE, "Pass the GT-produced gt-wire.json fixture")
    def test_expansion_budget_fallback_and_atomic_rejection(self):
        fixture = json.loads(WIRE.read_text())
        with tempfile.TemporaryDirectory() as directory:
            store = c.cas.Store(directory)
            for obj in fixture["objects"]:
                store.put_raw(obj["hash"], "".join(obj["parts"]))
            state = store.materialize(fixture["initial"])
            for value in state["entities"].values():
                value[5] = "X" * 4096
            state["tick"] = 1
            root = store.checkpoint(state)
            unit = c.plan(store, root, fixture["initial"])[0]
            self.assertGreater(c.measure(store, unit)[1], c.MAX_RAW)
            with self.assertRaisesRegex(ValueError, "Columnar bucket exceeds frame budget"):
                c.frame(store, root, fixture["initial"], 0)
            frame = dict(profile="columnar-1", root=root, base=fixture["initial"], cursor=0, next=1, total=1,
                         buckets=[c.bucket_packet(store, unit)], objects=[])
            before = sorted(path.name for path in store.directory.iterdir())
            with self.assertRaises(ValueError):
                c.reconstruct(store, frame, fixture["initial"], 0)
            self.assertEqual(sorted(path.name for path in store.directory.iterdir()), before)

    @unittest.skipUnless(ALL_FIELDS, "Pass the additional GT all-fields fixture")
    def test_all_fields_gt_interoperability(self):
        fixture = json.loads(ALL_FIELDS.read_text())
        self.assertTrue(fixture["passed"])
        self.assertEqual(fixture["fields"], 14)
        with tempfile.TemporaryDirectory() as directory:
            source, target = c.cas.Store(Path(directory)/"source"), c.cas.Store(Path(directory)/"target")
            for obj in fixture["objects"]:
                source.put_raw(obj["hash"], "".join(obj["parts"]))
            for frame in fixture["frames"]:
                self.assertEqual(c.frame(source, frame["root"], frame["base"], frame["cursor"]), frame)
                scratch = c.reconstruct(target, frame, frame["base"], frame["cursor"])
                target.put_many_raw(scratch.objects)
            self.assertEqual(target.materialize(fixture["target"]), source.materialize(fixture["target"]))
            state = target.materialize(fixture["target"])
            first, second = [state["entities"][key] for key in sorted(state["entities"])[:2]]
            self.assertEqual([first[1][0], second[1][0]], [c.I64_MAX, c.I64_MIN])
            self.assertEqual(first[6], (1 << 32)-1)
            self.assertEqual(first[7], 0)
            self.assertEqual(state["seed"], (1 << 64)-1)


if __name__ == "__main__":
    unittest.main()
