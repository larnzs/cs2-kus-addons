#!/usr/bin/env bash
# CS2 Executes; use the upstream no-map-configs archive and retain local map data.
source scripts/update/catalog-plugin.sh

PLUGIN_PATHS=("game/csgo/addons/counterstrikesharp/plugins/disabled/ExecutesPlugin")
DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/ExecutesPlugin"

plugin_assets() { echo "cs2-executes-*-no-map-configs.zip"; }
plugin_preflight() { require_file "$DESTINATION/ExecutesPlugin.dll"; }

plugin_apply() {
    local archive source
    archive="$(extract_asset "cs2-executes-*-no-map-configs.zip")"
    source="$(catalog_find_plugin_dir "$archive" "ExecutesPlugin.dll")"
    require_file "$source/ExecutesPlugin.dll"
    catalog_overlay_plugin_dir "$source" "$DESTINATION" "map_config/***"
    remove_extracted "$archive"
}
