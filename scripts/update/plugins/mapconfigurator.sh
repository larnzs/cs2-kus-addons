#!/usr/bin/env bash
# MapConfigurator currently has no published GitHub releases.
# This adapter is ready for the first ZIP release; archive layout is discovered
# by a unique DLL sentinel and ambiguous archives fail closed.
source scripts/update/catalog-plugin.sh

PLUGIN_PATHS=("game/csgo/addons/counterstrikesharp/plugins/MapConfigurator")
DESTINATION="game/csgo/addons/counterstrikesharp/plugins/MapConfigurator"

plugin_assets() { echo "*.zip"; }
plugin_preflight() { require_file "$DESTINATION/MapConfigurator.dll"; }

plugin_apply() {
    local archive source
    archive="$(extract_asset "*.zip")"
    source="$(catalog_find_plugin_dir "$archive" "MapConfigurator.dll")"
    require_file "$source/MapConfigurator.dll"
    catalog_overlay_plugin_dir "$source" "$DESTINATION"
    remove_extracted "$archive"
}
