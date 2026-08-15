#!/bin/bash
# PORTMASTER: xmplayer.zip, XMPlayer.sh

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt

[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

get_controls

GAMEDIR=/$directory/ports/xmplayer
CONFDIR="$GAMEDIR/conf/"

mkdir -p "$GAMEDIR/conf"

cd $GAMEDIR

> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

echo "CFW_NAME: ${CFW_NAME}"
export CFW_NAME
echo "DEVICE_NAME: ${DEVICE_NAME}"
export DEVICE_NAME
export GPTOKEYB
export XM_BUILD_TYPE="PortMaster"

# Set the XDG environment variables for config & savefiles
export XDG_DATA_HOME="$CONFDIR"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

# Setup Love2D 11.5 runtime
runtime="love_11.5"
if [ ! -f "$controlfolder/runtimes/${runtime}/love.txt" ]; then
  if [ ! -f "$controlfolder/harbourmaster" ]; then
    pm_message "This port requires the latest PortMaster to run, please go to https://portmaster.games/ for more info."
    sleep 5
    exit 1
  fi
  $ESUDO $controlfolder/harbourmaster --quiet --no-check runtime_check "${runtime}"
fi

source "$controlfolder/runtimes/${runtime}/love.txt"
export LOVE_GPTK

# Run Love2D game passing the gamedata directory containing main.lua
cd "$GAMEDIR/gamedata"

# Ensure ffmpeg binary is executable
chmod +x ./bin/ffmpeg
chmod +x ./bin/ffplay
chmod +x ./bin/ffprobe

# Start gptokeyb daemon mapping
if [ "$CFW_NAME" = "muOS" ]; then
  ./bin/gptokeyb2 "$LOVE_GPTK" -c "$GAMEDIR/xmplayer.gptk" &
else
  $GPTOKEYB "$LOVE_GPTK" -c "$GAMEDIR/xmplayer.gptk" &
fi

pm_platform_helper "$LOVE_BINARY"
$LOVE_RUN .

pm_finish
