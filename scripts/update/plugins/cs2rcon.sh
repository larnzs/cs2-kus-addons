#!/usr/bin/env bash
# Updater for LordFetznschaedl/CS2Rcon.
PLUGIN_PATHS=("game/csgo/addons/counterstrikesharp/plugins/CS2Rcon")
plugin_assets() { echo "CS2Rcon-${NEW_VERSION}.zip"; }
plugin_needs_repair() { [[ ! -f "game/csgo/addons/counterstrikesharp/plugins/CS2Rcon/CS2Rcon.dll" ]]; }
plugin_apply() {
    local x file source
    local -a matches=()
    if is_dry; then dry "overlay the CS2Rcon plugin directory only"; return 0; fi
    x=$(extract_asset "CS2Rcon-${NEW_VERSION}.zip")
    while IFS= read -r -d '' file; do matches+=("$file"); done < <(find "$x" -type f -name 'CS2Rcon.dll' -print0)
    [[ ${#matches[@]} -eq 1 ]] || die "Expected exactly one CS2Rcon.dll; found ${#matches[@]}."
    source=$(dirname "${matches[0]}")
    copy_dir "$source" "game/csgo/addons/counterstrikesharp/plugins/CS2Rcon"
    require_file "game/csgo/addons/counterstrikesharp/plugins/CS2Rcon/CS2Rcon.dll"
    remove_extracted "$x"
}
