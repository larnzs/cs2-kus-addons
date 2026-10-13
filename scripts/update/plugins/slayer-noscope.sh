#!/usr/bin/env bash
# Manifest-backed source-build adapter for SLAYER_Noscope (global).
source scripts/update/manifest-addon.sh

PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/SLAYER_Noscope"
)

plugin_assets() { echo "source.zip"; }
plugin_resolve_assets() { manifest_source_build_assets; }
plugin_apply() { manifest_source_build_apply "SLAYER_Noscope"; }
