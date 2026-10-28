#!/usr/bin/env python3
"""Patch specific vulnerable libraries bundled by npm 12.2.1."""
import base64
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import sys
import tarfile
import tempfile
import urllib.request

PATCHES = (
    ("undici", "6.29.0", "6.29.1", "node-gyp", "^6.25.0"),
    ("ip-address", "10.7.2", "10.7.5", "socks", "^10.1.1"),
)
AUDIT_PATH = Path(__file__).with_name("audit-npm-dependencies.py")


def get_https(url):
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args, **kwargs):
            raise ValueError("Registry redirected the request")
    with urllib.request.build_opener(NoRedirect).open(url, timeout=120) as response:
        content = response.read(128 * 1024 * 1024 + 1)
        if len(content) > 128 * 1024 * 1024:
            raise ValueError("Registry response is too large")
        return content


def fetch_package(name, version, fetch=get_https):
    meta = json.loads(fetch(f"https://registry.npmjs.org/{name}/{version}"))
    expected_url = f"https://registry.npmjs.org/{name}/-/{name}-{version}.tgz"
    if (meta.get("name") != name or meta.get("version") != version or
            meta.get("dist", {}).get("tarball") != expected_url or
            meta.get("dependencies")):
        raise ValueError(f"Unexpected registry metadata for {name}@{version}")
    integrity = meta["dist"].get("integrity", "")
    content = fetch(expected_url)
    actual = "sha512-" + base64.b64encode(hashlib.sha512(content).digest()).decode()
    if integrity != actual:
        raise ValueError(f"Integrity mismatch for {name}@{version}")
    return content


def unpack(content, dest, name, version):
    with tarfile.open(fileobj=io.BytesIO(content), mode="r:gz") as archive:
        members = archive.getmembers()
        if len(members) > 10000 or sum(m.size for m in members) > 128 * 1024 * 1024:
            raise ValueError("Package archive is too large")
        for member in members:
            path = PurePosixPath(member.name)
            if (not path.parts or path.parts[0] != "package" or ".." in path.parts or
                    not (member.isfile() or member.isdir())):
                raise ValueError("Unsafe package archive entry")
        for member in members:
            target = dest.joinpath(*PurePosixPath(member.name).parts)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(member) as source, target.open("wb") as output:
                    shutil.copyfileobj(source, output)
                target.chmod(member.mode & 0o755)
    package = dest / "package"
    manifest = json.loads((package / "package.json").read_text())
    if manifest.get("name") != name or manifest.get("version") != version or manifest.get("dependencies"):
        raise ValueError(f"Unexpected package contents for {name}@{version}")
    return package


def apply_patches(global_root, fetch=get_https, audit=None):
    npm_modules = global_root / "npm/node_modules"
    pending = []
    for name, old, new, dependent, expected_range in PATCHES:
        directory = npm_modules / name
        if directory.is_symlink():
            raise ValueError(f"Expected npm's bundled {name} directory")
        if not directory.exists():
            print(f"[npm-patch] {name}: not present")
            continue
        if not directory.is_dir():
            raise ValueError(f"Expected npm's bundled {name} directory")
        manifest = json.loads((directory / "package.json").read_text())
        if manifest.get("version") != old:
            print(f"[npm-patch] {name} {manifest.get('version')}: no targeted patch needed")
            continue
        parent = json.loads((npm_modules / dependent / "package.json").read_text())
        if parent.get("dependencies", {}).get(name) != expected_range:
            raise ValueError(f"Unexpected {dependent} dependency range for {name}")
        pending.append((name, new, directory))
    if not pending:
        return
    if audit is None:
        spec = importlib.util.spec_from_file_location("audit_npm", AUDIT_PATH)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        audit = module.scan
    findings = audit({(name, version) for name, version, _ in pending})
    if findings:
        raise ValueError(f"Replacement versions have OSV advisories: {sorted(findings)}")
    temp = Path(tempfile.mkdtemp(prefix=".npm-patch-", dir=npm_modules))
    try:
        staged = []
        for index, (name, version, original) in enumerate(pending):
            workspace = temp / str(index)
            workspace.mkdir()
            extracted = unpack(fetch_package(name, version, fetch), workspace, name, version)
            staged.append((name, version, original, extracted, workspace / "original"))
        for name, version, original, extracted, backup in staged:
            # OverlayFS cannot always rename a directory inherited from a lower
            # image layer. Copy a recoverable backup before removing it.
            shutil.copytree(original, backup, symlinks=True)
            try:
                shutil.rmtree(original)
                os.replace(extracted, original)
            except Exception:
                if original.exists():
                    shutil.rmtree(original)
                shutil.copytree(backup, original, symlinks=True)
                raise
            print(f"[npm-patch] updated bundled {name} to {version}")
            shutil.rmtree(backup)
    except BaseException:
        # Preserve backups if restoration was interrupted or failed.
        print(f"[npm-patch] update interrupted; inspect recovery files in {temp}", file=sys.stderr)
        raise
    else:
        shutil.rmtree(temp)


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("Usage: patch-npm-bundled.py NPM_GLOBAL_ROOT")
        apply_patches(Path(sys.argv[1]))
    except (OSError, ValueError, KeyError, tarfile.TarError) as exc:
        print(f"[npm-patch] unable to apply security patches: {exc}", file=sys.stderr)
        sys.exit(1)
