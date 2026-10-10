#!/usr/bin/env bash
# KUS-style manifest adapter for CS2-Kill-Plugin; install paths are restricted to the manifest's verified targets.
source scripts/update/manifest-addon.sh
PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/Kill"
)
plugin_assets() { manifest_addon_assets "CS2-Kill-Plugin"; }
plugin_apply() { manifest_plugin_apply "CS2-Kill-Plugin"; }
