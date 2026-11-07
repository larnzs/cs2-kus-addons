#!/usr/bin/env bash
# Integration test for complete game/ payload publication and container synchronization.
set -Eeuo pipefail

PAYLOAD_BASE="${1:?Usage: test-sync-payload.sh <published-payload-mount> <temporary-root>}"
TEST_ROOT="${2:?Usage: test-sync-payload.sh <published-payload-mount> <temporary-root>}"
SYNC_SCRIPT="$PAYLOAD_BASE/sync-addon-payload-container.sh"
GAME_ROOT="$TEST_ROOT/game"
TEST_SERVER_UUID="${FRAGCITY_TEST_SERVER_UUID:-00000000-0000-4000-8000-000000000001}"

[[ "$TEST_SERVER_UUID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
[[ -f "$PAYLOAD_BASE/CURRENT_COMMIT" && -f "$PAYLOAD_BASE/.sync.lock" && -f "$SYNC_SCRIPT" ]]
commit="$(tr -d '\r\n' < "$PAYLOAD_BASE/CURRENT_COMMIT")"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]]
revision_root="$PAYLOAD_BASE/revisions/$commit"
[[ "$(tr -d '\r\n' < "$revision_root/.source-commit")" == "$commit" ]]
SOURCE_GAME="$revision_root/game"
INVENTORY="$revision_root/.fragcity-game-files-v1.list"
[[ -d "$SOURCE_GAME" && -f "$INVENTORY" && ! -L "$INVENTORY" ]]
expected_count="$(wc -l < "$INVENTORY")"
[[ "$expected_count" =~ ^[1-9][0-9]*$ ]]
[[ "$(find "$SOURCE_GAME" -type f | wc -l)" -eq "$expected_count" ]]
for relative in csgo/subscribed_collection_ids.txt csgo/subscribed_file_ids.txt; do
    [[ -f "$SOURCE_GAME/$relative" && ! -L "$SOURCE_GAME/$relative" ]]
    grep -Fxq "$relative" "$INVENTORY"
done
is_runtime_excluded_path() {
    local path="$1"
    case "$path" in
        csgo/addons/counterstrikesharp/api/*|csgo/addons/counterstrikesharp/bin/*|\
        csgo/addons/counterstrikesharp/dotnet/*|csgo/addons/counterstrikesharp/lang/*|\
        csgo/addons/metamod/bin/*|csgo/addons/metamod/counterstrikesharp.vdf|csgo/addons/metamod/metaplugins.ini)
            return 0 ;;
    esac
    return 1
}
for relative in \
    csgo/addons/counterstrikesharp/api \
    csgo/addons/counterstrikesharp/bin \
    csgo/addons/counterstrikesharp/dotnet \
    csgo/addons/counterstrikesharp/lang \
    csgo/addons/metamod/bin \
    csgo/addons/metamod/counterstrikesharp.vdf \
    csgo/addons/metamod/metaplugins.ini; do
    [[ ! -e "$SOURCE_GAME/$relative" && ! -L "$SOURCE_GAME/$relative" ]] || { echo "FAIL: K4ryuu-managed runtime path was staged: $relative"; exit 1; }
done
while IFS= read -r relative; do
    if is_runtime_excluded_path "$relative"; then
        echo "FAIL: runtime-excluded path is present in deployable inventory: $relative"
        exit 1
    fi
done < "$INVENTORY"

for relative in \
    csgo/addons/counterstrikesharp/plugins/disabled \
    csgo/addons/counterstrikesharp/plugins/BotAI \
    csgo/addons/counterstrikesharp/plugins/disabled/CS2UpdateMonitor \
    csgo/addons/windows; do
    [[ -d "$SOURCE_GAME/$relative" ]] || { echo "FAIL: full game payload is missing $relative"; exit 1; }
done
[[ -n "$(find "$SOURCE_GAME/csgo/addons/counterstrikesharp/plugins/disabled" -type f -print -quit)" ]]

# Every listed config path is managed like every other repository payload file.
# Include each fixture path that is present in this branch's deployable inventory.
config_paths=(
    csgo/cfg/MatchZy/config.cfg
    csgo/addons/counterstrikesharp/configs/plugins/Advertisement/Advertisement.json
    csgo/gamemodes_server.txt
    csgo/mapcycle.txt
    csgo/mapcyclecustom.txt
    csgo/subscribed_collection_ids.txt
    csgo/subscribed_file_ids.txt
)
managed_config_paths=()
for rel in "${config_paths[@]}"; do
    if grep -Fxq "$rel" "$INVENTORY"; then
        [[ -f "$SOURCE_GAME/$rel" && ! -L "$SOURCE_GAME/$rel" ]]
        managed_config_paths+=("$rel")
    fi
done
[[ "${#managed_config_paths[@]}" -gt 0 ]] || { echo "FAIL: expected managed config fixtures were not found in the payload inventory"; exit 1; }

# Runtime filters are exact; disabled plugins and all other addon paths remain deployable.
for path in \
    csgo/addons/counterstrikesharp/api/runtime.dll \
    csgo/addons/counterstrikesharp/bin/CounterStrikeSharp.API.dll \
    csgo/addons/counterstrikesharp/dotnet/dotnet \
    csgo/addons/counterstrikesharp/lang/en.json \
    csgo/addons/metamod/bin/linuxsteamrt64/server.so \
    csgo/addons/metamod/counterstrikesharp.vdf \
    csgo/addons/metamod/metaplugins.ini; do
    is_runtime_excluded_path "$path" || { echo "FAIL: runtime exclude classifier missed $path"; exit 1; }
done
for path in \
    csgo/addons/counterstrikesharp/plugins/disabled/CS2UpdateMonitor/CS2UpdateMonitor.dll \
    csgo/addons/counterstrikesharp/plugins/BotAI/BotAI.dll \
    csgo/addons/counterstrikesharp/source/CounterStrikeSharp.API.cs \
    csgo/cfg/server.cfg; do
    ! is_runtime_excluded_path "$path" || { echo "FAIL: runtime exclude classifier was too broad: $path"; exit 1; }
done

config_sample_rel="csgo/addons/counterstrikesharp/configs/plugins/Advertisement/Advertisement.json"
[[ -f "$SOURCE_GAME/$config_sample_rel" ]] || { echo "FAIL: expected Advertisement config seed is missing"; exit 1; }
[[ -f "$SOURCE_GAME/$config_sample_rel" ]]
grep -Fxq "$config_sample_rel" "$INVENTORY"

# CS2 engine files absent from repository game/ must survive the overlay.
mkdir -p "$GAME_ROOT"
printf 'upstream-engine-file\n' > "$GAME_ROOT/fragcity-test-engine-file.dat"

# Missing identity must fail before any repository files are copied.
set +e
missing_uuid_output="$(env -u P_SERVER_UUID FRAGCITY_PAYLOAD_BASE="$PAYLOAD_BASE" FRAGCITY_GAME_ROOT="$GAME_ROOT" bash "$SYNC_SCRIPT" 2>&1)"
missing_uuid_status=$?
set -e
[[ "$missing_uuid_status" -ne 0 ]]
grep -Fq "P_SERVER_UUID is missing or invalid" <<< "$missing_uuid_output"
[[ ! -d "$GAME_ROOT/csgo" ]]

# Subsequent failures should report the exact assertion/command, not just exit 1.
trap 'status=$?; printf "FAIL: test-sync-payload.sh line %s (status %s): %s\\n" "$LINENO" "$status" "$BASH_COMMAND" >&2; exit "$status"' ERR

# Seed sentinels in every Egg-owned runtime path. The sync must not overwrite or delete them.
for rel in \
    csgo/addons/counterstrikesharp/api/runtime-fixture.txt \
    csgo/addons/counterstrikesharp/bin/runtime-fixture.txt \
    csgo/addons/counterstrikesharp/dotnet/runtime-fixture.txt \
    csgo/addons/counterstrikesharp/lang/runtime-fixture.txt \
    csgo/addons/metamod/bin/runtime-fixture.txt \
    csgo/addons/metamod/counterstrikesharp.vdf \
    csgo/addons/metamod/metaplugins.ini; do
    mkdir -p "$GAME_ROOT/$(dirname -- "$rel")"
    printf 'installed-by-k4ryuu:%s\n' "$rel" > "$GAME_ROOT/$rel"
done

# Simulate the real startup race: the UUID is not in the baseline registry and the
# server state marker arrives only after the container-side sync has begun waiting.
: > "$PAYLOAD_BASE/FRAGCITY_BASELINE_SHA256"
first_log="$TEST_ROOT/first-sync.log"
first_status="$TEST_ROOT/first-sync.status"
(
    set +e
    P_SERVER_UUID="$TEST_SERVER_UUID" FRAGCITY_PAYLOAD_BASE="$PAYLOAD_BASE" FRAGCITY_GAME_ROOT="$GAME_ROOT" bash "$SYNC_SCRIPT" > "$first_log" 2>&1
    rc=$?
    printf '%s\n' "$rc" > "$first_status"
    exit "$rc"
) &
sync_pid=$!

wait_seen=0
for attempt in {1..50}; do
    if grep -Fq "waiting up to 90 seconds for the host provisioner" "$first_log" 2>/dev/null; then
        wait_seen=1
        break
    fi
    sleep 0.1
done
if [[ "$wait_seen" -ne 1 ]]; then
    wait "$sync_pid" || true
    cat "$first_log" 2>/dev/null || true
    echo "FAIL: new UUID did not wait for host Provisioner registration."
    exit 1
fi

printf 'fragcity-config-seed-v1\nserver_uuid=%s\nmode=pending\n' "$TEST_SERVER_UUID" > "$TEST_ROOT/.fragcity-config-seed-v1.state"
chmod 0666 "$TEST_ROOT/.fragcity-config-seed-v1.state"
if ! wait "$sync_pid"; then
    cat "$first_log"
    echo "FAIL: sync did not continue after the host Provisioner registered the new server."
    exit 1
fi
first_output="$(cat "$first_log")"
grep -E 'Target server UUID|Using published payload revision|baseline|first-install config seeding|Sync completed successfully|Files copied:|ERROR' <<< "$first_output"
grep -Fq "Target server UUID: $TEST_SERVER_UUID." <<< "$first_output"
grep -Fq "Using published payload revision $commit." <<< "$first_output"
grep -Fq "Loaded the complete deployable game/ inventory: $expected_count files; only the seven explicit K4ryuu runtime paths are excluded; all repository-managed files are synchronized on every start." <<< "$first_output"
grep -Fq "Server UUID is not in the baseline; waiting up to 90 seconds for the host provisioner to register first-install state." <<< "$first_output"
grep -Fq "Host provisioner registered this new server; first-install config seeding is active." <<< "$first_output"
grep -Fq "Sync completed successfully." <<< "$first_output"
grep -Fq "First full game/ deployment completed and recorded; all repository-managed files, including configs, will continue updating on every start." <<< "$first_output"
grep -Fxq "mode=completed" "$TEST_ROOT/.fragcity-config-seed-v1.state"
grep -Fxq "upstream-engine-file" "$GAME_ROOT/fragcity-test-engine-file.dat"
[[ "$(sha256sum -- "$SOURCE_GAME/$config_sample_rel" | awk '{print $1}')" == "$(sha256sum -- "$GAME_ROOT/$config_sample_rel" | awk '{print $1}')" ]]
for rel in csgo/subscribed_collection_ids.txt csgo/subscribed_file_ids.txt; do
    [[ -f "$GAME_ROOT/$rel" && ! -L "$GAME_ROOT/$rel" ]]
    [[ "$(sha256sum -- "$SOURCE_GAME/$rel" | awk '{print $1}')" == "$(sha256sum -- "$GAME_ROOT/$rel" | awk '{print $1}')" ]]
done
grep -Fq "Verified both subscribed_*_ids.txt seed files on the first install." <<< "$first_output"
for rel in \
    csgo/addons/counterstrikesharp/api/runtime-fixture.txt \
    csgo/addons/counterstrikesharp/bin/runtime-fixture.txt \
    csgo/addons/counterstrikesharp/dotnet/runtime-fixture.txt \
    csgo/addons/counterstrikesharp/lang/runtime-fixture.txt \
    csgo/addons/metamod/bin/runtime-fixture.txt \
    csgo/addons/metamod/counterstrikesharp.vdf \
    csgo/addons/metamod/metaplugins.ini; do
    [[ "$(cat "$GAME_ROOT/$rel")" == "installed-by-k4ryuu:$rel" ]]
done

# The first-install manifest records every deployable payload file and every file is verified.
test "$(grep -vc '^#' "$TEST_ROOT/.fragcity-managed-payload-v1.list")" -eq "$expected_count"
grep -Eq "verified: $expected_count; stale managed files removed: 0\\." <<< "$first_output"
# Spot-check the files from each subtree that older publishers/synchronizers omitted.
for relative in \
    csgo/addons/counterstrikesharp/plugins/disabled \
    csgo/addons/counterstrikesharp/plugins/BotAI \
    csgo/addons/counterstrikesharp/plugins/disabled/CS2UpdateMonitor \
    csgo/addons/windows; do
    sample="$(find "$SOURCE_GAME/$relative" -type f -print -quit)"
    [[ -n "$sample" ]]
    rel="${sample#"$SOURCE_GAME"/}"
    [[ -f "$GAME_ROOT/$rel" && ! -L "$GAME_ROOT/$rel" ]]
    [[ "$(sha256sum -- "$sample" | awk '{print $1}')" == "$(sha256sum -- "$GAME_ROOT/$rel" | awk '{print $1}')" ]]
done

# On every later start, all repository-managed files are refreshed, including configs.
sample="$(find "$SOURCE_GAME/csgo/addons/counterstrikesharp/plugins/disabled" -type f -print -quit)"
[[ -n "$sample" ]]
relative="${sample#"$SOURCE_GAME"/}"
printf 'modified-on-container\n' > "$GAME_ROOT/$relative"
for rel in "${managed_config_paths[@]}"; do
    printf 'customer-customized-config:%s\n' "$rel" > "$GAME_ROOT/$rel"
done

stale_rel="csgo/addons/counterstrikesharp/plugins/LegacyFragCitySyncTest/removed-from-repo.txt"
mkdir -p "$GAME_ROOT/$(dirname -- "$stale_rel")"
printf 'stale-managed-file\n' > "$GAME_ROOT/$stale_rel"
stale_config_rel="csgo/addons/counterstrikesharp/configs/plugins/FragCityLegacySyncTest/removed.json"
mkdir -p "$GAME_ROOT/$(dirname -- "$stale_config_rel")"
printf 'stale-managed-config\n' > "$GAME_ROOT/$stale_config_rel"
printf '%s\n%s\n' "$stale_rel" "$stale_config_rel" >> "$TEST_ROOT/.fragcity-managed-payload-v1.list"
# Simulate an old version's manifest incorrectly claiming Egg-owned runtime files.
printf '%s\n' \
    csgo/addons/counterstrikesharp/api/runtime-fixture.txt \
    csgo/addons/counterstrikesharp/bin/runtime-fixture.txt \
    csgo/addons/counterstrikesharp/dotnet/runtime-fixture.txt \
    csgo/addons/counterstrikesharp/lang/runtime-fixture.txt \
    csgo/addons/metamod/bin/runtime-fixture.txt \
    csgo/addons/metamod/counterstrikesharp.vdf \
    csgo/addons/metamod/metaplugins.ini >> "$TEST_ROOT/.fragcity-managed-payload-v1.list"

second_output="$(P_SERVER_UUID="$TEST_SERVER_UUID" FRAGCITY_PAYLOAD_BASE="$PAYLOAD_BASE" FRAGCITY_GAME_ROOT="$GAME_ROOT" bash "$SYNC_SCRIPT" 2>&1)"
grep -Fq "Sync completed successfully." <<< "$second_output"
grep -Fq "Removing stale previously-managed payload file: $stale_rel" <<< "$second_output"
grep -Fq "Removing stale previously-managed payload file: $stale_config_rel" <<< "$second_output"
[[ ! -e "$GAME_ROOT/$stale_rel" ]]
[[ ! -e "$GAME_ROOT/$stale_config_rel" ]]
for rel in "${managed_config_paths[@]}"; do
    [[ "$(sha256sum -- "$SOURCE_GAME/$rel" | awk '{print $1}')" == "$(sha256sum -- "$GAME_ROOT/$rel" | awk '{print $1}')" ]]
done
for rel in \
    csgo/addons/counterstrikesharp/api/runtime-fixture.txt \
    csgo/addons/counterstrikesharp/bin/runtime-fixture.txt \
    csgo/addons/counterstrikesharp/dotnet/runtime-fixture.txt \
    csgo/addons/counterstrikesharp/lang/runtime-fixture.txt \
    csgo/addons/metamod/bin/runtime-fixture.txt \
    csgo/addons/metamod/counterstrikesharp.vdf \
    csgo/addons/metamod/metaplugins.ini; do
    [[ -f "$GAME_ROOT/$rel" && "$(cat "$GAME_ROOT/$rel")" == "installed-by-k4ryuu:$rel" ]]
done
[[ "$(sha256sum -- "$sample" | awk '{print $1}')" == "$(sha256sum -- "$GAME_ROOT/$relative" | awk '{print $1}')" ]]
second_copied=$((1 + ${#managed_config_paths[@]}))
second_unchanged=$((expected_count - second_copied))
grep -Eq "Files copied: $second_copied; already matching SHA-256: $second_unchanged; verified: $expected_count; stale managed files removed: 2\\." <<< "$second_output"
grep -Fxq "upstream-engine-file" "$GAME_ROOT/fragcity-test-engine-file.dat"

# Legacy volumes without a marker still receive the full current repository payload.
rm -- "$TEST_ROOT/.fragcity-config-seed-v1.state"
printf '%s' "$TEST_SERVER_UUID" | sha256sum | awk '{print $1}' > "$PAYLOAD_BASE/FRAGCITY_BASELINE_SHA256"
printf 'legacy-mismatch\n' > "$GAME_ROOT/$relative"
for rel in "${managed_config_paths[@]}"; do
    printf 'legacy-config-mismatch:%s\n' "$rel" > "$GAME_ROOT/$rel"
done
legacy_output="$(P_SERVER_UUID="$TEST_SERVER_UUID" FRAGCITY_PAYLOAD_BASE="$PAYLOAD_BASE" FRAGCITY_GAME_ROOT="$GAME_ROOT" bash "$SYNC_SCRIPT" 2>&1)"
grep -Fq "Server UUID belongs to the one-time baseline; treating this as an existing/legacy volume and synchronizing all deployable repository files." <<< "$legacy_output"
grep -Fq "Sync completed successfully." <<< "$legacy_output"
grep -Fq "No first-sync marker found; this legacy volume was classified through the baseline and its full repository-managed payload was synchronized." <<< "$legacy_output"
[[ ! -e "$TEST_ROOT/.fragcity-config-seed-v1.state" ]]
for rel in "${managed_config_paths[@]}"; do
    [[ "$(sha256sum -- "$SOURCE_GAME/$rel" | awk '{print $1}')" == "$(sha256sum -- "$GAME_ROOT/$rel" | awk '{print $1}')" ]]
done
[[ "$(sha256sum -- "$sample" | awk '{print $1}')" == "$(sha256sum -- "$GAME_ROOT/$relative" | awk '{print $1}')" ]]
grep -Eq "Files copied: $second_copied; already matching SHA-256: $second_unchanged; verified: $expected_count; stale managed files removed: 0\\." <<< "$legacy_output"

# The required Workshop ID files are refreshed on every sync, whether present or missing.
rm -- "$GAME_ROOT/csgo/subscribed_file_ids.txt"
printf 'legacy-customized-collection-ids\n' > "$GAME_ROOT/csgo/subscribed_collection_ids.txt"
repair_output="$(P_SERVER_UUID="$TEST_SERVER_UUID" FRAGCITY_PAYLOAD_BASE="$PAYLOAD_BASE" FRAGCITY_GAME_ROOT="$GAME_ROOT" bash "$SYNC_SCRIPT" 2>&1)"
grep -Fq "Sync completed successfully." <<< "$repair_output"
for rel in csgo/subscribed_file_ids.txt csgo/subscribed_collection_ids.txt; do
    [[ -f "$GAME_ROOT/csgo/$rel" && ! -L "$GAME_ROOT/csgo/$rel" ]]
    [[ "$(sha256sum -- "$SOURCE_GAME/csgo/$rel" | awk '{print $1}')" == "$(sha256sum -- "$GAME_ROOT/csgo/$rel" | awk '{print $1}')" ]]
done
[[ ! -e "$TEST_ROOT/.fragcity-config-seed-v1.state" ]]
echo "PASS: subscribed-ID files seed on first install and remain untouched when present; absent required files are safely repaired; only exact K4ryuu runtime paths are excluded; disabled plugins and all other non-excluded payloads deploy intact."
