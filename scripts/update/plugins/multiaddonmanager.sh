#!/usr/bin/env bash
# Linux Pterodactyl updater for Source2ZE MultiAddonManager.
# Use the verified SteamRT3 native build only. The Windows package and SteamRT4
# package are intentionally not part of this server's update path.
PLUGIN_PATHS=(
    "game/csgo/addons/multiaddonmanager/bin/multiaddonmanager.so"
    "game/csgo/addons/metamod/multiaddonmanager.vdf"
)

pterodactyl_linux_runtime() {
    local runtime
    runtime=$(jq -er '.architecture.pterodactyl_linux_runtime // empty' DEPENDENCIES.json) \
        || die "DEPENDENCIES.json is missing architecture.pterodactyl_linux_runtime"
    [ "$runtime" = "steamrt3" ] || die "Pterodactyl Linux runtime must be steamrt3; got '$runtime'"
    printf '%s' "$runtime"
}

plugin_assets() {
    local runtime
    runtime=$(pterodactyl_linux_runtime) || return 1
    printf 'MultiAddonManager-v%s-%s.tar.gz\n' "$NEW_VERSION" "$runtime"
}

plugin_preflight() {
    require_dir "game/csgo/addons/multiaddonmanager/bin"
    require_dir "game/csgo/addons/metamod"
}

plugin_needs_repair() {
    [[ ! -f "game/csgo/addons/multiaddonmanager/bin/multiaddonmanager.so" ||
       ! -f "game/csgo/addons/metamod/multiaddonmanager.vdf" ]]
}

plugin_apply() {
    local runtime linux
    runtime=$(pterodactyl_linux_runtime) || return 1

    if is_dry; then
        dry "extract MultiAddonManager-v${NEW_VERSION}-${runtime}.tar.gz (SteamRT3)"
        dry "copy addons/multiaddonmanager/bin/multiaddonmanager.so to the Linux runtime"
        dry "copy addons/metamod/multiaddonmanager.vdf to the MetaMod loader directory"
        dry "do not copy or alter any cfg/ files"
        return 0
    fi

    linux=$(extract_asset "MultiAddonManager-v${NEW_VERSION}-${runtime}.tar.gz")
    require_file "$linux/addons/multiaddonmanager/bin/multiaddonmanager.so"
    require_file "$linux/addons/metamod/multiaddonmanager.vdf"

    copy_file "$linux/addons/multiaddonmanager/bin/multiaddonmanager.so" \
        "game/csgo/addons/multiaddonmanager/bin/multiaddonmanager.so"
    copy_file "$linux/addons/metamod/multiaddonmanager.vdf" \
        "game/csgo/addons/metamod/multiaddonmanager.vdf"

    remove_extracted "$linux"
}
