#!/usr/bin/env bash
# Updater for partiusfabaa/cs2-advertisement.
PLUGIN_PATHS=("game/csgo/addons/counterstrikesharp/plugins/Advertisement")

plugin_assets() {
    echo "Advertisement.zip"
}

plugin_needs_repair() {
    [[ ! -f "game/csgo/addons/counterstrikesharp/plugins/Advertisement/Advertisement.dll" ]]
}

plugin_apply() {
    local x file source
    local -a matches=()
    if is_dry; then
        dry "extract Advertisement.zip and overlay the Advertisement plugin directory only; keep configs/plugins/Advertisement untouched"
        return 0
    fi
    x=$(extract_asset "Advertisement.zip")
    while IFS= read -r -d '' file; do matches+=("$file"); done < <(find "$x" -type f -name 'Advertisement.dll' -print0)
    [[ ${#matches[@]} -eq 1 ]] || die "Expected exactly one Advertisement.dll in Advertisement.zip; found ${#matches[@]}."
    source=$(dirname "${matches[0]}")
    copy_dir "$source" "game/csgo/addons/counterstrikesharp/plugins/Advertisement"
    require_file "game/csgo/addons/counterstrikesharp/plugins/Advertisement/Advertisement.dll"
    remove_extracted "$x"
}
