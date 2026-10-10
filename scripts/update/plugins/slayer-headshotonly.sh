#!/usr/bin/env bash
# KUS-style manifest adapter for SLAYER_HeadshotOnly; install paths are restricted to the manifest's verified targets.
source scripts/update/manifest-addon.sh
PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/SLAYER_HeadshotOnly"
    "game/csgo/addons/counterstrikesharp/source/SLAYER_HeadshotOnly"
)
plugin_assets() { manifest_addon_assets "SLAYER_HeadshotOnly"; }
plugin_apply() { manifest_plugin_apply "SLAYER_HeadshotOnly"; }
