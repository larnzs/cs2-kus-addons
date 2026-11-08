#!/usr/bin/env bash
# CS2-MutualScoringPlayers; keep existing translations while updating binaries.
source scripts/update/catalog-plugin.sh

PLUGIN_PATHS=("game/csgo/addons/counterstrikesharp/plugins/disabled/MutualScoringPlayers")
DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/MutualScoringPlayers"

plugin_assets() { echo "MutualScoringPlayers.zip"; }
plugin_preflight() { require_file "$DESTINATION/MutualScoringPlayers.dll"; }

plugin_apply() {
    local archive source
    archive="$(extract_asset "MutualScoringPlayers.zip")"
    source="$(catalog_find_plugin_dir "$archive" "MutualScoringPlayers.dll")"
    require_file "$source/MutualScoringPlayers.dll"
    catalog_overlay_plugin_dir "$source" "$DESTINATION" "lang/***"
    remove_extracted "$archive"
}
