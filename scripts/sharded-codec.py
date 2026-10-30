"""checkpoint-1 content-addressed pages shared by transport and conformance.

Objects are canonical ASCII, <=16 KiB, addressed by SHA-256. Entity/projection
tries use ID suffixes, independently of execution rank or spatial ownership.
"""
import hashlib
import os
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "conformance"))
from check_probe import encode, decode

PAGE = 16384


def digest(raw):
    return hashlib.sha256(raw.encode("ascii")).hexdigest()


def valid_hash(value):
    return type(value) is str and len(value) == 64 and set(value) <= set("0123456789abcdef")


class Store:
    def __init__(self, directory):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)

    def raw(self, key):
        assert valid_hash(key)
        raw = (self.directory / (key + ".canon")).read_text()
        assert len(raw) <= PAGE and digest(raw) == key
        return raw

    def get(self, key):
        return decode(self.raw(key))

    def put_raw(self, key, raw):
        assert valid_hash(key) and len(raw) <= PAGE and digest(raw) == key
        assert encode(decode(raw)) == raw
        path = self.directory / (key + ".canon")
        if path.exists():
            assert path.read_text() == raw
            return key
        temporary = self.directory / (key + "." + str(os.getpid()) + ".tmp")
        with temporary.open("w") as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        descriptor = os.open(self.directory, os.O_RDONLY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        return key

    def put(self, node):
        raw = encode(node)
        return self.put_raw(digest(raw), raw)

    def value(self, value):
        leaf = dict(kind="value", value=value)
        if len(encode(leaf)) <= PAGE:
            return self.put(leaf)
        if type(value) is list:
            if len(value) == 1:
                return self.put(dict(kind="item", value=self.value(value[0])))
            middle = len(value) // 2
            return self.put(dict(kind="array", left=self.value(value[:middle]), right=self.value(value[middle:])))
        assert type(value) is dict and value
        keys = sorted(value)
        if len(keys) == 1:
            return self.put(dict(kind="entry", key=keys[0], value=self.value(value[keys[0]])))
        middle = len(keys) // 2
        return self.put(dict(kind="map", left=self.value({k: value[k] for k in keys[:middle]}),
                             right=self.value({k: value[k] for k in keys[middle:]})))

    def read_value(self, key):
        node = self.get(key)
        kind = node["kind"]
        if kind == "value":
            return node["value"]
        if kind == "item":
            return [self.read_value(node["value"])]
        if kind == "entry":
            return {node["key"]: self.read_value(node["value"])}
        left, right = self.read_value(node["left"]), self.read_value(node["right"])
        if kind == "array":
            return left + right
        assert kind == "map" and not (set(left) & set(right))
        return dict(left, **right)

    def index(self, entries):
        leaf = dict(kind="index", entries=entries)
        if len(encode(leaf)) <= PAGE:
            return self.put(leaf)
        keys = sorted(entries)
        middle = len(keys) // 2
        return self.put(dict(kind="indexBranch", left=self.index({k: entries[k] for k in keys[:middle]}),
                             right=self.index({k: entries[k] for k in keys[middle:]})))

    def read_index(self, key):
        node = self.get(key)
        if node["kind"] == "index":
            return node["entries"]
        assert node["kind"] == "indexBranch"
        left, right = self.read_index(node["left"]), self.read_index(node["right"])
        assert not (set(left) & set(right))
        return dict(left, **right)

    def rows(self, rows, suffix, projection=False):
        kind = "projection" if projection else "entities"
        leaf = dict(kind=kind, suffix=suffix, rows=rows)
        if len(rows) <= 128 and len(encode(leaf)) <= PAGE:
            return self.put(leaf)
        assert len(suffix) < 32
        children = {}
        for digit in "0123456789abcdef":
            selected = {k: value for k, value in rows.items() if k.endswith(digit + suffix)}
            if selected:
                children[digit] = self.rows(selected, digit + suffix, projection)
        return self.put(dict(kind=kind + "Branch", suffix=suffix, children=children))

    def read_rows(self, key):
        node = self.get(key)
        if "rows" in node:
            return node["rows"]
        result = {}
        for child in node["children"].values():
            rows = self.read_rows(child)
            assert not (set(result) & set(rows))
            result.update(rows)
        return result

    def checkpoint(self, checkpoint):
        entities, projection = {}, {}
        for bucket in sorted({key[-2:] for key in checkpoint["entities"]}):
            rows = {key: value for key, value in checkpoint["entities"].items() if key.endswith(bucket)}
            entities[bucket] = self.rows(rows, bucket)
            projection[bucket] = self.rows({key: [row[0], row[1], row[2], row[5]] for key, row in rows.items()}, bucket, True)
        return self.put(dict(kind="checkpoint", version=1, model=self.value(checkpoint["model"]),
                             modelDigest=checkpoint["modelDigest"], tick=checkpoint["tick"], seed=checkpoint["seed"],
                             entities=self.index(entities), projection=self.index(projection), entityCount=len(checkpoint["entities"]),
                             resources=self.value(checkpoint["resources"]), events=self.value(checkpoint["events"]),
                             outcomes=self.value(checkpoint["outcomes"])))

    def materialize(self, key):
        node = self.get(key)
        assert node["kind"] == "checkpoint" and node["version"] == 1
        entities = {}
        for root in self.read_index(node["entities"]).values():
            entities.update(self.read_rows(root))
        assert len(entities) == node["entityCount"]
        return dict(version=2, model=self.read_value(node["model"]), modelDigest=node["modelDigest"], tick=node["tick"], seed=node["seed"],
                    entities=entities, resources=self.read_value(node["resources"]), events=self.read_value(node["events"]),
                    outcomes=self.read_value(node["outcomes"]))

    def references(self, node):
        kind = node["kind"]
        if kind in ("array", "map", "indexBranch"):
            return [node["left"], node["right"]]
        if kind in ("item", "entry"):
            return [node["value"]]
        if kind.endswith("Branch"):
            return list(node["children"].values())
        if kind == "index":
            return list(node["entries"].values())
        if kind == "checkpoint":
            return [node[field] for field in ("model", "entities", "projection", "resources", "events", "outcomes")]
        return []

    def closure(self, root):
        seen, pending = set(), [root]
        while pending:
            key = pending.pop()
            if key not in seen:
                seen.add(key)
                pending.extend(self.references(self.get(key)))
        return seen

    def objects(self, hashes):
        return [dict(hash=key, parts=[raw[i:i + 4096] for i in range(0, len(raw), 4096)])
                for key in hashes for raw in [self.raw(key)]]
