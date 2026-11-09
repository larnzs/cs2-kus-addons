#!/usr/bin/env bash
# CS2-GameModifiers; kept disabled for game-mode-specific loading.
# Preserve the local modifier presets and ConVar modifier CFGs.
source scripts/update/catalog-plugin.sh

DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/GameModifiers"
PLUGIN_PATHS=("$DESTINATION")

plugin_assets() { printf 'GameModifiers-v%s.zip\n' "$NEW_VERSION"; }

plugin_needs_repair() {
    [[ ! -s "$DESTINATION/GameModifiers.dll" || ! -s "$DESTINATION/GameModifiers.deps.json" ]]
}

plugin_preflight() {
    require_dir "game/csgo/addons/counterstrikesharp/plugins/disabled"
}

plugin_apply() {
    local archive source
    archive="$(extract_asset "GameModifiers-v*.zip")"
    source="$(catalog_find_plugin_dir "$archive" "GameModifiers.dll")"
    require_file "$source/GameModifiers.dll"
    require_file "$source/GameModifiers.deps.json"

    catalog_overlay_plugin_dir "$source" "$DESTINATION" \
        "ModifierConfig/***" "ConVarModifiers/***" "lang/***"
    remove_extracted "$archive"
}
