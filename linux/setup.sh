#!/usr/bin/env bash

# As root (sudo su)
# Run as root from a clone of this private repository.
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ ! -e "$ROOT_DIR/.git" ]]; then
    echo "ERROR: Run setup.sh from a clone of the private cs2-kus-addons repository." >&2
    exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Run setup.sh as root. Use linux/install.sh for the unified install/update workflow." >&2
    exit 1
fi
if pgrep -x cs2 >/dev/null 2>&1; then
    echo "ERROR: A CS2 server process is active. Stop all instances before running setup.sh." >&2
    exit 1
fi


# Server-specific settings belong in each private linux/instances/<name>/instance.env.

# Function to safely enable unprivileged user namespaces.
# Steam's runtime sandboxes the game with bwrap (pressure-vessel), which needs
# unprivileged user namespaces. Different distro/kernel versions gate these behind
# different sysctls, so we probe for each knob and only touch the ones that exist:
#   - kernel.apparmor_restrict_unprivileged_userns : Ubuntu 24.04+ AppArmor lockdown.
#       Left at its default of 1 it causes "bwrap: setting up uid map: Permission denied".
#   - kernel.unprivileged_userns_clone             : older Ubuntu (<= 23.10) / Debian.
# Settings are also written to /etc/sysctl.d so they survive reboots (GCP VMs reset
# runtime sysctl changes on restart).
enable_unprivileged_namespaces() {
    local persist_file="/etc/sysctl.d/99-cs2-userns.conf"
    local persist=""

    # Ubuntu 24.04+ : AppArmor blocks unprivileged userns even when otherwise allowed.
    if sysctl kernel.apparmor_restrict_unprivileged_userns >/dev/null 2>&1; then
        if [ "$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null)" != "0" ]; then
            echo "Disabling AppArmor restriction on unprivileged user namespaces (Ubuntu 24.04+)..."
            sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 \
                && echo "Successfully disabled AppArmor userns restriction" \
                || echo "Warning: Failed to disable AppArmor userns restriction"
        else
            echo "AppArmor userns restriction already disabled"
        fi
        persist+="kernel.apparmor_restrict_unprivileged_userns=0"$'\n'
    fi

    # Older Ubuntu / Debian : userns gated behind unprivileged_userns_clone.
    if sysctl kernel.unprivileged_userns_clone >/dev/null 2>&1; then
        if [ "$(sysctl -n kernel.unprivileged_userns_clone 2>/dev/null)" != "1" ]; then
            echo "Enabling unprivileged user namespaces..."
            sudo sysctl -w kernel.unprivileged_userns_clone=1 \
                && echo "Successfully enabled unprivileged user namespaces" \
                || echo "Warning: Failed to enable unprivileged user namespaces"
        else
            echo "Unprivileged user namespaces already enabled"
        fi
        persist+="kernel.unprivileged_userns_clone=1"$'\n'
    fi

    if [ -z "$persist" ]; then
        echo "Info: no unprivileged user namespace sysctls available on this system"
        return 0
    fi

    # Persist so the fix survives reboots.
    { echo "# Managed by cs2-modded-server: allow unprivileged user namespaces for Steam runtime (bwrap)"; \
      printf '%s' "$persist"; } | sudo tee "$persist_file" >/dev/null 2>&1 \
        && echo "Persisted user namespace settings to $persist_file"
    return 0
}

# Variables
user="steam"

# 32 or 64 bit Operating System
# If BITS environment variable is not set, try determine it
if [ -z "$BITS" ]; then
    # Determine the operating system architecture
    architecture=$(uname -m)

    # Set OS_BITS based on the architecture
    if [[ $architecture == *"64"* ]]; then
        export BITS=64
    elif [[ $architecture == *"i386"* ]] || [[ $architecture == *"i686"* ]]; then
        export BITS=32
    else
        echo "Unknown architecture: $architecture"
        exit 1
    fi
fi

if [ -f /etc/os-release ]; then
	# freedesktop.org and systemd
	. /etc/os-release
	DISTRO_OS=$NAME
	DISTRO_VERSION=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
	# linuxbase.org
	DISTRO_OS=$(lsb_release -si)
	DISTRO_VERSION=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
	# For some versions of Debian/Ubuntu without lsb_release command
	. /etc/lsb-release
	DISTRO_OS=$DISTRIB_ID
	DISTRO_VERSION=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
	# Older Debian/Ubuntu/etc.
	DISTRO_OS=Debian
	DISTRO_VERSION=$(cat /etc/debian_version)
else
	# Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
	DISTRO_OS=$(uname -s)
	DISTRO_VERSION=$(uname -r)
fi

echo "Starting on $DISTRO_OS: $DISTRO_VERSION..."

# Get the free space on the root filesystem in GB
FREE_SPACE=$(df / --output=avail -BG | tail -n 1 | tr -d 'G')

echo "With $FREE_SPACE Gb free space..."

# Check distrib
if ! command -v apt-get &> /dev/null; then
	echo "ERROR: OS distribution not supported (apt-get not available). $DISTRO_OS: $DISTRO_VERSION"
	exit 1
fi

echo "Updating Operating System..."
apt-get update -y -q && apt-get upgrade -y -q >/dev/null
if [ "$?" -ne "0" ]; then
	echo "ERROR: Updating Operating System..."
	exit 1
fi

dpkg --configure -a >/dev/null

echo "Adding i386 architecture..."
dpkg --add-architecture i386 >/dev/null
if [ "$?" -ne "0" ]; then
	echo "ERROR: Cannot add i386 architecture..."
	exit 1
fi

echo "Installing required packages for $DISTRO_OS: $DISTRO_VERSION..."
apt-get update -y -q >/dev/null
if [ "${DISTRO_OS}" == "Ubuntu" ]; then
	if [ "${DISTRO_VERSION}" == "16.04" ]; then
		apt-get install -y -q dnsutils sudo curl wget screen nano file tar bzip2 gzip unzip hostname bsdmainutils python3 util-linux procps xz-utils ca-certificates binutils bc jq tmux netcat lib32stdc++6 libsdl2-2.0-0:i386 lib32gcc1 steamcmd >/dev/null
	elif [ "${DISTRO_VERSION}" == "18.04" ]; then
		apt-get install -y -q dnsutils sudo curl wget screen nano file tar bzip2 gzip unzip hostname bsdmainutils python3 util-linux procps xz-utils ca-certificates binutils bc jq tmux netcat lib32stdc++6 libsdl2-2.0-0:i386 distro-info lib32gcc1 steamcmd >/dev/null
	elif [ "${DISTRO_VERSION}" == "20.04" ]; then
		apt-get install -y -q dnsutils sudo curl wget screen nano file tar bzip2 gzip unzip hostname bsdmainutils python3 util-linux procps xz-utils ca-certificates binutils bc jq tmux netcat lib32stdc++6 libsdl2-2.0-0:i386 distro-info lib32gcc1 steamcmd >/dev/null
	elif [ "${DISTRO_VERSION}" == "22.04" ]; then
		apt-get install -y -q dnsutils sudo curl wget screen nano file tar bzip2 gzip unzip hostname bsdmainutils python3 util-linux procps xz-utils ca-certificates binutils bc jq tmux netcat lib32stdc++6 libsdl2-2.0-0:i386 distro-info lib32gcc-s1 steamcmd >/dev/null
  	elif [ "${DISTRO_VERSION}" == "24.04" ]; then
		apt-get install -y -q dnsutils sudo curl wget screen nano file tar bzip2 gzip unzip hostname bsdmainutils python3 util-linux procps xz-utils ca-certificates binutils bc jq tmux netcat-traditional lib32stdc++6 libsdl2-2.0-0:i386 distro-info lib32gcc-s1 steamcmd >/dev/null
	else
		echo "$DISTRO_OS $DISTRO_VERSION not officially supported; using Ubuntu 24.04 config"
		apt-get install -y -q dnsutils sudo curl wget screen nano file tar bzip2 gzip unzip hostname bsdmainutils python3 util-linux procps xz-utils ca-certificates binutils bc jq tmux netcat-traditional lib32stdc++6 libsdl2-2.0-0:i386 distro-info lib32gcc-s1 steamcmd >/dev/null
	fi
elif [[ $DISTRO_OS == Debian* ]]; then
	if [ "${DISTRO_VERSION}" == "10" ]; then
		apt-get install -y dnsutils sudo curl wget screen nano file tar bzip2 gzip unzip hostname bsdmainutils python3 util-linux procps xz-utils ca-certificates binutils bc jq tmux netcat-traditional lib32stdc++6 libsdl2-2.0-0:i386 distro-info lib32gcc1 >/dev/null
	elif [ "${DISTRO_VERSION}" == "11" ]; then
		apt-get install -y dnsutils sudo curl wget screen nano file tar bzip2 gzip unzip hostname bsdmainutils python3 util-linux procps xz-utils ca-certificates binutils bc jq tmux netcat-traditional lib32stdc++6 libsdl2-2.0-0:i386 distro-info lib32gcc-s1 >/dev/null
	elif [ "${DISTRO_VERSION}" == "12" ]; then
		apt-get install -y dnsutils sudo curl wget screen nano file tar bzip2 gzip unzip hostname bsdmainutils python3 util-linux procps xz-utils ca-certificates binutils bc jq tmux netcat-traditional lib32stdc++6 libsdl2-2.0-0:i386 distro-info lib32gcc-s1 >/dev/null
	elif [ "${DISTRO_VERSION}" == "13" ]; then
		apt-get install -y dnsutils sudo curl wget screen nano file tar bzip2 gzip unzip hostname bsdmainutils python3 util-linux procps xz-utils ca-certificates binutils bc jq tmux netcat-traditional lib32stdc++6 libsdl2-2.0-0:i386 distro-info lib32gcc-s1 >/dev/null
	else
		echo "$DISTRO_OS: $DISTRO_VERSION not officially supported; using Debian 13 config"
		apt-get install -y dnsutils sudo curl wget screen nano file tar bzip2 gzip unzip hostname bsdmainutils python3 util-linux procps xz-utils ca-certificates binutils bc jq tmux netcat-traditional lib32stdc++6 libsdl2-2.0-0:i386 distro-info lib32gcc-s1 >/dev/null
	fi
else
	echo "ERROR: OS distribution not supported. $DISTRO_OS: $DISTRO_VERSION"
	exit 1
fi

# Plugin versions are curated and committed to this branch by maintainer automation.
# Node installs must be read-only: deploy the checked-out payload without running an
# upstream-release updater or attempting to commit/push changes to GitHub.

echo "Checking $user user exists..."
getent passwd "$user" >/dev/null 2>&1
if [ "$?" -ne "0" ]; then
	echo "Adding $user user..."
	addgroup ${user} && \
	adduser --system --home /home/${user} --shell /bin/false --ingroup ${user} ${user} && \
	usermod -a -G tty ${user} && \
	mkdir -m 755 /home/${user}/cs2 && \
	chown -R ${user}:${user} /home/${user}/cs2
	if [ "$?" -ne "0" ]; then
		echo "ERROR: Cannot add user $user..."
		exit 1
	fi
fi

echo "Checking steamcmd exists..."
if [ ! -x "/steamcmd/steamcmd.sh" ]; then
    mkdir -p /steamcmd || { echo "ERROR: Could not create /steamcmd."; exit 1; }
    cd /steamcmd || { echo "ERROR: Could not enter /steamcmd."; exit 1; }
    wget -O steamcmd_linux.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz || {
        echo "ERROR: Could not download SteamCMD."
        exit 1
    }
    tar -xzf steamcmd_linux.tar.gz || {
        echo "ERROR: Could not extract SteamCMD."
        exit 1
    }
fi
if [ ! -x "/steamcmd/steamcmd.sh" ]; then
    echo "ERROR: /steamcmd/steamcmd.sh is missing after the SteamCMD setup step."
    exit 1
fi

chown -R ${user}:${user} /steamcmd

STEAMCMD="/steamcmd/steamcmd.sh"
STEAMCMD_LOG_DIR="/var/log/cs2-kus-steamcmd"
STEAM_USER_HOME="$(getent passwd "$user" | cut -d: -f6)"
if [[ -z "$STEAM_USER_HOME" || ! -d "$STEAM_USER_HOME" ]]; then
    echo "ERROR: Could not determine the home directory for service user '$user'." >&2
    exit 1
fi
STEAM_APPINFO_CACHE="$STEAM_USER_HOME/Steam/appcache/appinfo.vdf"
mkdir -p "$STEAMCMD_LOG_DIR" || {
    echo "ERROR: Could not create SteamCMD log directory: $STEAMCMD_LOG_DIR" >&2
    exit 1
}
chmod 0755 "$STEAMCMD_LOG_DIR"

# Refresh Steam's app metadata before every install/update. On a fresh SteamCMD
# setup, app_update can otherwise fail with "Missing configuration" even for a
# valid public app such as Steam Linux Runtime 3.0 (App ID 1628350).
steamcmd_refresh_app_info() {
    local app_id="$1"
    local log_file="$STEAMCMD_LOG_DIR/app-info-$app_id.log"

    echo "Refreshing Steam app metadata for App ID $app_id..."
    if ! (
        set -o pipefail
        sudo -u "$user" "$STEAMCMD" \
            +api_logging 1 1 \
            +@sSteamCmdForcePlatformType linux \
            +@sSteamCmdForcePlatformBitness "$BITS" \
            +@ShutdownOnFailedCommand 1 \
            +@NoPromptForPassword 1 \
            +login anonymous \
            +app_info_update 1 \
            +app_info_request "$app_id" \
            +quit 2>&1 | tee "$log_file"
    ); then
        echo "ERROR: SteamCMD could not refresh app metadata for App ID $app_id." >&2
        echo "Diagnostic log: $log_file" >&2
        tail -n 40 "$log_file" 2>/dev/null || true
        return 1
    fi
}

# Install/update an app and check both SteamCMD's exit status and its output.
# "validate" is an argument to app_update; it must NOT be prefixed with '+'.
# If SteamCMD reports Missing configuration, clear only its per-user app-info cache
# and retry once after refreshing metadata.
steamcmd_install_app() {
    local app_id="$1"
    local install_dir="$2"
    local app_name="$3"
    local validate="$4"
    local attempt log_file
    local -a app_update_args

    app_update_args=(+app_update "$app_id")
    if [[ "$validate" == "1" ]]; then
        app_update_args+=(validate)
    fi

    mkdir -p "$install_dir" || {
        echo "ERROR: Could not create install directory: $install_dir" >&2
        return 1
    }
    chown "$user:$user" "$install_dir" || {
        echo "ERROR: Could not assign $install_dir to $user:$user." >&2
        return 1
    }

    for attempt in 1 2; do
        if ! steamcmd_refresh_app_info "$app_id"; then
            return 1
        fi

        log_file="$STEAMCMD_LOG_DIR/app-$app_id-attempt-$attempt.log"
        echo "Installing/updating $app_name (App ID $app_id; attempt $attempt/2)..."

        if (
            set -o pipefail
            sudo -u "$user" "$STEAMCMD" \
                +@ShutdownOnFailedCommand 1 \
                +@NoPromptForPassword 1 \
                +api_logging 1 1 \
                +@sSteamCmdForcePlatformType linux \
                +@sSteamCmdForcePlatformBitness "$BITS" \
                +force_install_dir "$install_dir" \
                +login anonymous \
                "${app_update_args[@]}" \
                +quit 2>&1 | tee "$log_file"
        ) && ! grep -Eiq "ERROR! Failed to install app|Missing configuration" "$log_file"; then
            return 0
        fi

        if [[ "$attempt" -eq 1 ]] && grep -Eiq "Missing configuration|No app info for AppID" "$log_file"; then
            echo "SteamCMD still reports missing app metadata. Clearing only its cached app-info file and retrying..."
            rm -f "$STEAM_APPINFO_CACHE" || {
                echo "ERROR: Could not remove stale Steam app-info cache: $STEAM_APPINFO_CACHE" >&2
                return 1
            }
            continue
        fi

        echo "ERROR: SteamCMD failed to install/update $app_name (App ID $app_id)." >&2
        echo "Diagnostic log: $log_file" >&2
        tail -n 60 "$log_file" 2>/dev/null || true
        return 1
    done

    echo "ERROR: SteamCMD exhausted retries for $app_name (App ID $app_id)." >&2
    return 1
}

echo "Downloading/updating Steam Linux Runtime 3.0 (sniper)..."
# App ID and Linux depot information: https://steamdb.info/app/1628350/depots/
if ! steamcmd_install_app 1628350 "/home/$user/steamrt" "Steam Linux Runtime 3.0 (sniper)" 1; then
    echo "ERROR: Steam Linux Runtime 3.0 installation failed; CS2 installation was not started." >&2
    exit 1
fi
if [[ ! -x "/home/$user/steamrt/run" ]]; then
    echo "ERROR: Steam Linux Runtime did not install correctly: /home/$user/steamrt/run is missing." >&2
    echo "Check $STEAMCMD_LOG_DIR for SteamCMD diagnostics." >&2
    exit 1
fi
chown -R "$user:$user" "/home/$user/steamrt"

echo "Downloading/updating Counter-Strike 2..."
# Steam application ID: 730
if ! steamcmd_install_app 730 "/home/$user/cs2" "Counter-Strike 2" 0; then
    echo "ERROR: CS2 installation failed." >&2
    exit 1
fi
if [[ ! -x "/home/$user/cs2/game/bin/linuxsteamrt64/cs2" ]]; then
    echo "ERROR: SteamCMD completed but the CS2 Linux executable is missing." >&2
    echo "Check $STEAMCMD_LOG_DIR for SteamCMD diagnostics." >&2
    exit 1
fi

cd /home/${user}

# Set up steam client libraries
# 32-bit
mkdir -p /home/${user}/.steam/sdk32/
rm -f /home/${user}/.steam/sdk32/steamclient.so
cp -v /steamcmd/linux32/steamclient.so /home/${user}/.steam/sdk32/steamclient.so || {
	echo "ERROR: Failed to copy 32-bit libraries"
}
# 64-bit
mkdir -p /home/${user}/.steam/sdk64/
rm -f /home/${user}/.steam/sdk64/steamclient.so
cp -v /steamcmd/linux64/steamclient.so /home/${user}/.steam/sdk64/steamclient.so || {
	echo "ERROR: Failed to copy 64-bit libraries"
}

# Copy .so files needed after 16.9.2025 update
# https://discord.com/channels/1160907911501991946/1160907912445710479/1417806634503372851
cp -v /home/${user}/cs2/game/bin/linuxsteamrt64/*.so  /home/${user}/cs2/game/csgo/bin/linuxsteamrt64/

if [ "${DISTRO_OS}" == "Ubuntu" ]; then
	if [ "${DISTRO_VERSION}" == "22.04" ]; then
		# https://forums.alliedmods.net/showthread.php?t=336183
		rm /home/${user}/cs2/bin/libgcc_s.so.1
	fi
fi

echo "Deploying tracked KUS/Larnz payload..."
PAYLOAD_ROOT="$ROOT_DIR/game/csgo"
GAME_ROOT="/home/${user}/cs2/game/csgo"
if [ ! -d "$PAYLOAD_ROOT/addons" ]; then
    echo "ERROR: Tracked payload is missing: $PAYLOAD_ROOT/addons"
    exit 1
fi

# Non-destructive overlay: add or overwrite tracked payload files only.
# Runtime files that are not present in the payload are never purged.
# CounterStrikeSharp configs and cfg/settings are manual-only and are not copied by automation.
# Windows assets are a staging overlay, not part of the Linux runtime copy.
mkdir -p "$GAME_ROOT"
if ! (
    set -o pipefail
    tar -C "$PAYLOAD_ROOT" \
        --exclude='./gameinfo.gi' \
        --exclude='./addons/windows' \
        --exclude='./addons/windows/*' \
        --exclude='./addons/counterstrikesharp/configs' \
        --exclude='./addons/counterstrikesharp/configs/*' \
        --exclude='./cfg/settings' \
        --exclude='./cfg/settings/*' \
        -cf - . | tar -C "$GAME_ROOT" -xf -
); then
    echo "ERROR: Non-destructive payload overlay failed."
    exit 1
fi

chown -R "${user}:${user}" "/home/${user}/cs2"
cd "/home/${user}/cs2" || exit
# Define the file name
FILE="game/csgo/gameinfo.gi"

# Define the pattern to search for and the line to add
PATTERN="Game_LowViolence[[:space:]]*csgo_lv // Perfect World content override"
LINE_TO_ADD="\t\t\tGame\tcsgo/addons/metamod"

# Use a regular expression to ignore spaces when checking if the line exists
REGEX_TO_CHECK="^[[:space:]]*Game[[:space:]]*csgo/addons/metamod"

# Check if the line already exists in the file, ignoring spaces
if grep -qE "$REGEX_TO_CHECK" "$FILE"; then
    echo "$FILE already patched for Metamod."
else
    # If the line isn't there, use awk to add it after the pattern
    awk -v pattern="$PATTERN" -v lineToAdd="$LINE_TO_ADD" '{
        print $0;
        if ($0 ~ pattern) {
            print lineToAdd;
        }
    }' "$FILE" > tmp_file && mv tmp_file "$FILE"
    echo "$FILE successfully patched for Metamod."
fi

if ! grep -qE "$REGEX_TO_CHECK" "$FILE"; then
    echo "ERROR: MetaMod entry is still missing from $FILE; the insertion marker may have changed."
    exit 1
fi


# Prepare host settings needed by the Steam Linux Runtime for instance launches.
# This configures the host only; this script must never launch the CS2 process.
enable_unprivileged_namespaces

echo
echo "SUCCESS: Linux prerequisites, SteamCMD, Steam Linux Runtime, CS2, tracked payload and gameinfo.gi are ready."
echo "The CS2 server was NOT launched. Configure an instance and start linux/instances/<name>/watchdog.sh."
exit 0
