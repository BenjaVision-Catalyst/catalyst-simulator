#!/usr/bin/env python3
"""Local resident Repast transport. GemStone remains the acceptance authority.

A placement has one claimed incarnation. It is never relaunched implicitly.
Runtime renews its client lease; the supervisor owns and reaps the MPI process.
Full result receipts survive both Runtime and resident-process restarts.
"""
import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import uuid

module = importlib.util.spec_from_file_location("batch", Path(__file__).with_name("repast-batch.py"))
batch = importlib.util.module_from_spec(module)
module.loader.exec_module(batch)
encode, decode, digest, publish = batch.encode, batch.decode, batch.digest, batch.publish
MARKER = "CatalystSimulation-native-resident-1"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def identity(binding):
    return {key: binding[key] for key in ("version", "world", "group", "generation", "owner", "modelDigest")}


def session_key(binding):
    return digest("CatalystSimulation-Resident-1:" + encode(identity(binding)))


def read(path):
    return json.loads(path.read_text())


def touch(path):
    path.touch()


def retire(spool, binding):
    done = True
    for path in (spool / "sessions").glob("*/claim.json"):
        old = read(path)["session"]
        if old["world"] == binding["world"] and old["group"] == binding["group"]:
            if old["generation"] < binding["generation"]:
                touch(path.parent / "stop")
                done = done and (path.parent / "finished.json").exists()
    return done


def observation(job, spec):
    if not job.exists():
        return dict(state="missing")
    if not (job / "claim.json").exists():
        return dict(state="unknown", reason="incomplete claim; never replay")
    claim = read(job / "claim.json")
    require(claim["specDigest"] == digest(encode(spec)), "Resident job identity reused")
    if not (job / "result.json").exists():
        return dict(state="uncertain", binding=spec["binding"], sessionKey=claim["sessionKey"])
    result = read(job / "result.json")
    require(result["binding"] == spec["binding"], "Resident result binding")
    if result["state"] == "complete":
        raw = (job / "result.canon").read_text()
        require(len(raw) <= batch.LIMIT and digest(raw) == result["checkpointDigest"], "Resident checksum")
        cp = decode(raw)
        require(cp["tick"] == spec["binding"]["targetTick"] and cp["model"] == spec["checkpoint"]["model"]
                and cp["seed"] == spec["checkpoint"]["seed"], "Resident result frontier")
        result["checkpoint"] = cp
    return result


def handle(spool, request):
    require((spool / "identity").read_text() == MARKER, "Initialize and retain the dedicated resident spool")
    require(set(request) == {"action", "spec", "executable", "mpi", "ranks", "acceptedRevision"}, "Resident request fields")
    spec, action = request["spec"], request["action"]
    b = batch.validate(spec)
    require(action in ("ensure", "query", "synchronize", "retire"), "Resident action")
    require(type(request["acceptedRevision"]) is int and request["acceptedRevision"] > 0, "Resident revision")
    require(request["ranks"] in (1, 2, 4), "Unqualified rank count")
    job = spool / "jobs" / b["batch"]
    with (spool / "launch.lock").open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if action == "query":
            return observation(job, spec)  # Never create, launch, acknowledge or replay.
        # Persist the placement high-water mark before process effects. A delayed
        # old view cannot launch or retire processes belonging to a newer owner.
        fence = spool / "placements" / (digest(encode([b["world"], b["group"]])) + ".json")
        if fence.exists():
            current = read(fence)
            if b["generation"] < current["generation"]:
                return dict(state="fenced")
            if b["generation"] == current["generation"]:
                require(identity(b) == current, "Resident generation identity reused")
        if not fence.exists() or b["generation"] > read(fence)["generation"]:
            publish(fence, identity(b))
        if action == "retire":
            return dict(state="retired" if retire(spool, b) else "retiring")
        if action == "ensure" and job.exists():
            prior = observation(job, spec)
            if prior["state"] in ("complete", "unknown"):
                if prior["state"] == "complete":
                    previous = spool / "sessions" / prior["sessionKey"]
                    if previous.exists() and not (previous / "finished.json").exists():
                        touch(previous / "client-heartbeat")
                return prior
        if not retire(spool, b):
            return dict(state="retiring")
        key = session_key(b)
        directory = spool / "sessions" / key
        if not directory.exists():
            for name in ("executable", "mpi"):
                require(Path(request[name]).is_absolute() and os.access(request[name], os.X_OK), "Native executable path")
            directory.mkdir(mode=0o700)
            batch.sync_directory(directory.parent)
            session = dict(identity(b), incarnation=uuid.uuid4().hex)
            claim = dict(session=session, initialSpec=spec, ranks=request["ranks"], executable=request["executable"],
                         mpi=request["mpi"], executableDigest=__import__("hashlib").sha256(Path(request["executable"]).read_bytes()).hexdigest())
            publish(directory / "claim.json", claim)
            touch(directory / "client-heartbeat")
            with (directory / "supervisor.log").open("w") as log:
                subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "--worker", str(directory)],
                                 stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                 close_fds=True, start_new_session=True)
        if not (directory / "claim.json").exists():
            return dict(state="unknown", reason="incomplete resident claim; never relaunch")
        claim = read(directory / "claim.json")
        require(identity(claim["session"]) == identity(b) and claim["ranks"] == request["ranks"], "Resident placement/configuration mismatch")
        touch(directory / "client-heartbeat")
        if (directory / "finished.json").exists():
            return dict(state="failed", sessionKey=key, reason="Resident ended; rotate placement to recover")
        if action == "synchronize":
            acceptance = dict(checkpointDigest=b["checkpointDigest"], revision=request["acceptedRevision"])
            if not (directory / "accepted.json").exists() or read(directory / "accepted.json") != acceptance:
                publish(directory / "accepted.json", acceptance)
            return dict(state="resident", sessionKey=key)
        if not job.exists():
            job.mkdir(mode=0o700)
            batch.sync_directory(job.parent)
            publish(job / "claim.json", dict(spec=spec, specDigest=digest(encode(spec)), sessionKey=key,
                                             acceptedRevision=request["acceptedRevision"]))
        if not (directory / "inbox.json").exists() or read(directory / "inbox.json")["batch"] != b["batch"]:
            publish(directory / "inbox.json", dict(batch=b["batch"]))
        return observation(job, spec)


def worker(directory):
    spool = directory.parent.parent
    with (directory / "worker.lock").open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if (directory / "started.json").exists():
            return
        claim = read(directory / "claim.json")
        spec, session = claim["initialSpec"], claim["session"]
        batch.validate(spec)
        publish(directory / "started.json", dict(supervisor=os.getpid(), session=session))
        native = directory / "native"
        native.mkdir()
        for name, data in (("registry", spec["registry"]), ("model", spec["checkpoint"]["model"]),
                           ("input", spec["checkpoint"]), ("session", session)):
            (native / (name + ".canon")).write_text(encode(data))
        process, last, state, reason = None, None, "stopped", None
        log = (directory / "native.log").open("w")

        def pulse():
            touch(native / "supervisor-heartbeat")

        def await_reply(number, timeout):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                pulse()
                require(process.poll() is None, "Resident MPI exited before reply")
                if (native / "reply.canon").exists():
                    reply = decode((native / "reply.canon").read_text())
                    require(reply["session"] == session, "Resident reply incarnation")
                    if reply["number"] == number:
                        return reply
                time.sleep(.01)
            raise TimeoutError("Resident native reply deadline")

        def command(action, binding=None, revision=0):
            nonlocal last
            binding = binding or dict(fromTick=last["tick"], targetTick=last["tick"], batch="0" * 64, inputDigest="0" * 64)
            payload = dict(version=1, session=session, number=last["number"] + 1, action=action,
                           checkpointDigest=last["checkpointDigest"], fromTick=binding["fromTick"], targetTick=binding["targetTick"],
                           batch=binding["batch"], inputDigest=binding["inputDigest"], acceptedRevision=revision)
            temporary = native / "command.tmp"
            temporary.write_text(encode(payload))
            os.replace(temporary, native / "command.canon")
            last = await_reply(payload["number"], 120 if action == "advance" else 5)
            publish(directory / "state.json", dict(state="resident", native=last))

        def interrupted(*unused):
            raise InterruptedError("Resident supervisor stopped")

        signal.signal(signal.SIGTERM, interrupted)
        try:
            pulse()
            arguments = [claim["mpi"], "--oversubscribe", "--bind-to", "none", "-n", str(claim["ranks"]),
                         claim["executable"], "--registry", str(native / "registry.canon"), "--model", str(native / "model.canon"),
                         "--input", str(native / "input.canon"), "--output", str(native), "--resident", str(native)]
            process = subprocess.Popen(arguments, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            last = await_reply(0, 15)
            publish(directory / "state.json", dict(state="resident", native=last))
            while not (directory / "stop").exists():
                pulse()
                require(process.poll() is None, "Resident MPI process failed")
                if time.time() - (directory / "client-heartbeat").stat().st_mtime > 60:
                    state = "expired"
                    break
                if (directory / "accepted.json").exists():
                    accepted = read(directory / "accepted.json")
                    if last["awaitingAcceptance"] and accepted["checkpointDigest"] == last["checkpointDigest"]:
                        command("ack", revision=accepted["revision"])
                paths = [] if not (directory / "inbox.json").exists() else [spool / "jobs" / read(directory / "inbox.json")["batch"] / "claim.json"]
                for path in paths:
                    job = path.parent
                    if (job / "result.json").exists():
                        continue
                    work = read(path)
                    if work["sessionKey"] != directory.name:
                        continue
                    b = batch.validate(work["spec"])
                    require(identity(b) == identity(session), "Resident queued placement")
                    require(last["checkpointDigest"] == b["checkpointDigest"] and last["tick"] == b["fromTick"], "Resident input differs from accepted frontier; recover placement")
                    if last["awaitingAcceptance"]:
                        command("ack", revision=work["acceptedRevision"])
                    if b["targetTick"] > b["fromTick"]:
                        command("advance", b)
                    raw = (native / "candidate.canon").read_text()
                    cp = decode(raw)
                    require(len(raw) <= batch.LIMIT and digest(raw) == last["checkpointDigest"] and cp["tick"] == b["targetTick"], "Resident candidate bytes/frontier")
                    require(cp["model"] == work["spec"]["checkpoint"]["model"] and cp["seed"] == work["spec"]["checkpoint"]["seed"], "Resident candidate model/seed")
                    with (job / "result.canon").open("w") as stream:
                        stream.write(raw)
                        stream.flush()
                        os.fsync(stream.fileno())
                    publish(job / "result.json", dict(state="complete", binding=b, checkpointDigest=digest(raw), sessionKey=directory.name,
                            native=last, ranks=claim["ranks"], executableDigest=claim["executableDigest"]))
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


def shutdown(spool):
    for path in (spool / "sessions").glob("*/claim.json"):
        touch(path.parent / "stop")
    return all((path.parent / "finished.json").exists() for path in (spool / "sessions").glob("*/claim.json"))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--spool", type=Path)
    parser.add_argument("--request")
    parser.add_argument("--worker", type=Path)
    parser.add_argument("--initialize", action="store_true")
    parser.add_argument("--shutdown", action="store_true")
    args = parser.parse_args()
    if args.worker:
        worker(args.worker)
    elif args.initialize:
        args.spool.mkdir(mode=0o700, parents=True, exist_ok=False)
        (args.spool / "sessions").mkdir()
        (args.spool / "jobs").mkdir()
        (args.spool / "placements").mkdir()
        (args.spool / "identity").write_text(MARKER)
    elif args.shutdown:
        require((args.spool / "identity").read_text() == MARKER, "Resident spool identity")
        print(json.dumps(dict(stopped=shutdown(args.spool))))
    else:
        require(args.request is not None and len(args.request) <= 49152, "Resident request byte limit")
        print(json.dumps(handle(args.spool.resolve(), json.loads(args.request)), separators=(",", ":")))


if __name__ == "__main__":
    main()
