"""Bounded columnar-1 checkpoint / field-delta frames over checkpoint-1 CAS.

Wire layout is independent of VM / rank storage. Every reconstructed entity and
projection bucket must have the sender's exact canonical checkpoint-1 hash.
"""
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("columnar_cas", Path(__file__).with_name("sharded-codec.py"))
cas = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cas)
MAX_ROWS, MAX_UNITS, MAX_WIRE, MAX_RAW = 4096, 128, 131072, 4194304
I64_MIN, I64_MAX = -(1 << 63), (1 << 63) - 1


def require(condition, message="Columnar frame"):
    if not condition:
        raise ValueError(message)


def fields(row):
    return row[1] + row[2] + [row[4], row[6], row[7]] + row[8] + [row[3], row[5]]


def row(identity, values):
    return [identity, values[:3], values[3:6], values[12], values[6], values[13], values[7], values[8], values[9:12]]


def parts(text):
    return [text[i:i+4096] for i in range(0, len(text), 4096)]


def join_parts(value):
    require(type(value) is list and len(value) <= 32)
    require(all(type(part) is str and 1 <= len(part) <= 4096 for part in value))
    return "".join(value)


def wire_fits(value):
    raw = cas.encode(value)
    return len(raw) <= MAX_WIRE and len(raw) + raw.count('"') + raw.count('\\') + 2048 <= 196608


def pack(column, mode, values):
    palette, indices, seen = [], [], {}
    for value in values:
        if value not in seen:
            seen[value] = len(palette)
            palette.append(value)
        indices.append(seen[value])
    if len(palette) == 1:
        return [column, mode, "constant", palette, []]
    if len(palette) <= 256:
        return [column, mode, "palette8", palette, parts(bytes(indices).hex())]
    if column <= 12:
        return [column, mode, "int64", [], parts(b"".join(value.to_bytes(8, "big", signed=True) for value in values).hex())]
    return [column, mode, "text", values, []]


def unpack(packet, count, has_base):
    require(type(packet) is list and len(packet) == 5)
    column, mode, encoding, values, data_parts = packet
    data = join_parts(data_parts)
    require(type(column) is int and 1 <= column <= 14 and mode in ("set", "add"))
    require(mode != "add" or (has_base and column <= 12))
    require(type(values) is list and type(data) is str)
    require(set(data) <= set("0123456789abcdef"))
    numeric = column <= 12
    require(all((type(value) is int and I64_MIN <= value <= I64_MAX) if numeric else
                (type(value) is str and len(value) <= 4096 and all(32 <= ord(c) <= 126 for c in value)) for value in values))
    if encoding == "constant":
        require(len(values) == 1 and data == "")
        result = values * count
    elif encoding == "palette8":
        require(2 <= len(values) <= 256 and len(data) == count * 2 and len(set(values)) == len(values))
        codes = bytes.fromhex(data)
        require(all(code < len(values) for code in codes))
        result = [values[code] for code in codes]
    elif encoding == "int64":
        require(numeric and values == [] and len(data) == count * 16)
        raw = bytes.fromhex(data)
        result = [int.from_bytes(raw[i:i+8], "big", signed=True) for i in range(0, len(raw), 8)]
    else:
        require(encoding == "text" and not numeric and len(values) == count and data == "")
        result = values
    return column, mode, result


def metadata(store, root):
    node = store.get(root)
    require(node["kind"] == "checkpoint" and node["version"] == 1)
    require(store.read_value(node["model"])[0] == "simulation-portable-1/typed-1")
    hashes = {root}
    for key in ("model", "resources", "events", "outcomes"):
        hashes.update(store.closure(node[key]))
    pending = [node["entities"], node["projection"]]
    while pending:
        key = pending.pop()
        hashes.add(key)
        index = store.get(key)
        require(index["kind"] in ("index", "indexBranch"))
        if index["kind"] == "indexBranch":
            pending.extend([index["left"], index["right"]])
    return node, hashes


def plan(store, root, base):
    node, hashes = metadata(store, root)
    entities, poses = store.read_index(node["entities"]), store.read_index(node["projection"])
    require(entities.keys() == poses.keys())
    old_entities, old_poses = {}, {}
    if base is not None:
        before, old_hashes = metadata(store, base)
        require(node["model"] == before["model"] and node["modelDigest"] == before["modelDigest"] and node["seed"] == before["seed"])
        old_entities, old_poses = store.read_index(before["entities"]), store.read_index(before["projection"])
        require(entities.keys() == old_entities.keys() == old_poses.keys())
        hashes -= old_hashes
    units = [[bucket, old_entities.get(bucket), old_poses.get(bucket), entities[bucket], poses[bucket]]
             for bucket in sorted(entities) if entities[bucket] != old_entities.get(bucket) or poses[bucket] != old_poses.get(bucket)]
    return units + sorted(hashes)


def bucket_packet(store, unit):
    bucket, before, old_pose, after, pose = unit
    rows = store.read_rows(after)
    old = store.read_rows(before) if before else None
    keys = sorted(rows)
    require(0 < len(keys) <= MAX_ROWS and (old is None or keys == sorted(old)))
    columns, current, previous = [], [fields(rows[key]) for key in keys], [fields(old[key]) for key in keys] if old is not None else None
    for i in range(14):
        values = [value[i] for value in current]
        if previous is not None and all(value == prior[i] for value, prior in zip(values, previous)):
            continue
        packet = pack(i + 1, "set", values)
        if previous is not None and i < 12:
            deltas = [value - prior[i] for value, prior in zip(values, previous)]
            if all(I64_MIN <= value <= I64_MAX for value in deltas):
                added = pack(i + 1, "add", deltas)
                if len(cas.encode(added)) < len(cas.encode(packet)):
                    packet = added
        columns.append(packet)
    return dict(bucket=bucket, baseEntities=before, baseProjection=old_pose, entities=after, projection=pose,
                count=len(keys), ids=parts("".join(keys)) if old is None else [], columns=columns)


def measure(store, unit):
    if type(unit) is str:
        return 0, len(store.raw(unit))
    seen, pending, rows, raw_bytes = set(), [unit[3], unit[4]], 0, 0
    while pending:
        key = pending.pop()
        if key in seen:
            continue
        seen.add(key)
        raw = store.raw(key)
        node = cas.decode(raw)
        rows += len(node["rows"]) if node["kind"] == "entities" else 0
        raw_bytes += len(raw)
        if rows > MAX_ROWS or raw_bytes > MAX_RAW:
            return rows, raw_bytes
        pending.extend(store.references(node))
    return rows, raw_bytes


def frame(store, root, base, cursor):
    units = plan(store, root, base)
    require(type(cursor) is int and 0 <= cursor <= len(units))
    result = dict(profile="columnar-1", root=root, base=base, cursor=cursor, next=cursor, total=len(units), buckets=[], objects=[])
    rows, raw_bytes = 0, 0
    while result["next"] < len(units) and result["next"] - cursor < MAX_UNITS:
        unit = units[result["next"]]
        count, expanded = measure(store, unit)
        if rows + count > MAX_ROWS or raw_bytes + expanded > MAX_RAW:
            break
        packet = bucket_packet(store, unit) if type(unit) is list else store.objects([unit])[0]
        field = "buckets" if type(unit) is list else "objects"
        result[field].append(packet)
        result["next"] += 1
        if not wire_fits(result):
            result[field].pop()
            result["next"] -= 1
            break
        rows += count
        raw_bytes += expanded
    require(result["next"] > cursor or cursor == len(units), "Columnar bucket exceeds frame budget; use canonical pages")
    return result


class Buffer:
    """Owned scratch store. Canonical objects are verified before bulk mutation."""
    def __init__(self):
        self.objects = {}
        self.byte_count = 0

    def put_raw(self, key, raw):
        require(cas.valid_hash(key) and len(raw) <= cas.PAGE and cas.digest(raw) == key and cas.encode(cas.decode(raw)) == raw)
        if key not in self.objects:
            self.byte_count += len(raw)
            require(self.byte_count <= MAX_RAW)
            self.objects[key] = raw
        return key

    def put(self, node):
        raw = cas.encode(node)
        return self.put_raw(cas.digest(raw), raw)

    rows = cas.Store.rows


def reconstruct(store, payload, expected_base, cursor):
    require(set(payload) == {"profile", "root", "base", "cursor", "next", "total", "buckets", "objects"})
    require(len(cas.encode(payload)) <= MAX_WIRE and payload["profile"] == "columnar-1")
    require(cas.valid_hash(payload["root"]) and payload["base"] == expected_base)
    require(expected_base is None or cas.valid_hash(expected_base))
    require(all(type(payload[key]) is int for key in ("cursor", "next", "total")))
    require(payload["cursor"] == cursor and 0 <= cursor < payload["next"] <= payload["total"] <= 65536 + 256)
    require(type(payload["buckets"]) is list and type(payload["objects"]) is list)
    require(len(payload["buckets"]) + len(payload["objects"]) == payload["next"] - cursor <= MAX_UNITS)
    before = store.get(expected_base) if expected_base else None
    old_entities = store.read_index(before["entities"]) if before else {}
    old_poses = store.read_index(before["projection"]) if before else {}
    scratch, total_rows, seen = Buffer(), 0, set()
    for packet in payload["buckets"]:
        require(set(packet) == {"bucket", "baseEntities", "baseProjection", "entities", "projection", "count", "ids", "columns"})
        bucket, count = packet["bucket"], packet["count"]
        require(type(bucket) is str and len(bucket) == 2 and set(bucket) <= set("0123456789abcdef") and bucket not in seen)
        seen.add(bucket)
        require(type(count) is int and 1 <= count <= MAX_ROWS)
        total_rows += count
        require(total_rows <= MAX_ROWS)
        require(packet["baseEntities"] == old_entities.get(bucket) and packet["baseProjection"] == old_poses.get(bucket))
        if before:
            old = store.read_rows(packet["baseEntities"])
            keys = sorted(old)
            require(len(keys) == count and packet["ids"] == [])
            values = [fields(old[key]) for key in keys]
        else:
            identities = join_parts(packet["ids"])
            require(len(identities) == count * 32)
            keys = [identities[i:i+32] for i in range(0, len(identities), 32)]
            require(keys == sorted(set(keys)))
            values = [[0] * 12 + ["", ""] for key in keys]
        require(all(len(key) == 32 and set(key) <= set("0123456789abcdef") and key.endswith(bucket) for key in keys))
        require(type(packet["columns"]) is list and len(packet["columns"]) <= 14)
        last = 0
        for column in packet["columns"]:
            number, mode, decoded = unpack(column, count, before is not None)
            require(number > last)
            last = number
            for value, delta in zip(values, decoded):
                value[number-1] = value[number-1] + delta if mode == "add" else delta
                if number <= 12:
                    require(type(value[number-1]) is int and I64_MIN <= value[number-1] <= I64_MAX)
        if before is None:
            require([column[0] for column in packet["columns"]] == list(range(1, 15)))
        rows = {key: row(key, value) for key, value in zip(keys, values)}
        require(scratch.rows(rows, bucket) == packet["entities"], "Columnar entity hash")
        require(scratch.rows({key: [value[0], value[1], value[2], value[5]] for key, value in rows.items()}, bucket, True) == packet["projection"], "Columnar projection hash")
    for obj in payload["objects"]:
        require(set(obj) == {"hash", "parts"} and type(obj["parts"]) is list and 1 <= len(obj["parts"]) <= 4)
        require(all(type(part) is str and len(part) <= 4096 for part in obj["parts"]))
        scratch.put_raw(obj["hash"], "".join(obj["parts"]))
    return scratch
