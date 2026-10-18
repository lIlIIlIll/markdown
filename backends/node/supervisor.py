"""Linux subreaper and bounded pipe proxy for the explicitly installed runtime."""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import selectors
import signal
import stat
import sys
import tempfile
import time


class Stop(Exception):
    def __init__(self, code: int):
        self.code = code


def check_stop(stopped: list[bool], deadline: float) -> None:
    if stopped[0]:
        raise Stop(130)
    if time.monotonic() >= deadline:
        raise Stop(124)


def verify(runtime: Path, identity: str, stopped: list[bool], deadline: float) -> None:
    with (runtime / "manifest.json").open("rb") as stream:
        encoded = stream.read(16777217)
    if len(encoded) > 16777216 or hashlib.sha256(encoded).hexdigest() != identity:
        raise Stop(65)
    manifest = json.loads(encoded)
    files = manifest["files"]
    required = {"worker.mjs", "protocol.mjs", "boundary.mjs", "supervisor.py", "package-lock.json",
        "node/bin/node", "chrome/chrome", "fonts/font.css", "fonts/NotoSansCJKsc-Regular.otf"}
    if manifest["schemaVersion"] != 1 or manifest["producerVersion"] != "1" or not required.issubset(files) or len(files) > 100000:
        raise Stop(65)
    total = 0
    for relative, expected in files.items():
        check_stop(stopped, deadline)
        path = PurePosixPath(relative)
        if path.is_absolute() or ".." in path.parts or not (runtime / path).resolve().is_relative_to(runtime):
            raise Stop(65)
        value = hashlib.sha256()
        with (runtime / path).open("rb") as stream:
            while chunk := stream.read(1048576):
                total += len(chunk)
                if total > 4294967296:
                    raise Stop(75)
                check_stop(stopped, deadline)
                value.update(chunk)
        if value.hexdigest() != expected:
            raise Stop(65)


def run_child(runtime: Path, directory: str, temporary_path: str, theme: str, diagram_theme: str, no_sandbox: bool,
    maximum_output: int, stopped: list[bool], deadline: float) -> int:
    incoming, input_writer = os.pipe()
    output_reader, outgoing = os.pipe()
    error_reader, errors = os.pipe()
    descriptors = [incoming, input_writer, output_reader, outgoing, error_reader, errors]
    worker = os.fork()
    if worker == 0:
        try:
            for source, target in [(incoming, 0), (outgoing, 1), (errors, 2)]:
                os.dup2(source, target)
            for descriptor in descriptors:
                os.close(descriptor)
            signal.signal(signal.SIGTERM, signal.SIG_DFL)
            signal.signal(signal.SIGINT, signal.SIG_DFL)
            environment = {"PATH": "/usr/bin:/bin", "HOME": directory, "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8",
                "TZ": "UTC", "TMPDIR": temporary_path, "TMP": temporary_path, "TEMP": temporary_path}
            command = str(runtime / "node/bin/node")
            os.execve(command, [command, "--max-old-space-size=384", str(runtime / "worker.mjs"), theme,
                diagram_theme, str(no_sandbox).lower()], environment)
        except BaseException:
            os._exit(70)
    for descriptor in [incoming, outgoing, errors]:
        os.close(descriptor)
    # The worker never owns the caller's output pipe. Even a broken descendant
    # cannot keep a Cangjie reader blocked after this supervisor exits.
    for descriptor in [0, 1, 2, input_writer, output_reader, error_reader]:
        os.set_blocking(descriptor, False)
    buffers = {input_writer: bytearray(), 1: bytearray(b"MDRICH-SUPERVISOR/1\n"), 2: bytearray()}
    open_fds = {0, input_writer, output_reader, error_reader}
    children_path = Path(f"/proc/self/task/{os.getpid()}/children")
    prefix = bytearray()
    expected = None
    received = 0
    worker_status = None
    reason = None
    cleanup_deadline = None
    totals = {output_reader: 0, error_reader: 0}

    def close(descriptor: int) -> None:
        if descriptor in open_fds:
            open_fds.remove(descriptor)
            os.close(descriptor)

    def shutdown(code: int) -> None:
        nonlocal reason, cleanup_deadline
        if reason is None:
            reason = code
            cleanup_deadline = time.monotonic() + 5
            close(0)
            close(input_writer)
            buffers[input_writer].clear()

    try:
        while True:
            if worker_status is None:
                pid, status = os.waitpid(worker, os.WNOHANG)
                if pid:
                    worker_status = os.waitstatus_to_exitcode(status)
            if reason is None:
                if stopped[0]:
                    shutdown(130)
                elif worker_status is not None:
                    shutdown(worker_status if worker_status >= 0 else 70)
                elif time.monotonic() >= deadline:
                    shutdown(124)
            no_children = False
            if reason is not None:
                # No reap occurs between ownership enumeration and kill. These
                # direct children cannot be replaced by a reused unrelated PID.
                for raw in children_path.read_text(encoding="ascii").split():
                    try:
                        os.kill(int(raw), signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                while True:
                    try:
                        pid, status = os.waitpid(-1, os.WNOHANG)
                    except ChildProcessError:
                        no_children = True
                        break
                    if not pid:
                        break
                    if pid == worker:
                        worker_status = os.waitstatus_to_exitcode(status)
                if no_children and output_reader not in open_fds and error_reader not in open_fds and not buffers[1] and not buffers[2]:
                    return reason
                if time.monotonic() >= cleanup_deadline:
                    return 125
            interests = {}
            if 0 in open_fds and len(buffers[input_writer]) < 65536:
                interests[0] = selectors.EVENT_READ
            if input_writer in open_fds and buffers[input_writer]:
                interests[input_writer] = selectors.EVENT_WRITE
            for source, target in [(output_reader, 1), (error_reader, 2)]:
                if source in open_fds and len(buffers[target]) < 65536:
                    interests[source] = selectors.EVENT_READ
                if buffers[target]:
                    interests[target] = selectors.EVENT_WRITE
            with selectors.DefaultSelector() as selector:
                for descriptor, event in interests.items():
                    selector.register(descriptor, event)
                events = selector.select(0.02)
            for key, event in events:
                descriptor = key.fd
                try:
                    if event == selectors.EVENT_WRITE:
                        pending = buffers[descriptor]
                        count = os.write(descriptor, pending)
                        del pending[:count]
                        if descriptor == input_writer and not pending and received == expected:
                            close(input_writer)
                        continue
                    if descriptor == 0:
                        count = min(65536 - len(buffers[input_writer]), 4 - len(prefix)) if expected is None else min(65536 - len(buffers[input_writer]), expected - received)
                        data = os.read(0, count)
                        if not data:
                            shutdown(65)
                            continue
                        received += len(data)
                        if expected is None:
                            prefix.extend(data)
                            if len(prefix) == 4:
                                expected = int.from_bytes(prefix, "big") + 4
                                if expected < 61 or expected > 33554436:
                                    shutdown(75)
                        buffers[input_writer].extend(data)
                        if received == expected:
                            close(0)
                        continue
                    target = 1 if descriptor == output_reader else 2
                    data = os.read(descriptor, 65536 - len(buffers[target]))
                    if not data:
                        close(descriptor)
                        continue
                    totals[descriptor] += len(data)
                    cap = maximum_output if descriptor == output_reader else 65536
                    if totals[descriptor] > cap:
                        shutdown(75)
                    elif reason != 75:
                        buffers[target].extend(data)
                except BlockingIOError:
                    pass
                except (BrokenPipeError, OSError):
                    shutdown(70)
                    if descriptor in open_fds:
                        close(descriptor)
                    if descriptor in buffers:
                        buffers[descriptor].clear()
    finally:
        for descriptor in list(open_fds):
            close(descriptor)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", type=Path, required=True)
    parser.add_argument("--identity", required=True)
    parser.add_argument("--work-directory", type=Path, required=True)
    parser.add_argument("--parent-pid", type=int, required=True)
    parser.add_argument("--timeout-ms", type=int, required=True)
    parser.add_argument("--maximum-output-bytes", type=int, required=True)
    parser.add_argument("--theme", choices=["github-light", "github-dark"], required=True)
    parser.add_argument("--diagram-theme", choices=["default", "dark", "neutral", "forest"], required=True)
    parser.add_argument("--allow-no-sandbox", action="store_true")
    args = parser.parse_args()
    if sys.platform != "linux" or not 1 <= args.timeout_ms <= 300000 or not 1 <= args.maximum_output_bytes <= 33600000:
        return 69
    if any(not stat.S_ISFIFO(os.fstat(descriptor).st_mode) for descriptor in [0, 1, 2]):
        return 69
    stopped = [False]
    def cancel(signum, frame):
        stopped[0] = True
    signal.signal(signal.SIGTERM, cancel)
    signal.signal(signal.SIGINT, cancel)
    libc = ctypes.CDLL(None, use_errno=True)
    libc.prctl.argtypes = [ctypes.c_int, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong]
    libc.prctl.restype = ctypes.c_int
    if libc.prctl(36, 1, 0, 0, 0) or libc.prctl(1, signal.SIGTERM, 0, 0, 0):
        return 69
    if os.getppid() != args.parent_pid:
        return 130
    Path(f"/proc/self/task/{os.getpid()}/children").read_text(encoding="ascii")
    deadline = time.monotonic() + args.timeout_ms / 1000
    runtime = args.runtime_root.resolve()
    verify(runtime, args.identity, stopped, deadline)
    with tempfile.TemporaryDirectory(prefix="markdown-rich-", dir=args.work_directory) as directory:
        descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            # Chromium's Unix socket path has a small fixed byte limit. Keep
            # storage in the caller's disk directory while exposing a short,
            # supervisor-owned path for the complete lifetime of all children.
            temporary_path = f"/proc/{os.getpid()}/fd/{descriptor}"
            return run_child(runtime, directory, temporary_path, args.theme, args.diagram_theme, args.allow_no_sandbox,
                args.maximum_output_bytes, stopped, deadline)
        finally:
            os.close(descriptor)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Stop as error:
        raise SystemExit(error.code)
    except FileNotFoundError:
        raise SystemExit(66)
    except Exception:
        # Never forward runtime paths, stack traces or author source to callers.
        raise SystemExit(70)
