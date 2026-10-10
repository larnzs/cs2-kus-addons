#!/usr/bin/env bash
# KUS-style manifest adapter for SimpleResetScore; install paths are restricted to the manifest's verified targets.
source scripts/update/manifest-addon.sh
PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/ResetScore"
)
plugin_assets() { manifest_addon_assets "SimpleResetScore"; }
plugin_apply() { manifest_plugin_apply "SimpleResetScore"; }
