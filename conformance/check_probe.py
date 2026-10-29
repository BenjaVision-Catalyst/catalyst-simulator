#!/usr/bin/env python3
"""Independent integer/ordering oracle for the committed probe fixtures.

Not an execution backend. No Smalltalk parser or source generation is involved.
Run with Python 3: python3 conformance/check_probe.py
"""
import copy
import json
from pathlib import Path


def encode(value):
    if value is None:
        return "n"
    if value is True:
        return "t"
    if value is False:
        return "f"
    if type(value) is int:
        assert -(1 << 63) <= value < (1 << 64)
        return f"i{value};"
    if type(value) is str:
        assert len(value) <= 4096 and all(32 <= ord(c) <= 126 for c in value)
        return f"s{len(value)}:{value}"
    if type(value) is list:
        return f"a{len(value)}:" + "".join(map(encode, value))
    assert type(value) is dict and all(type(k) is str for k in value)
    return f"d{len(value)}:" + "".join(encode(k) + encode(value[k]) for k in sorted(value))


def decode(text):
    pos = 0

    def read():
        nonlocal pos
        tag = text[pos]
        pos += 1
        if tag in "ntf":
            return {"n": None, "t": True, "f": False}[tag]
        delimiter = ";" if tag == "i" else ":"
        end = text.index(delimiter, pos)
        count = int(text[pos:end])
        pos = end + 1
        if tag == "i":
            return count
        if tag == "s":
            value = text[pos:pos + count]
            pos += count
            return value
        if tag == "a":
            return [read() for _ in range(count)]
        assert tag == "d"
        result = {}
        for _ in range(count):
            key = read()
            assert key not in result
            result[key] = read()
        return result

    value = read()
    assert pos == len(text) and encode(value) == text
    return value


MASK = (1 << 32) - 1


def philox(counter, key):
    c, k = list(counter), list(key)
    for _ in range(10):
        p0, p1 = 0xD2511F53 * c[0], 0xCD9E8D57 * c[2]
        c = [((p1 >> 32) ^ c[1] ^ k[0]) & MASK, p1 & MASK,
             ((p0 >> 32) ^ c[3] ^ k[1]) & MASK, p0 & MASK]
        k = [(k[0] + 0x9E3779B9) & MASK, (k[1] + 0xBB67AE85) & MASK]
    return c


def sample(entity, seed, stream, draw):
    e = int(entity, 16)
    return philox([draw, stream, e & MASK, (e >> 32) & MASK],
                  [((e >> 64) & MASK) ^ (seed & MASK),
                   ((e >> 96) & MASK) ^ ((seed >> 32) & MASK)])[0]


def step(accepted):
    state = copy.deepcopy(accepted)
    state["tick"] += 1
    events, generations, sequence, limit = state["events"]
    active = sorted(e for e in events if e[6] == generations[e[5]])
    for event in active:
        if event[0] <= state["tick"]:
            state["entities"][event[3]][5] = event[7]
    state["events"] = [[e for e in active if e[0] > state["tick"]], generations, sequence, limit]
    state["outcomes"] = []
    for entity_id in sorted(state["entities"]):
        e = state["entities"][entity_id]
        for axis in range(3):
            delta, remainder = divmod(e[2][axis] * state["model"][2] + e[8][axis], 1000)
            e[1][axis] += delta
            e[8][axis] = remainder
            assert -(1 << 63) <= e[1][axis] < (1 << 63)
        resource, requested = e[3], e[4]
        if requested and state["resources"][resource] >= requested:
            state["resources"][resource] -= requested
            e[4] = 0
            state["outcomes"].append([state["tick"], resource, entity_id, requested])
        e[7] = sample(entity_id, state["seed"], 0, e[6])
        e[6] += 1
        assert e[6] <= MASK
    return state


def main():
    root = Path(__file__).resolve().parents[1]
    fixture = json.loads((root / "contracts/probe-1/fixtures.json").read_text())
    assert philox([0] * 4, [0] * 2) == [0x6627E8D5, 0xE169C58D, 0xBC57AC4C, 0x9B00DBD8]
    assert philox([MASK] * 4, [MASK] * 2) == [0x408F276D, 0x41C83B0E, 0xA20BC7C6, 0x6D5451FD]
    assert philox([0x243F6A88, 0x85A308D3, 0x13198A2E, 0x03707344], [0xA4093822, 0x299F31D0]) == [0xD16CFE09, 0x94FDCCEB, 0x5001E420, 0x24126EA1]
    assert sample("0123456789abcdeffedcba9876543210", 0xFEDCBA9876543210, 0x13579BDF, 0x2468ACE0) == 697764476
    state = decode(fixture["initial"])
    assert state["tick"] == 0 and state["seed"] == 42
    checkpoints = fixture["checkpoints"]
    for tick in range(1, max(map(int, checkpoints)) + 1):
        state = step(state)
        if str(tick) in checkpoints:
            assert encode(state) == checkpoints[str(tick)], f"Checkpoint mismatch at tick {tick}"
            assert decode(checkpoints[str(tick)]) == state
    assert state["resources"] == {"charge": 1}
    assert state["entities"]["0" * 31 + "1"][5] == "ready"
    print(json.dumps({"oracle": "Python integer/ordering reference", "philoxKnownAnswers": 3,
                      "canonicalCheckpoints": 1 + len(checkpoints), "passed": True}))


if __name__ == "__main__":
    main()
