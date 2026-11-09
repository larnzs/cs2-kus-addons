#!/usr/bin/env bash
# Manifest-backed source-build adapter for CS2-Gunsmenu.
# The plugin stays under plugins/disabled for mode-specific css_plugins load commands.
source scripts/update/manifest-addon.sh

DESTINATION="game/csgo/addons/counterstrikesharp/plugins/disabled/GunsMenu"
PLUGIN_PATHS=("$DESTINATION")

plugin_assets() { echo "source.zip"; }
plugin_resolve_assets() { manifest_source_build_assets; }

plugin_needs_repair() {
    [[ ! -s "$DESTINATION/GunsMenu.dll" ||
       ! -s "$DESTINATION/GunsMenu.deps.json" ||
       -e "$DESTINATION/CounterStrikeSharp.API.dll" ]]
}

plugin_apply() {
    manifest_source_build_apply "CS2-Gunsmenu"
    if is_dry; then
        dry "remove stale plugin-local CounterStrikeSharp.API.dll; the server CSS runtime supplies this assembly"
        return 0
    fi
    rm -f -- "$DESTINATION/CounterStrikeSharp.API.dll" "$DESTINATION/CounterStrikeSharp.API.xml"
}
