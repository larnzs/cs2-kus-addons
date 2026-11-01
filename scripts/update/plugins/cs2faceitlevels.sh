#!/usr/bin/env bash
# Manifest-backed updater for CS2FaceitLevels (native MetaMod plugin).
# One upstream ZIP contains both platform binaries, gamedata and the MetaMod VDF.
# The runtime-generated JSON config/API key is deliberately outside PLUGIN_PATHS.
source scripts/update/manifest-addon.sh

PLUGIN_PATHS=(
    "game/csgo/addons/CS2FaceitLevels/bin"
    "game/csgo/addons/CS2FaceitLevels/workshop.gamedata.json"
    "game/csgo/addons/metamod/CS2FaceitLevels.vdf"
)

plugin_assets() { manifest_addon_assets "CS2FaceitLevels"; }

# Repair an incomplete initial import even when the manifest already tracks latest.
plugin_needs_repair() {
    local root="game/csgo/addons/CS2FaceitLevels"
    [[ ! -f "$root/bin/CS2FaceitLevels.so" ||
       ! -f "$root/bin/CS2FaceitLevels.dll" ||
       ! -f "$root/workshop.gamedata.json" ||
       ! -f "game/csgo/addons/metamod/CS2FaceitLevels.vdf" ]]
}

plugin_apply() { manifest_plugin_apply "CS2FaceitLevels"; }
