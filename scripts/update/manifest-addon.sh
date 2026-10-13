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
    if [ -d "$extract/addons" ]; then printf '%s\n' "$extract"; return 0; fi
    if [ -d "$extract/csgo/addons" ]; then printf '%s\n' "$extract/csgo"; return 0; fi
    candidate=""
    while IFS= read -r d; do
        if [ -d "$d/addons" ]; then candidate="$d"; break; fi
    done < <(find "$extract" -type d -name csgo -print 2>/dev/null)
    if [ -n "$candidate" ]; then printf '%s\n' "$candidate"; return 0; fi
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
    if is_dry; then
        dry "update DEPENDENCIES.json version for $name to $version"
        return 0
    fi
    repo=$(jq -r --arg name "$name" '.addons[] | select(.name == $name) | .repository' DEPENDENCIES.json)
    type=$(jq -r --arg name "$name" '.addons[] | select(.name == $name) | .type' DEPENDENCIES.json)
    tmp="DEPENDENCIES.json.tmp"
    if [ "$name" = "Metamod:Source" ]; then
        # KUS resolves MetaMod from metamodsource.net, not GitHub's unrelated stable /releases/latest line.
        tag=$(printf '%s' "$version" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+)-([0-9]+)$/\1.\2/')
        [ "$tag" != "$version" ] || die "could not derive the MetaMod release tag from version $version"
        jq --arg name "$name" --arg version "$version" --arg tag "$tag" '
            (.addons[] | select(.name == $name)) |= (.version = $version | .release_tag = $tag)
        ' DEPENDENCIES.json > "$tmp" || die "could not update MetaMod manifest metadata"
    elif [ "$type" = "github_release" ]; then
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
    if is_dry; then
        for asset in "${MATCHED_NAMES[@]}"; do
            dry "apply $asset using the DEPENDENCIES.json mappings for $addon"
        done
        dry "verify declared runtime paths for $addon"
        return 0
    fi
    for i in "${!MATCHED_NAMES[@]}"; do
        asset="${MATCHED_NAMES[$i]}"
        extract=$(extract_asset "$asset")
        mappings=$(manifest_mapping_for_asset "$addon" "$asset")
        [ -n "$mappings" ] || die "no manifest mapping exists for $addon asset $asset"
        while IFS= read -r mapping; do
            [ -n "$mapping" ] || continue
            manifest_apply_mapping "$addon" "$extract" "$mapping"
        done < <(printf '%s\n' "$mappings" | jq -c '.[]')
        remove_extracted "$extract"
    done
    manifest_verify_addon "$addon"
    manifest_update_version "$addon" "$NEW_VERSION"
}

# ----------------------------------------------------------------------------- source-built manifest add-ons
# Source-built plugins are tracked by their branch commit SHA in DEPENDENCIES.json.
# The per-plugin wrapper declares PLUGIN_PATHS; these shared functions only fetch,
# build and overlay files inside those declared targets. No existing files are deleted.

manifest_source_build_assets() {
    local repo
    repo=$(github_repo_from_url "$PLUGIN_URL")
    [ -n "$repo" ] || die "could not resolve GitHub repository for $PLUGIN_NAME"
    [ -n "$NEW_VERSION" ] || die "no source commit SHA available for $PLUGIN_NAME"
    printf 'source.zip\t%s\t0\n' "https://github.com/$repo/archive/$NEW_VERSION.zip"
}

manifest_source_build_apply() {
    local addon="$1"
    local project_relative output_file install_directory target_framework extract project source_root current
    local publish built relative destination source_relative install_relative source target

    project_relative=$(jq -er --arg name "$addon" '.addons[] | select(.name == $name) | .project // empty' DEPENDENCIES.json) \
        || die "manifest project is missing for source-built addon $addon"
    output_file=$(jq -er --arg name "$addon" '.addons[] | select(.name == $name) | .output_file // empty' DEPENDENCIES.json) \
        || die "manifest output_file is missing for source-built addon $addon"
    install_directory=$(jq -er --arg name "$addon" '.addons[] | select(.name == $name) | .install_directory // empty' DEPENDENCIES.json) \
        || die "manifest install_directory is missing for source-built addon $addon"
    target_framework=$(jq -r --arg name "$addon" '.addons[] | select(.name == $name) | .target_framework // empty' DEPENDENCIES.json)

    if [ -n "$target_framework" ] && [[ ! "$target_framework" =~ ^net[0-9]+\.[0-9]+$ ]]; then
        die "invalid target_framework for $addon: $target_framework"
    fi

    check_repo_relative "$project_relative" || die "unsafe project path for $addon: $project_relative"
    check_repo_relative "game/csgo/$install_directory" || die "unsafe install directory for $addon: $install_directory"
    case "$output_file" in
        ""|*/*|*\\*|*..*) die "unsafe output_file for $addon: $output_file" ;;
    esac

    if is_dry; then
        dry "download source commit $NEW_VERSION and build $addon using $project_relative"
        if [ -n "$target_framework" ]; then dry "override upstream target framework to $target_framework"; fi
        dry "overlay build output into game/csgo/$install_directory (excluding CounterStrikeSharp.API.dll/xml)"
        while IFS=$'\t' read -r source_relative install_relative; do
            [ -n "$source_relative" ] || continue
            dry "overlay source mapping $source_relative -> game/csgo/$install_relative"
        done < <(jq -r --arg name "$addon" '.addons[] | select(.name == $name) | .source_mappings[]? | [.source_path, .install_path] | @tsv' DEPENDENCIES.json)
        dry "verify declared runtime paths for $addon"
        manifest_update_version "$addon" "$NEW_VERSION"
        return 0
    fi

    extract=$(extract_asset "source.zip")
    project=$(find "$extract" -type f -path "*/$project_relative" -print -quit)
    [ -n "$project" ] && [ -f "$project" ] || die "could not find source project for $addon: $project_relative"

    # GitHub source ZIPs contain one wrapper folder. Walk upward from the project
    # to the repository root (identified by README.md), so source_mappings remain
    # relative to the upstream repository even when the csproj lives in src/.
    source_root=$(dirname "$project")
    while [ "$source_root" != "$extract" ]; do
        [ ! -f "$source_root/README.md" ] || break
        current=$(dirname "$source_root")
        [ "$current" != "$source_root" ] || break
        source_root="$current"
    done
    [ -f "$source_root/README.md" ] || die "could not identify upstream source root for $addon (expected README.md above the project)"
    [ -d "$source_root" ] || die "upstream source root is not a directory for $addon: $source_root"

    publish="$DOWNLOAD_DIR/publish"
    case "$publish" in
        tmp/update/*/publish) ;;
        *) die "refusing to use unexpected build output path: $publish" ;;
    esac
    rm -rf "$publish"
    mkdir -p "$publish"

    step "building $addon from commit $NEW_VERSION"
    local -a build_args
    build_args=(build "$project" -c Release -o "$publish" --nologo -p:CopyLocalLockFileAssemblies=true)
    if [ -n "$target_framework" ]; then
        # Patch the isolated downloaded project: a global TargetFramework property
        # alone may leave restore evaluating the upstream net8.0 declaration.
        if ! grep -Eq '<TargetFrameworks?>[[:space:]]*[^<]*[[:space:]]*</TargetFrameworks?>' "$project"; then
            die "target_framework is configured for $addon, but no TargetFramework/TargetFrameworks element exists in $project"
        fi
        sed -i -E "s#<TargetFrameworks?>[[:space:]]*[^<]*[[:space:]]*</TargetFrameworks?>#<TargetFramework>$target_framework</TargetFramework>#g" "$project"
        if ! grep -Fq "<TargetFramework>$target_framework</TargetFramework>" "$project"; then
            die "could not enforce target framework $target_framework for $addon"
        fi
        build_args+=(--framework "$target_framework" "-p:TargetFramework=$target_framework" "-p:TargetFrameworks=$target_framework")
        step "patched isolated source project and restore/build target framework to $target_framework"
    fi
    dotnet "${build_args[@]}" >&3 2>&3 || die "dotnet build failed for $addon"
    [ -f "$publish/$output_file" ] || die "expected build output missing for $addon: $publish/$output_file"

    # Keep the plugin's full build output (including .deps.json and private
    # NuGet dependencies), but use the live CounterStrikeSharp API supplied by
    # the server instead of shipping a private copy in every plugin directory.
    while IFS= read -r -d '' built; do
        relative="${built#"$publish"/}"
        case "$relative" in
            CounterStrikeSharp.API.dll|CounterStrikeSharp.API.xml) continue ;;
        esac
        destination="game/csgo/$install_directory/$relative"
        copy_file "$built" "$destination"
    done < <(find "$publish" -type f -print0)

    # Some projects keep language files or sample data beside the csproj rather
    # than copying them to dotnet's output. Apply the explicit manifest mappings
    # for those files without touching manually managed CounterStrikeSharp configs.
    while IFS=$'\t' read -r source_relative install_relative; do
        [ -n "$source_relative" ] || continue
        case "$source_relative" in
            ""|/*|..|../*|*/..|*/../*) die "unsafe source mapping path for $addon: $source_relative" ;;
        esac
        check_repo_relative "game/csgo/$install_relative" || die "unsafe source mapping destination for $addon: $install_relative"
        source="$source_root/$source_relative"
        destination="game/csgo/$install_relative"
        if [ -d "$source" ]; then
            copy_dir "$source" "$destination"
        elif [ -f "$source" ]; then
            copy_file "$source" "$destination"
        else
            die "manifest source mapping does not exist for $addon: $source_relative"
        fi
    done < <(jq -r --arg name "$addon" '.addons[] | select(.name == $name) | .source_mappings[]? | [.source_path, .install_path] | @tsv' DEPENDENCIES.json)

    manifest_verify_addon "$addon"
    manifest_update_version "$addon" "$NEW_VERSION"
    remove_extracted "$extract"
}
