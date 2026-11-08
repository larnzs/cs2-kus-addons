#!/usr/bin/env bash
# Updater for imi-tat0r/CS2-CustomVotes.
# Its release is a complete plugin folder: main DLL, Shared assembly, CSSharpUtils
# and the dependency manifest must always travel together. Preserve local language files.
source scripts/update/catalog-plugin.sh

DESTINATION="game/csgo/addons/counterstrikesharp/plugins/CS2-CustomVotes"
PLUGIN_PATHS=("$DESTINATION")

plugin_assets() {
    echo "CS2-CustomVotes-${NEW_VERSION}-*.zip"
}

customvotes_payload_valid() {
    local root="$1" deps="$1/CS2-CustomVotes.deps.json"
    [[ -f "$root/CS2-CustomVotes.dll" ]] || return 1
    [[ -f "$root/CS2-CustomVotes.Shared.dll" ]] || return 1
    [[ -f "$root/CSSharpUtils.dll" ]] || return 1
    [[ -f "$deps" ]] || return 1

    jq -e '
      .runtimeTarget.name as $target
      | .targets[$target] as $assemblies
      | ($assemblies | to_entries | map(select(.key | startswith("CS2-CustomVotes/"))) | first) as $plugin
      | ($plugin.value.dependencies.CSSharpUtils // "") as $utilsVersion
      | ($plugin.value.dependencies["CS2-CustomVotes.Shared"] // "") as $sharedVersion
      | ($plugin.value.runtime | has("CS2-CustomVotes.dll"))
        and ($utilsVersion != "")
        and ($sharedVersion != "")
        and (($assemblies["CSSharpUtils/" + $utilsVersion].runtime // {}) | has("lib/net8.0/CSSharpUtils.dll"))
        and (($assemblies["CS2-CustomVotes.Shared/" + $sharedVersion].runtime // {}) | has("CS2-CustomVotes.Shared.dll"))
    ' "$deps" >/dev/null 2>&1
}

plugin_needs_repair() {
    ! customvotes_payload_valid "$DESTINATION"
}

plugin_apply() {
    local archive source
    archive="$(extract_asset "CS2-CustomVotes-${NEW_VERSION}-*.zip")"

    local -a matches=()
    while IFS= read -r -d '' file; do matches+=("$file"); done \
      < <(find "$archive" -type f -name 'CS2-CustomVotes.dll' -print0)
    [[ ${#matches[@]} -eq 1 ]] || die "Expected exactly one CS2-CustomVotes.dll in release archive, found ${#matches[@]}."
    source="$(dirname "${matches[0]}")"

    customvotes_payload_valid "$source" || die "Release archive is missing a consistent CS2-CustomVotes / CSSharpUtils dependency set."
    catalog_overlay_plugin_dir "$source" "$DESTINATION" "lang/***"
    customvotes_payload_valid "$DESTINATION" || die "CS2-CustomVotes dependency verification failed after overlay."

    remove_extracted "$archive"
}
