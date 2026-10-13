#!/usr/bin/env bash
# Manifest-backed source-build adapter for CS2-Poor-MapPropAds (global).
source scripts/update/manifest-addon.sh

PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/CS2-Poor-MapPropAds"
)

plugin_assets() { echo "source.zip"; }
plugin_resolve_assets() { manifest_source_build_assets; }
plugin_apply() { manifest_source_build_apply "CS2-Poor-MapPropAds"; }
