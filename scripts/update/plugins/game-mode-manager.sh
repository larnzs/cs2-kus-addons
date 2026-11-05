#!/usr/bin/env bash
# Updater for GameModeManager 2.x.
# The release bundles PMM_GG1MapChooser; GG1MapChooser and PanoramaMenuManager
# are independently owned by their own adapters. Only plugin directories are copied.
PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/GameModeManager"
    "game/csgo/addons/counterstrikesharp/plugins/PMM_GG1MapChooser"
)

plugin_assets() {
    echo "GameModeManager_v${NEW_VERSION}.zip"
}

plugin_preflight() {
    require_dir "game/csgo/addons/counterstrikesharp/plugins"
    require_file "game/csgo/addons/counterstrikesharp/plugins/GG1MapChooser/GG1MapChooser.dll"
    require_file "game/csgo/addons/counterstrikesharp/shared/ggmcAPI/ggmcAPI.dll"
    require_file "game/csgo/addons/counterstrikesharp/plugins/MenuManagerCore/MenuManagerCore.dll"
    require_file "game/csgo/addons/counterstrikesharp/shared/MenuManagerApi/MenuManagerApi.dll"
}

plugin_needs_repair() {
    [[ ! -f "game/csgo/addons/counterstrikesharp/plugins/GameModeManager/GameModeManager.dll" ||
       ! -f "game/csgo/addons/counterstrikesharp/plugins/PMM_GG1MapChooser/PMM_GG1MapChooser.dll" ]]
}

plugin_apply() {
    local x file source
    local -a gmm=() pmm=()

    if is_dry; then
        dry "extract GameModeManager_v${NEW_VERSION}.zip and overlay only GameModeManager/ and PMM_GG1MapChooser/ plugin directories"
        dry "preserve GameModeManager.json, GG1MapChooser.json, MenuManagerCore.json, MenuManager_Modules_Translation.json and PMM_GG1MapChooser.json"
        dry "do not overwrite cfg/, GG1MapChooser, MenuManagerCore or shared dependencies owned by their dedicated adapters"
        return 0
    fi

    x=$(extract_asset "GameModeManager_v${NEW_VERSION}.zip")
    while IFS= read -r -d '' file; do gmm+=("$file"); done < <(find "$x" -type f -name 'GameModeManager.dll' -print0)
    while IFS= read -r -d '' file; do pmm+=("$file"); done < <(find "$x" -type f -name 'PMM_GG1MapChooser.dll' -print0)

    [[ ${#gmm[@]} -eq 1 ]] || die "Expected exactly one GameModeManager.dll in release archive; found ${#gmm[@]}."
    [[ ${#pmm[@]} -eq 1 ]] || die "Expected exactly one PMM_GG1MapChooser.dll in release archive; found ${#pmm[@]}."

    source=$(dirname "${gmm[0]}")
    copy_dir "$source" "game/csgo/addons/counterstrikesharp/plugins/GameModeManager"
    source=$(dirname "${pmm[0]}")
    copy_dir "$source" "game/csgo/addons/counterstrikesharp/plugins/PMM_GG1MapChooser"

    require_file "game/csgo/addons/counterstrikesharp/plugins/GameModeManager/GameModeManager.dll"
    require_file "game/csgo/addons/counterstrikesharp/plugins/PMM_GG1MapChooser/PMM_GG1MapChooser.dll"
    warn "GameModeManager 2.x changes GameModeManager.json. The updater preserved all configs; review the upstream migration note and back up/update this config manually before enabling the new version."
    warn "GMM release cfg files were not copied so local game-mode settings remain untouched."
    remove_extracted "$x"
}
