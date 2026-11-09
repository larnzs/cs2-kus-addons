#!/usr/bin/env bash
# CS2WarcraftMod; staged disabled for game-mode activation.
# CounterStrikeSharp.API.dll is supplied by the server runtime and must never be replaced
# by the copy bundled in the upstream archive. Keep local translations as well.
source scripts/update/catalog-plugin.sh

DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/WarcraftPlugin"
PLUGIN_PATHS=("$DESTINATION")

plugin_assets() { printf 'warcraft-plugin-%s.zip\n' "$NEW_VERSION"; }

plugin_needs_repair() {
    [[ ! -s "$DESTINATION/WarcraftPlugin.dll" || ! -s "$DESTINATION/WarcraftPlugin.deps.json" ]]
}

plugin_preflight() {
    require_dir "game/csgo/addons/counterstrikesharp/plugins/disabled"
}

plugin_apply() {
    local archive source
    archive="$(extract_asset "warcraft-plugin-*.zip")"
    source="$(catalog_find_plugin_dir "$archive" "WarcraftPlugin.dll")"
    require_file "$source/WarcraftPlugin.dll"
    require_file "$source/WarcraftPlugin.deps.json"

    catalog_overlay_plugin_dir "$source" "$DESTINATION" \
        "lang/***" "CounterStrikeSharp.API.dll"
    remove_extracted "$archive"
}
