#!/usr/bin/env bash
# Updater for kus/CS2_ExecAfter.
PLUGIN_PATHS=("game/csgo/addons/counterstrikesharp/plugins/CS2_ExecAfter")
plugin_assets() { echo "CS2_ExecAfter-${NEW_VERSION}.zip"; }
plugin_needs_repair() { [[ ! -f "game/csgo/addons/counterstrikesharp/plugins/CS2_ExecAfter/CS2_ExecAfter.dll" ]]; }
plugin_apply() {
    local x file source
    local -a matches=()
    if is_dry; then dry "overlay the CS2_ExecAfter plugin directory only"; return 0; fi
    x=$(extract_asset "CS2_ExecAfter-${NEW_VERSION}.zip")
    while IFS= read -r -d '' file; do matches+=("$file"); done < <(find "$x" -type f -name 'CS2_ExecAfter.dll' -print0)
    [[ ${#matches[@]} -eq 1 ]] || die "Expected exactly one CS2_ExecAfter.dll; found ${#matches[@]}."
    source=$(dirname "${matches[0]}")
    copy_dir "$source" "game/csgo/addons/counterstrikesharp/plugins/CS2_ExecAfter"
    require_file "game/csgo/addons/counterstrikesharp/plugins/CS2_ExecAfter/CS2_ExecAfter.dll"
    remove_extracted "$x"
}
