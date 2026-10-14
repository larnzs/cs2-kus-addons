#!/usr/bin/env bash
# Project:           Kus' modded Counter Strike 2 (CS2) Dedicated Server - https://github.com/kus/cs2-modded-server/
# Update script for: GG1MapChooser
# README row:        [GG1MapChooser](https://github.com/ssypchenko/GG1MapChooser)
# Sourced by scripts/update/update.sh - do not run directly.
#
# Manual process this automates:
#   1. Download the exact upstream release asset: GG1MapChooser.<version>.zip.
#   2. Locate the directory containing GG1MapChooser.dll, regardless of the wrapper
#      directories used by the upstream ZIP.
#   3. Overlay its files into the default plugin directory. This is intentionally a
#      non-destructive merge: stale upstream files are retained for manual review.
#   4. Never write to game/csgo/cfg/GGMCmaps.json or CounterStrikeSharp configs/.
#
# Configuration files are user-managed. The plugin can create its own CSS config on
# first load; GGMCmaps.json must be configured separately after this integration step.

PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/GG1MapChooser"
)

plugin_assets() {
    echo "GG1MapChooser.${NEW_VERSION}.zip"
}

plugin_preflight() {
    require_dir "game/csgo/addons/counterstrikesharp/plugins"
}

plugin_apply() {
    local x file src
    local matches=()

    x=$(extract_asset "GG1MapChooser.${NEW_VERSION}.zip")

    # The release ZIP may include csgo/, addons/, or a version wrapper.
    # Resolve by the actual assembly instead of trusting a guessed archive root.
    while IFS= read -r -d '' file; do
        matches+=("$file")
    done < <(find "$x" -type f -iname 'GG1MapChooser.dll' -print0)

    if [ "${#matches[@]}" -ne 1 ]; then
        die "Expected exactly one GG1MapChooser.dll in the upstream release archive; found ${#matches[@]}."
    fi

    src=$(dirname "${matches[0]}")
    require_file "$src/GG1MapChooser.dll"

    # Overlay only plugin-owned files. Do not copy any cfg/ or configs/ payload.
    copy_dir "$src" "game/csgo/addons/counterstrikesharp/plugins/GG1MapChooser"

    remove_extracted "$x"
}
