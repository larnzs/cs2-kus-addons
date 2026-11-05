#!/usr/bin/env bash
# Updater for lengran/CS2AnnouncementBroadcaster.
PLUGIN_PATHS=("game/csgo/addons/counterstrikesharp/plugins/CS2AnnouncementBroadcaster")
plugin_assets() { echo "CS2AnnouncementBroadcaster-v${NEW_VERSION}.zip"; }
plugin_needs_repair() { [[ ! -f "game/csgo/addons/counterstrikesharp/plugins/CS2AnnouncementBroadcaster/CS2AnnouncementBroadcaster.dll" ]]; }
plugin_apply() {
    local x file source
    local -a matches=()
    if is_dry; then dry "overlay only the CS2AnnouncementBroadcaster plugin directory"; return 0; fi
    x=$(extract_asset "CS2AnnouncementBroadcaster-v${NEW_VERSION}.zip")
    while IFS= read -r -d '' file; do matches+=("$file"); done < <(find "$x" -type f -name 'CS2AnnouncementBroadcaster.dll' -print0)
    [[ ${#matches[@]} -eq 1 ]] || die "Expected exactly one CS2AnnouncementBroadcaster.dll; found ${#matches[@]}."
    source=$(dirname "${matches[0]}")
    copy_dir "$source" "game/csgo/addons/counterstrikesharp/plugins/CS2AnnouncementBroadcaster"
    require_file "game/csgo/addons/counterstrikesharp/plugins/CS2AnnouncementBroadcaster/CS2AnnouncementBroadcaster.dll"
    remove_extracted "$x"
}
