#!/usr/bin/env python3
"""Resident checkpoint-1 transport: bounded objects and manifests, no flat state."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import uuid

HERE = Path(__file__).resolve().parent


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


resident = load("resident", "repast-resident.py")
codec = load("shards", "sharded-codec.py")
encode, decode, digest, publish = codec.encode, codec.decode, codec.digest, resident.publish
require, identity, session_key = resident.require, resident.identity, resident.session_key
MARKER = "CatalystSimulation-sharded-resident-1"


def validate(spec):
    require(set(spec) == {"binding", "root"}, "Sharded specification")
    b = spec["binding"]
    require(set(b) == {"version", "world", "group", "generation", "owner", "modelDigest", "batch", "inputDigest",
                       "checkpointDigest", "fromTick", "targetTick"}, "Sharded binding")
    require(b["version"] == 1 and type(b["generation"]) is int and b["generation"] > 0, "Sharded generation")
    for field in ("world", "group", "owner"):
        require(type(b[field]) is str and len(b[field]) == 32 and set(b[field]) <= set("0123456789abcdef"), "Sharded identity")
    for field in ("modelDigest", "batch", "inputDigest", "checkpointDigest"):
        require(codec.valid_hash(b[field]), "Sharded digest")
    require(spec["root"] == b["checkpointDigest"] and type(b["fromTick"]) is int and type(b["targetTick"]) is int
            and b["fromTick"] >= 0 and 0 <= b["targetTick"] - b["fromTick"] <= 64, "Sharded frontier")
    if b["targetTick"] > b["fromTick"]:
        require(b["batch"] == b["inputDigest"], "Sharded batch")
    return b


def missing(store, root, limit):
    seen, pending, result = set(), [(root, 0)], []
    while pending and len(result) < limit:
        key, depth = pending.pop()
        require(codec.valid_hash(key) and depth <= 64, "Artifact reference/depth")
        if key in seen:
            continue
        seen.add(key)
        if not (store.directory / (key + ".canon")).exists():
            result.append(key)
        else:
            pending.extend((child, depth + 1) for child in store.references(store.get(key)))
    return result


def observation(spool, job, spec):
    if not job.exists():
        return dict(state="missing")
    if not (job / "claim.json").exists():
        return dict(state="unknown")
    claim = resident.read(job / "claim.json")
    require(claim["specDigest"] == digest(encode(spec)), "Sharded request reused")
    if not (job / "result.json").exists():
        return dict(state="uncertain")
    result = resident.read(job / "result.json")
    require(result["binding"] == spec["binding"], "Sharded receipt binding")
    manifest = codec.Store(spool / "objects").get(result["root"])
    require(manifest["kind"] == "checkpoint" and manifest["tick"] == spec["binding"]["targetTick"]
            and manifest["modelDigest"] == spec["binding"]["modelDigest"], "Sharded receipt frontier")
    return result


def handle(spool, request):
    require(len(json.dumps(request, separators=(",", ":"))) <= 196608, "Sharded control byte limit")
    require((spool / "identity").read_text() == MARKER, "Initialize and retain the sharded spool")
    action = request["action"]
    store = codec.Store(spool / "objects")
    if action == "getObjects":
        require(set(request) == {"action", "hashes"} and 1 <= len(request["hashes"]) <= 32, "Artifact fetch budget")
        require(len(set(request["hashes"])) == len(request["hashes"]), "Duplicate artifact fetch")
        objects = []
        for key in request["hashes"]:
            candidate = objects + store.objects([key])
            if len(json.dumps(dict(objects=candidate), separators=(",", ":"))) > 160000:
                break
            objects = candidate
        return dict(objects=objects)
    if action == "putObjects":
        require(set(request) == {"action", "objects"} and 1 <= len(request["objects"]) <= 32, "Artifact offer budget")
        for obj in request["objects"]:
            require(set(obj) == {"hash", "parts"} and 1 <= len(obj["parts"]) <= 4
                    and all(type(part) is str and len(part) <= 4096 for part in obj["parts"]), "Artifact parts")
            store.put_raw(obj["hash"], "".join(obj["parts"]))
        with codec.Availability(spool / "availability.sqlite3") as available:
            for obj in request["objects"]:
                available.missing(store, obj["hash"], 1)
        return dict(stored=[obj["hash"] for obj in request["objects"]])
    if action == "missing":
        require(set(request) == {"action", "root"}, "Artifact availability")
        with codec.Availability(spool / "availability.sqlite3") as available:
            result = available.missing(store, request["root"], 32)
            return dict(missing=result, availability=available.stats)
    require(set(request) == {"action", "spec", "executable", "mpi", "ranks", "acceptedRevision"}, "Sharded request")
    require(action in ("ensure", "synchronize", "retire", "query"), "Sharded action")
    spec = request["spec"]
    b = validate(spec)
    require(request["ranks"] in (1, 2, 4) and type(request["acceptedRevision"]) is int and request["acceptedRevision"] > 0, "Sharded configuration")
    job = spool / "jobs" / b["batch"]
    with (spool / "launch.lock").open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if action == "query":
            return observation(spool, job, spec)
        fence = spool / "placements" / (digest(encode([b["world"], b["group"]])) + ".json")
        if fence.exists():
            current = resident.read(fence)
            if b["generation"] < current["generation"]:
                return dict(state="fenced")
            if b["generation"] == current["generation"]:
                require(identity(b) == current, "Sharded generation identity reused")
        if not fence.exists() or b["generation"] > resident.read(fence)["generation"]:
            publish(fence, identity(b))
        if action == "retire":
            return dict(state="retired" if resident.retire(spool, b) else "retiring")
        if action == "ensure" and job.exists():
            prior = observation(spool, job, spec)
            if prior["state"] in ("complete", "unknown"):
                if prior["state"] == "complete":
                    previous = spool / "sessions" / prior["sessionKey"]
                    if not (previous / "finished.json").exists():
                        resident.touch(previous / "client-heartbeat")
                return prior
        if not resident.retire(spool, b):
            return dict(state="retiring")
        manifest = store.get(spec["root"])
        require(manifest["modelDigest"] == b["modelDigest"] and manifest["tick"] == b["fromTick"], "Sharded input frontier")
        key = session_key(b)
        directory = spool / "sessions" / key
        if not directory.exists():
            for field in ("mpi", "executable"):
                require(Path(request[field]).is_absolute() and os.access(request[field], os.X_OK), "Native executable path")
            directory.mkdir(mode=0o700)
            resident.batch.sync_directory(directory.parent)
            publish(directory / "claim.json", dict(session=dict(identity(b), incarnation=uuid.uuid4().hex), initialSpec=spec,
                    ranks=request["ranks"], executable=request["executable"], mpi=request["mpi"],
                    executableDigest=hashlib.sha256(Path(request["executable"]).read_bytes()).hexdigest()))
            resident.touch(directory / "client-heartbeat")
            with (directory / "supervisor.log").open("w") as log:
                subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "--worker", str(directory)], stdin=subprocess.DEVNULL,
                                 stdout=log, stderr=subprocess.STDOUT, close_fds=True, start_new_session=True)
        if not (directory / "claim.json").exists():
            return dict(state="unknown")
        claim = resident.read(directory / "claim.json")
        require(identity(claim["session"]) == identity(b) and claim["ranks"] == request["ranks"], "Sharded placement/configuration")
        resident.touch(directory / "client-heartbeat")
        if (directory / "finished.json").exists():
            return dict(state="failed", sessionKey=key)
        if action == "synchronize":
            accepted = dict(checkpointDigest=spec["root"], revision=request["acceptedRevision"])
            if not (directory / "accepted.json").exists() or resident.read(directory / "accepted.json") != accepted:
                publish(directory / "accepted.json", accepted)
            return dict(state="resident", sessionKey=key)
        if not job.exists():
            job.mkdir(mode=0o700)
            resident.batch.sync_directory(job.parent)
            publish(job / "claim.json", dict(spec=spec, specDigest=digest(encode(spec)), sessionKey=key, acceptedRevision=request["acceptedRevision"]))
        if not (directory / "inbox.json").exists() or resident.read(directory / "inbox.json")["batch"] != b["batch"]:
            publish(directory / "inbox.json", dict(batch=b["batch"]))
        return observation(spool, job, spec)


def worker(directory):
    spool = directory.parent.parent
    store = codec.Store(spool / "objects")
    with (directory / "worker.lock").open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if (directory / "started.json").exists():
            return
        claim = resident.read(directory / "claim.json")
        spec, session = claim["initialSpec"], claim["session"]
        validate(spec)
        typed = store.read_value(store.get(spec["root"])["model"])[0] == "simulation-portable-1/typed-1"
        client_lease = 300 if typed else 60
        publish(directory / "started.json", dict(supervisor=os.getpid(), session=session, clientLeaseSeconds=client_lease))
        native = directory / "native"
        native.mkdir()
        (native / "session.canon").write_text(encode(session))
        registry = json.loads((HERE.parent / "contracts/graph-1/fixtures.json").read_text())["registry"]
        (native / "registry.canon").write_text(encode(registry))
        process, last, state, reason = None, None, "stopped", None
        log = (directory / "native.log").open("w")

        def pulse():
            resident.touch(native / "supervisor-heartbeat")

        def await_reply(number, timeout):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                pulse()
                require(process.poll() is None, "Sharded MPI exited")
                if (native / "reply.canon").exists():
                    reply = decode((native / "reply.canon").read_text())
                    require(reply["session"] == session and reply["profile"] == "checkpoint-1", "Sharded reply identity")
                    if reply["number"] == number:
                        return reply
                time.sleep(.01)
            raise TimeoutError("Sharded native reply deadline")

        def command(action, binding=None, revision=0):
            nonlocal last
            binding = binding or dict(fromTick=last["tick"], targetTick=last["tick"], batch="0" * 64, inputDigest="0" * 64)
            payload = dict(version=1, session=session, number=last["number"] + 1, action=action, checkpointDigest=last["checkpointDigest"],
                           fromTick=binding["fromTick"], targetTick=binding["targetTick"], batch=binding["batch"], inputDigest=binding["inputDigest"], acceptedRevision=revision)
            temporary = native / "command.tmp"
            temporary.write_text(encode(payload))
            os.replace(temporary, native / "command.canon")
            last = await_reply(payload["number"], 120 if action == "advance" else 5)
            publish(directory / "state.json", dict(state="resident", native=last))

        def interrupted(*unused):
            raise InterruptedError("Sharded supervisor stopped")

        signal.signal(signal.SIGTERM, interrupted)
        try:
            pulse()
            process = subprocess.Popen([claim["mpi"], "--oversubscribe", "--bind-to", "none", "-n", str(claim["ranks"]), claim["executable"],
                "--registry", str(native / "registry.canon"), "--profile", "checkpoint-1", "--objects", str(store.directory), "--root", spec["root"],
                "--resident", str(native), "--output", str(native)], stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            last = await_reply(0, 30)
            require(last["checkpointDigest"] == spec["root"], "Sharded restore changed root")
            publish(directory / "state.json", dict(state="resident", native=last))
            while not (directory / "stop").exists():
                pulse()
                require(process.poll() is None, "Sharded MPI failed")
                if time.time() - (directory / "client-heartbeat").stat().st_mtime > client_lease:
                    state = "expired"
                    break
                if (directory / "accepted.json").exists():
                    accepted = resident.read(directory / "accepted.json")
                    if last["awaitingAcceptance"] and accepted["checkpointDigest"] == last["checkpointDigest"]:
                        command("ack", revision=accepted["revision"])
                if (directory / "inbox.json").exists():
                    job = spool / "jobs" / resident.read(directory / "inbox.json")["batch"]
                    if not (job / "result.json").exists():
                        work = resident.read(job / "claim.json")
                        require(work["sessionKey"] == directory.name, "Sharded queued incarnation")
                        b = validate(work["spec"])
                        require(identity(b) == identity(session) and b["checkpointDigest"] == last["checkpointDigest"] and b["fromTick"] == last["tick"], "Sharded input differs from accepted frontier")
                        if last["awaitingAcceptance"]:
                            command("ack", revision=work["acceptedRevision"])
                        if b["targetTick"] > b["fromTick"]:
                            command("advance", b)
                        root = (native / "candidate-root").read_text()
                        manifest = store.get(root)
                        initial = store.get(work["spec"]["root"])
                        require(root == last["checkpointDigest"] and manifest["tick"] == b["targetTick"] and manifest["model"] == initial["model"]
                                and manifest["modelDigest"] == b["modelDigest"] and manifest["seed"] == initial["seed"], "Sharded result frontier")
                        publish(job / "result.json", dict(state="complete", binding=b, root=root, sessionKey=directory.name, native=last,
                                ranks=claim["ranks"], executableDigest=claim["executableDigest"]))
                time.sleep(.02)
        except BaseException as error:
            state, reason = "failed", repr(error)[:256]
        finally:
            if process is not None:
                if process.poll() is None and last is not None:
                    try:
                        command("stop")
                    except BaseException:
                        pass
                if process.poll() is None:
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGTERM)
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            os.killpg(process.pid, signal.SIGKILL)
                            process.wait()
                else:
                    process.wait()
            log.close()
            publish(directory / "finished.json", dict(state=state, reason=reason, nativeReaped=True, session=session, native=last))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--spool", type=Path)
    parser.add_argument("--request")
    parser.add_argument("--request-file", type=Path)
    parser.add_argument("--worker", type=Path)
    parser.add_argument("--initialize", action="store_true")
    parser.add_argument("--shutdown", action="store_true")
    args = parser.parse_args()
    if args.worker:
        worker(args.worker)
    elif args.initialize:
        args.spool.mkdir(mode=0o700, parents=True, exist_ok=False)
        for name in ("sessions", "jobs", "placements", "objects", "control"):
            (args.spool / name).mkdir()
        (args.spool / "identity").write_text(MARKER)
    elif args.shutdown:
        require((args.spool / "identity").read_text() == MARKER, "Sharded spool identity")
        print(json.dumps(dict(stopped=resident.shutdown(args.spool))))
    else:
        try:
            raw = args.request_file.read_text() if args.request_file else args.request
            require(raw is not None and len(raw) <= 196608, "Sharded control byte limit")
            print(json.dumps(handle(args.spool.resolve(), json.loads(raw)), separators=(",", ":")))
        finally:
            if args.request_file:
                args.request_file.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
