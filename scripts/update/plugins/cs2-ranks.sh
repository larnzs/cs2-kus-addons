#!/usr/bin/env bash
# KUS-style manifest adapter for cs2-ranks; install paths are restricted to the manifest's verified targets.
source scripts/update/manifest-addon.sh
PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/Ranks"
    "game/csgo/addons/counterstrikesharp/plugins/Ranks_ExStats_GeoIP"
    "game/csgo/addons/counterstrikesharp/plugins/Ranks_ExStats_Hits"
    "game/csgo/addons/counterstrikesharp/plugins/Ranks_FakeRank"
    "game/csgo/addons/counterstrikesharp/plugins/Ranks_Tag"
    "game/csgo/addons/counterstrikesharp/shared/RanksApi"
)
plugin_assets() { manifest_addon_assets "cs2-ranks"; }
plugin_apply() { manifest_plugin_apply "cs2-ranks"; }
