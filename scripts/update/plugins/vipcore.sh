#!/usr/bin/env bash
# Manifest-backed updater for VIPCore.
# Only the VIPCore plugin directory and VipCoreApi shared directory are managed.
# CounterStrikeSharp configs are deliberately outside PLUGIN_PATHS.
source scripts/update/manifest-addon.sh

PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/VIPCore"
    "game/csgo/addons/counterstrikesharp/shared/VipCoreApi"
)

plugin_assets() { manifest_addon_assets "VIPCore"; }
plugin_apply() { manifest_plugin_apply "VIPCore"; }
