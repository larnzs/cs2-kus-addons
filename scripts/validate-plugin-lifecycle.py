#!/usr/bin/env python3
"""Validate mode-scoped CounterStrikeSharp plugin load/unload consistency."""

from __future__ import annotations

import json
import re
import shlex
import sys
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
CFG_ROOT = ROOT / "game" / "csgo" / "cfg"
PLUGINS_ROOT = ROOT / "game" / "csgo" / "addons" / "counterstrikesharp"
UNLOAD_CFG = CFG_ROOT / "unload_plugins.cfg"
POLICY_FILE = ROOT / "scripts" / "plugin-mode-policy.json"

PLUGIN_PREFIX_RE = re.compile(r"^\s*css_plugins(?:\s|$)", re.IGNORECASE)
PLUGIN_COMMAND_RE = re.compile(
    r"^\s*css_plugins\s+(load|unload|reload)\s+(.+?)\s*$",
    re.IGNORECASE,
)
MODE_RE = re.compile(r"^\s*css_gamemode\b", re.IGNORECASE)
EXEC_UNLOAD_RE = re.compile(r"^\s*exec\s+unload_plugins\.cfg\b", re.IGNORECASE)
DLL_PATH_RE = re.compile(r"^plugins/.+\.dll$", re.IGNORECASE)
SPECIAL_MODULE = "CS2Rcon"


def read_lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8-sig").splitlines()


def is_comment_or_blank(line: str) -> bool:
    stripped = line.lstrip()
    return not stripped or stripped.startswith("//") or stripped.startswith("#")


def parse_plugin_command(line: str) -> tuple[str, str] | None:
    """Parse exactly one css_plugins operation and exactly one target argument."""
    command_text = line.partition("//")[0].strip()
    match = PLUGIN_COMMAND_RE.match(command_text)
    if not match:
        return None

    # shlex handles quoted paths and rejects malformed quotes or extra arguments.
    arguments = shlex.split(match.group(2), posix=True)
    if len(arguments) != 1:
        raise ValueError("expected exactly one plugin target argument")
    return match.group(1).lower(), arguments[0].strip()


def collect_plugin_commands(path: Path, errors: list[str]) -> list[tuple[int, str, str]]:
    found: list[tuple[int, str, str]] = []
    for number, line in enumerate(read_lines(path), start=1):
        if is_comment_or_blank(line) or not PLUGIN_PREFIX_RE.match(line):
            continue
        try:
            parsed = parse_plugin_command(line)
        except ValueError as exc:
            errors.append(f"{path.relative_to(ROOT)}:{number}: malformed css_plugins command: {exc}")
            continue
        if parsed is None:
            errors.append(
                f"{path.relative_to(ROOT)}:{number}: unsupported css_plugins command; "
                "use load, unload, or reload with exactly one quoted target"
            )
            continue
        operation, target = parsed
        found.append((number, operation, target))
    return found


def is_dll_target(target: str) -> bool:
    relative = PurePosixPath(target)
    return (
        bool(DLL_PATH_RE.fullmatch(target))
        and not relative.is_absolute()
        and ".." not in relative.parts
    )


def validate_dll_target(
    target: str,
    context: str,
    errors: list[str],
) -> bool:
    if not is_dll_target(target):
        errors.append(
            f"{context}: plugin targets must use a relative plugins/.../*.dll path; got {target!r}"
        )
        return False

    disk_path = PLUGINS_ROOT.joinpath(*PurePosixPath(target).parts)
    if not disk_path.is_file():
        errors.append(f"{context}: plugin DLL does not exist: {target}")
        return False
    return True


def main() -> int:
    errors: list[str] = []
    if not CFG_ROOT.is_dir() or not UNLOAD_CFG.is_file() or not POLICY_FILE.is_file():
        print("ERROR: missing CFG root, unload file, or plugin-mode policy.", file=sys.stderr)
        return 1

    try:
        policy = json.loads(POLICY_FILE.read_text(encoding="utf-8"))
        afk = policy["afk_manager"]
        afk_plugin = afk["plugin"]
        enabled_list = afk["enabled_modes"]
        disabled_list = afk["disabled_modes"]
        if not isinstance(afk_plugin, str) or not afk_plugin:
            raise TypeError("afk_manager.plugin must be a non-empty string")
        if not isinstance(enabled_list, list) or not all(isinstance(x, str) and x for x in enabled_list):
            raise TypeError("afk_manager.enabled_modes must be a list of non-empty strings")
        if not isinstance(disabled_list, list) or not all(isinstance(x, str) and x for x in disabled_list):
            raise TypeError("afk_manager.disabled_modes must be a list of non-empty strings")
        enabled_modes = set(enabled_list)
        disabled_modes = set(disabled_list)
    except (KeyError, TypeError, json.JSONDecodeError) as exc:
        print(f"ERROR: invalid {POLICY_FILE.relative_to(ROOT)}: {exc}", file=sys.stderr)
        return 1

    if len(enabled_modes) != len(enabled_list):
        errors.append("AFK policy contains duplicate entries in enabled_modes")
    if len(disabled_modes) != len(disabled_list):
        errors.append("AFK policy contains duplicate entries in disabled_modes")
    if enabled_modes & disabled_modes:
        errors.append(f"AFK policy contains modes in both lists: {sorted(enabled_modes & disabled_modes)}")
    if not is_dll_target(afk_plugin):
        errors.append(f"AFK policy plugin must be a relative plugins/.../*.dll path: {afk_plugin!r}")

    mode_configs: dict[str, Path] = {}
    for path in sorted(CFG_ROOT.glob("*.cfg")):
        lines = read_lines(path)
        if not any(
            MODE_RE.match(line) for line in lines if not is_comment_or_blank(line)
        ):
            continue

        mode_configs[path.name] = path
        reset_lines = [
            number for number, line in enumerate(lines, start=1)
            if not is_comment_or_blank(line) and EXEC_UNLOAD_RE.match(line)
        ]
        if len(reset_lines) != 1:
            errors.append(
                f"{path.relative_to(ROOT)}: expected exactly one exec unload_plugins.cfg, "
                f"found {len(reset_lines)}"
            )

    policy_modes = enabled_modes | disabled_modes
    actual_modes = set(mode_configs)
    if actual_modes - policy_modes:
        errors.append(f"Game-mode CFGs missing AFK policy entries: {sorted(actual_modes - policy_modes)}")
    if policy_modes - actual_modes:
        errors.append(f"AFK policy references missing/non-mode CFGs: {sorted(policy_modes - actual_modes)}")

    all_cfg_files = sorted(CFG_ROOT.rglob("*.cfg"))
    command_map: dict[Path, list[tuple[int, str, str]]] = {
        path: collect_plugin_commands(path, errors) for path in all_cfg_files
    }

    central_commands = command_map.get(UNLOAD_CFG, [])
    unload_paths = [
        target for _, operation, target in central_commands
        if operation == "unload" and is_dll_target(target)
    ]
    duplicates = sorted({target for target in unload_paths if unload_paths.count(target) > 1})
    if duplicates:
        errors.append(f"Central unload list contains duplicate DLL paths: {duplicates}")

    central_reload_special = [
        (number, target)
        for number, operation, target in central_commands
        if operation == "reload" and target == SPECIAL_MODULE
    ]
    if len(central_reload_special) != 1:
        errors.append(
            f"unload_plugins.cfg: expected exactly one reload of {SPECIAL_MODULE}, "
            f"found {len(central_reload_special)}"
        )

    if any(operation == "load" for _, operation, _ in central_commands):
        errors.append("unload_plugins.cfg: central reset must not load plugins")

    unique_loaded_paths: set[str] = set()
    afk_loads_by_cfg: dict[Path, list[int]] = {}

    for cfg in all_cfg_files:
        commands = command_map[cfg]
        reset_lines = [
            number for number, line in enumerate(read_lines(cfg), start=1)
            if not is_comment_or_blank(line) and EXEC_UNLOAD_RE.match(line)
        ]
        if reset_lines:
            first_reset = reset_lines[0]
            if any(number < first_reset for number, _, _ in commands):
                errors.append(
                    f"{cfg.relative_to(ROOT)}: a css_plugins command appears before its central reset"
                )

        for line_number, operation, target in commands:
            context = f"{cfg.relative_to(ROOT)}:{line_number}"

            if target == SPECIAL_MODULE:
                if operation == "load":
                    errors.append(
                        f"{context}: {SPECIAL_MODULE} must not be loaded by module name; "
                        "use an explicit DLL path for manually loaded plugins"
                    )
                elif operation == "reload" and cfg != UNLOAD_CFG:
                    errors.append(
                        f"{context}: {SPECIAL_MODULE} may only be reloaded by unload_plugins.cfg"
                    )
                elif operation == "unload" and cfg == UNLOAD_CFG:
                    errors.append(
                        f"{context}: central reset must reload {SPECIAL_MODULE}, not leave it unloaded"
                    )
                continue

            if not validate_dll_target(target, context, errors):
                continue

            if target not in unload_paths:
                errors.append(
                    f"{context}: {target} is used by css_plugins {operation} "
                    "but is absent from unload_plugins.cfg"
                )

            if operation == "load":
                unique_loaded_paths.add(target)
                if target == afk_plugin:
                    afk_loads_by_cfg.setdefault(cfg, []).append(line_number)

    # Every manually loaded DLL is centrally reset, and every central entry points to a real DLL.
    for line_number, operation, target in central_commands:
        context = f"unload_plugins.cfg:{line_number}"
        if operation == "unload":
            validate_dll_target(target, context, errors)
        elif operation == "reload" and target != SPECIAL_MODULE:
            errors.append(
                f"{context}: only the documented {SPECIAL_MODULE} special-case reload is allowed"
            )
        elif operation == "load":
            errors.append(f"{context}: central reset cannot load plugins")

    # Each primary mode must reset before any plugin command in that mode CFG.
    for mode_name, path in sorted(mode_configs.items()):
        lines = read_lines(path)
        reset_lines = [
            number for number, line in enumerate(lines, start=1)
            if not is_comment_or_blank(line) and EXEC_UNLOAD_RE.match(line)
        ]
        command_lines = [number for number, _, _ in command_map[path]]
        if len(reset_lines) == 1 and any(number < reset_lines[0] for number in command_lines):
            errors.append(f"{mode_name}: central unload reset must precede every plugin command")

    # AFKManager may only be loaded once, directly by allowlisted primary mode CFGs.
    enabled_paths = {mode_configs[name] for name in enabled_modes if name in mode_configs}
    for cfg, line_numbers in afk_loads_by_cfg.items():
        if cfg not in enabled_paths:
            errors.append(
                f"{cfg.relative_to(ROOT)}: AFKManager load is outside the enabled primary-mode allowlist"
            )
        if len(line_numbers) != 1:
            errors.append(
                f"{cfg.relative_to(ROOT)}: expected one AFKManager load, found {len(line_numbers)}"
            )

    for mode_name in sorted(enabled_modes & actual_modes):
        path = mode_configs[mode_name]
        count = len(afk_loads_by_cfg.get(path, []))
        if count != 1:
            errors.append(f"{mode_name}: expected exactly one AFKManager load, found {count}")

    for mode_name in sorted(disabled_modes & actual_modes):
        path = mode_configs[mode_name]
        count = len(afk_loads_by_cfg.get(path, []))
        if count:
            errors.append(f"{mode_name}: AFKManager must remain disabled, but {count} load command(s) exist")

    if afk_plugin not in unload_paths:
        errors.append(f"AFKManager is enabled in mode CFGs but missing from unload_plugins.cfg: {afk_plugin}")

    if errors:
        print("FAIL: mode plugin lifecycle validation")
        for error in errors:
            print(f" - {error}")
        return 1

    print(
        "PASS: validated "
        f"{len(all_cfg_files)} CFG files, {len(mode_configs)} primary mode CFGs, "
        f"{len(unique_loaded_paths)} unique path-loaded plugin DLLs; "
        f"{len(central_commands)} central lifecycle commands; "
        f"AFKManager enabled in {len(enabled_modes)} modes and disabled in {len(disabled_modes)}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
