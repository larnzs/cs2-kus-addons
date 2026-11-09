#!/usr/bin/env bash
# CS2 Retakes Allocator; stored disabled and loaded only by game-mode configuration.
# Preserve local config, gamedata/signatures and translations while refreshing its runtime set.
source scripts/update/catalog-plugin.sh

DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/RetakesAllocator"
PLUGIN_PATHS=("$DESTINATION")

plugin_assets() { printf 'cs2-retakes-allocator-v%s.zip\n' "$NEW_VERSION"; }

plugin_needs_repair() {
    local required
    for required in \
        "$DESTINATION/RetakesAllocator.dll" \
        "$DESTINATION/RetakesAllocator.deps.json" \
        "$DESTINATION/RetakesAllocatorCore.dll" \
        "$DESTINATION/RetakesPluginShared.dll" \
        "$DESTINATION/runtimes/linux-x64/native/libe_sqlite3.so" \
        "$DESTINATION/runtimes/win-x64/native/e_sqlite3.dll"; do
        [[ -s "$required" ]] || return 0
    done
    return 1
}

plugin_preflight() {
    require_dir "game/csgo/addons/counterstrikesharp/plugins/disabled"
}

plugin_apply() {
    local archive source
    archive="$(extract_asset "cs2-retakes-allocator-*.zip")"
    source="$(catalog_find_plugin_dir "$archive" "RetakesAllocator.dll")"
    for required in \
        "RetakesAllocator.dll" \
        "RetakesAllocator.deps.json" \
        "RetakesAllocatorCore.dll" \
        "RetakesPluginShared.dll" \
        "runtimes/linux-x64/native/libe_sqlite3.so" \
        "runtimes/win-x64/native/e_sqlite3.dll"; do
        require_file "$source/$required"
    done

    catalog_overlay_plugin_dir "$source" "$DESTINATION" "lang/***" "config/***" "gamedata/***"
    remove_extracted "$archive"
}
