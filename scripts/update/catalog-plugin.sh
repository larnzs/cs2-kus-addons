#!/usr/bin/env bash
# Shared fail-closed helpers for release-backed KUS catalog plugins.
# Source only after scripts/update/lib.sh has been loaded by update.sh.

catalog_find_plugin_dir() {
    local archive_root="$1" sentinel="$2" matches count
    if is_dry; then
        dry "find exactly one '$sentinel' below '$archive_root' and use its parent directory"
        printf '%s\n' "$archive_root"
        return 0
    fi

    require_dir "$archive_root"
    matches="$(find "$archive_root" -type f -name "$sentinel" -print)"
    count="$(printf '%s\n' "$matches" | awk 'NF { n++ } END { print n+0 }')"
    [ "$count" -eq 1 ] || die "expected exactly one '$sentinel' in release archive, found $count"
    dirname "$matches"
}

catalog_overlay_plugin_dir() {
    local source_dir="$1" destination_dir="$2" exclude
    shift 2
    local -a flags
    flags=("${RSYNC_FLAGS[@]}")
    for exclude in "$@"; do
        [ -n "$exclude" ] || continue
        flags+=(--exclude "$exclude")
    done

    assert_write_target "$destination_dir"
    if is_dry; then
        dry "merge release plugin directory '$source_dir' into '$destination_dir' (preserving excluded local files: $*)"
        return 0
    fi

    require_dir "$source_dir"
    mkdir -p "$destination_dir"
    step "overlaying release plugin files into $destination_dir"
    # Deliberately no --delete: this repository's deployment policy retains
    # stale/unknown files for operator review rather than deleting local content.
    rsync "${flags[@]}" "$source_dir/" "$destination_dir/" >&3 2>&3 || die "could not overlay release directory '$source_dir' into '$destination_dir'"
}
