#!/usr/bin/env bash
# KUS-style manifest adapter for MenuManagerCS2; mapping/path policy lives in DEPENDENCIES.json.
source scripts/update/manifest-addon.sh
PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/MenuManagerCore"
    "game/csgo/addons/counterstrikesharp/shared/MenuManagerApi"
)
plugin_assets() { manifest_addon_assets "MenuManagerCS2"; }
plugin_apply() { manifest_plugin_apply "MenuManagerCS2"; }
