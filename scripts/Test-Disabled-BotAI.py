#!/usr/bin/env python3
"""Ensure the unwanted BotAI plugin remains stored only in CSS's disabled directory."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CSS_ROOT = ROOT / "game/csgo/addons/counterstrikesharp"
ACTIVE = CSS_ROOT / "plugins/BotAI"
DISABLED = CSS_ROOT / "plugins/disabled/BotAI"
REQUIRED_FILES = ("BotAI.dll", "BotAI.deps.json", "Common.dll")
README = ROOT / "README.md"
UPDATER = ROOT / "scripts/update/plugins/cs2-botai.sh"
REQUIRED_UPDATERS = ROOT / "scripts/update/required-script-addons.txt"
CFG_ROOT = ROOT / "game/csgo/cfg"


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


if ACTIVE.exists():
    fail(f"active BotAI directory must not exist: {ACTIVE.relative_to(ROOT)}")

if not DISABLED.is_dir():
    fail(f"disabled BotAI payload is missing: {DISABLED.relative_to(ROOT)}")

for filename in REQUIRED_FILES:
    if not (DISABLED / filename).is_file():
        fail(f"disabled BotAI payload is incomplete; missing {filename}")

try:
    deps = json.loads((DISABLED / "BotAI.deps.json").read_text(encoding="utf-8"))
    target = deps["runtimeTarget"]["name"]
    assemblies = deps["targets"][target]
    plugin_key = next(key for key in assemblies if key.startswith("BotAI/"))
    plugin = assemblies[plugin_key]
except (OSError, KeyError, StopIteration, json.JSONDecodeError) as exc:
    fail(f"disabled BotAI dependency manifest is invalid: {exc}")

if "BotAI.dll" not in plugin.get("runtime", {}):
    fail("disabled BotAI dependency manifest does not declare BotAI.dll")

if "Common" not in plugin.get("dependencies", {}):
    fail("disabled BotAI dependency manifest no longer declares its Common dependency")

if not README.is_file():
    fail("README.md is missing")

readme_lines = README.read_text(encoding="utf-8-sig").splitlines()
catalog_rows = [line for line in readme_lines if line.startswith("| CS2-BotAI |")]
if len(catalog_rows) != 1:
    fail(f"expected exactly one CS2-BotAI payload catalog row, found {len(catalog_rows)}")

row = catalog_rows[0]
if "plugins/disabled/BotAI" not in row or "no updater by design" not in row.lower():
    fail("README must document BotAI as disabled-only and intentionally without an updater")

if UPDATER.exists():
    fail("CS2-BotAI updater must not be present while this plugin is decommissioned")

if REQUIRED_UPDATERS.is_file():
    required = {
        line.strip()
        for line in REQUIRED_UPDATERS.read_text(encoding="utf-8-sig").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }
    if "CS2-BotAI" in required:
        fail("decommissioned CS2-BotAI must not be a required automated updater")

load_re = re.compile(r"^\s*css_plugins\s+(?:load|reload)\s+(.+?)\s*$", re.IGNORECASE)
if CFG_ROOT.is_dir():
    for cfg in CFG_ROOT.rglob("*.cfg"):
        for number, line in enumerate(cfg.read_text(encoding="utf-8-sig").splitlines(), start=1):
            command = line.partition("//")[0].strip()
            match = load_re.match(command)
            if match and "botai" in match.group(1).lower():
                fail(f"BotAI is explicitly loaded by {cfg.relative_to(ROOT)}:{number}")

print("PASS: BotAI exists only under plugins/disabled/BotAI, has its dependency files, and is not scheduled for automatic loading or updating.")
