#!/usr/bin/env bash
# OpenPrefirePrac; disabled by default and loaded by selected prefire/practice CFGs.
# Keep operator-owned map profiles, default_cfg.json, resources and translations.
source scripts/update/catalog-plugin.sh

DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/OpenPrefirePrac"
PLUGIN_PATHS=("$DESTINATION")

plugin_assets() { printf 'OpenPrefirePrac-v%s.zip\n' "$NEW_VERSION"; }

plugin_needs_repair() {
    [[ ! -s "$DESTINATION/OpenPrefirePrac.dll" || ! -s "$DESTINATION/OpenPrefirePrac.deps.json" ]]
}

plugin_preflight() {
    require_dir "game/csgo/addons/counterstrikesharp/plugins/disabled"
}

plugin_apply() {
    local archive source
    archive="$(extract_asset "OpenPrefirePrac-v*.zip")"
    source="$(catalog_find_plugin_dir "$archive" "OpenPrefirePrac.dll")"
    require_file "$source/OpenPrefirePrac.dll"
    require_file "$source/OpenPrefirePrac.deps.json"

    catalog_overlay_plugin_dir "$source" "$DESTINATION" \
        "default_cfg.json" "maps/***" "resources/***" "lang/***"
    remove_extracted "$archive"
}
