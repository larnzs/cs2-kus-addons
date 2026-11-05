#!/usr/bin/env bash
# Updater for Austinbots/CS2-BotAI. Preserve both staged locations.
PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/BotAI"
    "game/csgo/addons/counterstrikesharp/plugins/disabled/BotAI"
)

plugin_assets() {
    echo "BotAiV${NEW_VERSION}.zip"
}

plugin_needs_repair() {
    [[ ! -f "game/csgo/addons/counterstrikesharp/plugins/BotAI/BotAI.dll" ||
       ! -f "game/csgo/addons/counterstrikesharp/plugins/disabled/BotAI/BotAI.dll" ]]
}

plugin_apply() {
    local x file source
    local -a matches=()
    if is_dry; then
        dry "extract BotAiV${NEW_VERSION}.zip and overlay the active and disabled BotAI folders without changing activation state"
        return 0
    fi
    x=$(extract_asset "BotAiV${NEW_VERSION}.zip")
    while IFS= read -r -d '' file; do matches+=("$file"); done < <(find "$x" -type f -name 'BotAI.dll' -print0)
    [[ ${#matches[@]} -eq 1 ]] || die "Expected exactly one BotAI.dll in release archive; found ${#matches[@]}."
    source=$(dirname "${matches[0]}")
    copy_dir "$source" "game/csgo/addons/counterstrikesharp/plugins/BotAI"
    copy_dir "$source" "game/csgo/addons/counterstrikesharp/plugins/disabled/BotAI"
    require_file "game/csgo/addons/counterstrikesharp/plugins/BotAI/BotAI.dll"
    require_file "game/csgo/addons/counterstrikesharp/plugins/disabled/BotAI/BotAI.dll"
    remove_extracted "$x"
}
