#!/usr/bin/env bash
# cs2-TeleportKill; runtime configuration is generated outside the plugin folder.
source scripts/update/catalog-plugin.sh

PLUGIN_PATHS=("game/csgo/addons/counterstrikesharp/plugins/disabled/TeleportKill")
DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/TeleportKill"

plugin_assets() { echo "TeleportKill-*.zip"; }
plugin_preflight() { require_file "$DESTINATION/TeleportKill.dll"; }

plugin_apply() {
    local archive source
    archive="$(extract_asset "TeleportKill-*.zip")"
    source="$(catalog_find_plugin_dir "$archive" "TeleportKill.dll")"
    require_file "$source/TeleportKill.dll"
    catalog_overlay_plugin_dir "$source" "$DESTINATION" "lang/***"
    remove_extracted "$archive"
}
