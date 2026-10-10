#!/usr/bin/env bash
# KUS-style manifest adapter for cs2-showdamage; install paths are restricted to the manifest's verified targets.
source scripts/update/manifest-addon.sh
PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/ShowDamage"
)
plugin_assets() { manifest_addon_assets "cs2-showdamage"; }
plugin_apply() { manifest_plugin_apply "cs2-showdamage"; }
