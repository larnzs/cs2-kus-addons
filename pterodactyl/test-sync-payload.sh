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

for relative in \
    csgo/addons/counterstrikesharp/plugins/disabled \
    csgo/addons/counterstrikesharp/plugins/BotAI \
    csgo/addons/counterstrikesharp/plugins/CS2UpdateMonitor \
    csgo/addons/windows; do
    [[ -d "$SOURCE_GAME/$relative" ]] || { echo "FAIL: full game payload is missing $relative"; exit 1; }
done
[[ -n "$(find "$SOURCE_GAME/csgo/addons/counterstrikesharp/plugins/disabled" -type f -print -quit)" ]]

is_test_config_path() {
    local path="$1"
    case "$path" in
        csgo/cfg/*|csgo/addons/counterstrikesharp/configs/*|\
        csgo/gamemodes_server.txt|csgo/mapcycle.txt|csgo/mapcyclecustom.txt|\
        csgo/subscribed_collection_ids.txt|csgo/subscribed_file_ids.txt)
            return 0
            ;;
    esac
    return 1
}

expect_config_path() {
    local expected="$1" path="$2" actual=no
    if is_test_config_path "$path"; then actual=yes; fi
    [[ "$actual" == "$expected" ]] || {
        echo "FAIL: config classifier for $path expected $expected, got $actual"
        exit 1
    }
}
expect_config_path yes csgo/cfg/MatchZy/config.cfg
expect_config_path yes csgo/addons/counterstrikesharp/configs/plugins/Advertisement/Advertisement.json
expect_config_path yes csgo/gamemodes_server.txt
expect_config_path yes csgo/mapcycle.txt
expect_config_path yes csgo/mapcyclecustom.txt
expect_config_path yes csgo/subscribed_collection_ids.txt
expect_config_path yes csgo/subscribed_file_ids.txt
expect_config_path no csgo/addons/otherplugin/configs/other.json
expect_config_path no csgo/addons/otherplugin/config/custom.json
expect_config_path no csgo/addons/otherplugin/extra.cfg
expect_config_path no csgo/addons/counterstrikesharp/plugins/SomePlugin/settings.cfg

config_sample_rel="csgo/addons/counterstrikesharp/configs/plugins/Advertisement/Advertisement.json"
[[ -f "$SOURCE_GAME/$config_sample_rel" ]] || { echo "FAIL: expected Advertisement config seed is missing"; exit 1; }
config_source_count=0
while IFS= read -r rel || [[ -n "$rel" ]]; do
    if is_test_config_path "$rel"; then
        config_source_count=$((config_source_count + 1))
    fi
done < "$INVENTORY"
[[ "$config_source_count" -gt 0 ]]
nonconfig_source_count=$((expected_count - config_source_count))
[[ "$nonconfig_source_count" -gt 0 ]]

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
grep -Fq "Loaded the complete repository game/ inventory: $expected_count files; config seeding is controlled by the per-server first-install state." <<< "$first_output"
grep -Fq "Server UUID is not in the baseline; waiting up to 90 seconds for the host provisioner to register first-install state." <<< "$first_output"
grep -Fq "Host provisioner registered this new server; first-install config seeding is active." <<< "$first_output"
grep -Fq "Sync completed successfully." <<< "$first_output"
grep -Fq "First-install full game/ deployment and config seed completed" <<< "$first_output"
grep -Fxq "mode=completed" "$TEST_ROOT/.fragcity-config-seed-v1.state"
grep -Fxq "upstream-engine-file" "$GAME_ROOT/fragcity-test-engine-file.dat"
[[ "$(sha256sum -- "$SOURCE_GAME/$config_sample_rel" | awk '{print $1}')" == "$(sha256sum -- "$GAME_ROOT/$config_sample_rel" | awk '{print $1}')" ]]

# The first-install manifest records every payload file and every file is verified.
test "$(grep -vc '^#' "$TEST_ROOT/.fragcity-managed-payload-v1.list")" -eq "$expected_count"
grep -Eq "verified: $expected_count; configs preserved: 0; stale managed files removed: 0\\." <<< "$first_output"
# Spot-check the files from each subtree that older publishers/synchronizers omitted.
for relative in \
    csgo/addons/counterstrikesharp/plugins/disabled \
    csgo/addons/counterstrikesharp/plugins/BotAI \
    csgo/addons/counterstrikesharp/plugins/CS2UpdateMonitor \
    csgo/addons/windows; do
    sample="$(find "$SOURCE_GAME/$relative" -type f -print -quit)"
    [[ -n "$sample" ]]
    rel="\${sample#"$SOURCE_GAME"/}"
    [[ -f "$GAME_ROOT/$rel" && ! -L "$GAME_ROOT/$rel" ]]
    [[ "$(sha256sum -- "$sample" | awk '{print $1}')" == "$(sha256sum -- "$GAME_ROOT/$rel" | awk '{print $1}')" ]]
done

# On the next start, non-config payload files are refreshed but customer configs are untouched.
sample=""
relative=""
while IFS= read -r candidate; do
    candidate_rel="\${candidate#"$SOURCE_GAME"/}"
    if ! is_test_config_path "$candidate_rel"; then
        sample="$candidate"
        relative="$candidate_rel"
        break
    fi
done < <(find "$SOURCE_GAME" -type f | LC_ALL=C sort)
[[ -n "$sample" && -n "$relative" ]]
printf 'modified-on-container\n' > "$GAME_ROOT/$relative"
printf 'customer-customized-config\n' > "$GAME_ROOT/$config_sample_rel"

stale_rel="csgo/addons/counterstrikesharp/plugins/LegacyFragCitySyncTest/removed-from-repo.txt"
mkdir -p "$GAME_ROOT/$(dirname -- "$stale_rel")"
printf 'stale-managed-file\n' > "$GAME_ROOT/$stale_rel"
stale_config_rel="csgo/addons/counterstrikesharp/configs/plugins/FragCityLegacySyncTest/removed.json"
mkdir -p "$GAME_ROOT/$(dirname -- "$stale_config_rel")"
printf 'customer-added-after-seed\n' > "$GAME_ROOT/$stale_config_rel"
printf '%s\n%s\n' "$stale_rel" "$stale_config_rel" >> "$TEST_ROOT/.fragcity-managed-payload-v1.list"

second_output="$(P_SERVER_UUID="$TEST_SERVER_UUID" FRAGCITY_PAYLOAD_BASE="$PAYLOAD_BASE" FRAGCITY_GAME_ROOT="$GAME_ROOT" bash "$SYNC_SCRIPT" 2>&1)"
grep -Fq "Sync completed successfully." <<< "$second_output"
grep -Fq "Removing stale previously-managed payload file: $stale_rel" <<< "$second_output"
grep -Fq "Preserving stale customer config file after first install: $stale_config_rel" <<< "$second_output"
[[ ! -e "$GAME_ROOT/$stale_rel" ]]
[[ "$(cat "$GAME_ROOT/$config_sample_rel")" == "customer-customized-config" ]]
[[ "$(cat "$GAME_ROOT/$stale_config_rel")" == "customer-added-after-seed" ]]
[[ "$(sha256sum -- "$sample" | awk '{print $1}')" == "$(sha256sum -- "$GAME_ROOT/$relative" | awk '{print $1}')" ]]
grep -Eq "Files copied: 1; already matching SHA-256: $((nonconfig_source_count - 1)); verified: $nonconfig_source_count; configs preserved: $config_source_count; stale managed files removed: 1\." <<< "$second_output"
grep -Fxq "upstream-engine-file" "$GAME_ROOT/fragcity-test-engine-file.dat"

# Legacy volumes without a seed marker are recognized through the baseline hash registry.
rm -- "$TEST_ROOT/.fragcity-config-seed-v1.state"
printf '%s\n' "$TEST_SERVER_UUID" | sha256sum | awk '{print $1}' > "$PAYLOAD_BASE/FRAGCITY_BASELINE_SHA256"
printf 'legacy-mismatch\n' > "$GAME_ROOT/$relative"
legacy_output="$(P_SERVER_UUID="$TEST_SERVER_UUID" FRAGCITY_PAYLOAD_BASE="$PAYLOAD_BASE" FRAGCITY_GAME_ROOT="$GAME_ROOT" bash "$SYNC_SCRIPT" 2>&1)"
grep -Fq "Server UUID belongs to the one-time baseline; treating this as an existing/legacy volume and preserving customer config paths." <<< "$legacy_output"
grep -Fq "Sync completed successfully." <<< "$legacy_output"
[[ ! -e "$TEST_ROOT/.fragcity-config-seed-v1.state" ]]
[[ "$(cat "$GAME_ROOT/$config_sample_rel")" == "customer-customized-config" ]]
[[ "$(cat "$GAME_ROOT/$stale_config_rel")" == "customer-added-after-seed" ]]
[[ "$(sha256sum -- "$sample" | awk '{print $1}')" == "$(sha256sum -- "$GAME_ROOT/$relative" | awk '{print $1}')" ]]
grep -Eq "configs preserved: $config_source_count; stale managed files removed: 0\\." <<< "$legacy_output"

echo "PASS: first-start sync waits for a new UUID to be registered, then seeds exact config paths; later starts preserve customer configs; baseline legacy servers keep configs and sync non-config payload files; disabled plugins deploy; unknown engine files persist; stale non-config files are removed."
