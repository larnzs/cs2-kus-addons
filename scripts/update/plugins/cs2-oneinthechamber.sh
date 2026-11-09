#!/usr/bin/env bash
# cs2-OneInTheChamber; stored disabled and loaded by its game-mode CFG.
source scripts/update/catalog-plugin.sh

DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/cs2-OneInTheChamber"
PLUGIN_PATHS=("$DESTINATION")

plugin_assets() { printf 'cs2-OneInTheChamber.zip\n'; }

plugin_needs_repair() {
    [[ ! -s "$DESTINATION/OneInTheChamber.dll" || ! -s "$DESTINATION/OneInTheChamber.deps.json" ]]
}

plugin_preflight() {
    require_dir "game/csgo/addons/counterstrikesharp/plugins/disabled"
}

plugin_apply() {
    local archive source
    archive="$(extract_asset "cs2-OneInTheChamber.zip")"
    source="$(catalog_find_plugin_dir "$archive" "OneInTheChamber.dll")"
    require_file "$source/OneInTheChamber.dll"
    require_file "$source/OneInTheChamber.deps.json"
    catalog_overlay_plugin_dir "$source" "$DESTINATION" "lang/***"
    remove_extracted "$archive"
}
