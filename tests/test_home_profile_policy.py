#!/usr/bin/env python3
"""Policy tests for the kasm-user home and login-shell repair.

The repair itself lives in scripts/home-repair.sh so the image startup and the
Vast.ai template onstart share one implementation. These tests also check that
runtime-init.sh only wires the shared script in, and that the image installs it.
"""

from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
DEFAULT_PROFILE = SCRIPTS / "configure-default-profile.sh"
RUNTIME_INIT = SCRIPTS / "runtime-init.sh"
HOME_REPAIR = SCRIPTS / "home-repair.sh"


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
    def test_profile_is_written_with_idempotent_tool_path(self) -> None:
        body = function_body(DEFAULT_PROFILE, "configure_profile")
        self.assertIn("# >>> kasm-noble-ai-workspace-profile", body)
        self.assertIn('case ":$PATH:" in', body)
        self.assertIn('*":$HOME/.opencode/bin:"*) ;;', body)
        self.assertIn('*) export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH" ;;', body)
        self.assertIn('if [ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ]; then', body)
        self.assertIn('. "$HOME/.bashrc"', body)

    def test_profile_is_registered_in_main(self) -> None:
        body = function_body(DEFAULT_PROFILE, "main")
        self.assertIn("configure_profile", body)

    def test_bashrc_path_export_is_idempotent(self) -> None:
        text = DEFAULT_PROFILE.read_text(encoding="utf-8")
        self.assertIn('case ":$PATH:" in', text)
        self.assertIn('*":$HOME/.opencode/bin:"*) ;;', text)


class RuntimeIntegrationTest(unittest.TestCase):
    def test_runtime_sources_the_shared_repair(self) -> None:
        text = RUNTIME_INIT.read_text(encoding="utf-8")
        self.assertIn("/usr/local/bin/kasm-home-repair", text)
        self.assertIn("home_repair_main", text)

    def test_runtime_does_not_redefine_the_repair(self) -> None:
        text = RUNTIME_INIT.read_text(encoding="utf-8")
        self.assertNotIn("configure_home_profile() {", text)
        self.assertNotIn("configure_login_shell() {", text)

    def test_repair_runs_before_workspace_setup(self) -> None:
        body = function_body(RUNTIME_INIT, "main")
        self.assertLess(body.index("home_repair_main"), body.index("configure_workspace"))


class HomeRepairTest(unittest.TestCase):
    def test_missing_profile_is_restored_without_clobber(self) -> None:
        body = function_body(HOME_REPAIR, "configure_home_profile")
        self.assertIn("cp -a --update=none", body)
        self.assertIn("chmod 0755", body)
        self.assertIn(".local/bin/herdr", body)
        self.assertIn(".opencode/bin/opencode", body)
        self.assertIn("# >>> kasm-noble-ai-workspace-profile", body)
        self.assertIn("# >>> kasm-noble-ai-workspace-runtime", body)

    def test_kasm_managed_files_are_not_chowned(self) -> None:
        body = command_lines(function_body(HOME_REPAIR, "configure_home_profile"))
        for managed in (".vast_api_key", ".kasmpasswd", ".Xauthority", ".vnc"):
            with self.subTest(path=managed):
                self.assertNotIn(managed, body)

    def test_login_shell_is_changed_to_bash(self) -> None:
        body = function_body(HOME_REPAIR, "configure_login_shell")
        self.assertIn("usermod -s /bin/bash", body)

    def test_broken_vast_pyenv_root_is_repaired(self) -> None:
        body = function_body(HOME_REPAIR, "configure_home_profile")
        self.assertIn('export PYENV_ROOT="/opt/pyenv"', body)
        self.assertIn("grep -Fqx 'export PYENV_ROOT='", body)

    def test_repair_can_be_disabled_or_forced(self) -> None:
        text = HOME_REPAIR.read_text(encoding="utf-8")
        self.assertIn("KASM_HOME_REPAIR", text)
        self.assertIn("KASM_HOME_REPAIR_FORCE", text)
        self.assertIn('if [[ "${KASM_HOME_REPAIR}" != "1" ]]', text)

    def test_path_export_is_idempotent(self) -> None:
        body = function_body(HOME_REPAIR, "configure_home_profile")
        self.assertIn('case ":$PATH:" in', body)
        self.assertIn('*":$HOME/.opencode/bin:"*) ;;', body)


class ImagePolicyTest(unittest.TestCase):
    def test_image_sets_bash_login_shell(self) -> None:
        dockerfile = (ROOT / "Dockerfile").read_text(encoding="utf-8")
        self.assertIn("usermod -s /bin/bash kasm-user", dockerfile)

    def test_image_installs_the_shared_repair(self) -> None:
        dockerfile = (ROOT / "Dockerfile").read_text(encoding="utf-8")
        self.assertIn("home-repair.sh /usr/local/bin/kasm-home-repair", dockerfile)

    def test_scripts_do_not_embed_credential_like_values(self) -> None:
        pattern = re.compile(
            r"(^|[^A-Za-z0-9])(sk-|hf_|ntn_|dckr_pat_|xai-)[A-Za-z0-9_-]{16,}"
        )
        for path in sorted(SCRIPTS.glob("*.sh")):
            with self.subTest(script=path.name):
                self.assertIsNone(pattern.search(path.read_text(encoding="utf-8")))


if __name__ == "__main__":
    unittest.main()
