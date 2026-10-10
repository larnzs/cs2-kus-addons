#!/usr/bin/env bash
# Shared adapter for Larnz-managed release add-ons. Individual plug-ins are KUS-style
# scripts that declare bounded PLUGIN_PATHS and delegate archive mappings here.
# This file is sourced by scripts/update/plugins/<slug>.sh; do not run directly.

manifest_addon_assets() {
    local name="$1"
    jq -r --arg name "$name" --arg version "$NEW_VERSION" '
        .addons[] | select(.name == $name) | .assets[]? | gsub("\\{version\\}"; $version)
    ' DEPENDENCIES.json
}

manifest_find_csgo_root() {
    local extract="$1" candidate d
    if [ -d "$extract/addons" ]; then printf '%s\\n' "$extract"; return 0; fi
    if [ -d "$extract/csgo/addons" ]; then printf '%s\\n' "$extract/csgo"; return 0; fi
    candidate=""
    while IFS= read -r d; do
        if [ -d "$d/addons" ]; then candidate="$d"; break; fi
    done < <(find "$extract" -type d -name csgo -print 2>/dev/null)
    if [ -n "$candidate" ]; then printf '%s\\n' "$candidate"; return 0; fi
    candidate=$(find "$extract" -type d -name addons -print 2>/dev/null | head -n 1)
    if [ -n "$candidate" ]; then dirname "$candidate"; return 0; fi
    return 1
}

manifest_mapping_for_asset() {
    local name="$1" asset="$2"
    jq -c --arg name "$name" --arg asset "$asset" --arg version "$NEW_VERSION" '
        .addons[] | select(.name == $name) as $addon |
        if ($addon.asset_mappings // null) == null then
            [{merge:($addon.merge // "release_csgo_root"),
              source_path:($addon.source_path // ""),
              install_path:($addon.install_path // "")}]
        else
            [ $addon.asset_mappings | to_entries[] |
              select((.key | gsub("\\{version\\}"; $version)) == $asset) |
              .value | (if type == "array" then .[] else . end) ]
        end
    ' DEPENDENCIES.json
}

manifest_copy_target() {
    local source="$1" destination="$2"
    if [ -d "$source" ]; then
        copy_dir "$source" "$destination"
    elif [ -f "$source" ]; then
        copy_file "$source" "$destination"
    else
        return 1
    fi
}

manifest_apply_mapping() {
    local addon="$1" extract="$2" mapping="$3"
    local mode source_path install_path source_root destination_root target relative source
    mode=$(printf '%s' "$mapping" | jq -r '.merge // empty')
    source_path=$(printf '%s' "$mapping" | jq -r '.source_path // empty')
    install_path=$(printf '%s' "$mapping" | jq -r '.install_path // empty')
    case "$mode" in
        release_csgo_root)
            source_root=$(manifest_find_csgo_root "$extract") || die "could not locate CS2/addons root for $addon"
            for target in "${PLUGIN_PATHS[@]}"; do
                case "$target" in game/csgo/*) relative="${target#game/csgo/}" ;; *) continue ;; esac
                source="$source_root/$relative"
                if [ -e "$source" ]; then
                    manifest_copy_target "$source" "$target" || die "could not overlay $source -> $target"
                fi
            done
            ;;
        release_plugin_directory)
            case "$source_path" in ""|/*|*..*) die "unsafe source_path '$source_path' for $addon" ;; esac
            case "$install_path" in ""|/*|*..*) die "unsafe install_path '$install_path' for $addon" ;; esac
            source_root="$extract/$source_path"
            destination_root="game/csgo/$install_path"
            [ -d "$source_root" ] || die "mapped source directory missing for $addon: $source_root"
            for target in "${PLUGIN_PATHS[@]}"; do
                case "$target" in
                    "$destination_root") relative="" ;;
                    "$destination_root"/*) relative="${target#"$destination_root"/}" ;;
                    *) continue ;;
                esac
                source="$source_root"
                [ -z "$relative" ] || source="$source_root/$relative"
                if [ -e "$source" ]; then
                    manifest_copy_target "$source" "$target" || die "could not overlay $source -> $target"
                fi
            done
            ;;
        *) die "unsupported manifest merge mode '$mode' for $addon" ;;
    esac
}

manifest_verify_addon() {
    local name="$1" path glob
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        [ -f "game/csgo/$path" ] || die "required file missing after update for $name: game/csgo/$path"
    done < <(jq -r --arg name "$name" '.addons[] | select(.name == $name) | .verify_paths[]?' DEPENDENCIES.json)
    while IFS= read -r glob; do
        [ -n "$glob" ] || continue
        compgen -G "game/csgo/$glob" >/dev/null || die "required file pattern missing after update for $name: game/csgo/$glob"
    done < <(jq -r --arg name "$name" '.addons[] | select(.name == $name) | .verify_globs[]?' DEPENDENCIES.json)
}

manifest_update_version() {
    local name="$1" version="$2" repo type tag json tmp
    repo=$(jq -r --arg name "$name" '.addons[] | select(.name == $name) | .repository' DEPENDENCIES.json)
    type=$(jq -r --arg name "$name" '.addons[] | select(.name == $name) | .type' DEPENDENCIES.json)
    tmp="DEPENDENCIES.json.tmp"
    if [ "$type" = "github_release" ]; then
        json=$(github_api "repos/$(github_repo_from_url "$repo")/releases?per_page=30") || die "could not confirm release tag for $name"
        tag=$(printf '%s' "$json" | jq -r --arg version "$version" '
            [.[] | select(.draft == false) |
             select((.tag_name | sub("^[^0-9]*";"") | gsub("[^0-9A-Za-z.-]";"")) == $version) |
             .tag_name] | first // empty
        ')
        [ -n "$tag" ] || die "no release tag matching $version was found for $name"
        jq --arg name "$name" --arg version "$version" --arg tag "$tag" '
            (.addons[] | select(.name == $name)) |= (.version = $version | .release_tag = $tag)
        ' DEPENDENCIES.json > "$tmp" || die "could not update manifest metadata for $name"
    else
        jq --arg name "$name" --arg version "$version" '
            (.addons[] | select(.name == $name)) |= (.version = $version | .source_commit = $version)
        ' DEPENDENCIES.json > "$tmp" || die "could not update source-build metadata for $name"
    fi
    mv "$tmp" DEPENDENCIES.json || die "could not replace manifest after updating $name"
}

manifest_plugin_apply() {
    local addon="$1" i asset extract mappings mapping
    for i in "${!MATCHED_NAMES[@]}"; do
        asset="${MATCHED_NAMES[$i]}"
        extract=$(extract_asset "$asset")
        mappings=$(manifest_mapping_for_asset "$addon" "$asset")
        [ -n "$mappings" ] || die "no manifest mapping exists for $addon asset $asset"
        while IFS= read -r mapping; do
            [ -n "$mapping" ] || continue
            manifest_apply_mapping "$addon" "$extract" "$mapping"
        done < <(printf '%s\\n' "$mappings" | jq -c '.')
        remove_extracted "$extract"
    done
    manifest_verify_addon "$addon"
    manifest_update_version "$addon" "$NEW_VERSION"
}
