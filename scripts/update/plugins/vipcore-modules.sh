#!/usr/bin/env bash
# Manifest-backed updater for the VIPCore module release archive.
# VIP_Modules.zip contains module plugin directories directly at archive root.
# Only these 45 VIP_* paths are managed; VIPCore and all configuration files are separate.
source scripts/update/manifest-addon.sh

PLUGIN_PATHS=(
    "game/csgo/addons/counterstrikesharp/plugins/VIP_AntiFlash"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_Armor"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_Bhop"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_BuyTeamWeapon"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_CustomDefaultAmmo"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_DamageChange"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_DecoyTeleport"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_DefuseKit"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_Defuser"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_Endurance"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_ExperienceMultiplier"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_FastDefuse"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_FastPlant"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_FastReload"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_Flags"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_Fov"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_Gifts"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_Gravity"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_Grenades"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_Health"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_Healthshot"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_InfiniteAmmo"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_Items"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_Jumps"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_KillScreen"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_Money"
    "game/csgo/addons/counterstrikesharp/plugins/disabled/VIP_NightVip"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_NoFallDamage"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_RainbowModel"
    "game/csgo/addons/counterstrikesharp/plugins/disabled/VIP_Random"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_RegenArmor"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_RegenHealth"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_ResetDeaths"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_Respawn"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_ShowDamage"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_SmokeColor"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_SniperCount"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_Speed"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_Tag"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_TeammatesHeal"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_Test"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_Vampirism"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_VipsOnline"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_WeaponsMenu"
    "game/csgo/addons/counterstrikesharp/plugins/VIP_Zeus"
)
PLUGIN_SOURCE_PATH_OVERRIDES["game/csgo/addons/counterstrikesharp/plugins/disabled/VIP_NightVip"]="VIP_NightVip"
PLUGIN_SOURCE_PATH_OVERRIDES["game/csgo/addons/counterstrikesharp/plugins/disabled/VIP_Random"]="VIP_Random"

plugin_assets() { manifest_addon_assets "VIPCore Modules"; }
plugin_apply() { manifest_plugin_apply "VIPCore Modules"; }
plugin_needs_repair() {
    manifest_addon_needs_repair "VIPCore Modules" || return 1

    local repo release_json repair_regex repair_tag
    repo=$(github_repo_from_url "$PLUGIN_URL")
    repair_regex=$(jq -er '.addons[] | select(.name == "VIPCore Modules") | .repair_track_tag_regex // empty' DEPENDENCIES.json) \
        || die "VIPCore Modules is missing repair_track_tag_regex."
    release_json=$(github_api "repos/$repo/releases?per_page=100") \
        || die "could not list VIPCore releases for full-package repair."
    repair_tag=$(github_latest_matching_release_tag "$release_json" "VIP_Modules.zip" "$repair_regex")
    [ -n "$repair_tag" ] || die "no full VIPCore Modules release matched $repair_regex."
    PLUGIN_REPAIR_VERSION=$(normalize_version "$repair_tag")
    warn "VIPCore module payload is incomplete; repairing from full release $repair_tag."
    return 0
}
