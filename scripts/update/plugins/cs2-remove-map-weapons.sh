#!/usr/bin/env bash
# CS2 Remove Map Weapons; stored disabled and loaded by the selected game-mode CFG.
# Updates only its plugin directory; its disabled placement/CFG load commands are untouched.
source scripts/update/catalog-plugin.sh

DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/CS2-Remove-Map-Weapons"
PLUGIN_PATHS=("$DESTINATION")

plugin_assets() { printf 'CS2-Remove-Map-Weapons-%s.zip\n' "$NEW_VERSION"; }

plugin_needs_repair() {
    [[ ! -s "$DESTINATION/CS2-Remove-Map-Weapons.dll" ]]
}

plugin_preflight() {
    require_dir "game/csgo/addons/counterstrikesharp/plugins/disabled"
}

plugin_apply() {
    local archive source
    archive="$(extract_asset "CS2-Remove-Map-Weapons-*.zip")"
    source="$(catalog_find_plugin_dir "$archive" "CS2-Remove-Map-Weapons.dll")"
    require_file "$source/CS2-Remove-Map-Weapons.dll"
    catalog_overlay_plugin_dir "$source" "$DESTINATION" "lang/***"
    remove_extracted "$archive"
}
