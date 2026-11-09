#!/usr/bin/env bash
# K4-DamageInfo; disabled placement is intentional and does not exclude updates.
# Its operator configuration is outside the plugin directory; preserve local translations.
source scripts/update/catalog-plugin.sh

DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/K4-DamageInfo"
PLUGIN_PATHS=("$DESTINATION")

plugin_assets() { printf 'K4-DamageInfo.zip\n'; }

plugin_needs_repair() {
    [[ ! -s "$DESTINATION/K4-DamageInfo.dll" ]]
}

plugin_preflight() {
    require_dir "game/csgo/addons/counterstrikesharp/plugins/disabled"
}

plugin_apply() {
    local archive source
    archive="$(extract_asset "K4-DamageInfo.zip")"
    source="$(catalog_find_plugin_dir "$archive" "K4-DamageInfo.dll")"
    require_file "$source/K4-DamageInfo.dll"
    catalog_overlay_plugin_dir "$source" "$DESTINATION" "lang/***"
    remove_extracted "$archive"
}
