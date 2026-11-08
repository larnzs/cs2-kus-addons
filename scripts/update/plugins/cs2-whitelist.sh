#!/usr/bin/env bash
# CS2 Whitelist; whitelist.txt is operator-owned data and must never be replaced.
source scripts/update/catalog-plugin.sh

PLUGIN_PATHS=("game/csgo/addons/counterstrikesharp/plugins/disabled/WhiteList")
DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/WhiteList"

plugin_assets() { echo "WhiteList.zip"; }
plugin_preflight() {
    require_file "$DESTINATION/WhiteList.dll"
    require_file "$DESTINATION/whitelist.txt"
}

plugin_apply() {
    local archive source
    archive="$(extract_asset "WhiteList.zip")"
    source="$(catalog_find_plugin_dir "$archive" "WhiteList.dll")"
    require_file "$source/WhiteList.dll"
    catalog_overlay_plugin_dir "$source" "$DESTINATION" "whitelist.txt"
    remove_extracted "$archive"
}
