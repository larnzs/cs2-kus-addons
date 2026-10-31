#!/usr/bin/env bash
# SharpTimer manifest adapter.
# DEPENDENCIES.json owns release source, archive layout and install destinations.
# Keep the existing disabled plugin location and leave cfg/SharpTimer operator-managed.
source scripts/update/manifest-addon.sh
PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/disabled/SharpTimer"
    "game/csgo/addons/counterstrikesharp/shared/SharpTimerAPI"
    "game/csgo/addons/counterstrikesharp/gamedata/stgamedata.json"
)
plugin_assets() { manifest_addon_assets "SharpTimer"; }
plugin_apply() { manifest_plugin_apply "SharpTimer"; }
