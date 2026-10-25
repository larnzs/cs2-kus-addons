#!/usr/bin/env bash
# Project:           Kus' modded Counter Strike 2 (CS2) Dedicated Server - https://github.com/kus/cs2-modded-server/
# Update script for: GG1MapChooser (Larnz manifest-managed release)
# README row:        [GG1MapChooser](https://github.com/ssypchenko/GG1MapChooser)
# Sourced by scripts/update/update.sh - do not run directly.
# This single adapter is called by the manifest pass; keep the plugin out of the
# KUS catalog version table to avoid downloading/applying the same release twice.
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
    "game/csgo/addons/counterstrikesharp/shared/ggmcAPI"
)

plugin_assets() {
    echo "GG1MapChooser.${NEW_VERSION}.zip"
}

plugin_preflight() {
    require_dir "game/csgo/addons/counterstrikesharp/plugins"
    require_dir "game/csgo/addons/counterstrikesharp/shared"
}

# Return success only when a repair is required. This is checked even when the
# manifest version matches upstream, so missing runtime dependencies are recoverable.
plugin_needs_repair() {
    local target="game/csgo/addons/counterstrikesharp/plugins/GG1MapChooser"
    local api_target="game/csgo/addons/counterstrikesharp/shared/ggmcAPI"
    [[ ! -f "$target/GG1MapChooser.dll" ||
       ! -f "$target/GG1MapChooser.deps.json" ||
       ! -f "$api_target/ggmcAPI.dll" ]]
}

plugin_apply() {
    local x file src api_file api_src target api_target
    local matches=()
    local api_matches=()

    x=$(extract_asset "GG1MapChooser.${NEW_VERSION}.zip")

    # Resolve the main assembly by content instead of assuming an archive root.
    while IFS= read -r -d '' file; do
        matches+=("$file")
    done < <(find "$x" -type f -iname 'GG1MapChooser.dll' -print0)

    if [ "${#matches[@]}" -ne 1 ]; then
        die "Expected exactly one GG1MapChooser.dll in the upstream release archive; found ${#matches[@]}."
    fi

    # The upstream release installs ggmcAPI as a CounterStrikeSharp shared library.
    # Preserve that shared/ggmcAPI destination rather than placing it with the plugin.
    while IFS= read -r -d '' file; do
        api_matches+=("$file")
    done < <(find "$x" -type f -iname 'ggmcAPI.dll' -print0)

    if [ "${#api_matches[@]}" -ne 1 ]; then
        die "Expected exactly one ggmcAPI.dll in the upstream release archive; found ${#api_matches[@]}."
    fi

    src=$(dirname "${matches[0]}")
    api_file="${api_matches[0]}"
    api_src=$(dirname "$api_file")
    target="game/csgo/addons/counterstrikesharp/plugins/GG1MapChooser"
    api_target="game/csgo/addons/counterstrikesharp/shared/ggmcAPI"
    require_file "$src/GG1MapChooser.dll"
    require_file "$src/GG1MapChooser.deps.json"
    require_file "$api_src/ggmcAPI.dll"

    # Overlay only plugin-owned files and the dedicated shared dependency directory.
    # Do not copy any cfg/ or CounterStrikeSharp configs/ payload.
    copy_dir "$src" "$target"
    copy_dir "$api_src" "$api_target"
    require_file "$api_target/ggmcAPI.dll"

    remove_extracted "$x"
}
