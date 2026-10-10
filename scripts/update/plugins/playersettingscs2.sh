#!/usr/bin/env bash
# KUS-style manifest adapter for PlayerSettingsCS2; mapping/path policy lives in DEPENDENCIES.json.
source scripts/update/manifest-addon.sh
PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/PlayerSettings"
    "game/csgo/addons/counterstrikesharp/shared/PlayerSettingsApi"
)
plugin_assets() { manifest_addon_assets "PlayerSettingsCS2"; }
plugin_apply() { manifest_plugin_apply "PlayerSettingsCS2"; }
