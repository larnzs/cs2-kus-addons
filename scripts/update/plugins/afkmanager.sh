#!/usr/bin/env bash
# KUS-style manifest adapter for AFKManager; install paths are restricted to the manifest's verified targets.
source scripts/update/manifest-addon.sh
PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/AFKManager"
)
plugin_assets() { manifest_addon_assets "AFKManager"; }
plugin_apply() { manifest_plugin_apply "AFKManager"; }
