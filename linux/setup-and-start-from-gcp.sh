#!/usr/bin/env bash

set -o pipefail

# Install
# As root (sudo su)
# Run this local helper from the cloned private repository: sudo bash ./linux/setup-and-start-from-gcp.sh

# Check bare minimum dependencies
# Check if curl is installed
if ! command -v curl &> /dev/null
then
    echo "Warning: curl is not installed. Please install it to continue. sudo apt update && sudo apt install curl"
    exit 1
fi

METADATA_URL="${METADATA_URL:-http://metadata.google.internal/computeMetadata/v1/instance/attributes}"

get_metadata () {
    if [ -z "$1" ]
    then
        local result=""
    else
        local result=$(curl -s "$METADATA_URL/$1?alt=text" -H "Metadata-Flavor: Google")
		if [[ $result == *"<!DOCTYPE html>"* ]]; then
			result=""
		fi
    fi

    echo $result
}

# Get meta data from GCP and set environment variables
META_RCON_PASSWORD=$(get_metadata RCON_PASSWORD)
META_API_KEY=$(get_metadata API_KEY)
META_MOD_BRANCH=$(get_metadata MOD_BRANCH)
META_PORT=$(get_metadata PORT)
META_TICKRATE=$(get_metadata TICKRATE)
META_MAXPLAYERS=$(get_metadata MAXPLAYERS)
META_LAN=$(get_metadata LAN)
META_EXEC=$(get_metadata EXEC)
export RCON_PASSWORD="${RCON_PASSWORD:-${META_RCON_PASSWORD:-}}"
export API_KEY="${API_KEY:-${META_API_KEY:-}}"
export STEAM_ACCOUNT="${STEAM_ACCOUNT:-$(get_metadata STEAM_ACCOUNT)}"
export MOD_BRANCH="${MOD_BRANCH:-${META_MOD_BRANCH:-integration/kus-monorepo}}"
export SERVER_PASSWORD="${SERVER_PASSWORD:-$(get_metadata SERVER_PASSWORD)}"
export PORT="${PORT:-${META_PORT:-27015}}"
export TICKRATE="${TICKRATE:-${META_TICKRATE:-128}}"
export MAXPLAYERS="${MAXPLAYERS:-${META_MAXPLAYERS:-32}}"
export LAN="${LAN:-${META_LAN:-0}}"
export EXEC="${EXEC:-${META_EXEC:-on_boot.cfg}}"
export DUCK_DOMAIN="${DUCK_DOMAIN:-$(get_metadata DUCK_DOMAIN)}"
export DUCK_TOKEN="${DUCK_TOKEN:-$(get_metadata DUCK_TOKEN)}"
export CUSTOM_FOLDER="${CUSTOM_FOLDER:-$(get_metadata CUSTOM_FOLDER)}"

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ ! -f "$ROOT_DIR/linux/setup-and-start.sh" || ! -d "$ROOT_DIR/game/csgo/addons" ]]; then
    echo "ERROR: The private repository payload was not found. Run this script from the cloned repository."
    exit 1
fi

# Run the install script included in this checkout; never overwrite it with the public KUS installer.
bash "$ROOT_DIR/linux/setup-and-start.sh" |& tee /install.log
