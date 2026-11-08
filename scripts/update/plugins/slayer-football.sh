#!/usr/bin/env bash
# SLAYER_Football; only the plugin directory is managed (never cfg/).
source scripts/update/catalog-plugin.sh

PLUGIN_PATHS=("game/csgo/addons/counterstrikesharp/plugins/disabled/SLAYER_Football")
DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/SLAYER_Football"

plugin_assets() { echo "CS2_SLAYER_Football_*.zip"; }
plugin_preflight() { require_file "$DESTINATION/SLAYER_Football.dll"; }

plugin_apply() {
    local archive source
    archive="$(extract_asset "CS2_SLAYER_Football_*.zip")"
    source="$(catalog_find_plugin_dir "$archive" "SLAYER_Football.dll")"
    require_file "$source/SLAYER_Football.dll"
    catalog_overlay_plugin_dir "$source" "$DESTINATION" "lang/***"
    remove_extracted "$archive"
}
