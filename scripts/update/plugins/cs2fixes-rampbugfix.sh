#!/usr/bin/env bash
# CS2Fixes-RampbugFix updater.
# Only the platform binaries and the plugin's gamedata are managed here.
# The repository keeps its own platform-specific Metamod VDF files under addons/surf;
# those are intentionally not replaced by the upstream archives.

PLUGIN_PATHS=(
    "game/csgo/addons/cs2fixes-rampbugfix/bin/linuxsteamrt64/cs2fixes-rampbugfix.so"
    "game/csgo/addons/cs2fixes-rampbugfix/bin/win64/cs2fixes-rampbugfix.dll"
    "game/csgo/addons/cs2fixes-rampbugfix/gamedata/cs2fixes.games.txt"
)

plugin_assets() {
    echo "CS2Fixes-RampbugFix-${NEW_VERSION}-linux.tar.gz"
    echo "CS2Fixes-RampbugFix-${NEW_VERSION}-windows.zip"
}

plugin_preflight() {
    require_file "game/csgo/addons/cs2fixes-rampbugfix/bin/linuxsteamrt64/cs2fixes-rampbugfix.so"
    require_file "game/csgo/addons/cs2fixes-rampbugfix/bin/win64/cs2fixes-rampbugfix.dll"
    require_file "game/csgo/addons/cs2fixes-rampbugfix/gamedata/cs2fixes.games.txt"
}

plugin_apply() {
    local linux windows
    local linux_root="addons/cs2fixes-rampbugfix"
    local windows_root="addons/cs2fixes-rampbugfix"

    linux="$(extract_asset "CS2Fixes-RampbugFix-${NEW_VERSION}-linux.tar.gz")"
    windows="$(extract_asset "CS2Fixes-RampbugFix-${NEW_VERSION}-windows.zip")"

    require_file "$linux/$linux_root/bin/linuxsteamrt64/cs2fixes-rampbugfix.so"
    require_file "$windows/$windows_root/bin/win64/cs2fixes-rampbugfix.dll"
    require_file "$linux/$linux_root/gamedata/cs2fixes.games.txt"
    require_file "$windows/$windows_root/gamedata/cs2fixes.games.txt"

    # Both packages ship the same gamedata; fail closed if upstream publishes
    # mismatched platform archives rather than silently choosing one.
    if ! cmp -s "$linux/$linux_root/gamedata/cs2fixes.games.txt" "$windows/$windows_root/gamedata/cs2fixes.games.txt"; then
        die "Linux and Windows archives contain different cs2fixes.games.txt files"
    fi

    copy_file "$linux/$linux_root/bin/linuxsteamrt64/cs2fixes-rampbugfix.so" \
        "game/csgo/addons/cs2fixes-rampbugfix/bin/linuxsteamrt64/cs2fixes-rampbugfix.so"
    copy_file "$windows/$windows_root/bin/win64/cs2fixes-rampbugfix.dll" \
        "game/csgo/addons/cs2fixes-rampbugfix/bin/win64/cs2fixes-rampbugfix.dll"
    copy_file "$linux/$linux_root/gamedata/cs2fixes.games.txt" \
        "game/csgo/addons/cs2fixes-rampbugfix/gamedata/cs2fixes.games.txt"

    remove_extracted "$windows"
    remove_extracted "$linux"
}
