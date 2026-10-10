#!/usr/bin/env bash
# KUS-style manifest adapter for CS2-SimpleAdmin; mapping/path policy lives in DEPENDENCIES.json.
source scripts/update/manifest-addon.sh
PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/CS2-SimpleAdmin"
    "game/csgo/addons/counterstrikesharp/plugins/CS2-SimpleAdmin_FunCommands"
    "game/csgo/addons/counterstrikesharp/plugins/CS2-SimpleAdmin_StealthModule"
    "game/csgo/addons/counterstrikesharp/shared/CS2-SimpleAdminApi"
)
plugin_assets() { manifest_addon_assets "CS2-SimpleAdmin"; }
plugin_apply() { manifest_plugin_apply "CS2-SimpleAdmin"; }
