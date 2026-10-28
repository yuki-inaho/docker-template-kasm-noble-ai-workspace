#!/usr/bin/env python3
"""Boundary tests for scripts/install-kasmvnc.sh.

The tests use the real installer and real sha256sum/dpkg version comparison.
curl, dpkg-deb, apt-get, dpkg-query, and Xvnc are replaced with fake commands
on PATH. No real network or host APT operation is performed.
"""

from __future__ import annotations

import hashlib
import os
import pathlib
import subprocess
import tempfile
import textwrap
import unittest

TARGET = "1.5.2+git20261028-1"
APPROVED_URL = (
    "https://github.com/yuki-inaho/KasmVNC/releases/download/"
    "v1.5.2-noble-test/kasmvncserver_noble_amd64.deb"
)
MIN_XORG = "12101025"


class InstallerPolicyTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.fixture = self.root / "fixture.deb"
        self.fixture.write_bytes(b"fake-debian-package-for-policy-tests\n")
        self.fixture_sha = hashlib.sha256(self.fixture.read_bytes()).hexdigest()
        self.call_log = self.root / "calls.log"
        self.call_log.write_text("")
        self.apt_state = self.root / "apt-installed"
        self.installer = (
            pathlib.Path(__file__).resolve().parents[1]
            / "scripts"
            / "install-kasmvnc.sh"
        )
        self._write_stubs()

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def _write_stub(self, name: str, body: str) -> None:
        path = self.bin / name
        path.write_text(textwrap.dedent(body).lstrip())
        path.chmod(0o755)

    def _write_stubs(self) -> None:
        self._write_stub(
            "curl",
            """\
            #!/usr/bin/env bash
            set -euo pipefail
            out=""
            while (($#)); do
              if [[ "$1" == "-o" ]]; then
                out="$2"
                shift 2
              else
                shift
              fi
            done
            [[ -n "$out" ]]
            cp "$FAKE_FIXTURE" "$out"
            printf 'curl\\n' >> "$FAKE_CALL_LOG"
            """,
        )
        self._write_stub(
            "dpkg-deb",
            """\
            #!/usr/bin/env bash
            set -euo pipefail
            [[ "$1" == "-f" ]]
            case "$3" in
              Package) printf '%s\\n' "${FAKE_PACKAGE:-kasmvncserver}" ;;
              Architecture) printf '%s\\n' "${FAKE_ARCH:-amd64}" ;;
              Version) printf '%s\\n' "${FAKE_VERSION:-1.5.2+git20261028-1}" ;;
              *) exit 1 ;;
            esac
            """,
        )
        self._write_stub(
            "apt-get",
            """\
            #!/usr/bin/env bash
            set -euo pipefail
            printf 'apt-get %s\\n' "$*" >> "$FAKE_CALL_LOG"
            case " $* " in
              *" install "*) touch "$FAKE_APT_STATE" ;;
            esac
            exit 0
            """,
        )
        self._write_stub(
            "dpkg-query",
            """\
            #!/usr/bin/env bash
            set -euo pipefail
            if [[ -e "$FAKE_APT_STATE" ]]; then
              printf '%s\\n' "${FAKE_AFTER:-${FAKE_VERSION:-1.5.2+git20261028-1}}"
            elif [[ -n "${FAKE_BEFORE:-}" ]]; then
              printf '%s\\n' "$FAKE_BEFORE"
            else
              exit 1
            fi
            """,
        )
        self._write_stub(
            "Xvnc",
            """\
            #!/usr/bin/env bash
            set -euo pipefail
            printf 'Xvnc KasmVNC test build\\n'
            if [[ -n "${FAKE_XORG:-}" ]]; then
              printf 'Underlying X server release %s\\n' "$FAKE_XORG"
            fi
            """,
        )

    def run_installer(self, **overrides: str) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env["PATH"] = f"{self.bin}:{env['PATH']}"
        env.update(
            {
                "KASMVNC_DEB_URL": APPROVED_URL,
                "KASMVNC_DEB_SHA256": self.fixture_sha,
                "KASMVNC_PACKAGE_VERSION": TARGET,
                "FAKE_FIXTURE": str(self.fixture),
                "FAKE_CALL_LOG": str(self.call_log),
                "FAKE_APT_STATE": str(self.apt_state),
                "FAKE_PACKAGE": "kasmvncserver",
                "FAKE_ARCH": "amd64",
                "FAKE_VERSION": TARGET,
                "FAKE_BEFORE": "1.3.4-1",
                "FAKE_AFTER": TARGET,
                "FAKE_XORG": MIN_XORG,
            }
        )
        env.update(overrides)
        return subprocess.run(
            ["/bin/bash", str(self.installer)],
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def reset_run_state(self) -> None:
        self.apt_state.unlink(missing_ok=True)
        self.call_log.write_text("")

    def apt_install_calls(self) -> int:
        if not self.call_log.exists():
            return 0
        return sum(
            1
            for line in self.call_log.read_text().splitlines()
            if " install " in line
        )

    def assert_rejected_before_install(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.apt_install_calls(), 0, result.stdout + result.stderr)

    def test_reviewed_fork_package_installs(self) -> None:
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.apt_install_calls(), 1)
        self.assertIn("kasmvncserver before:", result.stdout)
        self.assertIn("kasmvncserver after:", result.stdout)

    def test_unapproved_origin_rejected_before_install(self) -> None:
        result = self.run_installer(
            KASMVNC_DEB_URL="https://example.invalid/kasmvncserver.deb"
        )
        self.assert_rejected_before_install(result)
        self.assertIn("Unexpected package origin", result.stderr)

    def test_wrong_sha_rejected_before_install(self) -> None:
        result = self.run_installer(KASMVNC_DEB_SHA256="0" * 64)
        self.assert_rejected_before_install(result)

    def test_wrong_package_arch_or_version_rejected(self) -> None:
        cases = {
            "package": {"FAKE_PACKAGE": "not-kasmvncserver"},
            "architecture": {"FAKE_ARCH": "arm64"},
            "version": {"FAKE_VERSION": "9.9.9-1"},
        }
        for name, overrides in cases.items():
            with self.subTest(case=name):
                self.reset_run_state()
                result = self.run_installer(**overrides)
                self.assert_rejected_before_install(result)

    def test_same_or_older_installed_version(self) -> None:
        for before in ("1.3.4-1", "1.5.2-1+yuki20261026", TARGET):
            with self.subTest(before=before):
                self.reset_run_state()
                result = self.run_installer(FAKE_BEFORE=before)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.apt_install_calls(), 1)

    def test_unreviewed_newer_version_rejected(self) -> None:
        result = self.run_installer(FAKE_BEFORE="1.5.3-1")
        self.assert_rejected_before_install(result)
        combined = result.stdout + result.stderr
        self.assertTrue(
            "Refusing downgrade" in combined or "newer" in combined.lower(),
            combined,
        )

    def test_post_install_version_mismatch_rejected(self) -> None:
        result = self.run_installer(FAKE_BEFORE="1.3.4-1", FAKE_AFTER="1.5.1-1")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.apt_install_calls(), 1)
        self.assertIn("kasmvncserver after:", result.stdout)

    def test_xorg_minimum_and_newer_pass(self) -> None:
        for xorg in (MIN_XORG, "12101026"):
            with self.subTest(xorg=xorg):
                self.reset_run_state()
                result = self.run_installer(FAKE_XORG=xorg)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_old_or_unparseable_xorg_rejected(self) -> None:
        for xorg in ("12101024", "", "not-a-version"):
            with self.subTest(xorg=xorg):
                self.reset_run_state()
                result = self.run_installer(FAKE_XORG=xorg)
                self.assertNotEqual(
                    result.returncode, 0, result.stdout + result.stderr
                )

    @unittest.skip(
        "No limited downgrade is designed: the integrated package is newer than the prior fork package."
    )
    def test_scoped_downgrade_only_if_reviewed(self) -> None:
        self.fail("limited downgrade is intentionally not implemented")


if __name__ == "__main__":
    unittest.main()
