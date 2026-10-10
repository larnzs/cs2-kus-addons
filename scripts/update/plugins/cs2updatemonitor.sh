#!/usr/bin/env bash
# KUS-style manifest adapter for CS2UpdateMonitor; install paths are restricted to the manifest's verified targets.
source scripts/update/manifest-addon.sh
PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/CS2UpdateMonitor"
)
plugin_assets() { manifest_addon_assets "CS2UpdateMonitor"; }
plugin_apply() { manifest_plugin_apply "CS2UpdateMonitor"; }
