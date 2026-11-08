#!/usr/bin/env bash
# STFixes; upstream marks the project archived, but this adapter remains ready
# to detect and apply a future release without changing its disabled load state.
source scripts/update/catalog-plugin.sh

PLUGIN_PATHS=("game/csgo/addons/counterstrikesharp/plugins/disabled/STFixes")
DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/STFixes"

plugin_assets() { echo "STFixes_*.zip"; }
plugin_preflight() { require_file "$DESTINATION/STFixes.dll"; }

plugin_apply() {
    local archive source
    archive="$(extract_asset "STFixes_*.zip")"
    source="$(catalog_find_plugin_dir "$archive" "STFixes.dll")"
    require_file "$source/STFixes.dll"
    catalog_overlay_plugin_dir "$source" "$DESTINATION"
    remove_extracted "$archive"
}
