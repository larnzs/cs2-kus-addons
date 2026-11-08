#!/usr/bin/env bash
# SpectatorList-CS2; preserve translations and the locally staged PlayerSettings API.
source scripts/update/catalog-plugin.sh

PLUGIN_PATHS=("game/csgo/addons/counterstrikesharp/plugins/disabled/SpectatorList")
DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/SpectatorList"

plugin_assets() { echo "SpectatorList.zip"; }
plugin_preflight() {
    require_file "$DESTINATION/SpectatorList.dll"
    require_file "$DESTINATION/PlayerSettingsApi.dll"
}

plugin_apply() {
    local archive source
    archive="$(extract_asset "SpectatorList.zip")"
    source="$(catalog_find_plugin_dir "$archive" "SpectatorList.dll")"
    require_file "$source/SpectatorList.dll"
    catalog_overlay_plugin_dir "$source" "$DESTINATION" "lang/***" "PlayerSettingsApi.dll"
    remove_extracted "$archive"
}
