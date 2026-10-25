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

# Simulate the pending first-sync marker created by the host provisioner.
printf 'fragcity-config-seed-v1\nserver_uuid=%s\nmode=pending\n' "$TEST_SERVER_UUID" > "$TEST_ROOT/.fragcity-config-seed-v1.state"
chmod 0666 "$TEST_ROOT/.fragcity-config-seed-v1.state"

first_output="$(P_SERVER_UUID="$TEST_SERVER_UUID" FRAGCITY_PAYLOAD_BASE="$PAYLOAD_BASE" FRAGCITY_GAME_ROOT="$GAME_ROOT" bash "$SYNC_SCRIPT" 2>&1)"
printf '%s\n' "$first_output" | grep -E 'Target server UUID|Using published payload revision|every tracked file|Sync completed successfully|Files copied:|ERROR'
grep -Fq "Target server UUID: $TEST_SERVER_UUID." <<< "$first_output"
grep -Fq "Using published payload revision $commit." <<< "$first_output"
grep -Fq "Synchronizing every tracked file from repository game/ with no exclusions: $expected_count files." <<< "$first_output"
grep -Fq "Sync completed successfully." <<< "$first_output"
grep -Fq "Initial full game/ payload sync completed" <<< "$first_output"
grep -Fxq "mode=completed" "$TEST_ROOT/.fragcity-config-seed-v1.state"
grep -Fxq "upstream-engine-file" "$GAME_ROOT/fragcity-test-engine-file.dat"

# Verify that every payload file was entered into the manifest and hash-verified.
test "$(grep -vc '^#' "$TEST_ROOT/.fragcity-managed-payload-v1.list")" -eq "$expected_count"
grep -Eq "verified: $expected_count; stale managed files removed: 0\." <<< "$first_output"
# Spot-check the files from each subtree that older publishers/synchronizers omitted.
for relative in \
    csgo/addons/counterstrikesharp/plugins/disabled \
    csgo/addons/counterstrikesharp/plugins/BotAI \
    csgo/addons/counterstrikesharp/plugins/CS2UpdateMonitor \
    csgo/addons/windows; do
    sample="$(find "$SOURCE_GAME/$relative" -type f -print -quit)"
    [[ -n "$sample" ]]
    rel="${sample#"$SOURCE_GAME"/}"
    [[ -f "$GAME_ROOT/$rel" && ! -L "$GAME_ROOT/$rel" ]]
    [[ "$(sha256sum -- "$sample" | awk '{print $1}')" == "$(sha256sum -- "$GAME_ROOT/$rel" | awk '{print $1}')" ]]
done

# Change a tracked file and model an old-manifest path removed from Git.
sample="$(find "$SOURCE_GAME" -type f -print -quit)"
relative="${sample#"$SOURCE_GAME"/}"
printf 'modified-on-container\n' > "$GAME_ROOT/$relative"
stale_rel="csgo/addons/counterstrikesharp/plugins/LegacyFragCitySyncTest/removed-from-repo.txt"
mkdir -p "$GAME_ROOT/$(dirname -- "$stale_rel")"
printf 'stale-managed-file\n' > "$GAME_ROOT/$stale_rel"
printf '%s\n' "$stale_rel" >> "$TEST_ROOT/.fragcity-managed-payload-v1.list"

second_output="$(P_SERVER_UUID="$TEST_SERVER_UUID" FRAGCITY_PAYLOAD_BASE="$PAYLOAD_BASE" FRAGCITY_GAME_ROOT="$GAME_ROOT" bash "$SYNC_SCRIPT" 2>&1)"
grep -Fq "Sync completed successfully." <<< "$second_output"
grep -Fq "Removing stale previously-managed payload file: $stale_rel" <<< "$second_output"
[[ ! -e "$GAME_ROOT/$stale_rel" ]]
[[ "$(sha256sum -- "$sample" | awk '{print $1}')" == "$(sha256sum -- "$GAME_ROOT/$relative" | awk '{print $1}')" ]]
grep -Eq "Files copied: 1; already matching SHA-256: $((expected_count - 1)); verified: $expected_count; stale managed files removed: 1\." <<< "$second_output"
grep -Fxq "upstream-engine-file" "$GAME_ROOT/fragcity-test-engine-file.dat"

# Legacy volumes without an install marker still receive the complete payload.
rm -- "$TEST_ROOT/.fragcity-config-seed-v1.state"
printf 'legacy-mismatch\n' > "$GAME_ROOT/$relative"
legacy_output="$(P_SERVER_UUID="$TEST_SERVER_UUID" FRAGCITY_PAYLOAD_BASE="$PAYLOAD_BASE" FRAGCITY_GAME_ROOT="$GAME_ROOT" bash "$SYNC_SCRIPT" 2>&1)"
grep -Fq "No first-install marker found; full game/ payload is still synchronized on every start." <<< "$legacy_output"
grep -Fq "Sync completed successfully." <<< "$legacy_output"
[[ ! -e "$TEST_ROOT/.fragcity-config-seed-v1.state" ]]
[[ "$(sha256sum -- "$sample" | awk '{print $1}')" == "$(sha256sum -- "$GAME_ROOT/$relative" | awk '{print $1}')" ]]

echo "PASS: every tracked file under repository game/ is copied and hash-verified; disabled and formerly excluded trees deploy; untracked CS2 engine files persist; known stale files are removed; new and legacy volumes both receive full payload sync."
