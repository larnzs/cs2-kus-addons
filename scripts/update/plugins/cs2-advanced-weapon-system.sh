#!/usr/bin/env bash
# Advanced Weapon System; disabled placement is preserved for mode-specific css_plugins load.
# Its TOML config lives under CounterStrikeSharp configs and is outside this updater's scope.
source scripts/update/catalog-plugin.sh

DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/cs2-advanced-weapon-system"
PLUGIN_PATHS=("$DESTINATION")

plugin_assets() { printf 'cs2-advanced-weapon-system-v%s.zip\n' "$NEW_VERSION"; }

plugin_needs_repair() {
    [[ ! -s "$DESTINATION/cs2-advanced-weapon-system.dll" || ! -s "$DESTINATION/cs2-advanced-weapon-system.deps.json" ]]
}

plugin_preflight() {
    require_dir "game/csgo/addons/counterstrikesharp/plugins/disabled"
}

plugin_apply() {
    local archive source
    archive="$(extract_asset "cs2-advanced-weapon-system-v*.zip")"
    source="$(catalog_find_plugin_dir "$archive" "cs2-advanced-weapon-system.dll")"
    require_file "$source/cs2-advanced-weapon-system.dll"
    require_file "$source/cs2-advanced-weapon-system.deps.json"
    catalog_overlay_plugin_dir "$source" "$DESTINATION" "lang/***"
    remove_extracted "$archive"
}
