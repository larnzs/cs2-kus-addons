#!/usr/bin/env bash
# Integration test for the host publisher + in-container SHA-256 sync.
set -Eeuo pipefail
# Trace assertions so the integration job identifies exactly which safety check fails.
set -x

PAYLOAD_BASE="${1:?Usage: test-sync-payload.sh <published-payload-mount> <temporary-root>}"
TEST_ROOT="${2:?Usage: test-sync-payload.sh <published-payload-mount> <temporary-root>}"
SYNC_SCRIPT="$PAYLOAD_BASE/sync-addon-payload-container.sh"
GAME_ROOT="$TEST_ROOT/game/csgo"
TEST_SERVER_UUID="${FRAGCITY_TEST_SERVER_UUID:-00000000-0000-4000-8000-000000000001}"

[[ "$TEST_SERVER_UUID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
[[ -f "$PAYLOAD_BASE/CURRENT_COMMIT" ]]
[[ -f "$PAYLOAD_BASE/.sync.lock" ]]
[[ -f "$SYNC_SCRIPT" ]]
commit="$(tr -d '\r\n' < "$PAYLOAD_BASE/CURRENT_COMMIT")"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]]
revision_root="$PAYLOAD_BASE/revisions/$commit"
[[ "$(tr -d '\r\n' < "$revision_root/.source-commit")" == "$commit" ]]

# A root-only revision directory can pass tests run by the publishing account
# but fail in a non-root Pterodactyl container. Assert access mode bits directly.
bad_directory="$(find "$revision_root" -type d ! -perm -0005 -print -quit)"
[[ -z "$bad_directory" ]] || {
    echo "FAIL: revision directory is not readable/traversable by container users: $bad_directory"
    exit 1
}
bad_file="$(find "$revision_root" -type f ! -perm -0004 -print -quit)"
[[ -z "$bad_file" ]] || {
    echo "FAIL: revision file is not readable by container users: $bad_file"
    exit 1
}
[[ ! -e "$revision_root/game/csgo/addons/counterstrikesharp/plugins/CS2UpdateMonitor" ]]
DISABLED_SOURCE="$revision_root/game/csgo/addons/counterstrikesharp/plugins/disabled"
[[ -d "$DISABLED_SOURCE" ]]
disabled_sample="$(find "$DISABLED_SOURCE" -type f -print -quit)"
[[ -n "$disabled_sample" ]] || { echo "FAIL: payload contains no files under plugins/disabled/"; exit 1; }
disabled_relative="${disabled_sample#"$DISABLED_SOURCE"/}"
disabled_target="$GAME_ROOT/addons/counterstrikesharp/plugins/disabled/$disabled_relative"

CONFIGS_SOURCE="$revision_root/game/csgo/addons/counterstrikesharp/configs"
CFG_SOURCE="$revision_root/game/csgo/cfg"
[[ -d "$CONFIGS_SOURCE" && -n "$(find "$CONFIGS_SOURCE" -type f -print -quit)" ]]
[[ -d "$CFG_SOURCE" && -n "$(find "$CFG_SOURCE" -type f -print -quit)" ]]
configs_sample="$(find "$CONFIGS_SOURCE" -type f -print -quit)"
cfg_sample="$(find "$CFG_SOURCE" -type f -print -quit)"
configs_sample_relative="${configs_sample#"$CONFIGS_SOURCE"/}"
cfg_sample_relative="${cfg_sample#"$CFG_SOURCE"/}"
configs_sample_target="$GAME_ROOT/addons/counterstrikesharp/configs/$configs_sample_relative"
cfg_sample_target="$GAME_ROOT/cfg/$cfg_sample_relative"
CONFIG_FILE_NAMES=(gamemodes_server.txt mapcycle.txt mapcyclecustom.txt subscribed_collection_ids.txt subscribed_file_ids.txt)
for name in "${CONFIG_FILE_NAMES[@]}"; do
    [[ -f "$revision_root/game/csgo/$name" ]] || { echo "FAIL: missing payload file $name"; exit 1; }
done

mkdir -p \
    "$GAME_ROOT/addons/counterstrikesharp/plugins/BotAI" \
    "$GAME_ROOT/addons/counterstrikesharp/plugins/disabled" \
    "$GAME_ROOT/addons/counterstrikesharp/plugins/CS2UpdateMonitor" \
    "$GAME_ROOT/addons/counterstrikesharp/plugins/RemovedFromGitHubPlugin" \
    "$GAME_ROOT/addons/counterstrikesharp/plugins/PlayerSettings" \
    "$GAME_ROOT/addons/counterstrikesharp/plugins/SimpleAdmin/data" \
    "$GAME_ROOT/addons/counterstrikesharp/plugins/CS2-Poor-MapPropAds/maps" \
    "$GAME_ROOT/addons/counterstrikesharp/configs" \
    "$GAME_ROOT/cfg"
# Simulate stock game files that are not present in the repository payload.
printf 'stock-user-keys\n' > "$GAME_ROOT/cfg/user_keys_default.vcfg"
printf 'stock-competitive-mode\n' > "$GAME_ROOT/cfg/gamemode_competitive.cfg"
printf 'stock-machine-convars\n' > "$GAME_ROOT/cfg/machine_convars_default.vcfg"
printf 'protect-botai\n' > "$GAME_ROOT/addons/counterstrikesharp/plugins/BotAI/fragcity-test-keep.txt"
printf 'stale-disabled-marker\n' > "$GAME_ROOT/addons/counterstrikesharp/plugins/disabled/fragcity-test-stale.txt"
printf 'protect-update-monitor\n' > "$GAME_ROOT/addons/counterstrikesharp/plugins/CS2UpdateMonitor/fragcity-test-keep.txt"
# Model a broken plugin left behind on a legacy server after its entire folder
# was removed from the current GitHub branch. This server has no old manifest.
printf 'obsolete-broken-plugin-dll\n' > "$GAME_ROOT/addons/counterstrikesharp/plugins/RemovedFromGitHubPlugin/RemovedFromGitHubPlugin.dll"
printf 'keep-for-recovery\n' > "$GAME_ROOT/addons/counterstrikesharp/plugins/RemovedFromGitHubPlugin/plugin-data.json"
printf 'persistent-player-settings-db\n' > "$GAME_ROOT/addons/counterstrikesharp/plugins/PlayerSettings/settings.sqlite"
printf 'persistent-admin-bans-db\n' > "$GAME_ROOT/addons/counterstrikesharp/plugins/SimpleAdmin/bans.db"
printf 'persistent-simpleadmin-data\n' > "$GAME_ROOT/addons/counterstrikesharp/plugins/SimpleAdmin/data/groups.json"
printf '{"customer":"map data must persist"}\n' > "$GAME_ROOT/addons/counterstrikesharp/plugins/CS2-Poor-MapPropAds/maps/de_dust2.json"
printf 'stale-config-marker\n' > "$GAME_ROOT/addons/counterstrikesharp/configs/fragcity-test-stale.json"
printf 'stale-cfg-marker\n' > "$GAME_ROOT/cfg/fragcity-test-stale.cfg"
# Simulate the marker created by the provisioner for a newly created server.
printf 'fragcity-config-seed-v1\nserver_uuid=%s\nmode=pending\n' "$TEST_SERVER_UUID" > "$TEST_ROOT/.fragcity-config-seed-v1.state"
chmod 0666 "$TEST_ROOT/.fragcity-config-seed-v1.state"

assert_tree_mirror() {
    local source_dir="$1" target_dir="$2" label="$3"
    local source_file relative_file target_file source_hash target_hash source_count target_count
    [[ -d "$source_dir" && -d "$target_dir" ]] || {
        echo "FAIL: $label source or target directory missing."
        return 1
    }
    [[ -z "$(find "$source_dir" -type l -print -quit)" ]] || {
        echo "FAIL: symlink exists in $label source tree."
        return 1
    }
    [[ -z "$(find "$target_dir" -type l -print -quit)" ]] || {
        echo "FAIL: symlink exists in $label target tree."
        return 1
    }
    source_count="$(find "$source_dir" -type f | wc -l)"
    target_count="$(find "$target_dir" -type f | wc -l)"
    [[ "$source_count" -eq "$target_count" ]] || {
        echo "FAIL: $label file count mismatch: source=$source_count target=$target_count"
        return 1
    }
    while IFS= read -r -d '' source_file; do
        relative_file="${source_file#"$source_dir"/}"
        target_file="$target_dir/$relative_file"
        [[ -f "$target_file" && ! -L "$target_file" ]] || {
            echo "FAIL: $label file missing or unsafe: $relative_file"
            return 1
        }
        source_hash="$(sha256sum -- "$source_file" | awk '{print $1}')"
        target_hash="$(sha256sum -- "$target_file" | awk '{print $1}')"
        [[ "$source_hash" == "$target_hash" ]] || {
            echo "FAIL: $label SHA-256 mismatch: $relative_file"
            return 1
        }
    done < <(find "$source_dir" -type f -print0)
    echo "PASS: $label exactly mirrors $source_count file(s)."
}

assert_payload_files_present() {
    local source_dir="$1" target_dir="$2" label="$3"
    local source_file relative_file target_file source_hash target_hash source_count=0
    [[ -d "$source_dir" && -d "$target_dir" && ! -L "$target_dir" ]] || {
        echo "FAIL: $label source or target directory missing or unsafe."
        return 1
    }
    [[ -z "$(find "$source_dir" -type l -print -quit)" ]] || {
        echo "FAIL: symlink exists in $label source tree."
        return 1
    }
    while IFS= read -r -d '' source_file; do
        relative_file="${source_file#"$source_dir"/}"
        target_file="$target_dir/$relative_file"
        [[ -f "$target_file" && ! -L "$target_file" ]] || {
            echo "FAIL: $label payload file missing or unsafe: $relative_file"
            return 1
        }
        source_hash="$(sha256sum -- "$source_file" | awk '{print $1}')"
        target_hash="$(sha256sum -- "$target_file" | awk '{print $1}')"
        [[ "$source_hash" == "$target_hash" ]] || {
            echo "FAIL: $label SHA-256 mismatch: $relative_file"
            return 1
        }
        source_count=$((source_count + 1))
    done < <(find "$source_dir" -type f -print0)
    [[ "$source_count" -gt 0 ]] || {
        echo "FAIL: $label contains no payload files."
        return 1
    }
    echo "PASS: all $source_count $label payload file(s) match; unrelated target files are preserved."
}

assert_top_level_config_files() {
    local name source_file target_file source_hash target_hash
    for name in "${CONFIG_FILE_NAMES[@]}"; do
        source_file="$revision_root/game/csgo/$name"
        target_file="$GAME_ROOT/$name"
        [[ -f "$target_file" && ! -L "$target_file" ]] || {
            echo "FAIL: top-level CS2 config file missing or unsafe: $name"
            return 1
        }
        source_hash="$(sha256sum -- "$source_file" | awk '{print $1}')"
        target_hash="$(sha256sum -- "$target_file" | awk '{print $1}')"
        [[ "$source_hash" == "$target_hash" ]] || {
            echo "FAIL: top-level CS2 config file SHA-256 mismatch: $name"
            return 1
        }
    done
    echo "PASS: all five top-level CS2 config/list files match."
}

# A missing server UUID must fail closed before writing into any game directory.
set +e
missing_uuid_output="$(env -u P_SERVER_UUID FRAGCITY_PAYLOAD_BASE="$PAYLOAD_BASE" FRAGCITY_GAME_ROOT="$GAME_ROOT" bash "$SYNC_SCRIPT" 2>&1)"
missing_uuid_status=$?
set -e
[[ "$missing_uuid_status" -ne 0 ]]
grep -Fq "P_SERVER_UUID is missing or invalid" <<< "$missing_uuid_output"
[[ ! -d "$GAME_ROOT/addons/counterstrikesharp/source" ]]

first_output="$(P_SERVER_UUID="$TEST_SERVER_UUID" FRAGCITY_PAYLOAD_BASE="$PAYLOAD_BASE" FRAGCITY_GAME_ROOT="$GAME_ROOT" bash "$SYNC_SCRIPT" 2>&1)"
printf '%s\n' "$first_output" | grep -E 'Target server UUID|Using published payload revision|Sync completed successfully|Files copied:|BotAI/|ERROR'
grep -Fq "Target server UUID: $TEST_SERVER_UUID." <<< "$first_output"
grep -Fq "Using published payload revision $commit." <<< "$first_output"
grep -Fq "Sync completed successfully." <<< "$first_output"
grep -Fq "BotAI/ and CS2UpdateMonitor/ were not copied from this payload; inventory reconciliation quarantines either directory if its GitHub source folder is removed." <<< "$first_output"
grep -Fq "plugins/disabled/ was synced from the published payload and remains under disabled/." <<< "$first_output"
grep -Fq "First-install config seed completed successfully" <<< "$first_output"
[[ -f "$TEST_ROOT/.fragcity-config-seed-v1.state" && ! -L "$TEST_ROOT/.fragcity-config-seed-v1.state" ]]
grep -Fxq "mode=completed" "$TEST_ROOT/.fragcity-config-seed-v1.state"
[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/plugins/CS2UpdateMonitor/fragcity-test-keep.txt")" == "protect-update-monitor" ]]
[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/plugins/disabled/fragcity-test-stale.txt")" == "stale-disabled-marker" ]]
[[ -e "$disabled_target" && ! -L "$disabled_target" ]]
[[ "$(sha256sum -- "$disabled_sample" | awk '{print $1}')" == "$(sha256sum -- "$disabled_target" | awk '{print $1}')" ]]
[[ ! -e "$GAME_ROOT/addons/counterstrikesharp/configs/fragcity-test-stale.json" ]]
[[ -e "$GAME_ROOT/cfg/fragcity-test-stale.cfg" ]]
[[ -f "$TEST_ROOT/.fragcity-managed-payload-v1.list" ]]
[[ -f "$revision_root/.fragcity-plugin-inventory-v1.list" ]]
grep -Fxq 'disabled' "$revision_root/.fragcity-plugin-inventory-v1.list"
grep -Fxq 'BotAI' "$revision_root/.fragcity-plugin-inventory-v1.list"
grep -Fxq 'CS2UpdateMonitor' "$revision_root/.fragcity-plugin-inventory-v1.list"
[[ ! -d "$revision_root/game/csgo/addons/counterstrikesharp/plugins/BotAI" ]]
[[ ! -d "$revision_root/game/csgo/addons/counterstrikesharp/plugins/CS2UpdateMonitor" ]]
# Directory reconciliation must work on the first sync without a prior manifest.
[[ ! -e "$GAME_ROOT/addons/counterstrikesharp/plugins/RemovedFromGitHubPlugin" ]]
retired_plugin="$(find "$TEST_ROOT/.fragcity-retired-plugins" -mindepth 2 -maxdepth 2 -type d -name 'RemovedFromGitHubPlugin' -print -quit)"
[[ -n "$retired_plugin" ]]
[[ "$(cat "$retired_plugin/RemovedFromGitHubPlugin.dll")" == "obsolete-broken-plugin-dll" ]]
[[ "$(cat "$retired_plugin/plugin-data.json")" == "keep-for-recovery" ]]
grep -Fq "Quarantined stale plugin directory missing from current GitHub inventory: RemovedFromGitHubPlugin" <<< "$first_output"
! grep -Fq 'PlayerSettings/settings.sqlite' "$TEST_ROOT/.fragcity-managed-payload-v1.list"
! grep -Fq 'SimpleAdmin/bans.db' "$TEST_ROOT/.fragcity-managed-payload-v1.list"
! grep -Fq 'SimpleAdmin/data/groups.json' "$TEST_ROOT/.fragcity-managed-payload-v1.list"
! grep -Fq 'CS2-Poor-MapPropAds/maps/de_dust2.json' "$TEST_ROOT/.fragcity-managed-payload-v1.list"
[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/plugins/PlayerSettings/settings.sqlite")" == "persistent-player-settings-db" ]]
[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/plugins/SimpleAdmin/bans.db")" == "persistent-admin-bans-db" ]]
[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/plugins/SimpleAdmin/data/groups.json")" == "persistent-simpleadmin-data" ]]
[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/plugins/CS2-Poor-MapPropAds/maps/de_dust2.json")" == '{"customer":"map data must persist"}' ]]
assert_tree_mirror "$CONFIGS_SOURCE" "$GAME_ROOT/addons/counterstrikesharp/configs" "CounterStrikeSharp configs"
assert_payload_files_present "$CFG_SOURCE" "$GAME_ROOT/cfg" "game/csgo/cfg"
for stock_file in user_keys_default.vcfg gamemode_competitive.cfg machine_convars_default.vcfg; do
    [[ -f "$GAME_ROOT/cfg/$stock_file" && ! -L "$GAME_ROOT/cfg/$stock_file" ]] || {
        echo "FAIL: game-owned cfg file was removed or replaced unsafely: $stock_file"
        exit 1
    }
done
assert_top_level_config_files

# Every allowlisted payload must be installed; no Git metadata is staged.
[[ -d "$GAME_ROOT/addons/counterstrikesharp/source" ]]
[[ -d "$GAME_ROOT/addons/counterstrikesharp/shared" ]]
[[ -d "$GAME_ROOT/addons/counterstrikesharp/gamedata" ]]
[[ -f "$GAME_ROOT/addons/metamod/serverlistplayersfix_mm.vdf" ]]
for name in MovementUnlocker serverlistplayersfix_mm surf scripts multiaddonmanager; do
    [[ -d "$GAME_ROOT/addons/$name" ]]
done

# User-owned plugin directories remain untouched; config files are seeded once and then preserved.
[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/plugins/BotAI/fragcity-test-keep.txt")" == "protect-botai" ]]
[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/plugins/disabled/fragcity-test-stale.txt")" == "stale-disabled-marker" ]]
[[ -f "$disabled_target" ]]
[[ "$(sha256sum -- "$disabled_sample" | awk '{print $1}')" == "$(sha256sum -- "$disabled_target" | awk '{print $1}')" ]]
[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/plugins/CS2UpdateMonitor/fragcity-test-keep.txt")" == "protect-update-monitor" ]]
[[ ! -e "$GAME_ROOT/addons/counterstrikesharp/configs/fragcity-test-stale.json" ]]
[[ -e "$GAME_ROOT/cfg/fragcity-test-stale.cfg" ]]

# Change config files and add a new file after first install: later starts must keep these edits.
printf 'customer-customized-config\n' > "$configs_sample_target"
printf 'customer-customized-cfg\n' > "$cfg_sample_target"
printf 'customer-added-after-seed\n' > "$GAME_ROOT/addons/counterstrikesharp/configs/fragcity-test-stale.json"
for name in "${CONFIG_FILE_NAMES[@]}"; do
    printf 'customer-customized-%s\n' "$name" > "$GAME_ROOT/$name"
done

# A stale plugin file should still be removed after all desired addon copies verify.
printf 'stale\n' > "$GAME_ROOT/addons/counterstrikesharp/source/fragcity-sync-test-stale.tmp"
# These two entries simulate files owned by the previous payload that are now stale.
printf '%s\n' 'addons/counterstrikesharp/source/fragcity-sync-test-stale.tmp' 'addons/counterstrikesharp/plugins/disabled/fragcity-test-stale.txt' >> "$TEST_ROOT/.fragcity-managed-payload-v1.list"
set +e
second_output="$(P_SERVER_UUID="$TEST_SERVER_UUID" FRAGCITY_PAYLOAD_BASE="$PAYLOAD_BASE" FRAGCITY_GAME_ROOT="$GAME_ROOT" bash "$SYNC_SCRIPT" 2>&1)"
second_status=$?
set -e
printf '%s\n' "$second_output" | grep -E 'Target server UUID|Using published payload revision|Sync completed successfully|Files copied:|BotAI/|ERROR' || true
if [[ "$second_status" -ne 0 ]]; then
    echo "FAIL: second container sync exited with status $second_status."
    printf '%s\n' "$second_output" | tail -n 80
    exit 1
fi
[[ ! -e "$GAME_ROOT/addons/counterstrikesharp/source/fragcity-sync-test-stale.tmp" ]]
grep -Eq 'Files copied: 0; already matching SHA-256: [0-9]+; verified: [0-9]+; stale files removed: 2\.' <<< "$second_output"

[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/plugins/BotAI/fragcity-test-keep.txt")" == "protect-botai" ]]
[[ ! -e "$GAME_ROOT/addons/counterstrikesharp/plugins/disabled/fragcity-test-stale.txt" ]]
[[ -e "$disabled_target" && ! -L "$disabled_target" ]]
[[ "$(sha256sum -- "$disabled_sample" | awk '{print $1}')" == "$(sha256sum -- "$disabled_target" | awk '{print $1}')" ]]
[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/plugins/CS2UpdateMonitor/fragcity-test-keep.txt")" == "protect-update-monitor" ]]
[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/plugins/PlayerSettings/settings.sqlite")" == "persistent-player-settings-db" ]]
[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/plugins/SimpleAdmin/bans.db")" == "persistent-admin-bans-db" ]]
[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/plugins/SimpleAdmin/data/groups.json")" == "persistent-simpleadmin-data" ]]
[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/plugins/CS2-Poor-MapPropAds/maps/de_dust2.json")" == '{"customer":"map data must persist"}' ]]
[[ "$(cat "$configs_sample_target")" == "customer-customized-config" ]]
[[ "$(cat "$cfg_sample_target")" == "customer-customized-cfg" ]]
[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/configs/fragcity-test-stale.json")" == "customer-added-after-seed" ]]
[[ -e "$GAME_ROOT/cfg/fragcity-test-stale.cfg" ]]
for name in "${CONFIG_FILE_NAMES[@]}"; do
    [[ "$(cat "$GAME_ROOT/$name")" == "customer-customized-$name" ]] || {
        echo "FAIL: config/list file was overwritten after first install: $name"
        exit 1
    }
done
for stock_file in user_keys_default.vcfg gamemode_competitive.cfg machine_convars_default.vcfg; do
    [[ -f "$GAME_ROOT/cfg/$stock_file" && ! -L "$GAME_ROOT/cfg/$stock_file" ]] || {
        echo "FAIL: game-owned cfg file disappeared after the second sync: $stock_file"
        exit 1
    }
done
grep -Fq "First-install config seed not active" <<< "$second_output"
grep -Fxq "mode=completed" "$TEST_ROOT/.fragcity-config-seed-v1.state"

# Simulate an existing server from before this feature: no seed state means
# preserve every established config while still syncing the addon/plugin payload.
rm -- "$TEST_ROOT/.fragcity-config-seed-v1.state"
legacy_output="$(P_SERVER_UUID="$TEST_SERVER_UUID" FRAGCITY_PAYLOAD_BASE="$PAYLOAD_BASE" FRAGCITY_GAME_ROOT="$GAME_ROOT" bash "$SYNC_SCRIPT" 2>&1)"
grep -Fq "No first-install marker found; treating this as an existing server" <<< "$legacy_output"
[[ ! -e "$TEST_ROOT/.fragcity-config-seed-v1.state" ]]
[[ "$(cat "$configs_sample_target")" == "customer-customized-config" ]]
[[ "$(cat "$cfg_sample_target")" == "customer-customized-cfg" ]]
[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/configs/fragcity-test-stale.json")" == "customer-added-after-seed" ]]
for name in "${CONFIG_FILE_NAMES[@]}"; do
    [[ "$(cat "$GAME_ROOT/$name")" == "customer-customized-$name" ]] || {
        echo "FAIL: legacy server config was overwritten: $name"
        exit 1
    }
done

# Config symlinks are ignored after the initial seed/for legacy volumes; plugin payload synchronization must continue.

cfg_nested_target="$GAME_ROOT/cfg/MatchZy"
cfg_nested_backup="$TEST_ROOT/fragcity-test-MatchZy-backup"
if [[ -d "$CFG_SOURCE/MatchZy" && -f "$CFG_SOURCE/MatchZy/config.cfg" ]]; then
    mv "$cfg_nested_target" "$cfg_nested_backup"
    ln -s "$cfg_nested_backup" "$cfg_nested_target"
    parent_guard_output="$(P_SERVER_UUID="$TEST_SERVER_UUID" FRAGCITY_PAYLOAD_BASE="$PAYLOAD_BASE" FRAGCITY_GAME_ROOT="$GAME_ROOT" bash "$SYNC_SCRIPT" 2>&1)"
    [[ -L "$cfg_nested_target" ]]
    [[ -d "$cfg_nested_backup" ]]
    rm "$cfg_nested_target"
    mv "$cfg_nested_backup" "$cfg_nested_target"
fi

cfg_guard_sentinel="$TEST_ROOT/fragcity-protected-target.txt"
printf 'do-not-overwrite-through-symlink\n' > "$cfg_guard_sentinel"
rm -f -- "$cfg_sample_target"
ln -s "$cfg_guard_sentinel" "$cfg_sample_target"
file_guard_output="$(P_SERVER_UUID="$TEST_SERVER_UUID" FRAGCITY_PAYLOAD_BASE="$PAYLOAD_BASE" FRAGCITY_GAME_ROOT="$GAME_ROOT" bash "$SYNC_SCRIPT" 2>&1)"
[[ -L "$cfg_sample_target" ]]
[[ "$(cat "$cfg_guard_sentinel")" == "do-not-overwrite-through-symlink" ]]
grep -Fq "First-install config seed not active" <<< "$file_guard_output"

echo "PASS: addon files update idempotently on each start, first-install cfg/configs/txt files seed only once, customer edits and new config files persist, stock files remain, and BotAI/CS2UpdateMonitor stay protected."
