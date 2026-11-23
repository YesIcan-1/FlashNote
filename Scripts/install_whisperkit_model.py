#!/usr/bin/env python3
"""Install the checked WhisperKit large-v3 model for offline FlashNote use."""

import hashlib
import json
import os
import pathlib
import sys
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "Scripts" / "whisperkit_model_manifest.json"
DESTINATION = pathlib.Path.home() / "Library/Application Support/FlashNote/models/whisperkit"


def digest(path: pathlib.Path, kind: str) -> str:
    h = hashlib.sha256() if kind == "sha256" else hashlib.sha1()
    if kind == "git-sha1":
        h.update(f"blob {path.stat().st_size}\0".encode())
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def install(entry: dict) -> None:
    path = DESTINATION / entry["destination"]
    if path.is_file() and path.stat().st_size == entry["size"]:
        if digest(path, entry["hash_kind"]) == entry["hash"]:
            print(f"verified {entry['destination']}", flush=True)
            return
    path.parent.mkdir(parents=True, exist_ok=True)
    source_path = urllib.parse.quote(entry["source_path"], safe="/")
    url = f"https://modelscope.cn/models/{entry['repository']}/resolve/master/{source_path}"
    partial = path.with_name(path.name + ".partial")
    print(f"downloading {entry['destination']} ({entry['size']} bytes)", flush=True)
    request = urllib.request.Request(url, headers={"User-Agent": "FlashNote-model-installer/1.0"})
    with urllib.request.urlopen(request, timeout=120) as response, partial.open("wb") as target:
        while block := response.read(1024 * 1024):
            target.write(block)
    if partial.stat().st_size != entry["size"] or digest(partial, entry["hash_kind"]) != entry["hash"]:
        partial.unlink(missing_ok=True)
        raise ValueError(f"model hash mismatch: {entry['destination']}")
    os.replace(partial, path)
    print(f"verified {entry['destination']}", flush=True)


def main() -> int:
    entries = json.loads(MANIFEST.read_text())
    for entry in entries:
        install(entry)
    print(f"model ready: {DESTINATION}", flush=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"model installation failed: {error}", file=sys.stderr)
        sys.exit(1)
