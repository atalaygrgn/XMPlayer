#!/bin/sh

# HELP: XMPlayer - XMB Style Media Player
# ICON: xmplayer
# GRID: XMPlayer

. /opt/muos/script/var/func.sh

# Application Setup
APP_BIN="love"
SETUP_APP "$APP_BIN" ""

# Kill background music if playing
if pgrep -f "playbgm.sh" >/dev/null; then
    killall -q "playbgm.sh" "mpg123"
fi

# Define paths
# muOS provides a bind-mounted runtime path in /run/muos/storage/application/
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
APP_DIR="$SCRIPT_DIR/.xmplayer"

# Hall sensor override for clamshell devices (e.g. RG35XX SP).
# Bind-mounting a constant value keeps lid-close from triggering sleep
# while XMPlayer is running. We unmount on exit.
HALL_OVERRIDE_FILE="/tmp/xmplayer_hallkey_override"
HALL_TARGETS="/sys/class/power_supply/axp2202-battery/hallkey /sys/devices/platform/hall-mh248/hallvalue"

setup_hall_override() {
    echo "1" > "$HALL_OVERRIDE_FILE"

    for TARGET in $HALL_TARGETS; do
        [ -e "$TARGET" ] || continue

        if findmnt -n "$TARGET" >/dev/null 2>&1; then
            echo "Hall target already mounted, skipping: $TARGET"
            continue
        fi

        if mount --bind "$HALL_OVERRIDE_FILE" "$TARGET" 2>/dev/null; then
            echo "Mounted hall override on: $TARGET"
        else
            echo "Failed to mount hall override on: $TARGET"
        fi
    done
}

cleanup() {
    kill -9 "$(pidof gptokeyb2)" 2>/dev/null

    for TARGET in $HALL_TARGETS; do
        [ -e "$TARGET" ] || continue

        while findmnt -n "$TARGET" >/dev/null 2>&1; do
            if umount -l "$TARGET" 2>/dev/null; then
                echo "Unmounted hall override: $TARGET"
            else
                echo "Failed to unmount hall override: $TARGET"
                break
            fi
        done
    done

    rm -f "$HALL_OVERRIDE_FILE"
}

# Redirections for debugging
echo "Starting XMPlayer Script" > "$APP_DIR/log.txt"
exec >> "$APP_DIR/log.txt" 2>&1

trap cleanup EXIT INT TERM

setup_hall_override

# Exports
export WIDTH=$(GET_VAR device mux/width)
export HEIGHT=$(GET_VAR device mux/height)
export SDL_GAMECONTROLLERCONFIG_FILE="/usr/lib/gamecontrollerdb.txt"
export LD_LIBRARY_PATH="$APP_DIR/libs:$LD_LIBRARY_PATH"

# Ensure binaries are executable
chmod +x "$APP_DIR/bin/love"
chmod +x "$APP_DIR/bin/gptokeyb2"

# Launch Application
cd "$APP_DIR" || exit

# Run with gptokeyb mapping
echo "Launching gptokeyb..."
./bin/gptokeyb2 "love" -c "$APP_DIR/config/xmplayer.gptk" &

echo "Launching love binary..."
./bin/love .

