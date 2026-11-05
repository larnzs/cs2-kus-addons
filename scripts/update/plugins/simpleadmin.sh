#!/usr/bin/env bash
# Updater for the distinct KUS-bundled connercsbn/SimpleAdmin plugin.
PLUGIN_PATHS=("game/csgo/addons/counterstrikesharp/plugins/SimpleAdmin")
plugin_assets() { echo "SimpleAdmin.zip"; }
plugin_needs_repair() { [[ ! -f "game/csgo/addons/counterstrikesharp/plugins/SimpleAdmin/SimpleAdmin.dll" ]]; }
plugin_apply() {
    local x file source
    local -a matches=()
    if is_dry; then dry "overlay only the KUS SimpleAdmin plugin directory; do not touch CS2-SimpleAdmin"; return 0; fi
    x=$(extract_asset "SimpleAdmin.zip")
    while IFS= read -r -d '' file; do matches+=("$file"); done < <(find "$x" -type f -name 'SimpleAdmin.dll' -print0)
    [[ ${#matches[@]} -eq 1 ]] || die "Expected exactly one SimpleAdmin.dll; found ${#matches[@]}."
    source=$(dirname "${matches[0]}")
    copy_dir "$source" "game/csgo/addons/counterstrikesharp/plugins/SimpleAdmin"
    require_file "game/csgo/addons/counterstrikesharp/plugins/SimpleAdmin/SimpleAdmin.dll"
    remove_extracted "$x"
}
