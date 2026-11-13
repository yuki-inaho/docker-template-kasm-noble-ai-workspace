"""Check one-time IBus selection without a running desktop."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/initialize-ibus-engine.sh"


class IbusInitializationTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home / "bin"
        self.bin.mkdir()
        fake = self.bin / "ibus"
        fake.write_text('#!/bin/sh\nif [ "$2" = mozc-jp ]; then echo mozc-jp > "$HOME/engine"; else cat "$HOME/engine"; fi\n')
        fake.chmod(0o755)
        (self.home / "engine").write_text("xkb:jp::jpn\n")

    def run_init(self):
        return subprocess.run(["bash", str(SCRIPT)], env=dict(os.environ, HOME=str(self.home), PATH=f"{self.bin}:{os.environ['PATH']}"), check=False)

    def test_fresh_home_selects_once_and_preserves_later_choice(self):
        pending = self.home / ".kasm-ibus-initialize"
        pending.touch()
        self.assertEqual(self.run_init().returncode, 0)
        self.assertEqual((self.home / "engine").read_text().strip(), "mozc-jp")
        self.assertFalse(pending.exists())
        self.assertTrue((self.home / ".kasm-ibus-initialized").exists())
        (self.home / "engine").write_text("xkb:jp::jpn\n")
        self.assertEqual(self.run_init().returncode, 0)
        self.assertEqual((self.home / "engine").read_text().strip(), "xkb:jp::jpn")

    def test_no_marker_does_not_change_engine(self):
        self.assertEqual(self.run_init().returncode, 0)
        self.assertEqual((self.home / "engine").read_text().strip(), "xkb:jp::jpn")

    def test_symlinked_marker_is_not_followed(self):
        (self.home / ".kasm-ibus-initialize").symlink_to(self.home / "engine")
        self.assertEqual(self.run_init().returncode, 0)
        self.assertEqual((self.home / "engine").read_text().strip(), "xkb:jp::jpn")


if __name__ == "__main__":
    unittest.main()
