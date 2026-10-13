#!/usr/bin/env bash
# Manifest-backed release adapter for CS2-KillFeedFilter (disabled; game-mode activation only).
source scripts/update/manifest-addon.sh

PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/disabled/KillFeedFilter"
)

plugin_assets() { manifest_addon_assets "CS2-KillFeedFilter"; }
plugin_apply() { manifest_plugin_apply "CS2-KillFeedFilter"; }
