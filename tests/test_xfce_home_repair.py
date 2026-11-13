"""Exercise XFCE profile repair against disposable homes, not source text."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPAIR = Path(__file__).resolve().parents[1] / "scripts/home-repair.sh"
XFCE = Path(".config/xfce4/xfconf/xfce-perchannel-xml")


class XfceHomeRepairTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / "home"
        self.profile = self.root / "default-profile"
        (self.profile / XFCE).mkdir(parents=True)
        (self.profile / XFCE / "xfce4-desktop.xml").write_text("default desktop\n")
        (self.profile / XFCE / "xfce4-panel.xml").write_text("default panel\n")
        (self.profile / ".bashrc").write_text("")
        for name in (".local/bin/herdr", ".opencode/bin/opencode", ".nvm/nvm.sh", ".cargo/env"):
            path = self.home / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("existing tool\n")
            path.chmod(0o755)

    def repair(self) -> None:
        env = dict(os.environ, HOME=str(self.home), DEFAULT_PROFILE_HOME=str(self.profile))
        command = 'source "$1"; home_repair_run_sudo() { "$@"; }; configure_home_profile'
        result = subprocess.run(
            ["bash", "-c", command, "test", str(REPAIR)],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_xfce_profile_is_restored_even_when_tools_exist(self) -> None:
        self.repair()
        self.assertEqual((self.home / XFCE / "xfce4-desktop.xml").read_text(), "default desktop\n")
        self.assertEqual((self.home / XFCE / "xfce4-panel.xml").read_text(), "default panel\n")

    def test_existing_xfce_profile_is_not_overwritten(self) -> None:
        existing = self.home / XFCE / "xfce4-desktop.xml"
        existing.parent.mkdir(parents=True)
        existing.write_text("user desktop\n")
        self.repair()
        self.repair()
        self.assertEqual(existing.read_text(), "user desktop\n")

    def test_existing_xfce_symlink_is_not_followed(self) -> None:
        destination = self.root / "user-config"
        destination.mkdir()
        sentinel = destination / "sentinel"
        sentinel.write_text("do not modify\n")
        link = self.home / ".config/xfce4"
        link.parent.mkdir(parents=True)
        link.symlink_to(destination, target_is_directory=True)
        self.repair()
        self.assertTrue(link.is_symlink())
        self.assertEqual(sentinel.read_text(), "do not modify\n")
        self.assertEqual(list(destination.iterdir()), [sentinel])

    def test_existing_config_symlink_is_not_followed(self) -> None:
        destination = self.root / "user-config-root"
        destination.mkdir()
        sentinel = destination / "sentinel"
        sentinel.write_text("do not modify\n")
        link = self.home / ".config"
        link.symlink_to(destination, target_is_directory=True)
        self.repair()
        self.assertTrue(link.is_symlink())
        self.assertEqual(list(destination.iterdir()), [sentinel])


if __name__ == "__main__":
    unittest.main()
