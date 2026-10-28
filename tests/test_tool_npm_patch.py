import base64
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

PATH = Path(__file__).resolve().parents[1] / "scripts/patch-npm-bundled.py"
SPEC = importlib.util.spec_from_file_location("patch_npm", PATH)
PATCH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PATCH)


class NpmPatchTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.modules = self.root / "npm/node_modules"
        for name, old, _, dependent, expected in PATCH.PATCHES:
            for item in (name, dependent):
                (self.modules / item).mkdir(parents=True, exist_ok=True)
            (self.modules / name / "package.json").write_text(json.dumps({"name": name, "version": old}))
            (self.modules / dependent / "package.json").write_text(json.dumps({"dependencies": {name: expected}}))

    @staticmethod
    def archive(name, version, unsafe=False):
        data = json.dumps({"name": name, "version": version}).encode()
        output = io.BytesIO()
        with tarfile.open(fileobj=output, mode="w:gz") as archive:
            entry = tarfile.TarInfo("package/package.json")
            entry.size = len(data)
            archive.addfile(entry, io.BytesIO(data))
            if unsafe:
                entry = tarfile.TarInfo("package/../../escape")
                entry.size = 1
                archive.addfile(entry, io.BytesIO(b"x"))
        return output.getvalue()

    def fetch(self, url):
        for name, _, version, _, _ in PATCH.PATCHES:
            archive = self.archive(name, version, unsafe=getattr(self, "unsafe", False) and name == "ip-address")
            if url == f"https://registry.npmjs.org/{name}/{version}":
                integrity = "sha512-" + base64.b64encode(hashlib.sha512(archive).digest()).decode()
                return json.dumps({"name": name, "version": version, "dist": {
                    "tarball": f"https://registry.npmjs.org/{name}/-/{name}-{version}.tgz",
                    "integrity": integrity}}).encode()
            if url == f"https://registry.npmjs.org/{name}/-/{name}-{version}.tgz":
                return archive
        raise AssertionError(url)

    def test_updates_vulnerable_bundled_versions(self):
        PATCH.apply_patches(self.root, fetch=self.fetch, audit=lambda _: set())
        for name, _, version, _, _ in PATCH.PATCHES:
            self.assertEqual(json.loads((self.modules / name / "package.json").read_text())["version"], version)

    def test_bad_second_archive_preserves_both_packages(self):
        self.unsafe = True
        with self.assertRaises(ValueError):
            PATCH.apply_patches(self.root, fetch=self.fetch, audit=lambda _: set())
        for name, old, _, _, _ in PATCH.PATCHES:
            self.assertEqual(json.loads((self.modules / name / "package.json").read_text())["version"], old)

    def test_advisory_prevents_download(self):
        with self.assertRaises(ValueError):
            PATCH.apply_patches(self.root, fetch=lambda _: self.fail("should not download"),
                                audit=lambda _: {("undici", "6.29.1", "MAL-test")})

    def test_changed_dependent_range_is_rejected(self):
        (self.modules / "socks/package.json").write_text('{"dependencies":{"ip-address":"10.7.2"}}')
        with self.assertRaises(ValueError):
            PATCH.apply_patches(self.root, fetch=self.fetch, audit=lambda _: set())


if __name__ == "__main__":
    unittest.main()
