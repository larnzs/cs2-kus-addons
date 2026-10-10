#!/usr/bin/env bash
# KUS-style manifest adapter for AnyBaseLibCS2; mapping/path policy lives in DEPENDENCIES.json.
source scripts/update/manifest-addon.sh
PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/shared/AnyBaseLib"
)
plugin_assets() { manifest_addon_assets "AnyBaseLibCS2"; }
plugin_apply() { manifest_plugin_apply "AnyBaseLibCS2"; }
