#!/usr/bin/env bash
# CS2 Instadefuse; remains in the disabled plugin directory.
source scripts/update/catalog-plugin.sh

PLUGIN_PATHS=("game/csgo/addons/counterstrikesharp/plugins/disabled/InstadefusePlugin")
DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/InstadefusePlugin"

plugin_assets() { echo "cs2-instadefuse-*.zip"; }
plugin_preflight() { require_file "$DESTINATION/InstadefusePlugin.dll"; }

plugin_apply() {
    local archive source
    archive="$(extract_asset "cs2-instadefuse-*.zip")"
    source="$(catalog_find_plugin_dir "$archive" "InstadefusePlugin.dll")"
    require_file "$source/InstadefusePlugin.dll"
    catalog_overlay_plugin_dir "$source" "$DESTINATION" "lang/***"
    remove_extracted "$archive"
}
