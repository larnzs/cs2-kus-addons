#!/usr/bin/env bash
# Updater for imi-tat0r/CS2-CustomVotes.
PLUGIN_PATHS=("game/csgo/addons/counterstrikesharp/plugins/CS2-CustomVotes")

plugin_assets() {
    echo "CS2-CustomVotes-${NEW_VERSION}-*.zip"
}

plugin_needs_repair() {
    [[ ! -f "game/csgo/addons/counterstrikesharp/plugins/CS2-CustomVotes/CS2-CustomVotes.dll" ]]
}

plugin_apply() {
    local x file source
    local -a matches=()
    if is_dry; then
        dry "extract the version-matched CS2-CustomVotes release and overlay only its plugin directory"
        return 0
    fi
    x=$(extract_asset "CS2-CustomVotes-${NEW_VERSION}-*.zip")
    while IFS= read -r -d '' file; do matches+=("$file"); done < <(find "$x" -type f -name 'CS2-CustomVotes.dll' -print0)
    [[ ${#matches[@]} -eq 1 ]] || die "Expected exactly one CS2-CustomVotes.dll in release archive; found ${#matches[@]}."
    source=$(dirname "${matches[0]}")
    copy_dir "$source" "game/csgo/addons/counterstrikesharp/plugins/CS2-CustomVotes"
    require_file "game/csgo/addons/counterstrikesharp/plugins/CS2-CustomVotes/CS2-CustomVotes.dll"
    remove_extracted "$x"
}
