#!/usr/bin/env bash
# Manifest-backed source-build adapter for AdvancedFriendlyFire (disabled; game-mode activation only).
source scripts/update/manifest-addon.sh

PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/disabled/advanced_friendlyfire"
)

plugin_assets() { echo "source.zip"; }
plugin_resolve_assets() { manifest_source_build_assets; }
plugin_apply() { manifest_source_build_apply "AdvancedFriendlyFire"; }
