#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

command -v bash >/dev/null || fail "bash is required"
command -v jq >/dev/null || fail "jq is required"
command -v sort >/dev/null || fail "sort is required"

bash -n scripts/check-updates.sh scripts/update/update.sh scripts/update/lib.sh scripts/update/manifest-addon.sh scripts/update/catalog-plugin.sh
pass "core Bash updater syntax"

manifest="$(jq -e '.addons | type == "array"' DEPENDENCIES.json)"
[ "$manifest" = "true" ] || fail "DEPENDENCIES.json has no addons array"
[ -s scripts/update/required-script-addons.txt ] || fail "required-script-addons.txt is missing or empty"

required_count=0
while IFS= read -r name; do
    [ -z "$name" ] && continue
    [ "${name:0:1}" = "#" ] && continue
    slug="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//')"
    script="scripts/update/plugins/$slug.sh"
    [ -f "$script" ] || fail "installed add-on '$name' has no adapter: $script"
    bash -n "$script" || fail "syntax error in $script"

    owned="$(bash -c '
        set -Eeuo pipefail
        exec 3>&1
        source scripts/update/lib.sh
        source "$1"
        [ "${#PLUGIN_PATHS[@]}" -gt 0 ]
        printf "%s\n" "${PLUGIN_PATHS[@]}"
    ' bash "$script")" || fail "could not source $script or read PLUGIN_PATHS"

    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        [[ "$path" != /* && "$path" != *".."* ]] || fail "$script declares unsafe path: $path"
        case "$path" in
            game/csgo/cfg|game/csgo/cfg/*|game/csgo/addons/counterstrikesharp/configs|game/csgo/addons/counterstrikesharp/configs/*|game/csgo/addons/windows/addons/counterstrikesharp/configs|game/csgo/addons/windows/addons/counterstrikesharp/configs/*)
                [[ "$path" == game/csgo/addons/counterstrikesharp/configs/plugins/cs2-tags* ]] || fail "$script owns protected config path: $path"
                ;;
        esac
    done <<< "$owned"

    required_count=$((required_count + 1))
done < scripts/update/required-script-addons.txt
[ "$required_count" -gt 0 ] || fail "no required add-ons were checked"
pass "$required_count required installed KUS add-ons have syntactically valid adapters and bounded paths"

# Every entry in the 5-minute fast-safe allowlist must have a supported updater.
fast_count=0
[ -s scripts/update/fast-safe-addons.txt ] || fail "fast-safe-addons.txt is missing or empty"
while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    [[ "${name:0:1}" = "#" ]] && continue
    if ! grep -Fqx -- "$name" scripts/update/required-script-addons.txt &&
       ! grep -Fqx -- "$name" scripts/update/future-release-addons.txt; then
        jq -e --arg name "$name" '.addons[] | select(.name == $name and .automation_supported != false)' DEPENDENCIES.json >/dev/null ||
            fail "fast allowlist entry '$name' is not required, future-release, or an automated Manifest add-on"
    fi
    slug="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//')"
    script="scripts/update/plugins/$slug.sh"
    [ -f "$script" ] || fail "fast allowlist entry '$name' has no adapter: $script"
    bash -n "$script" || fail "syntax error in fast adapter $script"
    owned="$(bash -c 'set -Eeuo pipefail; exec 3>&1; source scripts/update/lib.sh; source "$1"; printf "%s\n" "${PLUGIN_PATHS[@]}"; plugin_assets >/dev/null' bash "$script")" || fail "could not load fast adapter $script"
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        [ -e "$path" ] || fail "$script points to a missing payload path: $path"
    done <<< "$owned"
    fast_count=$((fast_count + 1))
done < scripts/update/fast-safe-addons.txt
[ "$fast_count" -gt 0 ] || fail "no fast allowlist adapters were checked"
pass "$fast_count 5-minute fast-safe allowlist entries have loadable adapters and existing payload paths"

# Future-release plugins remain covered even before upstream publishes its first release.
[ -s scripts/update/future-release-addons.txt ] || fail "future-release-addons.txt is missing or empty"
future_count=0
while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    [[ "${name:0:1}" = "#" ]] && continue
    if grep -Fqx -- "$name" scripts/update/required-script-addons.txt; then
        fail "future-release add-on '$name' must not be required to resolve a non-existent release"
    fi
    slug="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//')"
    script="scripts/update/plugins/$slug.sh"
    [ -f "$script" ] || fail "future-release add-on '$name' has no adapter: $script"
    bash -n "$script" || fail "syntax error in future-release adapter $script"
    owned="$(bash -c 'set -Eeuo pipefail; exec 3>&1; source scripts/update/lib.sh; source "$1"; printf "%s\n" "${PLUGIN_PATHS[@]}"; plugin_assets >/dev/null' bash "$script")" || fail "could not load future-release adapter $script"
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        [ -e "$path" ] || fail "$script points to a missing payload path: $path"
    done <<< "$owned"
    future_count=$((future_count + 1))
done < scripts/update/future-release-addons.txt
[ "$future_count" -gt 0 ] || fail "no future-release adapters were checked"
pass "$future_count first-release adapters are covered without causing unknown-version failures"

# Exercise the catalog helper against fixtures: unique DLL discovery, local-file
# preservation, merge-only behavior, and bounded write destinations.
command -v rsync >/dev/null || fail "rsync is required for catalog helper tests"
mkdir -p tmp
fixture="$(mktemp -d tmp/catalog-updater-test.XXXXXX)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/archive/package" "$fixture/source" "$fixture/destination"
printf 'release-binary' > "$fixture/archive/package/plugin.dll"
printf 'new-binary' > "$fixture/source/plugin.dll"
printf 'operator-setting' > "$fixture/source/local.json"
printf 'old-setting' > "$fixture/destination/local.json"
printf 'keep-old-file' > "$fixture/destination/obsolete.dll"
DRY_RUN=0
source scripts/update/lib.sh
PLUGIN_PATHS=("$fixture/destination")
source scripts/update/catalog-plugin.sh
resolved="$(catalog_find_plugin_dir "$fixture/archive" "plugin.dll")"
[ "$resolved" = "$fixture/archive/package" ] || fail "catalog helper resolved the wrong plugin directory: $resolved"
catalog_overlay_plugin_dir "$fixture/source" "$fixture/destination" "local.json"
[ "$(cat "$fixture/destination/plugin.dll")" = "new-binary" ] || fail "catalog helper did not overlay the release binary"
[ "$(cat "$fixture/destination/local.json")" = "old-setting" ] || fail "catalog helper overwrote an excluded local file"
[ "$(cat "$fixture/destination/obsolete.dll")" = "keep-old-file" ] || fail "catalog helper unexpectedly deleted an existing file"
mkdir -p "$fixture/ambiguous/a" "$fixture/ambiguous/b"
: > "$fixture/ambiguous/a/duplicate.dll"
: > "$fixture/ambiguous/b/duplicate.dll"
if ( catalog_find_plugin_dir "$fixture/ambiguous" "duplicate.dll" >/dev/null 2>&1 ); then
    fail "catalog helper accepted an ambiguous DLL sentinel"
fi
pass "catalog helper fails closed on ambiguous archives and preserves excluded/local files"
rm -rf "$fixture"
trap - EXIT

# Every automation-enabled manifest entry, including bootstrap installs, must have its own adapter.
manifest_count=0
while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    slug="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//')"
    script="scripts/update/plugins/$slug.sh"
    [ -f "$script" ] || fail "manifest add-on '$name' has no adapter: $script"
    bash -n "$script" || fail "syntax error in manifest adapter $script"
    manifest_count=$((manifest_count + 1))
done < <(jq -r '.addons[] | select(.automation_supported != false) | .name' DEPENDENCIES.json)
pass "$manifest_count installed/automated manifest add-ons have adapter files"

# These mode-specific plugins are disabled by default, not excluded from updating.
# Their adapters must keep targeting the exact plugins/disabled payload folders.
mode_plugins=(
    "CS2 Remove Map Weapons"
    "K4-DamageInfo"
    "K4-Arenas"
    "CS2 Retakes Allocator"
    "OpenPrefirePrac"
    "CS2-GameModifiers"
    "CS2WarcraftMod"
    "cs2-advanced-weapon-system"
    "cs2-OneInTheChamber"
    "CS2-WeaponSpeed"
)
mode_count=0
for name in "${mode_plugins[@]}"; do
    grep -Fqx -- "$name" scripts/update/required-script-addons.txt || fail "disabled mode plugin '$name' is not mandatory updater coverage"
    slug="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//')"
    script="scripts/update/plugins/$slug.sh"
    [ -f "$script" ] || fail "disabled mode plugin '$name' has no updater: $script"
    paths="$(bash -c 'set -Eeuo pipefail; exec 3>&1; source scripts/update/lib.sh; source "$1"; printf "%s\n" "${PLUGIN_PATHS[@]}"' bash "$script")" || fail "could not inspect disabled plugin paths for '$name'"
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        [[ "$path" == game/csgo/addons/counterstrikesharp/plugins/disabled/* ]] || fail "$name updater escapes plugins/disabled: $path"
    done <<< "$paths"
    mode_count=$((mode_count + 1))
done
[ "$mode_count" -eq 10 ] || fail "expected exactly 10 disabled mode-plugin adapters, checked $mode_count"
pass "$mode_count disabled mode-specific plugins have required adapters and preserve their disabled payload locations"

# GG1MapChooser and MenuManagerCS2 are supplied by the GameModeManager release,
# so neither component may have an independent release tracker or updater adapter.
for bundled_name in "GG1MapChooser" "MenuManagerCS2"; do
    bundled_entry="$(jq -c --arg name "$bundled_name" '.addons[] | select(.name == $name)' DEPENDENCIES.json)"
    [ -n "$bundled_entry" ] || fail "$bundled_name is missing from DEPENDENCIES.json"
    printf '%s' "$bundled_entry" | jq -e '
        .type == "bundled" and
        .version == "bundled" and
        .installed == true and
        .automation_supported == false and
        .bundled_by == "GameModeManager" and
        (.bundle_component | type == "string" and length > 0) and
        (.bundle_shared_dependency | type == "string" and length > 0) and
        ((.verify_paths | length) >= 4) and
        (has("assets") | not) and
        (has("asset_mappings") | not) and
        (has("track") | not)
    ' >/dev/null || fail "$bundled_name is not configured as a verified GameModeManager bundle dependency"
done
[ ! -e "scripts/update/plugins/gg1mapchooser.sh" ] || fail "GG1MapChooser still has a competing standalone updater"
[ ! -e "scripts/update/plugins/menumanagercs2.sh" ] || fail "MenuManagerCS2 still has a competing standalone updater"
pass "GG1MapChooser and MenuManagerCS2 are bundle-only manifest dependencies with no duplicate updater"

# GameModeManager must resolve through its exact slug-derived script filename.
gmm_slug="$(bash -c 'source scripts/update/lib.sh; slugify "GameModeManager"')"
[ "$gmm_slug" = "gamemodemanager" ] || fail "GameModeManager slug changed unexpectedly: $gmm_slug"
gmm_script="scripts/update/plugins/$gmm_slug.sh"
[ -f "$gmm_script" ] || fail "GameModeManager auto-loader path is missing: $gmm_script"
bash -n "$gmm_script" || fail "GameModeManager updater syntax is invalid"
gmm_paths="$(bash -c 'set -Eeuo pipefail; exec 3>&1; source scripts/update/lib.sh; source "$1"; printf "%s\n" "${PLUGIN_PATHS[@]}"' bash "$gmm_script")" || fail "could not inspect GMM PLUGIN_PATHS"
for required_path in \
    "plugins/GameModeManager" \
    "plugins/GG1MapChooser" \
    "plugins/MenuManagerCore" \
    "plugins/PMM_GG1MapChooser" \
    "shared/GameModeManager.Shared" \
    "shared/ggmcAPI" \
    "shared/MenuManagerApi"; do
    printf '%s' "$gmm_paths" | grep -Fq "$required_path" || fail "GMM bundled path is missing: $required_path"
done
if printf '%s\n' "$gmm_paths" | grep -E '(^|/)(cfg|configs)(/|$)' >/dev/null; then
    fail "GMM PLUGIN_PATHS must not include cfg or config trees"
fi
gmm_script_text="$(cat "$gmm_script")"
for required_archive_path in \
    'addons/counterstrikesharp/plugins/GameModeManager' \
    'addons/counterstrikesharp/plugins/GG1MapChooser' \
    'addons/counterstrikesharp/plugins/MenuManagerCore' \
    'addons/counterstrikesharp/plugins/PMM_GG1MapChooser' \
    'addons/counterstrikesharp/shared/GameModeManager.Shared' \
    'addons/counterstrikesharp/shared/ggmcAPI' \
    'addons/counterstrikesharp/shared/MenuManagerApi'; do
    printf '%s' "$gmm_script_text" | grep -Fq "$required_archive_path" || fail "GMM updater is missing archive source path: $required_archive_path"
done
pass "GameModeManager owns all four bundled plugins and three shared APIs; cfg/configs remain protected"

# MultiAddonManager is Linux-only for Pterodactyl and must choose the tested SteamRT3 asset.
mam_runtime="$(jq -r '.architecture.pterodactyl_linux_runtime // empty' DEPENDENCIES.json)"
[ "$mam_runtime" = "steamrt3" ] || fail "Pterodactyl runtime must be steamrt3, got '$mam_runtime'"
mam_asset="$(bash -c 'set -Eeuo pipefail; exec 3>&1; source scripts/update/lib.sh; source scripts/update/plugins/multiaddonmanager.sh; NEW_VERSION=1.7.3; plugin_assets')"
[ "$mam_asset" = "MultiAddonManager-v1.7.3-steamrt3.tar.gz" ] || fail "MultiAddonManager selected the wrong release asset: $mam_asset"
mam_paths="$(bash -c 'set -Eeuo pipefail; exec 3>&1; source scripts/update/lib.sh; source scripts/update/plugins/multiaddonmanager.sh; printf "%s\n" "${PLUGIN_PATHS[@]}"')"
printf '%s' "$mam_paths" | grep -Fq 'multiaddonmanager.so' || fail "MultiAddonManager Linux binary path is missing"
printf '%s' "$mam_paths" | grep -Fq 'addons/metamod/multiaddonmanager.vdf' || fail "MultiAddonManager MetaMod VDF path is missing"
if printf '%s\n' "$mam_paths" | grep -E 'multiaddonmanager.dll|(^|/)(cfg|configs)(/|$)' >/dev/null; then
    fail "MultiAddonManager must not own Windows binaries or cfg/config trees"
fi
grep -Fq 'MultiAddonManager' scripts/update/required-script-addons.txt || fail "MultiAddonManager is not in required updater coverage"
pass "MultiAddonManager SteamRT3 asset selection and Linux destination paths"

# Same-version repair verifies the complete GameModeManager bundle, not separate adapters.
grep -Fq 'plugin_needs_repair()' scripts/update/plugins/gamemodemanager.sh || fail "GameModeManager bundle same-version repair is missing"
grep -Fq 'GameModeManager.Shared/GameModeManager.Shared.dll' scripts/update/plugins/gamemodemanager.sh || fail "GameModeManager shared contract verification is missing"
grep -Fq 'MenuManagerApi/MenuManagerApi.dll' scripts/update/plugins/gamemodemanager.sh || fail "MenuManagerApi bundle verification is missing"
pass "GameModeManager bundle same-version repair covers all bundled runtime components"

# The runner must treat missing adapters on required installed rows as failures.
grep -Fq 'is_required_script_addon "$PLUGIN_NAME"' scripts/update/update.sh || fail "update.sh does not enforce required adapter coverage"
grep -Fq 'installed add-on is missing its required updater adapter' scripts/update/update.sh || fail "update.sh missing-adapter failure message is absent"
pass "missing updater adapters cannot produce a successful run for required installed add-ons"

printf '\nHARDCheck complete: %s required add-ons, %s automated manifest add-ons.\n' "$required_count" "$manifest_count"
