#!/usr/bin/env bash
# CS2-WeaponSpeed; its disabled directory is still part of the automatic update catalog.
# The operator configuration is stored outside this plugin directory.
source scripts/update/catalog-plugin.sh

DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/WeaponSpeed"
PLUGIN_PATHS=("$DESTINATION")

plugin_assets() { printf 'WeaponSpeed.zip\n'; }

plugin_needs_repair() {
    [[ ! -s "$DESTINATION/WeaponSpeed.dll" || ! -s "$DESTINATION/WeaponSpeed.deps.json" ]]
}

plugin_preflight() {
    require_dir "game/csgo/addons/counterstrikesharp/plugins/disabled"
}

plugin_apply() {
    local archive source
    archive="$(extract_asset "WeaponSpeed.zip")"
    source="$(catalog_find_plugin_dir "$archive" "WeaponSpeed.dll")"
    require_file "$source/WeaponSpeed.dll"
    require_file "$source/WeaponSpeed.deps.json"
    catalog_overlay_plugin_dir "$source" "$DESTINATION" "lang/***"
    remove_extracted "$archive"
}
