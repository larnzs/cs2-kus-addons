#!/usr/bin/env bash
# Manifest-managed updater for GG1MapChooser and its shared ggmcAPI.
# This plugin is updated separately from GameModeManager. Only the plugin and
# shared API directories are owned here; cfg/ and CSS configs remain untouched.
source scripts/update/manifest-addon.sh

PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/GG1MapChooser"
    "game/csgo/addons/counterstrikesharp/shared/ggmcAPI"
)

plugin_assets() {
    manifest_addon_assets "GG1MapChooser"
}

plugin_preflight() {
    require_dir "game/csgo/addons/counterstrikesharp/plugins"
    require_dir "game/csgo/addons/counterstrikesharp/shared"
}

plugin_needs_repair() {
    manifest_addon_needs_repair "GG1MapChooser"
}

plugin_apply() {
    local x file src api_file api_src
    local -a matches=() api_matches=()

    if is_dry; then
        dry "extract GG1MapChooser.${NEW_VERSION}.zip"
        dry "overlay GG1MapChooser plugin directory"
        dry "overlay shared/ggmcAPI dependency directory"
        dry "preserve cfg/GGMCmaps.json and CounterStrikeSharp configs"
        manifest_update_version "GG1MapChooser" "$NEW_VERSION"
        return 0
    fi

    x=$(extract_asset "GG1MapChooser.${NEW_VERSION}.zip")

    while IFS= read -r -d '' file; do matches+=("$file"); done \
        < <(find "$x" -type f -iname 'GG1MapChooser.dll' -print0)
    while IFS= read -r -d '' file; do api_matches+=("$file"); done \
        < <(find "$x" -type f -iname 'ggmcAPI.dll' -print0)

    [[ ${#matches[@]} -eq 1 ]] || die "Expected exactly one GG1MapChooser.dll; found ${#matches[@]}."
    [[ ${#api_matches[@]} -eq 1 ]] || die "Expected exactly one ggmcAPI.dll; found ${#api_matches[@]}."

    src=$(dirname "${matches[0]}")
    api_file="${api_matches[0]}"
    api_src=$(dirname "$api_file")

    require_file "$src/GG1MapChooser.deps.json"
    require_file "$api_src/ggmcAPI.deps.json"

    copy_dir "$src" "game/csgo/addons/counterstrikesharp/plugins/GG1MapChooser"
    copy_dir "$api_src" "game/csgo/addons/counterstrikesharp/shared/ggmcAPI"

    manifest_verify_addon "GG1MapChooser"
    manifest_update_version "GG1MapChooser" "$NEW_VERSION"
    remove_extracted "$x"
}
