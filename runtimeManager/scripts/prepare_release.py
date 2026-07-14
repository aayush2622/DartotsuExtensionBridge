#!/usr/bin/env python3
"""
prepare_release.py

Runs inside GitHub Actions, after `./gradlew buildAllPlugins` and after
the previous "latest" release assets have been downloaded into
`previous-release/`.

This script is the ONLY place in the whole pipeline that knows about
GitHub release tags / download URLs. plugin.gradle.kts stays completely
host-agnostic; this is where that gap gets filled in.

For each builds/<plugin>/<plugin>-plugin.json:
  1. Compare the artifact's SHA-256 against the previous release's copy.
  2. If it changed (or there was no previous release): bump versionCode
     by 1 and bump the patch segment of versionName.
  3. If unchanged: keep the previous version numbers as-is.
  4. Set downloadUrl to point at the (recreated) "latest" release.
  5. Write the patched JSON back in place.

Finally, writes builds/plugins.json as an aggregate index of every
plugin's metadata, and reports via $GITHUB_OUTPUT whether *anything*
changed, so the workflow knows whether to cut a new release at all.

builds/plugins.json is deliberately deterministic when nothing changed
(createdAt is preserved, not re-stamped) — the workflow copies it to
the repo root and commits it, and we don't want a no-op diff every run.
"""

import hashlib
import json
import os
import sys
from pathlib import Path

BUILDS_DIR = Path("builds")
PREVIOUS_DIR = Path("previous-release")
TAG = "latest"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()


def bump_patch(version_name: str) -> str:
    parts = (str(version_name).split(".") + ["0", "0", "0"])[:3]
    parts = [int(part) if part.isdigit() else 0 for part in parts]
    parts[2] += 1
    return ".".join(str(part) for part in parts)


def load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError:
        return {}


def download_url(repo: str, file_name: str) -> str:
    return f"https://github.com/{repo}/releases/download/{TAG}/{file_name}"


def process_plugin(metadata_path: Path, repo: str) -> tuple[dict, bool]:
    metadata = load_json(metadata_path)
    plugin_dir = metadata_path.parent
    file_name = metadata["fileName"]
    artifact_path = plugin_dir / file_name

    previous_metadata = load_json(PREVIOUS_DIR / metadata_path.name)
    previous_artifact = PREVIOUS_DIR / file_name

    changed = True
    if previous_artifact.exists():
        changed = sha256(artifact_path) != sha256(previous_artifact)

    if changed:
        metadata["versionCode"] = int(previous_metadata.get("versionCode", 0)) + 1
        metadata["versionName"] = bump_patch(previous_metadata.get("versionName", "1.0.0"))
        # keep the fresh createdAt stamped by Gradle for this build
    else:
        metadata["versionCode"] = previous_metadata.get("versionCode", metadata["versionCode"])
        metadata["versionName"] = previous_metadata.get("versionName", metadata["versionName"])
        metadata["createdAt"] = previous_metadata.get("createdAt", metadata["createdAt"])

    metadata["downloadUrl"] = download_url(repo, file_name)

    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n")
    return metadata, changed


def main() -> None:
    repo = os.environ.get("GITHUB_REPOSITORY")
    if not repo:
        sys.exit("GITHUB_REPOSITORY environment variable is required.")

    metadata_files = sorted(BUILDS_DIR.glob("*/*-plugin.json"))
    if not metadata_files:
        print("No plugin metadata found under builds/ — nothing to release.")
        write_output("changed", "false")
        return

    index = []
    any_changed = False

    for metadata_path in metadata_files:
        metadata, changed = process_plugin(metadata_path, repo)
        index.append(metadata)
        any_changed = any_changed or changed
        status = "changed" if changed else "unchanged"
        print(f"[{metadata['name']}] {status} -> v{metadata['versionName']} ({metadata['versionCode']})")

    (BUILDS_DIR / "plugins.json").write_text(json.dumps(index, indent=2) + "\n")

    write_output("changed", "true" if any_changed else "false")


def write_output(key: str, value: str) -> None:
    github_output = os.environ.get("GITHUB_OUTPUT")
    if not github_output:
        return
    with open(github_output, "a") as handle:
        handle.write(f"{key}={value}\n")


if __name__ == "__main__":
    main()