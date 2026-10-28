"""Exercise update success and corrupted downloads without external services."""
import io
import os
from pathlib import Path
import signal
import subprocess
import tarfile
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/workspace-update-tools.sh"


class ToolUpdateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.home = root / "home"
        self.bin = root / "bin"
        self.home.mkdir()
        self.bin.mkdir()
        (self.home / ".nvm").mkdir()
        (self.home / ".nvm/nvm.sh").write_text("nvm() { return 0; }\n")
        skill = self.home / ".agents/skills/agmsg"
        skill.mkdir(parents=True)
        (skill / "VERSION").write_text("v1.7.0\n")
        self.old_herdr = self.home / ".local/bin/herdr"
        self.old_herdr.parent.mkdir(parents=True)
        self.old_herdr.write_text("old executable\n")
        self.herdr = root / "herdr"
        self.herdr.write_text("#!/bin/sh\necho herdr-test\n")
        self.ajc = root / "agent.tar.gz"
        with tarfile.open(self.ajc, "w:gz") as archive:
            data = b"#!/bin/sh\necho agent-test\n"
            item = tarfile.TarInfo("agent-jsonl-compact")
            item.size = len(data)
            archive.addfile(item, io.BytesIO(data))
        self.uv = root / "uv.tar.gz"
        with tarfile.open(self.uv, "w:gz") as archive:
            for name in ("uv", "uvx"):
                data = f"#!/bin/sh\necho {name}-test\n".encode()
                item = tarfile.TarInfo(f"uv-release/{name}")
                item.size = len(data)
                archive.addfile(item, io.BytesIO(data))
        fake = self.bin / "fake"
        fake.write_text("#!/bin/sh\nprintf '%s\\n' \"$(basename \"$0\")\" >> \"$FAKE_CALLS\"\n")
        fake.chmod(0o755)
        for name in ("playwright", "claude", "opencode", "rustup", "uv", "sudo"):
            (self.bin / name).symlink_to(fake)
        npm = self.bin / "npm"
        npm.write_text('''#!/usr/bin/python3
import json, os, pathlib, sys
args = sys.argv[1:]
names = ("npm", "@openai/codex", "playwright", "@playwright/cli")
if "--package-lock-only" in args:
    prefix = pathlib.Path.cwd()
    data = {"packages": {"node_modules/" + n: {"version": "1.0.0"} for n in names}}
    (prefix / "package-lock.json").write_text(json.dumps(data))
elif "ls" in args:
    print(json.dumps({"dependencies": {n: {"version": "1.0.0"} for n in names}}))
elif "install" in args and "-g" in args:
    pathlib.Path(os.environ["FAKE_NPM_GLOBAL"]).write_text("installed")
''')
        npm.chmod(0o755)
        python = self.bin / "python3"
        python.write_text('''#!/bin/sh
if [ "$1" = /usr/local/bin/audit-npm-dependencies.py ]; then
  if [ "$2" = --lock ] && [ "${FAKE_MALWARE:-0}" = 1 ]; then exit 1; fi
  exit 0
fi
if [ "$1" = /usr/local/bin/patch-npm-bundled.py ]; then exit 0; fi
exec /usr/bin/python3 "$@"
''')
        python.chmod(0o755)
        curl = self.bin / "curl"
        curl.write_text('''#!/usr/bin/python3
import hashlib, json, os, pathlib, shutil, sys
args = sys.argv[1:]
url = next(a for a in args if a.startswith("https://"))
assets = {"herdrdev/herdr": ("v0.9.5", "herdr-linux-x86_64", os.environ["FAKE_HERDR"]), "yuki-inaho/agent-jsonl-compact": ("v0.4.0", "agent-jsonl-compact-x86_64-unknown-linux-musl.tar.gz", os.environ["FAKE_AJC"]), "astral-sh/uv": ("0.13.6", "uv-x86_64-unknown-linux-gnu.tar.gz", os.environ["FAKE_UV"])}
if "api.github.com" in url:
    repo = url.split("/repos/")[1].split("/releases/")[0]
    if repo == "fujibee/agmsg":
        print(json.dumps({"tag_name": "v1.7.0"}))
    else:
        tag, name, path = assets[repo]
        digest = hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()
        print(json.dumps({"tag_name": tag, "assets": [{"name": name, "digest": "sha256:" + digest}]}))
else:
    path = (os.environ["FAKE_HERDR"] if "herdr-linux" in url else
            os.environ["FAKE_UV"] if "/astral-sh/uv/" in url else os.environ["FAKE_AJC"])
    target = args[args.index("-o") + 1]
    if os.environ.get("FAKE_CORRUPT") and "herdr-linux" in url:
        pathlib.Path(target).write_bytes(b"wrong")
    else:
        shutil.copyfile(path, target)
''')
        curl.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), PATH=f"{self.bin}:/usr/bin:/bin",
                        FAKE_HERDR=str(self.herdr), FAKE_AJC=str(self.ajc), FAKE_UV=str(self.uv),
                        FAKE_CALLS=str(root / "calls"), FAKE_NPM_GLOBAL=str(root / "npm-global"))

    def run_update(self):
        return subprocess.run(["bash", str(SCRIPT), "--once"], env=self.env,
                              text=True, capture_output=True, timeout=20)

    def test_updates_and_preserves_current_agmsg(self):
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.old_herdr.read_text(), self.herdr.read_text())
        self.assertTrue((self.home / ".local/bin/agent-jsonl-compact").is_file())
        self.assertTrue((self.home / ".local/bin/uv").is_file())
        self.assertTrue((self.home / ".local/bin/uvx").is_file())
        self.assertIn("agmsg: OK", result.stdout)
        self.assertIn("playwright", Path(self.env["FAKE_CALLS"]).read_text())

    def test_bad_checksum_keeps_old_binary_and_continues(self):
        self.env["FAKE_CORRUPT"] = "1"
        result = self.run_update()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(self.old_herdr.read_text(), "old executable\n")
        self.assertIn("herdr: FAILED", result.stdout)
        self.assertIn("agent-jsonl-compact: OK", result.stdout)
        self.assertIn("browsers: OK", result.stdout)

    def test_malware_preflight_prevents_global_install(self):
        self.env["FAKE_MALWARE"] = "1"
        result = self.run_update()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertFalse(Path(self.env["FAKE_NPM_GLOBAL"]).exists())
        self.assertIn("npm-and-codex: FAILED", result.stdout)

    def test_broken_uvx_does_not_replace_uv(self):
        with tarfile.open(self.uv, "w:gz") as archive:
            for name, data in (("uv", b"#!/bin/sh\nexit 0\n"),
                               ("uvx", b"#!/bin/sh\nexit 1\n")):
                item = tarfile.TarInfo(name)
                item.size = len(data)
                archive.addfile(item, io.BytesIO(data))
        previous = self.home / ".local/bin/uv"
        previous.write_text("original uv\n")
        result = self.run_update()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(previous.read_text(), "original uv\n")
        self.assertIn("uv: FAILED", result.stdout)

    def test_watcher_runs_and_avoids_duplicate_workers(self):
        worker = subprocess.Popen(["bash", str(SCRIPT), "--watch"], env=self.env,
                                  start_new_session=True)
        try:
            log = self.home / ".local/state/kasm-workspace/tool-update.log"
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                if log.exists() and "All user tools updated" in log.read_text():
                    break
                time.sleep(0.1)
            else:
                self.fail("worker did not complete its initial update")
            duplicate = subprocess.run(["bash", str(SCRIPT), "--watch"], env=self.env,
                                       timeout=5, capture_output=True)
            self.assertEqual(duplicate.returncode, 0)
            self.assertEqual(log.stat().st_mode & 0o777, 0o600)
        finally:
            os.killpg(worker.pid, signal.SIGTERM)
            worker.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
