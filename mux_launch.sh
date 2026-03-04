#!/bin/bash
# HELP: XMPlayer - XMB Style Media Player
# ICON: xmplayer
# GRID: XMPlayer

# Source muOS system functions
. /opt/muos/script/var/func.sh

# Kill background music if playing
if pgrep -f "playbgm.sh" >/dev/null; then
    killall -q "playbgm.sh" "mpg123"
fi

echo "app" >/tmp/act_go

# Governor setup
GOV_GO="/tmp/gov_go"
[ -e "$GOV_GO" ] && cat "$GOV_GO" >"$(GET_VAR "device" "cpu/governor")"

# Define paths
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
APP_DIR="$SCRIPT_DIR/.xmplayer"
GPTOKEYB="$APP_DIR/gptokeyb2"

# Redirections for debugging
echo "Starting XMPlayer Script" > "$APP_DIR/log.txt"
exec >> "$APP_DIR/log.txt" 2>&1

# Exports
export WIDTH=$(GET_VAR device mux/width)
export HEIGHT=$(GET_VAR device mux/height)
export SDL_GAMECONTROLLERCONFIG_FILE="/usr/lib/gamecontrollerdb.txt"
export LD_LIBRARY_PATH="$APP_DIR/libs:$LD_LIBRARY_PATH"

# Ensure binaries are executable
chmod +x "$APP_DIR/love"
chmod +x "$GPTOKEYB"

# Launch Application
cd "$APP_DIR" || exit
SET_VAR "system" "foreground_process" "love"

# Run with gptokeyb mapping
echo "Launching gptokeyb..."
$GPTOKEYB "love" -c "$APP_DIR/xmplayer.gptk" &
echo "Launching love binary..."
./love .

# Cleanup
kill -9 "$(pidof gptokeyb2)"
