"""Exercise the real supervisor with owned process fixtures, not rendering mocks."""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
TASK: Path
NODE: Path

WORKER = r"""
import {spawn} from 'node:child_process';
const grandchildCode = "process.on('SIGTERM',()=>{});setInterval(()=>{},1000)";
const childCode = `import {spawn} from 'node:child_process';
process.on('SIGTERM',()=>{});
const grandchild=spawn(process.execPath,['-e',${JSON.stringify(grandchildCode)}],{stdio:'inherit'});
process.send({child:process.pid,grandchild:grandchild.pid});process.disconnect();setInterval(()=>{},1000);`;
async function read() {
 let all=Buffer.alloc(0),size;
 for await(const part of process.stdin) {
  all=Buffer.concat([all,part]);
  if(all.length>=4) size=all.readUInt32BE();
  if(size!==undefined && all.length>=size+4) return JSON.parse(all.subarray(4,size+4).toString());
 }
 throw Error('input');
}
const mode=process.argv[2]==='github-dark'?'blocked-input':(await read()).mode;
process.on('SIGTERM',()=>{});
if(mode==='flood') process.on('SIGUSR2',()=>process.stdout.write(Buffer.alloc(1048576,120)));
const child=spawn(process.execPath,['--input-type=module','-e',childCode],{detached:true,stdio:['ignore','inherit','inherit','ipc']});
const record=await new Promise(resolve=>child.once('message',resolve));
process.stdout.write(JSON.stringify({worker:process.pid,...record})+'\n');
if(mode==='exit') process.exit(17);
setInterval(()=>{},1000);
"""


def frame(mode: str, padding: int = 0) -> bytes:
    data = json.dumps({"mode": mode, "padding": "x" * padding}).encode().ljust(128, b" ")
    return struct.pack(">I", len(data)) + data


def manifest(directory: Path) -> str:
    files = {path.relative_to(directory).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(directory.rglob("*")) if path.is_file()}
    encoded = (json.dumps({"schemaVersion": 1, "producerVersion": "1", "files": files}, sort_keys=True, separators=(",", ":")) + "\n").encode()
    (directory / "manifest.json").write_bytes(encoded)
    return hashlib.sha256(encoded).hexdigest()


class SupervisorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.runtime = TASK / "fixture"
        cls.runtime.mkdir()
        for relative in ["node/bin", "chrome", "fonts"]:
            (cls.runtime / relative).mkdir(parents=True)
        shutil.copyfile(NODE, cls.runtime / "node/bin/node")
        (cls.runtime / "node/bin/node").chmod(0o700)
        shutil.copyfile(ROOT / "backends/node/supervisor.py", cls.runtime / "supervisor.py")
        (cls.runtime / "worker.mjs").write_text(WORKER)
        # Only the process fixture runs. Required non-executed rendering assets
        # are marked placeholders; real engine tests use the installed runtime.
        for relative in ["chrome/chrome", "fonts/font.css", "fonts/NotoSansCJKsc-Regular.otf", "protocol.mjs", "boundary.mjs", "package-lock.json"]:
            (cls.runtime / relative).write_text("process fixture placeholder\n")
        cls.identity = manifest(cls.runtime)
        cls.jobs = TASK / "jobs"
        cls.jobs.mkdir()

    def command(self, timeout=5000, output=8192, theme="github-light", parent=None):
        return [sys.executable, "-I", "-S", str(self.runtime / "supervisor.py"), "--runtime-root", str(self.runtime),
            "--identity", self.identity, "--work-directory", str(self.jobs), "--parent-pid", str(parent or os.getpid()),
            "--timeout-ms", str(timeout), "--maximum-output-bytes", str(output), "--theme", theme, "--diagram-theme", "default"]

    def launch(self, mode, timeout=5000, output=8192):
        process = subprocess.Popen(self.command(timeout, output), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(self.stop, process)
        process.stdin.write(frame(mode)); process.stdin.flush()
        self.assertEqual(process.stdout.readline(), b"MDRICH-SUPERVISOR/1\n")
        record = json.loads(process.stdout.readline())
        return process, record

    @staticmethod
    def stop(process):
        if process.poll() is None:
            process.terminate()
            process.communicate(timeout=8)

    def finish(self, process, record, expected):
        output, errors = process.communicate(timeout=8)
        self.assertEqual(process.returncode, expected, errors)
        self.assertEqual(errors, b"")
        self.assertLessEqual(len(output), 8192)
        for pid in record.values():
            self.assertFalse(Path(f"/proc/{pid}").exists(), "owned descendant was not reaped")
        self.assertEqual(list(self.jobs.iterdir()), [])

    def test_worker_exit_reaps_detached_descendants_holding_pipes(self):
        process, record = self.launch("exit")
        self.finish(process, record, 17)

    def test_worker_signal_crash_reaps_detached_descendants(self):
        process, record = self.launch("hold")
        os.kill(record["worker"], signal.SIGKILL)
        self.finish(process, record, 70)

    def test_cancel_reaps_term_ignoring_descendants(self):
        process, record = self.launch("hold")
        process.terminate()
        self.finish(process, record, 130)

    def test_timeout_reaps_descendants_and_removes_job_directory(self):
        process, record = self.launch("hold", timeout=5000)
        self.finish(process, record, 124)

    def test_output_limit_is_bounded_and_reaps_descendants(self):
        process, record = self.launch("flood", output=1024)
        os.kill(record["worker"], signal.SIGUSR2)
        self.finish(process, record, 75)

    def test_blocked_input_writer_cannot_prevent_timeout(self):
        process = subprocess.Popen(self.command(timeout=5000, theme="github-dark"), stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(self.stop, process)
        output, errors = process.communicate(frame("blocked-input", padding=4194304), timeout=8)
        self.assertEqual(process.returncode, 124, errors)
        self.assertTrue(output.startswith(b"MDRICH-SUPERVISOR/1\n"))
        record = json.loads(output.splitlines()[1])
        for pid in record.values():
            self.assertFalse(Path(f"/proc/{pid}").exists())
        self.assertEqual(list(self.jobs.iterdir()), [])

    def test_parent_death_triggers_cleanup_without_waiting_for_job_timeout(self):
        launcher = """import json,os,subprocess,sys
command=json.loads(sys.argv[1]);command[command.index('--parent-pid')+1]=str(os.getpid())
p=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE)
p.stdin.write(bytes.fromhex(sys.argv[2]));p.stdin.flush()
header=p.stdout.readline();record=json.loads(p.stdout.readline())
print(json.dumps({'supervisor':p.pid,'record':record,'header':header.decode()}),flush=True)
"""
        process = subprocess.Popen([sys.executable, "-I", "-S", "-c", launcher,
            json.dumps(self.command()), frame("hold").hex()], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        output, errors = process.communicate(timeout=8)
        self.assertEqual(process.returncode, 0, errors)
        value = json.loads(output)
        self.assertEqual(value["header"], "MDRICH-SUPERVISOR/1\n")
        deadline = time.monotonic() + 8
        while True:
            pid, status = os.waitpid(value["supervisor"], os.WNOHANG)
            if pid:
                break
            self.assertLess(time.monotonic(), deadline, "orphan supervisor did not exit")
            time.sleep(0.005)
        self.assertEqual(os.waitstatus_to_exitcode(status), 130)
        for pid in value["record"].values():
            self.assertFalse(Path(f"/proc/{pid}").exists())
        self.assertEqual(list(self.jobs.iterdir()), [])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--node", type=Path, required=True)
    parser.add_argument("--work-directory", type=Path, required=True)
    args = parser.parse_args()
    NODE = args.node.resolve()
    TASK = Path(tempfile.mkdtemp(prefix="markdown-rich-supervisor-test-", dir=args.work_directory))
    if ctypes.CDLL(None).prctl(36, 1, 0, 0, 0):
        raise SystemExit("Linux subreaper capability required")
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(SupervisorTests))
    if result.wasSuccessful():
        shutil.rmtree(TASK)
    else:
        print(f"Failure evidence retained: {TASK}", file=sys.stderr)
    raise SystemExit(0 if result.wasSuccessful() else 1)
