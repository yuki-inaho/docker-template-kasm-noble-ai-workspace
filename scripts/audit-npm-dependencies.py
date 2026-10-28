#!/usr/bin/env python3
"""Check the selected public npm packages against OSV without uploading files."""
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOTS = ("npm", "@openai/codex", "playwright", "@playwright/cli")
API = "https://api.osv.dev/v1/querybatch"
SAFE_NAME = re.compile(r"^@?[a-z0-9][a-z0-9._~/-]*$", re.I)


def packages_from_lock(data):
    packages = set()
    for path, item in data["packages"].items():
        if not path:
            continue
        if item.get("link") or not item.get("version"):
            raise ValueError(f"Unsupported lock entry: {path}")
        resolved = item.get("resolved")
        if resolved:
            if not resolved.startswith("https://registry.npmjs.org/") or not item.get("integrity"):
                raise ValueError(f"Unverified package source: {path}")
        elif not item.get("inBundle"):
            raise ValueError(f"Missing package source: {path}")
        name = item.get("name") or path.rsplit("node_modules/", 1)[-1]
        packages.add((name, item["version"]))
    return packages


def packages_from_tree(data):
    roots = data.get("dependencies", {})
    missing = set(ROOTS) - roots.keys()
    if missing:
        raise ValueError(f"Missing expected packages: {', '.join(sorted(missing))}")
    packages = set()
    pending = [(name, roots[name]) for name in ROOTS]
    while pending:
        name, item = pending.pop()
        version = item.get("version")
        if version:
            packages.add((name, version))
        elif name in ROOTS:
            raise ValueError(f"Missing version for {name}")
        # npm lists unavailable optional platform packages as empty objects.
        pending.extend(item.get("dependencies", {}).items())
    return packages


def restrict_to_lock_names(packages, lock):
    # Validate the lock before using it as a list of public package names.
    validated = packages_from_lock(lock)
    allowed = {name for name, _ in validated}
    allowed.update(path.rsplit("node_modules/", 1)[-1]
                   for path in lock["packages"] if path)
    if any(name not in allowed for name, _ in packages):
        raise ValueError("Installed dependency tree differs from the public lock; scan withheld")
    return packages


def scan(packages, query=None):
    if not packages:
        raise ValueError("No npm packages found")
    if any(not SAFE_NAME.fullmatch(name) or not version for name, version in packages):
        raise ValueError("Invalid package name or version")
    pending = [({"package": {"ecosystem": "npm", "name": name}, "version": version},
                (name, version)) for name, version in sorted(packages)]
    findings = set()
    while pending:
        batch, pending = pending[:200], pending[200:]
        queries = [item[0] for item in batch]
        results = (query or query_osv)(queries)
        if len(results) != len(batch):
            raise ValueError("OSV returned an incomplete response")
        for (request, package), result in zip(batch, results):
            for vuln in result.get("vulns", []):
                identifier = vuln.get("id", "")
                if not identifier:
                    raise ValueError("OSV returned an advisory without an ID")
                findings.add((*package, identifier))
            if result.get("next_page_token"):
                pending.append(({**request, "page_token": result["next_page_token"]}, package))
    return findings


def query_osv(queries):
    request = urllib.request.Request(
        API, data=json.dumps({"queries": queries}).encode(),
        headers={"Content-Type": "application/json"}, method="POST")
    # Never send package information to a redirected host.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args, **kwargs):
            raise ValueError("OSV redirected the request")
    with urllib.request.build_opener(NoRedirect).open(request, timeout=60) as response:
        return json.load(response)["results"]


def main():
    if (len(sys.argv) not in (3, 5) or sys.argv[1] not in ("--lock", "--tree") or
            (len(sys.argv) == 5 and (sys.argv[1] != "--tree" or sys.argv[3] != "--allowed-lock"))):
        raise ValueError("Usage: audit-npm-dependencies.py --lock FILE | --tree FILE [--allowed-lock FILE]")
    data = json.loads(Path(sys.argv[2]).read_text())
    packages = packages_from_lock(data) if sys.argv[1] == "--lock" else packages_from_tree(data)
    if len(sys.argv) == 5:
        packages = restrict_to_lock_names(packages, json.loads(Path(sys.argv[4]).read_text()))
    findings = scan(packages)
    for name, version, identifier in sorted(findings):
        print(f"[npm-audit] {name}@{version}: {identifier}")
    malicious = [item for item in findings if item[2].startswith("MAL-")]
    print(f"[npm-audit] checked {len(packages)} versions; "
          f"{len(malicious)} malware advisories, {len(findings) - len(malicious)} other advisories")
    return 1 if malicious else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyError, ValueError, OSError, urllib.error.URLError) as exc:
        print(f"[npm-audit] unable to complete scan: {exc}", file=sys.stderr)
        sys.exit(2)
