#!/usr/bin/env bash
# Integration test for the host publisher + in-container SHA-256 sync.
set -Eeuo pipefail

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
[[ "$(tr -d '\r\n' < "$PAYLOAD_BASE/revisions/$commit/.source-commit")" == "$commit" ]]

mkdir -p \
    "$GAME_ROOT/addons/counterstrikesharp/plugins/BotAI" \
    "$GAME_ROOT/addons/counterstrikesharp/plugins/disabled" \
    "$GAME_ROOT/addons/counterstrikesharp/configs" \
    "$GAME_ROOT/cfg"
printf 'protect-botai\n' > "$GAME_ROOT/addons/counterstrikesharp/plugins/BotAI/fragcity-test-keep.txt"
printf 'protect-disabled\n' > "$GAME_ROOT/addons/counterstrikesharp/plugins/disabled/fragcity-test-keep.txt"
printf 'protect-css-config\n' > "$GAME_ROOT/addons/counterstrikesharp/configs/fragcity-test-keep.json"
printf 'protect-game-config\n' > "$GAME_ROOT/cfg/fragcity-test-keep.cfg"

first_output="$(P_SERVER_UUID="$TEST_SERVER_UUID" FRAGCITY_PAYLOAD_BASE="$PAYLOAD_BASE" FRAGCITY_GAME_ROOT="$GAME_ROOT" bash "$SYNC_SCRIPT" 2>&1)"
printf '%s\n' "$first_output"
grep -Fq "Target server UUID: $TEST_SERVER_UUID." <<< "$first_output"
grep -Fq "Using published payload revision $commit." <<< "$first_output"
grep -Fq "Sync completed successfully." <<< "$first_output"
grep -Fq "BotAI/ and disabled/ were not copied or pruned." <<< "$first_output"

# Every allowlisted payload must be installed; no private repo metadata is staged.
[[ -d "$GAME_ROOT/addons/counterstrikesharp/source" ]]
[[ -d "$GAME_ROOT/addons/counterstrikesharp/shared" ]]
[[ -d "$GAME_ROOT/addons/counterstrikesharp/gamedata" ]]
[[ -f "$GAME_ROOT/addons/metamod/serverlistplayersfix_mm.vdf" ]]
for name in MovementUnlocker serverlistplayersfix_mm surf scripts multiaddonmanager; do
    [[ -d "$GAME_ROOT/addons/$name" ]]
done

# User-owned paths and manually managed configs must survive first sync and re-sync.
[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/plugins/BotAI/fragcity-test-keep.txt")" == "protect-botai" ]]
[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/plugins/disabled/fragcity-test-keep.txt")" == "protect-disabled" ]]
[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/configs/fragcity-test-keep.json")" == "protect-css-config" ]]
[[ "$(cat "$GAME_ROOT/cfg/fragcity-test-keep.cfg")" == "protect-game-config" ]]

# A stale file is removed from a managed tree only after verified payload copies.
printf 'stale\n' > "$GAME_ROOT/addons/counterstrikesharp/source/fragcity-sync-test-stale.tmp"
second_output="$(P_SERVER_UUID="$TEST_SERVER_UUID" FRAGCITY_PAYLOAD_BASE="$PAYLOAD_BASE" FRAGCITY_GAME_ROOT="$GAME_ROOT" bash "$SYNC_SCRIPT" 2>&1)"
printf '%s\n' "$second_output"
[[ ! -e "$GAME_ROOT/addons/counterstrikesharp/source/fragcity-sync-test-stale.tmp" ]]
grep -Eq 'Files copied: 0; already matching SHA-256: [0-9]+; verified: [0-9]+; stale files removed: 1\.' <<< "$second_output"

[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/plugins/BotAI/fragcity-test-keep.txt")" == "protect-botai" ]]
[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/plugins/disabled/fragcity-test-keep.txt")" == "protect-disabled" ]]
[[ "$(cat "$GAME_ROOT/addons/counterstrikesharp/configs/fragcity-test-keep.json")" == "protect-css-config" ]]
[[ "$(cat "$GAME_ROOT/cfg/fragcity-test-keep.cfg")" == "protect-game-config" ]]

echo "PASS: staging metadata, hash sync, idempotency, safe stale cleanup, and exclusions."
