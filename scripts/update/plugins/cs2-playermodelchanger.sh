#!/usr/bin/env bash
# CS2-PlayerModelChanger; runtime config is outside this plugin folder.
source scripts/update/catalog-plugin.sh

PLUGIN_PATHS=("game/csgo/addons/counterstrikesharp/plugins/disabled/PlayerModelChanger")
DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/PlayerModelChanger"

plugin_assets() { echo "PlayerModelChanger.zip"; }
plugin_preflight() { require_file "$DESTINATION/PlayerModelChanger.dll"; }

plugin_apply() {
    local archive source
    archive="$(extract_asset "PlayerModelChanger.zip")"
    source="$(catalog_find_plugin_dir "$archive" "PlayerModelChanger.dll")"
    require_file "$source/PlayerModelChanger.dll"
    catalog_overlay_plugin_dir "$source" "$DESTINATION" "lang/***"
    remove_extracted "$archive"
}
