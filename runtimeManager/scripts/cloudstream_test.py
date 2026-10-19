#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
import threading
import time
import urllib.request

MAIN = "com.aayush262.dartotsu_extension_bridge.Main"


def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read()


def download_repo(repo_url, target, limit, only):
    os.makedirs(target, exist_ok=True)
    manifest = json.loads(fetch(repo_url))
    plugins = []
    for list_url in manifest.get("pluginLists", []):
        plugins.extend(json.loads(fetch(list_url)))
    if only:
        plugins = [p for p in plugins if p.get("internalName") in only]
    if limit:
        plugins = plugins[:limit]
    for p in plugins:
        path = os.path.join(target, p["internalName"] + ".cs3")
        if not os.path.exists(path):
            with open(path, "wb") as f:
                f.write(fetch(p["url"]))
    return len(plugins)


def main():
    ap = argparse.ArgumentParser(
        description="Run the CloudStream desktop jar from the terminal and load every .cs3 in a folder."
    )
    ap.add_argument("jar", help="cloudStreamDesktop-all.jar, or a classpath joined with ':' (Main class is added)")
    ap.add_argument("plugins", help="folder holding .cs3 files")
    ap.add_argument("--work", default="cloudstream-work", help="app data folder for the jar")
    ap.add_argument("--repo", help="repo.json url; its plugins are downloaded into the plugins folder first")
    ap.add_argument("--limit", type=int, default=0, help="only download the first N plugins of the repo")
    ap.add_argument("--only", nargs="*", default=[], help="only download these internal names")
    ap.add_argument("--xmx", default="1536m", help="max heap for the jar")
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--log", default="cloudstream.log", help="file that receives every log line")
    args = ap.parse_args()

    if args.repo:
        count = download_repo(args.repo, args.plugins, args.limit, set(args.only))
        print(f"downloaded {count} plugins into {args.plugins}")
    os.makedirs(args.work, exist_ok=True)

    if ":" in args.jar:
        cmd = ["java", f"-Xmx{args.xmx}", "-cp", args.jar, MAIN]
    else:
        cmd = ["java", f"-Xmx{args.xmx}", "-jar", args.jar]
    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    logs, replies = [], {}

    def reader():
        for line in proc.stdout:
            line = line.rstrip("\n")
            if line.startswith('{"id"'):
                try:
                    reply = json.loads(line)
                    replies[reply["id"]] = reply
                    continue
                except (ValueError, KeyError):
                    pass
            logs.append(line)

    threading.Thread(target=reader, daemon=True).start()

    def call(i, method, params):
        proc.stdin.write(json.dumps({"id": i, "method": method, "args": params}) + "\n")
        proc.stdin.flush()
        deadline = time.time() + args.timeout
        while i not in replies and time.time() < deadline:
            time.sleep(0.2)
        return replies.get(i)

    call(1, "initializeDesktop", {"path": os.path.abspath(args.work)})
    reply = call(2, "getInstalledAnimeExtensions", {"path": os.path.abspath(args.plugins)})
    time.sleep(2)
    proc.terminate()

    with open(args.log, "w") as f:
        f.write("\n".join(logs))

    loaded = sum(1 for l in logs if "Loaded plugin" in l)
    failed = [l for l in logs if "Failed loading" in l or "Failed to load" in l]
    fallbacks = sum(1 for l in logs if "keeping untouched original" in l)
    files = len([n for n in os.listdir(args.plugins) if n.endswith(".cs3")])
    sources = 0
    if reply and reply.get("success"):
        sources = len(json.loads(reply["data"]))
    elif reply:
        print("request failed:", reply.get("error"))
    print(f"plugins on disk: {files}")
    print(f"plugins loaded: {loaded}")
    print(f"sources reported: {sources}")
    print(f"classes left unrepaired: {fallbacks}")
    for line in failed:
        print(line[:240])
    print(f"full log: {args.log}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
