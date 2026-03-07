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

# Redirections for debugging
echo "Starting XMPlayer Script" > "$APP_DIR/log.txt"
exec >> "$APP_DIR/log.txt" 2>&1

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

# Cleanup
kill -9 "$(pidof gptokeyb2)" 2>/dev/null

