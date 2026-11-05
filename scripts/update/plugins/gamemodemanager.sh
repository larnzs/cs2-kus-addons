#!/usr/bin/env bash
# Updater for GameModeManager 2.x.
# The release owns GameModeManager, its shared contract assembly and the
# bundled PMM_GG1MapChooser plugin. GG1MapChooser and MenuManagerCore remain
# independently managed so this adapter never overwrites their runtime files.
PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/GameModeManager"
    "game/csgo/addons/counterstrikesharp/plugins/PMM_GG1MapChooser"
    "game/csgo/addons/counterstrikesharp/shared/GameModeManager.Shared"
)

plugin_assets() {
    printf 'GameModeManager_v%s.zip\n' "$NEW_VERSION"
}

plugin_preflight() {
    require_dir "game/csgo/addons/counterstrikesharp/plugins"
    require_file "game/csgo/addons/counterstrikesharp/plugins/GG1MapChooser/GG1MapChooser.dll"
    require_file "game/csgo/addons/counterstrikesharp/shared/ggmcAPI/ggmcAPI.dll"
    require_file "game/csgo/addons/counterstrikesharp/plugins/MenuManagerCore/MenuManagerCore.dll"
    require_file "game/csgo/addons/counterstrikesharp/shared/MenuManagerApi/MenuManagerApi.dll"
}

plugin_needs_repair() {
    local gmm="game/csgo/addons/counterstrikesharp/plugins/GameModeManager"
    local pmm="game/csgo/addons/counterstrikesharp/plugins/PMM_GG1MapChooser"
    local shared="game/csgo/addons/counterstrikesharp/shared/GameModeManager.Shared"

    [[ ! -f "$gmm/GameModeManager.dll" ||
       ! -f "$gmm/GameModeManager.deps.json" ||
       ! -f "$gmm/Gameloop.Vdf.dll" ||
       ! -f "$gmm/lang/en.json" ||
       ! -f "$pmm/PMM_GG1MapChooser.dll" ||
       ! -f "$pmm/PMM_GG1MapChooser.deps.json" ||
       ! -f "$pmm/harmony/0Harmony.dll" ||
       ! -f "$shared/GameModeManager.Shared.dll" ||
       ! -f "$shared/GameModeManager.Shared.deps.json" ]]
}

plugin_apply() {
    local x file source
    local -a gmm=() pmm=() shared=()

    if is_dry; then
        dry "extract GameModeManager_v${NEW_VERSION}.zip"
        dry "overlay GameModeManager/ -> addons/counterstrikesharp/plugins/GameModeManager/"
        dry "overlay PMM_GG1MapChooser/ -> addons/counterstrikesharp/plugins/PMM_GG1MapChooser/"
        dry "overlay GameModeManager.Shared/ -> addons/counterstrikesharp/shared/GameModeManager.Shared/"
        dry "preserve GameModeManager.json, PMM_GG1MapChooser.json and all cfg/config trees"
        return 0
    fi

    x=$(extract_asset "GameModeManager_v${NEW_VERSION}.zip")

    while IFS= read -r -d '' file; do gmm+=("$file"); done \
        < <(find "$x" -type f -name 'GameModeManager.dll' -print0)
    while IFS= read -r -d '' file; do pmm+=("$file"); done \
        < <(find "$x" -type f -name 'PMM_GG1MapChooser.dll' -print0)
    while IFS= read -r -d '' file; do shared+=("$file"); done \
        < <(find "$x" -type f -name 'GameModeManager.Shared.dll' -print0)

    [[ ${#gmm[@]} -eq 1 ]] || die "Expected exactly one GameModeManager.dll in release archive; found ${#gmm[@]}."
    [[ ${#pmm[@]} -eq 1 ]] || die "Expected exactly one PMM_GG1MapChooser.dll in release archive; found ${#pmm[@]}."
    [[ ${#shared[@]} -eq 1 ]] || die "Expected exactly one GameModeManager.Shared.dll in release archive; found ${#shared[@]}."

    source=$(dirname "${gmm[0]}")
    require_file "$source/GameModeManager.deps.json"
    require_file "$source/Gameloop.Vdf.dll"
    copy_dir "$source" "game/csgo/addons/counterstrikesharp/plugins/GameModeManager"

    source=$(dirname "${pmm[0]}")
    require_file "$source/PMM_GG1MapChooser.deps.json"
    require_file "$source/harmony/0Harmony.dll"
    copy_dir "$source" "game/csgo/addons/counterstrikesharp/plugins/PMM_GG1MapChooser"

    source=$(dirname "${shared[0]}")
    require_file "$source/GameModeManager.Shared.deps.json"
    copy_dir "$source" "game/csgo/addons/counterstrikesharp/shared/GameModeManager.Shared"

    require_file "game/csgo/addons/counterstrikesharp/plugins/GameModeManager/GameModeManager.dll"
    require_file "game/csgo/addons/counterstrikesharp/plugins/PMM_GG1MapChooser/PMM_GG1MapChooser.dll"
    require_file "game/csgo/addons/counterstrikesharp/shared/GameModeManager.Shared/GameModeManager.Shared.dll"

    warn "GameModeManager 2.x has a config migration; GameModeManager.json was not changed."
    warn "The release cfg/ tree and all CounterStrikeSharp configs were excluded from this update."
    remove_extracted "$x"
}
