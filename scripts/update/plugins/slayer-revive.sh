#!/usr/bin/env bash
# SLAYER_Revive; preserve the operator-managed JSON settings and translations.
source scripts/update/catalog-plugin.sh

PLUGIN_PATHS=("game/csgo/addons/counterstrikesharp/plugins/disabled/SLAYER_Revive")
DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/SLAYER_Revive"

plugin_assets() { echo "CS2.SLAYER_Revive.*.zip"; }
plugin_preflight() {
    require_file "$DESTINATION/SLAYER_Revive.dll"
    require_file "$DESTINATION/SLAYER_Revive.json"
}

plugin_apply() {
    local archive source
    archive="$(extract_asset "CS2.SLAYER_Revive.*.zip")"
    source="$(catalog_find_plugin_dir "$archive" "SLAYER_Revive.dll")"
    require_file "$source/SLAYER_Revive.dll"
    catalog_overlay_plugin_dir "$source" "$DESTINATION" "SLAYER_Revive.json" "lang/***"
    remove_extracted "$archive"
}
