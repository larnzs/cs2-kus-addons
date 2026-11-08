#!/usr/bin/env python3
"""Regression guard for the GiveNamedItem signature fix from CSS PR #1120."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {
    "windows": "48 89 5C 24 ? 48 89 74 24 ? 48 89 7C 24 ? 44 89 44 24",
    "linux": (
        "55 48 89 E5 41 57 41 56 41 55 41 54 53 48 81 EC ? ? ? ? "
        "48 89 BD ? ? ? ? 89 95 ? ? ? ? 48 89 8D ? ? ? ? 44 89 85"
    ),
}
OLD = {
    "windows": (
        "48 89 5C 24 ? 48 89 74 24 ? 55 57 41 55 41 56 41 57 "
        "48 8D 6C 24 ? 48 81 EC ? ? ? ? 4D 8B F9"
    ),
    "linux": "55 48 89 E5 41 57 41 56 41 55 41 54 53 48 81 EC D8 00 00 00 48 89 8D 18 FF FF FF",
}
FILES = (
    ROOT / "game/csgo/addons/counterstrikesharp/gamedata/gamedata.json",
    ROOT / "game/csgo/addons/windows/addons/counterstrikesharp/gamedata/gamedata.json",
)


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


manifest_path = ROOT / "DEPENDENCIES.json"
try:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    css = next(item for item in manifest["addons"] if item["name"] == "CounterStrikeSharp")
    version = tuple(int(part) for part in css["version"].split("."))
except (OSError, KeyError, StopIteration, ValueError, json.JSONDecodeError) as exc:
    fail(f"could not read CounterStrikeSharp manifest version: {exc}")

if version < (1, 0, 347):
    fail(f"CounterStrikeSharp {css['version']} predates the GiveNamedItem signature fix (1.0.347)")

for path in FILES:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        signatures = data["GiveNamedItem"]["signatures"]
    except (OSError, KeyError, json.JSONDecodeError) as exc:
        fail(f"{path.relative_to(ROOT)} has no valid GiveNamedItem signatures: {exc}")

    for platform, expected in EXPECTED.items():
        actual = " ".join(signatures.get(platform, "").split())
        if actual != expected:
            fail(
                f"{path.relative_to(ROOT)}: {platform} GiveNamedItem signature differs from "
                f"the known fixed pattern. Expected: {expected!r}; got: {actual!r}"
            )
        if actual == OLD[platform]:
            fail(f"{path.relative_to(ROOT)}: obsolete pre-fix {platform} GiveNamedItem signature found")

print(
    f"PASS: CounterStrikeSharp {css['version']} has the fixed GiveNamedItem signatures "
    "in both Linux and Windows payload copies."
)
