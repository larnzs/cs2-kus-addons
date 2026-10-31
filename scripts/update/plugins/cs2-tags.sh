#!/usr/bin/env bash
# cs2-tags manifest adapter.
# The upstream ZIP has plugins/cs2-tags, shared/TagsApi and
# configs/plugins/cs2-tags directories at its root. The config allowlist is
# limited to the upstream example TOML; other CounterStrikeSharp configs stay protected.
source scripts/update/manifest-addon.sh
PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/cs2-tags"
    "game/csgo/addons/counterstrikesharp/shared/TagsApi"
    "game/csgo/addons/counterstrikesharp/configs/plugins/cs2-tags"
)
plugin_assets() { manifest_addon_assets "cs2-tags"; }
plugin_apply() { manifest_plugin_apply "cs2-tags"; }
