#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
INSTANCE_CONFIG="${INSTANCE_CONFIG:-$SCRIPT_DIR/instance.env}"
if [[ ! -f "$INSTANCE_CONFIG" ]]; then
    echo "ERROR: Missing instance configuration: $INSTANCE_CONFIG" >&2
    echo "Copy instance.example.env to instance.env and edit it first." >&2
    exit 2
fi

# instance.env is administrator-controlled Bash assignment syntax.
set -a
# shellcheck disable=SC1090
source "$INSTANCE_CONFIG"
set +a

if [[ -z "${REPO_ROOT:-}" ]]; then
    REPO_ROOT="$(realpath -m -- "$SCRIPT_DIR/../../..")"
fi
SERVER_DIR="${SERVER_DIR:-/home/steam/cs2}"
STEAMRT_DIR="${STEAMRT_DIR:-/home/steam/steamrt}"
CS2_USER="${CS2_USER:-steam}"
BIND_IP="${BIND_IP:-0.0.0.0}"
IP="${IP:-}"
PORT="${PORT:-27015}"
TICKRATE="${TICKRATE:-128}"
MAXPLAYERS="${MAXPLAYERS:-32}"
LAN="${LAN:-0}"
EXEC="${EXEC:-on_boot.cfg}"
MAPGROUP="${MAPGROUP:-mg_active}"
MAP="${MAP:-de_dust2}"
API_KEY="${API_KEY:-}"
STEAM_ACCOUNT="${STEAM_ACCOUNT:-}"
SERVER_PASSWORD="${SERVER_PASSWORD:-}"
RCON_PASSWORD="${RCON_PASSWORD:-}"
WORKSHOP_COLLECTION="${WORKSHOP_COLLECTION:-}"
CUSTOM_FOLDER="${CUSTOM_FOLDER:-}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"

if [[ "$SERVER_DIR" != /* ]]; then SERVER_DIR="$SCRIPT_DIR/$SERVER_DIR"; fi
if [[ "$STEAMRT_DIR" != /* ]]; then STEAMRT_DIR="$SCRIPT_DIR/$STEAMRT_DIR"; fi
if [[ "$LOG_DIR" != /* ]]; then LOG_DIR="$SCRIPT_DIR/$LOG_DIR"; fi
SERVER_DIR="$(realpath -m -- "$SERVER_DIR")"
STEAMRT_DIR="$(realpath -m -- "$STEAMRT_DIR")"
LOG_DIR="$(realpath -m -- "$LOG_DIR")"
GAME_DIR="$SERVER_DIR/game/csgo"
CS2_BIN="$SERVER_DIR/game/bin/linuxsteamrt64/cs2"
STEAMRT_RUN="$STEAMRT_DIR/run"
PID_FILE="$LOG_DIR/runner.pid"
LOCK_FILE="${CS2_MAINTENANCE_LOCK_FILE:-/tmp/CS2-KUS-Maintenance.lock}"

die() {
    echo "ERROR: $*" >&2
    exit 2
}

if [[ "$(id -un)" != "$CS2_USER" ]]; then
    die "Run this instance as '$CS2_USER' (for example: sudo -u $CS2_USER bash \"$SCRIPT_DIR/watchdog.sh\")."
fi
if [[ ! "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then die "PORT must be between 1 and 65535."; fi
if [[ ! "$MAXPLAYERS" =~ ^[0-9]+$ ]] || (( MAXPLAYERS < 1 || MAXPLAYERS > 64 )); then die "MAXPLAYERS must be between 1 and 64."; fi
if [[ ! "$TICKRATE" =~ ^[0-9]+$ ]] || (( TICKRATE < 1 )); then die "TICKRATE must be a positive integer."; fi
if [[ "$LAN" != "0" && "$LAN" != "1" ]]; then die "LAN must be 0 or 1."; fi

rcon_lower="${RCON_PASSWORD,,}"
if [[ -z "$RCON_PASSWORD" || "$rcon_lower" == "changeme" || "$rcon_lower" == "change_me_to_a_strong_password" ]]; then
    die "Set RCON_PASSWORD to a strong, unique password in instance.env."
fi

[[ -x "$STEAMRT_RUN" ]] || die "Steam Linux Runtime is missing or not executable: $STEAMRT_RUN"
[[ -x "$CS2_BIN" ]] || die "CS2 executable is missing or not executable: $CS2_BIN"
[[ -d "$GAME_DIR/cfg" ]] || die "CS2 cfg directory is missing: $GAME_DIR/cfg"
[[ -f "$GAME_DIR/gameinfo.gi" ]] || die "gameinfo.gi is missing: $GAME_DIR/gameinfo.gi"
[[ -d "$REPO_ROOT/.git" || -f "$REPO_ROOT/.git" ]] || die "REPO_ROOT is not a Git checkout: $REPO_ROOT"

if [[ "${INSTANCE_SUPERVISED:-0}" != "1" ]]; then
    exec 8>"$SCRIPT_DIR/.instance.lock"
    if ! flock -n 8; then die "This instance already has a watchdog/runner. Use stop.sh before starting another."; fi
fi

mkdir -p "$LOG_DIR"
if [[ ! -e "$LOCK_FILE" ]]; then
    (umask 022; : > "$LOCK_FILE") || die "Could not create the shared maintenance lock: $LOCK_FILE"
fi
[[ -r "$LOCK_FILE" ]] || die "Cannot read the shared maintenance lock: $LOCK_FILE"
# Hold a shared lock through the CS2 process lifetime. linux/update.sh takes the exclusive lock.
exec 9<"$LOCK_FILE"
flock -s 9

CUSTOM_DIR=""
if [[ -n "$CUSTOM_FOLDER" ]]; then
    if [[ "$CUSTOM_FOLDER" = /* ]]; then
        CUSTOM_DIR="$(realpath -m -- "$CUSTOM_FOLDER")"
    else
        CUSTOM_DIR="$(realpath -m -- "$SCRIPT_DIR/$CUSTOM_FOLDER")"
    fi
fi

copy_custom_tree() {
    local source_dir="$1"
    local target_dir="$2"
    if [[ -d "$source_dir" ]]; then
        mkdir -p "$target_dir"
        cp -a -- "$source_dir/." "$target_dir/"
    fi
}

if [[ -n "$CUSTOM_DIR" ]]; then
    if [[ -d "$CUSTOM_DIR" ]]; then
        echo "Applying additive custom-file overlay from $CUSTOM_DIR"
        copy_custom_tree "$CUSTOM_DIR/cfg" "$GAME_DIR/cfg"
        copy_custom_tree "$CUSTOM_DIR/addons" "$GAME_DIR/addons"
    else
        echo "WARNING: CUSTOM_FOLDER does not exist: $CUSTOM_DIR; skipping custom-file overlay."
    fi
fi

LAUNCH_PID=""
STOP_SIGNAL=0
cleanup_pidfile() {
    if [[ -f "$PID_FILE" ]] && [[ "$(cat "$PID_FILE" 2>/dev/null || true)" == "$$" ]]; then
        rm -f -- "$PID_FILE"
    fi
}
terminate_tree() {
    local parent_pid="$1" child_pid
    while read -r child_pid; do
        [[ -n "$child_pid" ]] && terminate_tree "$child_pid"
    done < <(pgrep -P "$parent_pid" 2>/dev/null || true)
    kill -TERM "$parent_pid" 2>/dev/null || true
}
handle_signal() {
    STOP_SIGNAL=1
    if [[ -n "$LAUNCH_PID" ]] && kill -0 "$LAUNCH_PID" 2>/dev/null; then
        terminate_tree "$LAUNCH_PID"
        wait "$LAUNCH_PID" 2>/dev/null || true
    fi
    cleanup_pidfile
    exit 143
}
trap 'handle_signal' TERM INT HUP
printf '%s\n' "$$" > "$PID_FILE"

cmd=(
    "$STEAMRT_RUN" ./game/bin/linuxsteamrt64/cs2
    --graphics-provider "" --
    -dedicated -console -debug -usercon -disable_workshop_command_filtering
    -ip "$BIND_IP"
    -port "$PORT"
    -tickrate "$TICKRATE"
    -maxplayers_override "$MAXPLAYERS"
    +sv_visiblemaxplayers "$MAXPLAYERS"
    +sv_region 255
    +game_type 0 +game_mode 0
    +mapgroup "$MAPGROUP"
    +map "$MAP"
    +sv_lan "$LAN"
    +sv_password "$SERVER_PASSWORD"
    +rcon_password "$RCON_PASSWORD"
)
[[ -n "$IP" ]] && cmd+=(+net_public_adr "$IP")
[[ -n "$API_KEY" ]] && cmd+=(-authkey "$API_KEY")
[[ -n "$STEAM_ACCOUNT" ]] && cmd+=(+sv_setsteamaccount "$STEAM_ACCOUNT")
[[ -n "$WORKSHOP_COLLECTION" ]] && cmd+=(+host_workshop_collection "$WORKSHOP_COLLECTION")
[[ -n "$EXEC" ]] && cmd+=(+exec "$EXEC")

echo "Starting CS2 instance: address=${IP:-auto}, bind=$BIND_IP, port=$PORT, map=$MAP, mapgroup=$MAPGROUP, maxplayers=$MAXPLAYERS"
echo "Runtime: $SERVER_DIR"
"${cmd[@]}" &
LAUNCH_PID=$!

if wait "$LAUNCH_PID"; then
    SERVER_EXIT=0
else
    SERVER_EXIT=$?
fi
LAUNCH_PID=""
cleanup_pidfile
if (( STOP_SIGNAL )); then exit 143; fi

echo "WARNING: CS2 exited with code $SERVER_EXIT. The watchdog will restart this instance."
exit 100
