#!/usr/bin/env python3
"""Native, local-only Runtime batch transport. A claimed job is never replayed.

The spool is durable evidence, not a second simulation authority. GemStone alone
accepts revisions. Keep the spool across Runtime restarts; loss requires operator
reconciliation. No shell, network listener, containers or domain behaviour.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "conformance"))
from check_probe import encode, decode

MARKER = "CatalystSimulation-native-batches-1"
LIMIT = 196608


def digest(raw):
    return hashlib.sha256(raw.encode("ascii")).hexdigest()


def publish(path, value):
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"))
    temporary = path.with_suffix(".tmp")
    with temporary.open("w") as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)
    descriptor = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def sync_directory(path):
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def validate(spec):
    assert set(spec) == {"binding", "checkpoint", "registry"}
    b, cp = spec["binding"], spec["checkpoint"]
    assert set(b) == {"version", "world", "group", "generation", "owner", "modelDigest",
                      "batch", "inputDigest", "checkpointDigest", "fromTick", "targetTick"}
    assert b["version"] == 1 and type(b["generation"]) is int and b["generation"] > 0
    for key in ("world", "group", "owner"):
        assert re.fullmatch("[0-9a-f]{32}", b[key])
    for key in ("modelDigest", "batch", "inputDigest", "checkpointDigest"):
        assert re.fullmatch("[0-9a-f]{64}", b[key])
    assert b["fromTick"] == cp["tick"] and 0 <= b["targetTick"] - cp["tick"] <= 64
    assert type(b["targetTick"]) is int
    assert cp["modelDigest"] == b["modelDigest"] == digest("CatalystSimulation-Model-1:" + encode(cp["model"]))
    assert len(encode(cp)) <= LIMIT and digest(encode(cp)) == b["checkpointDigest"]
    assert digest("CatalystSimulation-Registry-1:" + encode(spec["registry"])) == "710502049ac1f485589d81eb27482360017ed9d048afb0452694792bf23fc367"
    if b["targetTick"] != b["fromTick"]:
        assert b["batch"] == b["inputDigest"]
    return b


def observe(directory, spec):
    if not directory.exists():
        return dict(state="missing")
    if not (directory / "claim.json").exists():
        return dict(state="unknown", reason="incomplete-claim; never replay")
    claim = json.loads((directory / "claim.json").read_text())
    assert claim["specDigest"] == digest(encode(spec)), "job identity reused with different bytes"
    if not (directory / "result.json").exists():
        return dict(state="uncertain", binding=spec["binding"])
    result = json.loads((directory / "result.json").read_text())
    assert result["binding"] == spec["binding"]
    if result["state"] == "complete":
        raw = (directory / "result.canon").read_text()
        assert len(raw) <= LIMIT and digest(raw) == result["checkpointDigest"]
        cp = decode(raw)
        assert cp["tick"] == spec["binding"]["targetTick"]
        assert cp["model"] == spec["checkpoint"]["model"] and cp["seed"] == spec["checkpoint"]["seed"]
        result["checkpoint"] = cp
    return result


def worker(directory):
    """Only the uniquely claimed child may start MPI; duplicate children cannot."""
    with (directory / "worker.lock").open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if (directory / "started.json").exists():
            return
        launch = json.loads((directory / "claim.json").read_text())
        spec = launch["spec"]
        b = validate(spec)
        publish(directory / "started.json", dict(supervisor=os.getpid(), binding=b))
        def interrupted(*unused):
            raise InterruptedError("Owned native supervisor stopped")
        signal.signal(signal.SIGTERM, interrupted)
        process = None
        try:
            for name, data in (("registry", spec["registry"]), ("model", spec["checkpoint"]["model"]),
                               ("input", spec["checkpoint"])):
                (directory / (name + ".canon")).write_text(encode(data))
            command = [launch["mpi"], "--oversubscribe", "--bind-to", "none", "-n", str(launch["ranks"]),
                       launch["executable"], "--registry", str(directory / "registry.canon"),
                       "--model", str(directory / "model.canon"), "--input", str(directory / "input.canon"),
                       "--output", str(directory / "native"), "--steps", str(b["targetTick"] - b["fromTick"])]
            with (directory / "native.log").open("w") as log:
                process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    code = process.wait(timeout=120)
                except BaseException:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                    raise
            assert code == 0, f"MPI exit {code}"
            raw = (directory / "native/accepted.canon").read_text()
            cp = decode(raw)
            assert len(raw) <= LIMIT and cp["tick"] == b["targetTick"]
            assert cp["model"] == spec["checkpoint"]["model"] and cp["seed"] == spec["checkpoint"]["seed"]
            with (directory / "result.canon").open("w") as stream:
                stream.write(raw)
                stream.flush()
                os.fsync(stream.fileno())
            publish(directory / "result.json", dict(state="complete", binding=b, checkpointDigest=digest(raw),
                    executableDigest=launch["executableDigest"], ranks=launch["ranks"]))
        except BaseException as error:
            publish(directory / "result.json", dict(state="failed", binding=b, reason=repr(error)[:256]))
        finally:
            publish(directory / "finished.json", dict(supervisor=os.getpid(), nativeReaped=True))


def handle(spool, request):
    assert (spool / "identity").read_text() == MARKER, "Initialize and retain the dedicated spool"
    assert set(request) == {"action", "spec", "executable", "mpi", "ranks"}
    spec = request["spec"]
    b = validate(spec)
    assert request["ranks"] in (1, 2, 4)
    directory = spool / b["batch"]
    with (spool / "launch.lock").open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if request["action"] == "ensure" and not directory.exists():
            for name in ("executable", "mpi"):
                assert Path(request[name]).is_absolute() and os.access(request[name], os.X_OK)
            directory.mkdir(mode=0o700)
            sync_directory(spool)
            launch = dict(spec=spec, specDigest=digest(encode(spec)), ranks=request["ranks"],
                          executable=request["executable"], mpi=request["mpi"],
                          executableDigest=hashlib.sha256(Path(request["executable"]).read_bytes()).hexdigest())
            publish(directory / "claim.json", launch)
            with (directory / "supervisor.log").open("w") as log:
                subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "--worker", str(directory)],
                                 stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                 close_fds=True, start_new_session=True)
        else:
            assert request["action"] in ("query", "ensure")
        return observe(directory, spec)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--spool", type=Path)
    parser.add_argument("--request")
    parser.add_argument("--initialize", action="store_true")
    parser.add_argument("--worker", type=Path)
    args = parser.parse_args()
    if args.worker:
        worker(args.worker)
        return
    if args.initialize:
        args.spool.mkdir(mode=0o700, parents=True, exist_ok=False)
        (args.spool / "identity").write_text(MARKER)
        return
    assert len(args.request) <= 49152
    print(json.dumps(handle(args.spool.resolve(), json.loads(args.request)), separators=(",", ":")))


if __name__ == "__main__":
    main()
