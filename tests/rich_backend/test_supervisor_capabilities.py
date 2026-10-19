"""Check supervisor exit states without installing Node or rendering assets."""
from __future__ import annotations

import errno
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SUPERVISOR = Path(__file__).resolve().parents[2] / "backends/node/supervisor.py"

# Inject the kernel file result at the standard I/O boundary in a fresh process.
# All other file reads, argument handling and exit classification run unchanged.
LAUNCHER = """
import io,os,runpy,sys
probe=f'/proc/self/task/{os.getpid()}/children'
failure=int(sys.argv[2])
open_file=io.open
def open_probe(path,*args,**kwargs):
    if isinstance(path,(str,bytes,os.PathLike)) and os.fsdecode(path)==probe:
        if failure:
            raise OSError(failure,'unavailable proc children')
        return io.StringIO('')
    return open_file(path,*args,**kwargs)
io.open=open_probe
def no_worker(event,args):
    if event=='os.fork':
        raise RuntimeError('worker started during capability preflight')
sys.addaudithook(no_worker)
sys.argv=[sys.argv[1],*sys.argv[3:]]
runpy.run_path(sys.argv[0],run_name='__main__')
"""


@unittest.skipUnless(sys.platform == "linux", "Linux supervisor required")
class SupervisorCapabilityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="markdown-rich-capability-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.runtime = self.root / "runtime"
        self.jobs = self.root / "jobs"
        self.jobs.mkdir()
        files = {}
        for relative in ["worker.mjs", "protocol.mjs", "boundary.mjs", "supervisor.py", "package-lock.json",
                "node/bin/node", "chrome/chrome", "fonts/font.css", "fonts/NotoSansCJKsc-Regular.otf"]:
            path = self.runtime / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"capability fixture; must not execute\n")
            files[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
        encoded = json.dumps({"schemaVersion": 1, "producerVersion": "1", "files": files}).encode()
        (self.runtime / "manifest.json").write_bytes(encoded)
        self.identity = hashlib.sha256(encoded).hexdigest()

    def check_exit(self, failure, expected):
        command = [sys.executable, "-I", "-S", "-c", LAUNCHER, str(SUPERVISOR), str(failure),
            "--runtime-root", str(self.runtime), "--identity", self.identity,
            "--work-directory", str(self.jobs), "--parent-pid", str(os.getpid()), "--timeout-ms", "5000",
            "--maximum-output-bytes", "8192", "--theme", "github-light", "--diagram-theme", "default"]
        result = subprocess.run(command, input=b"", stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8)
        self.assertEqual(result.returncode, expected, result.stderr)
        self.assertEqual(result.stdout, b"")
        self.assertEqual(result.stderr, b"")
        self.assertEqual(list(self.jobs.iterdir()), [])

    def test_missing_proc_children_reports_unsupported(self):
        self.check_exit(errno.ENOENT, 69)

    def test_denied_proc_children_reports_unsupported(self):
        self.check_exit(errno.EACCES, 69)

    def test_unreadable_proc_children_reports_unsupported(self):
        self.check_exit(errno.EIO, 69)

    def test_missing_runtime_manifest_still_reports_missing(self):
        (self.runtime / "manifest.json").unlink()
        self.check_exit(0, 66)


if __name__ == "__main__":
    unittest.main(verbosity=2)
