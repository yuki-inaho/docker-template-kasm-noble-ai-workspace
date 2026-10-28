import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).resolve().parents[1] / "scripts/audit-npm-dependencies.py"
SPEC = importlib.util.spec_from_file_location("audit_npm", PATH)
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


class AuditTest(unittest.TestCase):
    def test_lock_collects_bundled_and_rejects_unverified_sources(self):
        lock = {"packages": {
            "": {},
            "node_modules/npm": {"version": "1.2.3", "resolved": "https://registry.npmjs.org/npm/-/npm-1.2.3.tgz", "integrity": "sha512-test"},
            "node_modules/npm/node_modules/dep": {"version": "4.5.6", "inBundle": True},
        }}
        self.assertEqual(AUDIT.packages_from_lock(lock), {("npm", "1.2.3"), ("dep", "4.5.6")})
        lock["packages"]["node_modules/npm"]["resolved"] = "https://example.invalid/npm.tgz"
        with self.assertRaises(ValueError):
            AUDIT.packages_from_lock(lock)

    def test_tree_filters_unrelated_global_packages(self):
        tree = {"dependencies": {name: {"version": "1.0.0"} for name in AUDIT.ROOTS}}
        tree["dependencies"]["npm"]["dependencies"] = {"dep": {"version": "2.0.0"}, "optional": {}}
        tree["dependencies"]["private-package"] = {"version": "9.0.0"}
        packages = AUDIT.packages_from_tree(tree)
        self.assertIn(("dep", "2.0.0"), packages)
        self.assertNotIn(("private-package", "9.0.0"), packages)

    def test_pagination_and_malware_advisories(self):
        calls = []
        def query(batch):
            calls.append(batch)
            if len(calls) == 1:
                return [{"vulns": [{"id": "GHSA-test"}], "next_page_token": "next"}]
            return [{"vulns": [{"id": "MAL-2026-test"}]}]
        findings = AUDIT.scan({("example", "1.0.0")}, query=query)
        self.assertEqual({item[2] for item in findings}, {"GHSA-test", "MAL-2026-test"})
        self.assertEqual(calls[1][0]["page_token"], "next")

    def test_incomplete_response_is_rejected(self):
        with self.assertRaises(ValueError):
            AUDIT.scan({("example", "1.0.0")}, query=lambda _: [])

    def test_tree_with_unexpected_name_is_not_sent_for_scanning(self):
        lock = {"packages": {"": {}, "node_modules/npm": {
            "version": "1.0.0", "resolved": "https://registry.npmjs.org/npm/-/npm-1.0.0.tgz",
            "integrity": "sha512-test"}}}
        with self.assertRaises(ValueError):
            AUDIT.restrict_to_lock_names({("private-name", "1.0.0")}, lock)


if __name__ == "__main__":
    unittest.main()
