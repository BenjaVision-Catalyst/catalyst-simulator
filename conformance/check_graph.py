#!/usr/bin/env python3
"""Independent graph interpreter and hashlib oracle for graph-1 fixtures.

This is a conformance oracle, not a supported simulation backend.
"""
import copy
import hashlib
import json
from pathlib import Path

from check_probe import decode, encode, sample


STAGES = ["events", "decide", "motion", "resolve", "random"]
FIELDS = ["id", "position", "velocity", "requestedResource", "requestedQuantity",
          "mode", "drawIndex", "sample", "motionRemainders"]


def digest(prefix, text):
    return hashlib.sha256((prefix + text).encode("ascii")).hexdigest()


def checked(value):
    assert -(1 << 63) <= value < (1 << 63)
    return value


def ordered_nodes(graph):
    by_id = {node["id"]: node for node in graph["nodes"]}
    assert len(by_id) == len(graph["nodes"]) <= 128
    remaining, completed, ordered = set(by_id), set(), []
    while remaining:
        ready = [by_id[key] for key in remaining
                 if set(by_id[key]["inputs"] + by_id[key]["after"]) <= completed]
        assert ready, "Cyclic graph"
        node = min(ready, key=lambda n: (STAGES.index(n["stage"]), n["id"]))
        for ref in node["inputs"] + node["after"]:
            assert STAGES.index(by_id[ref]["stage"]) <= STAGES.index(node["stage"])
        ordered.append(node)
        completed.add(node["id"])
        remaining.remove(node["id"])
    return ordered


def evaluate(node, args, state, read, entity_id):
    op, params = node["operation"], node["parameters"]
    if op == "core.constant":
        return copy.deepcopy(params["value"])
    if op == "core.tick":
        return read["tick"]
    if op == "core.entity.field":
        return copy.deepcopy(read["entities"][entity_id][FIELDS.index(params["field"])])
    if op == "core.i64.add":
        return checked(args[0] + args[1])
    if op == "core.i64.less":
        return args[0] < args[1]
    if op == "core.select.i64":
        return args[1] if args[0] else args[2]
    if op == "core.string.equal":
        return args[0] == args[1]
    if op == "core.bool.and":
        return args[0] and args[1]
    if op == "core.bool.not":
        return not args[0]
    if op == "core.events.apply":
        events, generations, sequence, limit = state["events"]
        active = sorted(event for event in events if event[6] == generations[event[5]])
        for event in active:
            if event[0] <= state["tick"]:
                state["entities"][event[3]][5] = event[7]
        state["events"] = [[event for event in active if event[0] > state["tick"]],
                           generations, sequence, limit]
        return
    if op == "core.resource.resolve":
        outcomes = []
        for key, entity in sorted(state["entities"].items()):
            resource, quantity = entity[3:5]
            if quantity > 0 and state["resources"][resource] >= quantity:
                state["resources"][resource] -= quantity
                entity[4] = 0
                outcomes.append([state["tick"], resource, key, quantity])
        state["outcomes"] = outcomes
        return
    if not args[0]:
        return
    entity = state["entities"][entity_id]
    if op == "core.velocity.set":
        entity[2] = copy.deepcopy(args[1])
    elif op == "core.mode.set":
        entity[5] = args[1]
    elif op == "core.resource.request":
        assert args[2] >= 0
        entity[3:5] = args[1:3]
    elif op == "core.motion.integrate":
        for axis in range(3):
            delta, remainder = divmod(entity[2][axis] * state["model"][2] + entity[8][axis], 1000)
            entity[1][axis] = checked(entity[1][axis] + delta)
            entity[8][axis] = remainder
    elif op == "core.random.draw":
        entity[7] = sample(entity_id, state["seed"], params["stream"], entity[6])
        entity[6] += 1
        assert entity[6] < (1 << 32)
    else:
        raise AssertionError(f"Unsupported oracle operation: {op}")


def step(accepted):
    state = copy.deepcopy(accepted)
    state["tick"] = checked(state["tick"] + 1)
    state["outcomes"] = []
    graph = state["model"][5]
    nodes = ordered_nodes(graph)
    by_id = {node["id"]: node for node in nodes}
    entity_ids = sorted(state["entities"])
    cost = sum(1 if n["scope"] == "world" else len(entity_ids) for n in nodes)
    assert cost <= graph["maxNodeEvaluations"]
    values, stage, read = {}, None, None
    for node in nodes:
        if node["stage"] != stage:
            stage, read = node["stage"], copy.deepcopy(state)
        ids = [None] if node["scope"] == "world" else entity_ids
        results = {}
        for entity_id in ids:
            args = [values[ref][entity_id] if by_id[ref]["scope"] == "entity" else values[ref]
                    for ref in node["inputs"]]
            results[entity_id] = evaluate(node, args, state, read, entity_id)
        if node["type"] != "void":
            values[node["id"]] = results[None] if node["scope"] == "world" else results
    return state


def main():
    root = Path(__file__).resolve().parents[1]
    fixture = json.loads((root / "contracts/graph-1/fixtures.json").read_text())
    assert {record["name"] for record in fixture["models"]} == {"graph-probe", "conditional-graph", "expression-graph"}
    registry = fixture["registry"]
    assert len(registry) == 16
    assert digest("CatalystSimulation-Registry-1:", encode(registry)) == fixture["registryDigest"]
    checkpoint_count = 0
    for record in fixture["models"]:
        model = decode(record["model"])
        assert model[0] == fixture["profile"] and model[1] == record["name"]
        nodes = model[5]["nodes"]
        assert [n["id"] for n in nodes] == sorted(n["id"] for n in nodes)
        assert all(n["after"] == sorted(n["after"]) for n in nodes)
        assert digest("CatalystSimulation-Model-1:", record["model"]) == record["modelDigest"]
        state = decode(record["initial"])
        assert state["model"] == model and state["modelDigest"] == record["modelDigest"]
        assert state["version"] == 2 and state["tick"] == 0
        checkpoint_count += 1
        for tick in range(1, 7):
            state = step(state)
            if str(tick) in record["checkpoints"]:
                assert encode(state) == record["checkpoints"][str(tick)], (record["name"], tick)
                checkpoint_count += 1
    expected_codes = {"missing-operation": "unsupported-operation", "version": "unsupported-version",
                      "unknown": "unsupported-operation", "type": "input-type", "budget": "evaluation-budget",
                      "value-budget": "value-budget"}
    assert {record["name"] for record in fixture["compatibility"]} == set(expected_codes)
    for record in fixture["compatibility"]:
        report = record["report"]
        assert report["compatible"] is False
        assert report["modelDigest"] == digest("CatalystSimulation-Model-1:", record["model"])
        selected = {name: registry[name] for name in record["operations"]}
        assert report["registryDigest"] == digest("CatalystSimulation-Registry-1:", encode(selected))
        assert report["issues"][0]["code"] == expected_codes[record["name"]]
        assert report["issues"][0]["path"].startswith("model/graph/")
    print(json.dumps({"oracle": "Python graph interpreter and hashlib", "models": len(fixture["models"]),
                      "canonicalCheckpoints": checkpoint_count, "compatibilityFixtures": len(expected_codes),
                      "operationDeclarations": len(registry), "passed": True}))


if __name__ == "__main__":
    main()
