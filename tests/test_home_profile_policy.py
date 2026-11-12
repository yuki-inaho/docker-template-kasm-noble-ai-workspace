#!/usr/bin/env python3
"""Policy tests for the kasm-user home and login-shell repair.

These are static checks on the image build scripts. The runtime behaviour is
exercised separately against a built image by scripts/test-home-profile-runtime.sh.
"""

from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"


def function_body(script: pathlib.Path, name: str) -> str:
    text = script.read_text(encoding="utf-8")
    match = re.search(
        rf"^{re.escape(name)}\(\) \{{\n(.*?)^\}}$",
        text,
        flags=re.MULTILINE | re.DOTALL,
    )
    if match is None:
        raise AssertionError(f"{name} is missing from {script.name}")
    return match.group(1)


def command_lines(body: str) -> str:
    return "\n".join(
        line for line in body.splitlines() if not line.lstrip().startswith("#")
    )


class DefaultProfileTest(unittest.TestCase):
    def setUp(self) -> None:
        self.script = SCRIPTS / "configure-default-profile.sh"

    def test_profile_is_written_with_tool_path(self) -> None:
        body = function_body(self.script, "configure_profile")
        self.assertIn("# >>> kasm-noble-ai-workspace-profile", body)
        self.assertIn(
            'export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"',
            body,
        )
        self.assertIn('if [ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ]; then', body)
        self.assertIn('. "$HOME/.bashrc"', body)

    def test_bashrc_path_export_is_idempotent(self) -> None:
        text = self.script.read_text(encoding="utf-8")
        self.assertIn('case ":$PATH:" in', text)
        self.assertIn('*":$HOME/.opencode/bin:"*) ;;', text)

    def test_profile_is_registered_in_main(self) -> None:
        body = function_body(self.script, "main")
        self.assertIn("configure_profile", body)


class RuntimeRepairTest(unittest.TestCase):
    def setUp(self) -> None:
        self.script = SCRIPTS / "runtime-init.sh"

    def test_missing_profile_is_restored_without_clobber(self) -> None:
        body = function_body(self.script, "configure_home_profile")
        self.assertIn("cp -an", body)
        self.assertIn("chmod 0755", body)
        self.assertIn(".local/bin/herdr", body)
        self.assertIn(".opencode/bin/opencode", body)
        self.assertIn("# >>> kasm-noble-ai-workspace-profile", body)
        self.assertIn("# >>> kasm-noble-ai-workspace-runtime", body)

    def test_kasm_managed_files_are_not_chowned(self) -> None:
        body = command_lines(function_body(self.script, "configure_home_profile"))
        for managed in (".vast_api_key", ".kasmpasswd", ".Xauthority", ".vnc"):
            with self.subTest(path=managed):
                self.assertNotIn(managed, body)

    def test_login_shell_is_changed_to_bash(self) -> None:
        body = function_body(self.script, "configure_login_shell")
        self.assertIn("usermod -s /bin/bash", body)

    def test_broken_vast_pyenv_root_is_repaired(self) -> None:
        body = function_body(self.script, "configure_home_profile")
        self.assertIn('export PYENV_ROOT="/opt/pyenv"', body)
        self.assertIn("grep -Fqx 'export PYENV_ROOT='", body)

    def test_repair_runs_before_workspace_setup(self) -> None:
        body = function_body(self.script, "main")
        self.assertLess(
            body.index("configure_home_profile"),
            body.index("configure_workspace"),
        )


class ImagePolicyTest(unittest.TestCase):
    def test_image_sets_bash_login_shell(self) -> None:
        dockerfile = (ROOT / "Dockerfile").read_text(encoding="utf-8")
        self.assertIn("usermod -s /bin/bash kasm-user", dockerfile)

    def test_scripts_do_not_embed_credential_like_values(self) -> None:
        pattern = re.compile(
            r"(^|[^A-Za-z0-9])(sk-|hf_|ntn_|dckr_pat_|xai-)[A-Za-z0-9_-]{16,}"
        )
        for path in sorted(SCRIPTS.glob("*.sh")):
            with self.subTest(script=path.name):
                self.assertIsNone(pattern.search(path.read_text(encoding="utf-8")))


if __name__ == "__main__":
    unittest.main()
