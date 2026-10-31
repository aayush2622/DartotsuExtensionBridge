#!/usr/bin/env python3
"""
prepare_release.py

Runs inside GitHub Actions, after `./gradlew buildAllPlugins` and after
the previous "latest" release assets (the .apk/.jar binaries only) have
been downloaded into `previous-release/`.

This script is the ONLY place in the whole pipeline that knows about
GitHub release tags / download URLs. plugin.gradle.kts stays completely
host-agnostic; this is where that gap gets filled in.

Per-plugin version history is NOT tracked via separate per-plugin JSON
release assets — there is exactly one version ledger, the aggregate
plugins.json already committed at the repo root, which this script reads
as REPO_PLUGINS_JSON before overwriting it.

For each builds/<plugin>/<plugin>-plugin.json:
  1. Look up the matching entry (by fileName) in the previous aggregate
     plugins.json.
  2. Compare the artifact's SHA-256 against the previous release's copy.
  3. If it changed (or there was no previous entry): bump versionCode
     by 1 and bump the patch segment of versionName.
  4. If unchanged: keep the previous version numbers as-is.
  5. Set downloadUrl to point at the (recreated) "latest" release.
  6. A desktop backend is published twice: the self-contained jar app builds
     from before the split know (`<name>-plugin.jar`, platform "desktop",
     versioned exactly as it always was) and the thin one for builds with the
     shared core (`<name>-split.jar`, platform "desktopSplit"). The split
     entry's first version is the fat one's plus one, so a client that has
     the fat jar always sees the split one as newer.
  7. A plugin that needs another one on its classpath (the desktop plugins
     need desktopCore) carries `requires: {name: minimum versionCode}`. When
     the plugin changed, the minimum is the required plugin's version in this
     release; when it did not, the plugin keeps the minimum it already had
     (its bytes are the same, so what it was built against is the same).
  8. Write the patched JSON back in place.

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
REPO_PLUGINS_JSON = Path("../plugins.json")
TAG = "latest"
SPLIT_PLATFORM = "desktopSplit"


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


def load_previous_index() -> dict[str, dict]:
    """fileName -> metadata, from the aggregate plugins.json already committed at the repo root."""
    entries = load_json(REPO_PLUGINS_JSON)
    if isinstance(entries, dict):
        return {}
    return {entry["fileName"]: entry for entry in entries if "fileName" in entry}


def process_plugin(metadata_path: Path, repo: str, previous_index: dict[str, dict]) -> tuple[dict, bool]:
    metadata = load_json(metadata_path)
    plugin_dir = metadata_path.parent
    file_name = metadata["fileName"]
    artifact_path = plugin_dir / file_name

    previous_metadata = previous_index.get(file_name, {})
    previous_artifact = PREVIOUS_DIR / file_name

    if not previous_metadata and metadata.get("platform") == SPLIT_PLATFORM:
        previous_metadata = previous_index.get(f"{metadata['name']}-plugin.jar", {})

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


def resolve_requires(results: list[tuple[Path, dict, bool]], previous_index: dict[str, dict]) -> None:
    """Replace the placeholder minimums Gradle wrote into `requires`."""
    versions = {
        metadata["name"]: int(metadata["versionCode"])
        for _, metadata, _ in results
        if metadata.get("platform") == SPLIT_PLATFORM
    }

    for metadata_path, metadata, changed in results:
        needs = metadata.get("requires")
        if not needs:
            continue

        previous = previous_index.get(metadata["fileName"], {}).get("requires", {})
        resolved = {}
        for dependency in needs:
            if dependency not in versions:
                sys.exit(f"[{metadata['name']}] requires {dependency}, which was not built.")
            if changed or dependency not in previous:
                resolved[dependency] = versions[dependency]
            else:
                resolved[dependency] = previous[dependency]

        metadata["requires"] = resolved
        metadata_path.write_text(json.dumps(metadata, indent=2) + "\n")


def main() -> None:
    repo = os.environ.get("GITHUB_REPOSITORY")
    if not repo:
        sys.exit("GITHUB_REPOSITORY environment variable is required.")

    metadata_files = sorted(
        [*BUILDS_DIR.glob("*/*-plugin.json"), *BUILDS_DIR.glob("*/*-split.json")]
    )
    if not metadata_files:
        print("No plugin metadata found under builds/ — nothing to release.")
        write_output("changed", "false")
        return

    previous_index = load_previous_index()

    results = []
    any_changed = False

    for metadata_path in metadata_files:
        metadata, changed = process_plugin(metadata_path, repo, previous_index)
        results.append((metadata_path, metadata, changed))
        any_changed = any_changed or changed
        status = "changed" if changed else "unchanged"
        print(
            f"[{metadata['name']} / {metadata['platform']}] {status} -> "
            f"v{metadata['versionName']} ({metadata['versionCode']})"
        )

    resolve_requires(results, previous_index)
    index = [metadata for _, metadata, _ in results]

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