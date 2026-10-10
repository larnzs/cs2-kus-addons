#!/usr/bin/env bash
# KUS-style manifest adapter for SLAYER_AntiCamp; install paths are restricted to the manifest's verified targets.
source scripts/update/manifest-addon.sh
PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/SLAYER_AntiCamp"
    "game/csgo/addons/counterstrikesharp/source/SLAYER_AntiCamp"
)
plugin_assets() { manifest_addon_assets "SLAYER_AntiCamp"; }
plugin_apply() { manifest_plugin_apply "SLAYER_AntiCamp"; }
