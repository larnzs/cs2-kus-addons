#!/usr/bin/env python3
"""Validate mode-scoped CounterStrikeSharp plugin load/unload consistency."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CFG_ROOT = ROOT / "game" / "csgo" / "cfg"
PLUGINS_ROOT = ROOT / "game" / "csgo" / "addons" / "counterstrikesharp"
UNLOAD_CFG = CFG_ROOT / "unload_plugins.cfg"
POLICY_FILE = ROOT / "scripts" / "plugin-mode-policy.json"

LOAD_RE = re.compile(r'^\s*css_plugins\s+load\s+"([^"]+)"', re.IGNORECASE)
UNLOAD_RE = re.compile(r'^\s*css_plugins\s+unload\s+"([^"]+)"', re.IGNORECASE)
MODE_RE = re.compile(r'^\s*css_gamemode\b', re.IGNORECASE)
EXEC_UNLOAD_RE = re.compile(r'^\s*exec\s+unload_plugins\.cfg\b', re.IGNORECASE)
DLL_PATH_RE = re.compile(r"^plugins/.+\.dll$", re.IGNORECASE)


def read_lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8-sig").splitlines()


def commands(path: Path, pattern: re.Pattern[str]) -> list[tuple[int, str]]:
    found: list[tuple[int, str]] = []
    for number, line in enumerate(read_lines(path), start=1):
        stripped = line.lstrip()
        if not stripped or stripped.startswith("//") or stripped.startswith("#"):
            continue
        match = pattern.match(line)
        if match:
            found.append((number, match.group(1).strip()))
    return found


def main() -> int:
    errors: list[str] = []
    if not CFG_ROOT.is_dir() or not UNLOAD_CFG.is_file() or not POLICY_FILE.is_file():
        print("ERROR: missing CFG root, unload file, or plugin-mode policy.", file=sys.stderr)
        return 1

    try:
        policy = json.loads(POLICY_FILE.read_text(encoding="utf-8"))
        afk = policy["afk_manager"]
        afk_plugin = afk["plugin"]
        enabled_modes = set(afk["enabled_modes"])
        disabled_modes = set(afk["disabled_modes"])
    except (KeyError, TypeError, json.JSONDecodeError) as exc:
        print(f"ERROR: invalid {POLICY_FILE.relative_to(ROOT)}: {exc}", file=sys.stderr)
        return 1

    if enabled_modes & disabled_modes:
        errors.append(f"AFK policy contains modes in both lists: {sorted(enabled_modes & disabled_modes)}")

    mode_configs: dict[str, Path] = {}
    modes_missing_reset: list[str] = []
    for path in sorted(CFG_ROOT.glob("*.cfg")):
        uncommented = [line for line in read_lines(path) if not line.lstrip().startswith("//")]
        if any(MODE_RE.match(line) for line in uncommented):
            if any(EXEC_UNLOAD_RE.match(line) for line in uncommented):
                mode_configs[path.name] = path
            else:
                modes_missing_reset.append(path.name)

    if modes_missing_reset:
        errors.append(f"Primary game-mode CFGs missing exec unload_plugins.cfg: {sorted(modes_missing_reset)}")

    policy_modes = enabled_modes | disabled_modes
    actual_modes = set(mode_configs)
    if actual_modes - policy_modes:
        errors.append(f"Game-mode CFGs missing AFK policy entries: {sorted(actual_modes - policy_modes)}")
    if policy_modes - actual_modes:
        errors.append(f"AFK policy references missing/non-mode CFGs: {sorted(policy_modes - actual_modes)}")

    unload_commands = commands(UNLOAD_CFG, UNLOAD_RE)
    unload_paths = [target for _, target in unload_commands if DLL_PATH_RE.match(target)]
    duplicates = sorted({target for target in unload_paths if unload_paths.count(target) > 1})
    if duplicates:
        errors.append(f"Central unload list contains duplicate DLL paths: {duplicates}")

    for line_number, target in unload_commands:
        if DLL_PATH_RE.match(target) and not (PLUGINS_ROOT / target).is_file():
            errors.append(f"unload_plugins.cfg:{line_number}: DLL does not exist: {target}")

    all_cfg_files = sorted(CFG_ROOT.rglob("*.cfg"))
    unique_loaded_paths: set[str] = set()
    for cfg in all_cfg_files:
        path_loads = [
            (line, target) for line, target in commands(cfg, LOAD_RE)
            if DLL_PATH_RE.match(target)
        ]
        for line_number, target in path_loads:
            unique_loaded_paths.add(target)
            if not (PLUGINS_ROOT / target).is_file():
                errors.append(f"{cfg.relative_to(ROOT)}:{line_number}: loaded DLL does not exist: {target}")
            if target not in unload_paths:
                errors.append(f"{cfg.relative_to(ROOT)}:{line_number}: {target} is loaded but absent from unload_plugins.cfg")

        # Sub-configs inherit the reset from their parent mode CFG. If this CFG
        # explicitly runs the reset itself, its own loads must come after it.
        reset_lines = [
            number for number, line in enumerate(read_lines(cfg), start=1)
            if EXEC_UNLOAD_RE.match(line) and not line.lstrip().startswith("//")
        ]
        if reset_lines and any(number < reset_lines[0] for number, _ in path_loads):
            errors.append(f"{cfg.relative_to(ROOT)}: a path-based plugin loads before its central reset")

    for mode_name, path in sorted(mode_configs.items()):
        mode_lines = read_lines(path)
        reset_lines = [
            number for number, line in enumerate(mode_lines, start=1)
            if EXEC_UNLOAD_RE.match(line) and not line.lstrip().startswith("//")
        ]
        direct_load_lines = [
            number for number, line in enumerate(mode_lines, start=1)
            if LOAD_RE.match(line) and not line.lstrip().startswith("//")
            and DLL_PATH_RE.match(LOAD_RE.match(line).group(1).strip())
        ]
        if not reset_lines or any(number < reset_lines[0] for number in direct_load_lines):
            errors.append(f"{mode_name}: central unload reset must precede every direct DLL load")

    for mode_name in sorted(enabled_modes & actual_modes):
        loads = [target for _, target in commands(mode_configs[mode_name], LOAD_RE) if target == afk_plugin]
        if len(loads) != 1:
            errors.append(f"{mode_name}: expected exactly one AFKManager load, found {len(loads)}")

    for mode_name in sorted(disabled_modes & actual_modes):
        loads = [target for _, target in commands(mode_configs[mode_name], LOAD_RE) if target == afk_plugin]
        if loads:
            errors.append(f"{mode_name}: AFKManager must remain disabled, but a load command exists")

    if afk_plugin not in unload_paths:
        errors.append(f"AFKManager is enabled in mode CFGs but missing from unload_plugins.cfg: {afk_plugin}")

    if errors:
        print("FAIL: mode plugin lifecycle validation")
        for error in errors:
            print(f" - {error}")
        return 1

    print(
        "PASS: validated "
        f"{len(all_cfg_files)} CFG files, {len(mode_configs)} mode CFGs, "
        f"{len(unique_loaded_paths)} unique path-loaded plugin DLLs; "
        f"AFKManager enabled in {len(enabled_modes)} modes and disabled in {len(disabled_modes)}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
