#!/usr/bin/env python3
"""Hard audit of README catalog -> updater adapter -> real payload paths.

Default mode prints a full report and exits non-zero only for broken references or
broken declared paths. --strict also fails when any README catalog row is not
covered by a dedicated updater or a documented bundle updater.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLUGIN_DIR = ROOT / "scripts" / "update" / "plugins"


def run(command: list[str], *, cwd: Path = ROOT) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=cwd, text=True, capture_output=True, check=False)


def slugify(name: str) -> str:
    return re.sub(r"^-+|-+$", "", re.sub(r"[^a-z0-9]+", "-", name.lower()))


def catalog_rows() -> list[dict[str, str]]:
    lines = (ROOT / "README.md").read_text(encoding="utf-8-sig").splitlines()
    header = "| Mod | Version / revision | Purpose | Payload placement / activation | Update automation |"
    try:
        start = lines.index(header) + 2
    except ValueError as exc:
        raise RuntimeError("README.md unified plugin catalog table header was not found") from exc

    rows: list[dict[str, str]] = []
    for line in lines[start:]:
        if not line.startswith("|"):
            break
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) != 5 or cells[0].startswith("---"):
            continue
        linked = re.match(r"^\[([^\]]+)\]\((https?://[^)]+)\)$", cells[0])
        name = linked.group(1) if linked else cells[0].strip(chr(96))
        url = linked.group(2) if linked else ""

        linked_scripts = re.findall(
            r"\]\(scripts/update/plugins/([^)/]+\.sh)\)", cells[4]
        )
        scripts = list(dict.fromkeys(linked_scripts))
        manual = "manual-only" in cells[4].lower() and "not installed" in cells[4].lower()
        rows.append({
            "name": name,
            "url": url,
            "version": cells[1],
            "purpose": cells[2],
            "placement": cells[3],
            "automation": cells[4],
            "scripts": scripts,
            "bundled": "1" if "bundled" in cells[4].lower() else "0",
            "manual": "1" if manual else "0",
        })
    return rows

def source_adapter(script_name: str) -> tuple[list[str], str | None]:
    script_path = PLUGIN_DIR / script_name
    if not script_path.is_file():
        return [], f"missing script file: scripts/update/plugins/{script_name}"

    syntax = run(["bash", "-n", str(script_path)])
    if syntax.returncode != 0:
        return [], f"bash syntax failed for {script_name}: {syntax.stderr.strip()}"

    loader = (
        'set -Eeuo pipefail; exec 3>&2; '
        'source scripts/update/lib.sh; '
        'source "$1"; '
        'printf "%s\\n" "${PLUGIN_PATHS[@]}"'
    )
    loaded = run(["bash", "-c", loader, "catalog-audit", str(script_path.relative_to(ROOT))])
    if loaded.returncode != 0:
        error = loaded.stderr.strip() or loaded.stdout.strip() or "unknown source error"
        return [], f"could not source {script_name}: {error}"

    paths = [line.strip() for line in loaded.stdout.splitlines() if line.strip()]
    if not paths:
        return [], f"{script_name} declares no PLUGIN_PATHS"
    return paths, None


def check_paths(script_name: str, paths: list[str]) -> list[str]:
    errors: list[str] = []
    for value in paths:
        candidate = Path(value)
        if candidate.is_absolute() or ".." in candidate.parts:
            errors.append(f"{script_name}: unsafe PLUGIN_PATHS entry {value!r}")
            continue
        if not (ROOT / candidate).exists():
            errors.append(f"{script_name}: payload path does not exist: {value}")
    return errors


def read_names(path: Path) -> list[str]:
    if not path.is_file():
        return []
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8-sig").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--strict",
        action="store_true",
        help="fail if any README catalog row has no updater or bundle mapping",
    )
    args = parser.parse_args()

    errors: list[str] = []
    rows = catalog_rows()
    referenced_scripts: dict[str, list[str]] = {}
    covered_rows: list[dict[str, str]] = []
    uncovered_rows: list[dict[str, str]] = []
    manual_rows: list[dict[str, str]] = []
    catalog_names: set[str] = set()

    for row in rows:
        names = row["scripts"]
        if not row["url"].startswith(("https://github.com/", "https://www.metamodsource.net/")):
            errors.append(f"{row['name']}: missing or unsupported upstream source link: {row['url']!r}")
        normalized = slugify(row["name"])
        if normalized in catalog_names:
            errors.append(f"{row['name']}: duplicate plugin catalog row")
        catalog_names.add(normalized)
        if not names:
            if row["manual"] == "1":
                manual_rows.append(row)
            else:
                uncovered_rows.append(row)
            continue

        row_errors = False
        for script_name in names:
            referenced_scripts.setdefault(script_name, []).append(row["name"])
            paths, error = source_adapter(script_name)
            if error:
                errors.append(f"{row['name']}: {error}")
                row_errors = True
                continue
            path_errors = check_paths(script_name, paths)
            errors.extend(path_errors)
            row_errors = row_errors or bool(path_errors)

        if not row_errors:
            covered_rows.append(row)

    # Every manifest component must also be represented in the single README catalog.
    manifest_path = ROOT / "DEPENDENCIES.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    catalog_display_names = {row["name"] for row in rows}
    for item in manifest.get("addons", []):
        if item["name"] not in catalog_display_names:
            errors.append(f"Manifest {item['name']}: missing from the README plugin catalog")

    # Manifest completeness and path existence: every automation-enabled entry, including bootstrap installs.
    manifest_entries = [
        item for item in manifest.get("addons", [])
        if item.get("automation_supported") is not False
    ]
    manifest_ok = 0
    for item in manifest_entries:
        name = item["name"]
        script_name = f"{slugify(name)}.sh"
        paths, error = source_adapter(script_name)
        if error:
            errors.append(f"Manifest {name}: {error}")
            continue
        path_errors = check_paths(script_name, paths)
        errors.extend(f"Manifest {name}: {entry}" for entry in path_errors)
        if not path_errors:
            manifest_ok += 1

    # The combined README table is partitioned into KUS catalog rows and Manifest rows.
    # Metamod is intentionally kept in the KUS pass because its adapter synchronizes DEPENDENCIES.json.
    manifest_names = {item["name"] for item in manifest.get("addons", [])}
    expected_kus_names = {
        row["name"] for row in rows
        if row["name"] == "Metamod:Source" or row["name"] not in manifest_names
    }
    listed = run(["bash", "scripts/update/update.sh", "--list"])
    if listed.returncode != 0:
        errors.append("KUS updater --list failed: " + (listed.stderr.strip() or listed.stdout.strip()))
    else:
        listed_names = {
            line[:28].strip()
            for line in listed.stdout.splitlines()[1:]
            if line[:28].strip()
        }
        if listed_names != expected_kus_names:
            errors.append(
                "KUS/Manifest updater partition mismatch: "
                f"expected {len(expected_kus_names)} KUS rows, got {len(listed_names)}; "
                f"missing={sorted(expected_kus_names - listed_names)}; "
                f"unexpected={sorted(listed_names - expected_kus_names)}"
            )

    # The fast list and first-release list have independent real-path checks.
    fast_names = read_names(ROOT / "scripts" / "update" / "fast-safe-addons.txt")
    future_names = read_names(ROOT / "scripts" / "update" / "future-release-addons.txt")
    fast_ok = 0
    for name in fast_names:
        script_name = f"{slugify(name)}.sh"
        paths, error = source_adapter(script_name)
        if error:
            errors.append(f"Priority {name}: {error}")
            continue
        path_errors = check_paths(script_name, paths)
        errors.extend(f"Priority {name}: {entry}" for entry in path_errors)
        if not path_errors:
            fast_ok += 1

    future_ok = 0
    for name in future_names:
        script_name = f"{slugify(name)}.sh"
        paths, error = source_adapter(script_name)
        if error:
            errors.append(f"Future-release {name}: {error}")
            continue
        path_errors = check_paths(script_name, paths)
        errors.extend(f"Future-release {name}: {entry}" for entry in path_errors)
        if not path_errors:
            future_ok += 1

    # Current CustomVotes release has a native dependency that must stay in its
    # plugin-local folder and match the dependency graph declared by its .deps.json.
    customvotes = ROOT / "game/csgo/addons/counterstrikesharp/plugins/CS2-CustomVotes"
    deps_file = customvotes / "CS2-CustomVotes.deps.json"
    try:
        deps = json.loads(deps_file.read_text(encoding="utf-8"))
        target = deps["runtimeTarget"]["name"]
        assemblies = deps["targets"][target]
        plugin_key = next(k for k in assemblies if k.startswith("CS2-CustomVotes/"))
        plugin = assemblies[plugin_key]
        utils_version = plugin["dependencies"]["CSSharpUtils"]
        shared_version = plugin["dependencies"]["CS2-CustomVotes.Shared"]
        valid_customvotes = (
            (customvotes / "CS2-CustomVotes.dll").is_file()
            and (customvotes / "CS2-CustomVotes.Shared.dll").is_file()
            and (customvotes / "CSSharpUtils.dll").is_file()
            and "CS2-CustomVotes.dll" in plugin["runtime"]
            and "lib/net8.0/CSSharpUtils.dll" in assemblies[f"CSSharpUtils/{utils_version}"]["runtime"]
            and "CS2-CustomVotes.Shared.dll" in assemblies[f"CS2-CustomVotes.Shared/{shared_version}"]["runtime"]
        )
        if not valid_customvotes:
            errors.append("CS2-CustomVotes: plugin DLL, Shared DLL, CSSharpUtils DLL and .deps.json are not a consistent set")
    except (OSError, KeyError, StopIteration, json.JSONDecodeError) as exc:
        errors.append(f"CS2-CustomVotes: could not verify runtime dependency set: {exc}")

    print("=== Unified README plugin catalog hard-check ===")
    print(f"Catalog rows: {len(rows)}")
    print(f"Rows mapped to an existing updater/bundle script and real payload paths: {len(covered_rows)}")
    print(f"Rows without a dedicated updater or bundle mapping: {len(uncovered_rows)}")
    print(f"Explicit manual-only rows (not installed): {len(manual_rows)}")
    print(f"Unique scripts referenced by catalog rows: {len(referenced_scripts)}")
    print(f"Manifest automation entries with valid scripts and paths: {manifest_ok}/{len(manifest_entries)}")
    print(f"Manual priority allowlist entries with valid scripts and paths: {fast_ok}/{len(fast_names)}")
    print(f"Future-release adapters with valid scripts and paths: {future_ok}/{len(future_names)}")
    print(f"Other hard-check failures: {len(errors)}")

    if manual_rows:
        print("\nEXPLICIT MANUAL-ONLY README CATALOG ROWS:")
        for row in manual_rows:
            print(f" - {row['name']}: {row['placement']}")

    if uncovered_rows:
        print("\nUNCOVERED README CATALOG ROWS:")
        for row in uncovered_rows:
            print(f" - {row['name']}: {row['placement']}")

    if errors:
        print("\nBROKEN ADAPTERS / PATHS / DEPENDENCIES:")
        for error in errors:
            print(f" - {error}")

    if args.strict and (uncovered_rows or errors or manifest_ok != len(manifest_entries)
                        or fast_ok != len(fast_names) or future_ok != len(future_names)):
        return 1
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
