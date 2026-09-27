#!/usr/bin/env python3
"""Pick an image from one or more folders, unique per screen."""

from __future__ import annotations

import argparse
import json
import os
import random
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse

try:
    import fcntl
except ImportError:  # pragma: no cover
    fcntl = None

IMAGE_SUFFIXES = {
    ".jpg",
    ".jpeg",
    ".png",
    ".webp",
    ".bmp",
    ".tif",
    ".tiff",
    ".gif",
    ".svg",
    ".svgz",
    ".avif",
    ".heif",
    ".heic",
    ".jxl",
}

SKIP_DIR_NAMES = {".git", ".hg", ".svn", "node_modules", ".Trash", "lost+found"}


def cache_path() -> Path:
    base = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    directory = Path(base) / "org.grey.simpleslideshow"
    directory.mkdir(parents=True, exist_ok=True)
    return directory / "claims.json"


def normalize_folder(raw: str) -> Path:
    text = raw.strip()
    if text.startswith("file:"):
        parsed = urlparse(text)
        text = unquote(parsed.path)
    return Path(text).expanduser()


def collect_images(folders: list[str]) -> list[str]:
    found: set[str] = set()
    for raw in folders:
        root = normalize_folder(raw)
        if not root.is_dir():
            continue
        for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
            dirnames[:] = [
                name
                for name in dirnames
                if name not in SKIP_DIR_NAMES and not name.startswith(".")
            ]
            for name in filenames:
                suffix = Path(name).suffix.lower()
                if suffix not in IMAGE_SUFFIXES:
                    continue
                path = Path(dirpath) / name
                try:
                    found.add(str(path.resolve()))
                except OSError:
                    found.add(str(path))
    return found


def load_claims(handle) -> dict:
    handle.seek(0)
    raw = handle.read()
    if not raw:
        return {}
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def save_claims(handle, claims: dict) -> None:
    handle.seek(0)
    handle.truncate()
    handle.write(json.dumps(claims, indent=2, sort_keys=True))
    handle.flush()
    os.fsync(handle.fileno())


def pick(args: argparse.Namespace) -> dict:
    images = collect_images(args.folder)
    live_screens = set(args.screens or [])
    live_screens.add(args.screen)

    state_file = cache_path()
    with open(state_file, "a+", encoding="utf-8") as handle:
        if fcntl is not None:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        claims = load_claims(handle)
        if live_screens:
            claims = {name: path for name, path in claims.items() if name in live_screens}

        taken = {
            os.path.realpath(path)
            for name, path in claims.items()
            if name != args.screen and path
        }
        avoid = set(taken)
        if args.avoid:
            try:
                avoid.add(str(Path(args.avoid).resolve()))
            except OSError:
                avoid.add(args.avoid)

        unique = [path for path in images if path not in taken]
        pool = [path for path in unique if path not in avoid] or unique or images

        if not pool:
            save_claims(handle, claims)
            return {
                "error": "no images found in the configured folders",
                "count": 0,
                "path": "",
            }

        choice = random.choice(pool)
        claims[args.screen] = choice
        save_claims(handle, claims)
        return {
            "path": choice,
            "count": len(images),
            "unique": len(unique),
            "screen": args.screen,
        }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--screen", required=True)
    parser.add_argument(
        "--screens",
        default="",
        help="Comma-separated names of currently connected screens",
    )
    parser.add_argument("--folder", action="append", default=[], dest="folder")
    parser.add_argument("--avoid", default="")
    args = parser.parse_args()
    args.screens = [name for name in args.screens.split(",") if name]
    result = pick(args)
    sys.stdout.write(json.dumps(result))
    sys.stdout.write("\n")
    return 0 if not result.get("error") else 1


if __name__ == "__main__":
    raise SystemExit(main())