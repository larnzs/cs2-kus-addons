#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

command -v bash >/dev/null || fail "bash is required"
command -v jq >/dev/null || fail "jq is required"
command -v sort >/dev/null || fail "sort is required"

bash -n scripts/check-updates.sh scripts/update/update.sh scripts/update/lib.sh scripts/update/manifest-addon.sh
pass "core Bash updater syntax"

manifest="$(jq -e '.addons | type == "array"' DEPENDENCIES.json)"
[ "$manifest" = "true" ] || fail "DEPENDENCIES.json has no addons array"
[ -s scripts/update/required-script-addons.txt ] || fail "required-script-addons.txt is missing or empty"

required_count=0
while IFS= read -r name; do
    [[ -z "$name" || "$name" == #* ]] && continue
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

# Every installed, automation-enabled manifest entry must have its own adapter.
manifest_count=0
while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    slug="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//')"
    script="scripts/update/plugins/$slug.sh"
    [ -f "$script" ] || fail "manifest add-on '$name' has no adapter: $script"
    bash -n "$script" || fail "syntax error in manifest adapter $script"
    manifest_count=$((manifest_count + 1))
done < <(jq -r '.addons[] | select(.installed == true) | select(.automation_supported != false) | .name' DEPENDENCIES.json)
pass "$manifest_count installed/automated manifest add-ons have adapter files"

# Regression: the RRimmer archive uses a CSS-build suffix that must match the
# wildcard asset mapping on both Bash and PowerShell updater code paths.
mm_repo="$(jq -r '.addons[] | select(.name == "MenuManagerCS2") | .repository' DEPENDENCIES.json)"
mm_asset="$(jq -r '.addons[] | select(.name == "MenuManagerCS2") | .assets[0]' DEPENDENCIES.json)"
[ "$mm_repo" = "https://github.com/RRimmer/PanoramaMenuManagerCS2" ] || fail "MenuManagerCS2 is not tracking the PanoramaMenuManager fork"
[[ "$mm_asset" == *"cssharp*.zip" ]] || fail "MenuManagerCS2 must match the CSS-versioned archive"
mapping="$(bash -c '
    set -Eeuo pipefail
    exec 3>&1
    source scripts/update/lib.sh
    source scripts/update/manifest-addon.sh
    NEW_VERSION="1.3.01"
    manifest_mapping_for_asset "MenuManagerCS2" "MenuManagerCS2-1.3.01-cssharp377.zip"
' )" || fail "wildcard manifest asset mapping failed"
printf '%s' "$mapping" | jq -e 'length == 1 and .[0].merge == "release_plugin_directory" and .[0].source_path == "Server-plugins/addons" and .[0].install_path == "addons"' >/dev/null || fail "MenuManagerCS2 wildcard mapping resolved incorrectly"
pass "wildcard MenuManagerCS2 asset mapping resolves to the intended server-plugin root"

# GameModeManager must resolve through its exact slug-derived script filename.
gmm_slug="$(bash -c 'source scripts/update/lib.sh; slugify "GameModeManager"')"
[ "$gmm_slug" = "gamemodemanager" ] || fail "GameModeManager slug changed unexpectedly: $gmm_slug"
gmm_script="scripts/update/plugins/$gmm_slug.sh"
[ -f "$gmm_script" ] || fail "GameModeManager auto-loader path is missing: $gmm_script"
bash -n "$gmm_script" || fail "GameModeManager updater syntax is invalid"
gmm_paths="$(bash -c 'set -Eeuo pipefail; exec 3>&1; source scripts/update/lib.sh; source "$1"; printf "%s\n" "\${PLUGIN_PATHS[@]}"' bash "$gmm_script")" || fail "could not inspect GMM PLUGIN_PATHS"
printf '%s' "$gmm_paths" | grep -Fq 'plugins/GameModeManager' || fail "GMM plugin path is missing"
printf '%s' "$gmm_paths" | grep -Fq 'plugins/PMM_GG1MapChooser' || fail "GMM bundled PMM path is missing"
printf '%s' "$gmm_paths" | grep -Fq 'shared/GameModeManager.Shared' || fail "GMM shared dependency path is missing"
if printf '%s\n' "$gmm_paths" | grep -E '(^|/)(cfg|configs)(/|$)' >/dev/null; then
    fail "GMM PLUGIN_PATHS must not include cfg or config trees"
fi
pass "GameModeManager slug, bundled plugins, shared API and protected configs"

# MultiAddonManager is Linux-only for Pterodactyl and must choose the tested SteamRT3 asset.
mam_runtime="$(jq -r '.architecture.pterodactyl_linux_runtime // empty' DEPENDENCIES.json)"
[ "$mam_runtime" = "steamrt3" ] || fail "Pterodactyl runtime must be steamrt3, got '$mam_runtime'"
mam_asset="$(bash -c 'set -Eeuo pipefail; exec 3>&1; source scripts/update/lib.sh; source scripts/update/plugins/multiaddonmanager.sh; NEW_VERSION=1.7.3; plugin_assets')"
[ "$mam_asset" = "MultiAddonManager-v1.7.3-steamrt3.tar.gz" ] || fail "MultiAddonManager selected the wrong release asset: $mam_asset"
mam_paths="$(bash -c 'set -Eeuo pipefail; exec 3>&1; source scripts/update/lib.sh; source scripts/update/plugins/multiaddonmanager.sh; printf "%s\n" "\${PLUGIN_PATHS[@]}"')"
printf '%s' "$mam_paths" | grep -Fq 'multiaddonmanager.so' || fail "MultiAddonManager Linux binary path is missing"
printf '%s' "$mam_paths" | grep -Fq 'addons/metamod/multiaddonmanager.vdf' || fail "MultiAddonManager MetaMod VDF path is missing"
if printf '%s\n' "$mam_paths" | grep -E 'multiaddonmanager.dll|(^|/)(cfg|configs)(/|$)' >/dev/null; then
    fail "MultiAddonManager must not own Windows binaries or cfg/config trees"
fi
grep -Fq 'MultiAddonManager' scripts/update/required-script-addons.txt || fail "MultiAddonManager is not in required updater coverage"
pass "MultiAddonManager SteamRT3 asset selection and Linux destination paths"

# Manifest adapters must self-repair missing runtime files and GG1 must persist its release version.
grep -Fq 'manifest_addon_needs_repair "GG1MapChooser"' scripts/update/plugins/gg1mapchooser.sh || fail "GG1MapChooser same-version repair is missing"
grep -Fq 'manifest_update_version "GG1MapChooser" "$NEW_VERSION"' scripts/update/plugins/gg1mapchooser.sh || fail "GG1MapChooser release version is not persisted"
grep -Fq 'plugin_needs_repair()' scripts/update/plugins/menumanagercs2.sh || fail "MenuManagerCS2 same-version repair is missing"
pass "GG1MapChooser and MenuManagerCS2 dependency repair paths"

# The runner must treat missing adapters on required installed rows as failures.
grep -Fq 'is_required_script_addon "$PLUGIN_NAME"' scripts/update/update.sh || fail "update.sh does not enforce required adapter coverage"
grep -Fq 'installed add-on is missing its required updater adapter' scripts/update/update.sh || fail "update.sh missing-adapter failure message is absent"
pass "missing updater adapters cannot produce a successful run for required installed add-ons"

printf '\nHARDCheck complete: %s required add-ons, %s automated manifest add-ons.\n' "$required_count" "$manifest_count"
