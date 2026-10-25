#!/usr/bin/env python3
"""Update the stable release, source hash, and reproducible pnpm store hash."""
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
RELEASE = ROOT / "nix/release.json"
FAKE_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="


def run(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True)


def main():
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "open-design-nix-updater"}
    if token := os.environ.get("GH_TOKEN"):
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        "https://api.github.com/repos/nexu-io/open-design/releases/latest", headers=headers
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        latest = json.load(response)
    tag = latest["tag_name"]
    match = re.fullmatch(r"open-design-v(\d+\.\d+\.\d+)", tag)
    if not match or latest["draft"] or latest["prerelease"]:
        raise RuntimeError(f"Unexpected stable release: {tag!r}")
    previous = RELEASE.read_text()
    old = json.loads(previous)
    version = match[1]
    if version == old["version"]:
        print(f"Already at {tag}")
        return

    source = json.loads(run(
        "nix", "store", "prefetch-file", "--unpack", "--json",
        f"https://github.com/nexu-io/open-design/archive/refs/tags/{tag}.tar.gz",
    ))
    updated = {"version": version, "srcHash": source["hash"], "pnpmDepsHash": FAKE_HASH}

    def write():
        RELEASE.write_text(json.dumps(updated, indent=2) + "\n")

    try:
        write()
        result = subprocess.run(
            ["nix", "build", "path:.#open-design.pnpmDeps", "--no-link", "-L"],
            cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        print(result.stdout)
        hashes = re.findall(r"got:\s+(sha256-[A-Za-z0-9+/]+=*)", result.stdout)
        if result.returncode == 0 or len(hashes) != 1:
            raise RuntimeError("Dependency hash calculation failed; see build output above")
        updated["pnpmDepsHash"] = hashes[0]
        write()
        subprocess.run(["nix", "build", "path:.#default", "--no-link", "-L"], cwd=ROOT, check=True)
    except BaseException:
        RELEASE.write_text(previous)
        raise
    print(f"Updated to {tag}")


if __name__ == "__main__":
    main()
