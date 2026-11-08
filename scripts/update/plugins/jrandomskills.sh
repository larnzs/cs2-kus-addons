#!/usr/bin/env bash
# Project:           Kus' modded Counter Strike 2 (CS2) Dedicated Server - https://github.com/kus/cs2-modded-server/
# Update script for: jRandomSkills
# README row:        [jRandomSkills](https://github.com/Juzlus/jRandomSkills)
# Sourced by scripts/update/update.sh - do not run directly.
#
# Process:
#   1. Download the release zip, named jRandomSkills.v<version>.zip
#   2. Extract it. The archive is laid out relative to addons/counterstrikesharp/:
#        plugins/jRandomSkills/                plugin, its configs, languages and packages
#        gamedata/jRandomSkills.gamedata.json  the signatures
#   3. Keep the managed copy under plugins/disabled/jRandomSkills so it remains
#      disabled by default and can be enabled deliberately by a game mode.
#   4. The updater's repository-wide non-destructive overlay policy preserves existing
#      files and adds/updates release content; it never deletes stale files automatically.
#
# This is an optional, disabled-by-default payload. Older integrated checkouts may not
# contain its folder or gamedata file yet, so preflight allows a safe bootstrap while
# still refusing symlink/type conflicts. The parent roots must exist.
#
# configs/config.json, configs/skillsInfo.json and languages/ are operator-owned.
# They are preserved when present; release defaults are copied only on first install.
#
# Release versions look like v1.2.4.b3, so NEW_VERSION is the bare 1.2.4.b3 after the
# normalisation performed by check-updates.sh.

source scripts/update/catalog-plugin.sh

PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/disabled/jRandomSkills"
    "game/csgo/addons/counterstrikesharp/gamedata/jRandomSkills.gamedata.json"
)

plugin_assets() {
    echo "jRandomSkills.v${NEW_VERSION}.zip"
}

plugin_needs_repair() {
    [[ ! -f "game/csgo/addons/counterstrikesharp/plugins/disabled/jRandomSkills/jRandomSkills.dll" ||
       ! -f "game/csgo/addons/counterstrikesharp/plugins/disabled/jRandomSkills/configs/config.json" ||
       ! -f "game/csgo/addons/counterstrikesharp/plugins/disabled/jRandomSkills/configs/skillsInfo.json" ||
       ! -d "game/csgo/addons/counterstrikesharp/plugins/disabled/jRandomSkills/languages" ||
       ! -f "game/csgo/addons/counterstrikesharp/gamedata/jRandomSkills.gamedata.json" ]]
}

plugin_preflight() {
    local plugin_dir="game/csgo/addons/counterstrikesharp/plugins/disabled/jRandomSkills"
    local gamedata_file="game/csgo/addons/counterstrikesharp/gamedata/jRandomSkills.gamedata.json"

    require_dir "game/csgo/addons/counterstrikesharp/plugins/disabled"
    require_dir "game/csgo/addons/counterstrikesharp/gamedata"

    [[ ! -L "$plugin_dir" ]] || die "refusing to update jRandomSkills: target directory is a symlink"
    [[ ! -e "$plugin_dir" || -d "$plugin_dir" ]] || die "refusing to update jRandomSkills: target exists but is not a directory"
    [[ ! -L "$gamedata_file" ]] || die "refusing to update jRandomSkills: gamedata target is a symlink"
    [[ ! -e "$gamedata_file" || -f "$gamedata_file" ]] || die "refusing to update jRandomSkills: gamedata target exists but is not a regular file"
}

plugin_apply() {
    local x
    x=$(extract_asset "jRandomSkills.v*.zip")

    require_file "$x/plugins/jRandomSkills/jRandomSkills.dll"
    require_dir  "$x/plugins/jRandomSkills/configs"
    require_dir  "$x/plugins/jRandomSkills/languages"
    require_file "$x/gamedata/jRandomSkills.gamedata.json"

    local destination="game/csgo/addons/counterstrikesharp/plugins/disabled/jRandomSkills"
    local gamedata_file="game/csgo/addons/counterstrikesharp/gamedata/jRandomSkills.gamedata.json"

    # Merge binaries and libraries without deleting unknown/stale files.
    # Local config and language folders are never overwritten by an upstream ZIP.
    catalog_overlay_plugin_dir "$x/plugins/jRandomSkills" "$destination" "configs/***" "languages/***"

    # Seed defaults only when this is a first install and the operator has no files yet.
    if [[ ! -d "$destination/configs" ]]; then
        copy_dir "$x/plugins/jRandomSkills/configs" "$destination/configs"
    else
        for config in config.json skillsInfo.json; do
            if [[ ! -f "$destination/configs/$config" ]]; then
                copy_file "$x/plugins/jRandomSkills/configs/$config" "$destination/configs/$config"
            fi
        done
    fi
    if [[ ! -d "$destination/languages" ]]; then
        copy_dir "$x/plugins/jRandomSkills/languages" "$destination/languages"
    fi

    copy_file "$x/gamedata/jRandomSkills.gamedata.json" "$gamedata_file"
    require_file "$destination/jRandomSkills.dll"
    require_file "$gamedata_file"

    remove_extracted "$x"
}
