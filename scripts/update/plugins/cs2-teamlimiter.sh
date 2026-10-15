#!/usr/bin/env bash
# KUS-style source-build script for CS2-TeamLimiter.
# The version is the configured branch commit SHA; the release archive is built with the .NET SDK.
source scripts/update/manifest-addon.sh

PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/TeamLimiter/TeamLimiter.dll"
)

plugin_assets() { echo "source.zip"; }
plugin_resolve_assets() {
    local repo
    repo=$(github_repo_from_url "$PLUGIN_URL")
    printf 'source.zip\t%s\t0\n' "https://github.com/$repo/archive/$NEW_VERSION.zip"
}
plugin_apply() {
    local extract project output destination publish
    if is_dry; then
        dry "download source commit $NEW_VERSION and build TeamLimiter.dll with dotnet"
        dry "overlay game/csgo/addons/counterstrikesharp/plugins/TeamLimiter/TeamLimiter.dll"
        return 0
    fi
    extract=$(extract_asset "source.zip")
    project=$(jq -r --arg name "$PLUGIN_NAME" '.addons[] | select(.name == $name) | .project' DEPENDENCIES.json)
    output=$(jq -r --arg name "$PLUGIN_NAME" '.addons[] | select(.name == $name) | .output_file' DEPENDENCIES.json)
    destination=$(jq -r --arg name "$PLUGIN_NAME" '.addons[] | select(.name == $name) | .install_path' DEPENDENCIES.json)
    project=$(find "$extract" -type f -name "$project" -print -quit)
    [ -f "$project" ] || die "could not find source project for $PLUGIN_NAME"
    publish="$DOWNLOAD_DIR/publish"
    mkdir -p "$publish"
    dotnet build "$project" -c Release -o "$publish" --nologo >&3 2>&3 || die "dotnet build failed for $PLUGIN_NAME"
    [ -f "$publish/$output" ] || die "expected output missing: $publish/$output"
    copy_file "$publish/$output" "game/csgo/$destination"
    manifest_update_version "$PLUGIN_NAME" "$NEW_VERSION"
    remove_extracted "$extract"
}
