#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from pathlib import Path
from typing import List, Tuple

DEFAULT_MINRATE = "196608"
DEFAULT_MAXRATE = "196608"
DEFAULT_GRAPHIC1 = 'sv_server_graphic1 "sv_server_graphic1.png"'
DEFAULT_GRAPHIC2 = 'sv_server_graphic2 "sv_server_graphic2.png"'

HOSTNAME_RE = re.compile(
    r'^(?P<indent>\s*)hostname(?P<sep>\s+)(".*?"|[^\s;]+)(?P<trail>.*)$',
    re.IGNORECASE,
)
SVTAGS_RE = re.compile(
    r'^(?P<indent>\s*)sv_tags(?P<sep>\s+)(".*?"|[^\s;]+)(?P<trail>.*)$',
    re.IGNORECASE,
)
MINRATE_RE = re.compile(
    r'^(?P<indent>\s*)sv_minrate(?P<sep>\s+)(".*?"|[^\s;]+|[0-9]+)(?P<trail>.*)$',
    re.IGNORECASE,
)
MAXRATE_RE = re.compile(
    r'^(?P<indent>\s*)sv_maxrate(?P<sep>\s+)(".*?"|[^\s;]+|[0-9]+)(?P<trail>.*)$',
    re.IGNORECASE,
)
GRAPHIC1_RE = re.compile(
    r'^(?P<indent>\s*)sv_server_graphic1(?P<sep>\s+)(".*?"|[^\s;]+)(?P<trail>.*)$',
    re.IGNORECASE,
)
GRAPHIC2_RE = re.compile(
    r'^(?P<indent>\s*)sv_server_graphic2(?P<sep>\s+)(".*?"|[^\s;]+)(?P<trail>.*)$',
    re.IGNORECASE,
)

MODE_RULES: List[Tuple[str, Tuple[str, str]]] = [
    ("valve-deathmatch-freeforall", ("Deathmatch FFA", "☠")),
    ("deathmatch-freeforall", ("Deathmatch FFA", "☠")),
    ("valve-deathmatch", ("Deathmatch", "☠")),
    ("deathmatch", ("Deathmatch", "☠")),
    ("valve-competitive", ("Competitive", "⚔")),
    ("competitive", ("Competitive", "⚔")),
    ("comp", ("Competitive", "⚔")),
    ("retake", ("Retake", "🔄")),
    ("wingman", ("Wingman", "👥")),
    ("scoutzknivez", ("Scoutzknivez", "🎯")),
    ("minigames", ("Minigames", "🎮")),
    ("deathrun", ("Deathrun", "🏃")),
    ("surf", ("Surf", "🏄")),
    ("bhop", ("Bhop", "🐇")),
    ("kz", ("KZ", "🧗")),
    ("aim", ("Aim", "🚧")),
    ("awp", ("AWP", "🎯")),
    ("hs", ("Headshot", "💥")),
    ("gg", ("Gun Game", "🔫")),
    ("ctf", ("CTF", "🚩")),
    ("br", ("Battle Royale", "👑")),
    ("battle", ("Battle", "🛡")),
    ("practice", ("Practice", "🧪")),
    ("prefire", ("Prefire", "🔥")),
    ("oitc", ("OITC", "🔪")),
    ("course", ("Course", "🧭")),
    ("executes", ("Executes", "⚙")),
    ("soccer", ("Soccer", "⚽")),
    ("war", ("War", "⚔")),
    ("1v1", ("1v1", "🥊")),
]

def prompt_value(label: str) -> str:
    value = input(f"{label}: ").strip()
    if not value:
        raise ValueError(f"{label} cannot be empty")
    return value

def scan_targets(root: Path) -> List[Path]:
    return sorted(root.rglob("custom_*.cfg"))

def split_mode_from_filename(path: Path) -> str:
    stem = path.stem
    if stem.lower().startswith("custom_"):
        return stem[len("custom_"):]
    return stem

def friendly_mode_label(path: Path) -> str:
    raw = split_mode_from_filename(path).strip().lower()
    if not raw:
        return ""

    normalized = raw.replace("_", "-")

    for needle, (label, emoji) in MODE_RULES:
        if needle in normalized:
            return f"{label} {emoji}".strip()

    fallback = normalized.replace("-", " ").strip()
    fallback = re.sub(r"\s+", " ", fallback)
    return fallback.title()

def build_hostname(base_hostname: str, path: Path) -> str:
    mode = friendly_mode_label(path)
    if mode:
        return f"{base_hostname} | Mode : {mode}"
    return base_hostname

def insert_before_first_real_line(lines: List[str], insertions: List[str]) -> List[str]:
    if not insertions:
        return lines

    insert_at = len(lines)
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if stripped and not stripped.startswith((";", "#", "//")):
            insert_at = idx
            break

    return lines[:insert_at] + insertions + lines[insert_at:]

def update_text(text: str, hostname: str, tags: str) -> Tuple[str, bool]:
    changed = False
    lines = text.splitlines(keepends=True)
    out_lines: List[str] = []

    seen_hostname = False
    seen_tags = False
    seen_minrate = False
    seen_maxrate = False
    seen_graphic1 = False
    seen_graphic2 = False

    for line in lines:
        line_wo_nl = line.rstrip("\r\n")
        newline = line[len(line_wo_nl):]

        m = HOSTNAME_RE.match(line_wo_nl)
        if m:
            out_lines.append(
                f'{m.group("indent")}hostname{m.group("sep")}"{hostname}"{m.group("trail")}{newline}'
            )
            seen_hostname = True
            changed = True
            continue

        m = SVTAGS_RE.match(line_wo_nl)
        if m:
            out_lines.append(
                f'{m.group("indent")}sv_tags{m.group("sep")}"{tags}"{m.group("trail")}{newline}'
            )
            seen_tags = True
            changed = True
            continue

        m = MINRATE_RE.match(line_wo_nl)
        if m:
            out_lines.append(
                f'{m.group("indent")}sv_minrate{m.group("sep")}{DEFAULT_MINRATE}{m.group("trail")}{newline}'
            )
            seen_minrate = True
            changed = True
            continue

        m = MAXRATE_RE.match(line_wo_nl)
        if m:
            out_lines.append(
                f'{m.group("indent")}sv_maxrate{m.group("sep")}{DEFAULT_MAXRATE}{m.group("trail")}{newline}'
            )
            seen_maxrate = True
            changed = True
            continue

        m = GRAPHIC1_RE.match(line_wo_nl)
        if m:
            out_lines.append(
                f'{m.group("indent")}sv_server_graphic1{m.group("sep")}"sv_server_graphic1.png"{m.group("trail")}{newline}'
            )
            seen_graphic1 = True
            changed = True
            continue

        m = GRAPHIC2_RE.match(line_wo_nl)
        if m:
            out_lines.append(
                f'{m.group("indent")}sv_server_graphic2{m.group("sep")}"sv_server_graphic2.png"{m.group("trail")}{newline}'
            )
            seen_graphic2 = True
            changed = True
            continue

        out_lines.append(line)

    insertions: List[str] = []
    if not seen_hostname:
        insertions.append(f'hostname "{hostname}"\n')
        changed = True
    if not seen_tags:
        insertions.append(f'sv_tags "{tags}"\n')
        changed = True
    if not seen_minrate:
        insertions.append(f"sv_minrate {DEFAULT_MINRATE}\n")
        changed = True
    if not seen_maxrate:
        insertions.append(f"sv_maxrate {DEFAULT_MAXRATE}\n")
        changed = True
    if not seen_graphic1:
        insertions.append(DEFAULT_GRAPHIC1 + "\n")
        changed = True
    if not seen_graphic2:
        insertions.append(DEFAULT_GRAPHIC2 + "\n")
        changed = True

    if insertions:
        out_lines = insert_before_first_real_line(out_lines, insertions)

    return "".join(out_lines), changed

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        type=Path,
        default=Path.cwd(),
        help="Root folder to search (default: current working directory)",
    )
    parser.add_argument(
        "--hostname",
        type=str,
        default=None,
        help="Base hostname (if not set, you will be prompted)",
    )
    parser.add_argument(
        "--tags",
        type=str,
        default=None,
        help="sv_tags value (if not set, you will be prompted)",
    )
    args = parser.parse_args()

    root = args.root.resolve()
    if not root.exists() or not root.is_dir():
        raise SystemExit(f"Root folder not found or not a directory: {root}")

    targets = scan_targets(root)
    if not targets:
        print(f"No custom_*.cfg files found under: {root}")
        return 0

    print("\nFound these custom configs and detected modes:\n")
    for path in targets:
        print(f"  {path.relative_to(root)}  ->  {friendly_mode_label(path) or 'Unknown'}")
    print()

    base_hostname = args.hostname or prompt_value("hostname")
    tags = args.tags or prompt_value("tags")

    updated = 0
    for path in targets:
        try:
            original = path.read_text(encoding="utf-8-sig")
        except UnicodeDecodeError:
            original = path.read_text(encoding="cp1252", errors="replace")

        final_hostname = build_hostname(base_hostname, path)
        new_text, changed = update_text(original, final_hostname, tags)

        if changed and new_text != original:
            path.write_text(new_text, encoding="utf-8", newline="\n")
            updated += 1
            print(f"updated: {path.relative_to(root)}  ->  {final_hostname}")
        else:
            print(f"skipped:  {path.relative_to(root)}")

    print(f"\nDone. Updated {updated}/{len(targets)} file(s).")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())