#!/usr/bin/env bash
# CS2FunMatchPlugin; use the Linux-specific release asset for the Linux payload.
source scripts/update/catalog-plugin.sh

PLUGIN_PATHS=("game/csgo/addons/counterstrikesharp/plugins/disabled/FunMatchPlugin")
DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/FunMatchPlugin"

plugin_assets() { echo "FunMatchPlugin_dll_linux_*.zip"; }
plugin_preflight() { require_file "$DESTINATION/FunMatchPlugin.dll"; }

plugin_apply() {
    local archive source
    archive="$(extract_asset "FunMatchPlugin_dll_linux_*.zip")"
    source="$(catalog_find_plugin_dir "$archive" "FunMatchPlugin.dll")"
    require_file "$source/FunMatchPlugin.dll"
    catalog_overlay_plugin_dir "$source" "$DESTINATION" "lang/***"
    remove_extracted "$archive"
}
