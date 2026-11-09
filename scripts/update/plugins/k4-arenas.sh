#!/usr/bin/env bash
# K4-Arenas and its separately packaged K4-Arenas-Bots companion.
# Both stay under plugins/disabled; this updater never changes game-mode CFGs or activation.
source scripts/update/catalog-plugin.sh

DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/K4-Arenas"
BOTS_DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/K4-Arenas-Bots"
PLUGIN_PATHS=("$DESTINATION" "$BOTS_DESTINATION")

# The Bots ZIP is not attached to every K4-Arenas release. Resolve the latest
# main release plus the newest non-draft release that actually carries the Bots ZIP.
plugin_resolve_assets() {
    local release_assets repo releases bots_asset
    release_assets="$(github_release_assets "$PLUGIN_URL" "$NEW_VERSION")" || return 1

    if printf '%s\n' "$release_assets" | awk -F '\t' '$1 == "K4-Arenas-Bots.zip" { found=1 } END { exit !found }'; then
        printf '%s\n' "$release_assets"
        return 0
    fi

    repo="$(github_repo_from_url "$PLUGIN_URL")"
    releases="$(github_api "repos/$repo/releases?per_page=100")" || return 1
    bots_asset="$(printf '%s' "$releases" | jq -r '
        [ .[] | select(.draft != true) | .assets[]? | select(.name == "K4-Arenas-Bots.zip") ][0]
        | if . == null then empty else [.name, .browser_download_url, (.size | tostring)] | @tsv end
    ')"
    [[ -n "$bots_asset" ]] || die "No non-draft K4-Arenas-Bots.zip asset exists in the upstream release history."
    printf '%s\n%s\n' "$release_assets" "$bots_asset"
}

plugin_assets() {
    printf 'K4-Arenas.zip\nK4-Arenas-Bots.zip\n'
}

plugin_needs_repair() {
    [[ ! -s "$DESTINATION/K4-Arenas.dll" || ! -s "$BOTS_DESTINATION/K4-Arenas-Bots.dll" ]]
}

plugin_preflight() {
    require_dir "game/csgo/addons/counterstrikesharp/plugins/disabled"
}

plugin_apply() {
    local main_archive bots_archive main_source bots_source
    main_archive="$(extract_asset "K4-Arenas.zip")"
    bots_archive="$(extract_asset "K4-Arenas-Bots.zip")"

    main_source="$(catalog_find_plugin_dir "$main_archive" "K4-Arenas.dll")"
    bots_source="$(catalog_find_plugin_dir "$bots_archive" "K4-Arenas-Bots.dll")"
    require_file "$main_source/K4-Arenas.dll"
    require_file "$bots_source/K4-Arenas-Bots.dll"

    # K4-Arenas.json is managed under CounterStrikeSharp configs, not copied here.
    catalog_overlay_plugin_dir "$main_source" "$DESTINATION" "lang/***"
    catalog_overlay_plugin_dir "$bots_source" "$BOTS_DESTINATION" "lang/***"
    remove_extracted "$main_archive"
    remove_extracted "$bots_archive"
}
