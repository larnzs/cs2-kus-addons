#!/usr/bin/env bash
# KUS-style manifest adapter for WeaponPaints; mapping/path policy lives in DEPENDENCIES.json.
source scripts/update/manifest-addon.sh
PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/WeaponPaints"
    "game/csgo/addons/counterstrikesharp/gamedata/weaponpaints.json"
)
plugin_assets() { manifest_addon_assets "WeaponPaints"; }
plugin_apply() { manifest_plugin_apply "WeaponPaints"; }
