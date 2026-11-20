#!/bin/sh
# CHAI retrofit setup: Spruce
#
# Usage: setup.sh setup|teardown
#
# Starts vol_listener, which watches the volume keys and runs
# "chai notify-volume" with Spruce's volume after each press.

CHAI_PROFILE_SOURCED=1
. "$(dirname "$0")/../default/setup.sh"

chai_setup() {
	sh "$CHAI_RETRO_DIR/Spruce/vol_listener" "$CHAI_CMD" </dev/null >/dev/null 2>&1 &
}

# busybox's getevent | while loop runs as two processes, so kill by command
# line. Matching the full chai_retrofit path keeps this off Spruce's own scripts.
chai_teardown() {
	for PID in $(ps | grep "[c]hai_retrofit/Spruce/vol_listener" | awk '{print $1}'); do
		kill "$PID" 2>/dev/null
	done
}

chai_setup_main "$@"
