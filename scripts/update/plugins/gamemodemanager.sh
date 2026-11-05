#!/usr/bin/env bash
# GameModeManager 2.x owns its complete bundled plugin/runtime set.
# The official ZIP root is addons/ and cfg/. Only the seven explicitly listed
# subdirectories under addons/counterstrikesharp are ever copied.
PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/GameModeManager"
    "game/csgo/addons/counterstrikesharp/plugins/GG1MapChooser"
    "game/csgo/addons/counterstrikesharp/plugins/MenuManagerCore"
    "game/csgo/addons/counterstrikesharp/plugins/PMM_GG1MapChooser"
    "game/csgo/addons/counterstrikesharp/shared/GameModeManager.Shared"
    "game/csgo/addons/counterstrikesharp/shared/ggmcAPI"
    "game/csgo/addons/counterstrikesharp/shared/MenuManagerApi"
)

plugin_assets() { printf 'GameModeManager_v%s.zip\n' "$NEW_VERSION"; }

plugin_needs_repair() {
    local root="game/csgo/addons/counterstrikesharp" required
    local -a required_files=(
        "$root/plugins/GameModeManager/GameModeManager.dll"
        "$root/plugins/GameModeManager/GameModeManager.deps.json"
        "$root/plugins/GameModeManager/Gameloop.Vdf.dll"
        "$root/plugins/GameModeManager/lang/en.json"
        "$root/plugins/GG1MapChooser/GG1MapChooser.dll"
        "$root/plugins/GG1MapChooser/GG1MapChooser.deps.json"
        "$root/plugins/GG1MapChooser/lang/en.json"
        "$root/plugins/MenuManagerCore/MenuManagerCore.dll"
        "$root/plugins/MenuManagerCore/MenuManagerCore.deps.json"
        "$root/plugins/MenuManagerCore/runtimes/linux-x64/native/libe_sqlite3.so"
        "$root/plugins/MenuManagerCore/runtimes/win-x64/native/e_sqlite3.dll"
        "$root/plugins/PMM_GG1MapChooser/PMM_GG1MapChooser.dll"
        "$root/plugins/PMM_GG1MapChooser/PMM_GG1MapChooser.deps.json"
        "$root/plugins/PMM_GG1MapChooser/harmony/0Harmony.dll"
        "$root/plugins/PMM_GG1MapChooser/lang/en.json"
        "$root/shared/GameModeManager.Shared/GameModeManager.Shared.dll"
        "$root/shared/GameModeManager.Shared/GameModeManager.Shared.deps.json"
        "$root/shared/ggmcAPI/ggmcAPI.dll"
        "$root/shared/ggmcAPI/ggmcAPI.deps.json"
        "$root/shared/MenuManagerApi/MenuManagerApi.dll"
        "$root/shared/MenuManagerApi/MenuManagerApi.deps.json"
    )
    for required in "${required_files[@]}"; do [[ -f "$required" ]] || return 0; done
    return 1
}

plugin_apply() {
    local extract_root source_root relative source destination
    local -a bundle_dirs=(
        "plugins/GameModeManager"
        "plugins/GG1MapChooser"
        "plugins/MenuManagerCore"
        "plugins/PMM_GG1MapChooser"
        "shared/GameModeManager.Shared"
        "shared/ggmcAPI"
        "shared/MenuManagerApi"
    )
    if is_dry; then
        dry "extract GameModeManager_v${NEW_VERSION}.zip"
        dry "overlay addons/counterstrikesharp/{plugins/GameModeManager,GG1MapChooser,MenuManagerCore,PMM_GG1MapChooser}"
        dry "overlay addons/counterstrikesharp/shared/{GameModeManager.Shared,ggmcAPI,MenuManagerApi}"
        dry "preserve ZIP cfg/, CounterStrikeSharp configs/, and generated configuration files"
        return 0
    fi

    extract_root=$(extract_asset "GameModeManager_v${NEW_VERSION}.zip")
    source_root="$extract_root/addons/counterstrikesharp"
    require_dir "$extract_root/addons"
    require_dir "$source_root/plugins"
    require_dir "$source_root/shared"

    # Validate every component before writing any destination.
    require_file "$source_root/plugins/GameModeManager/GameModeManager.dll"
    require_file "$source_root/plugins/GameModeManager/GameModeManager.deps.json"
    require_file "$source_root/plugins/GameModeManager/Gameloop.Vdf.dll"
    require_file "$source_root/plugins/GameModeManager/lang/en.json"
    require_file "$source_root/plugins/GG1MapChooser/GG1MapChooser.dll"
    require_file "$source_root/plugins/GG1MapChooser/GG1MapChooser.deps.json"
    require_file "$source_root/plugins/GG1MapChooser/lang/en.json"
    require_file "$source_root/plugins/MenuManagerCore/MenuManagerCore.dll"
    require_file "$source_root/plugins/MenuManagerCore/MenuManagerCore.deps.json"
    require_file "$source_root/plugins/MenuManagerCore/runtimes/linux-x64/native/libe_sqlite3.so"
    require_file "$source_root/plugins/MenuManagerCore/runtimes/win-x64/native/e_sqlite3.dll"
    require_file "$source_root/plugins/PMM_GG1MapChooser/PMM_GG1MapChooser.dll"
    require_file "$source_root/plugins/PMM_GG1MapChooser/PMM_GG1MapChooser.deps.json"
    require_file "$source_root/plugins/PMM_GG1MapChooser/harmony/0Harmony.dll"
    require_file "$source_root/plugins/PMM_GG1MapChooser/lang/en.json"
    require_file "$source_root/shared/GameModeManager.Shared/GameModeManager.Shared.dll"
    require_file "$source_root/shared/GameModeManager.Shared/GameModeManager.Shared.deps.json"
    require_file "$source_root/shared/ggmcAPI/ggmcAPI.dll"
    require_file "$source_root/shared/ggmcAPI/ggmcAPI.deps.json"
    require_file "$source_root/shared/MenuManagerApi/MenuManagerApi.dll"
    require_file "$source_root/shared/MenuManagerApi/MenuManagerApi.deps.json"

    for relative in "${bundle_dirs[@]}"; do
        source="$source_root/$relative"
        destination="game/csgo/addons/counterstrikesharp/$relative"
        require_dir "$source"
        copy_dir "$source" "$destination"
    done
    plugin_needs_repair && die "GameModeManager bundle verification failed after overlay."
    warn "Operator-owned configs/ and the release cfg/ directory were not copied."
    remove_extracted "$extract_root"
}
