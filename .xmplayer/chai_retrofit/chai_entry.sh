#!/bin/bash
# CHAI entry point
#
# Sourced by an app's launch script (needs CFW_NAME from PortMaster). After
# this, "chai" is a command the app and anything it starts can run, whether
# or not the CFW implements CHAI:
#  - The CFW ships chai: nothing to do.
#  - It doesn't: picks this CFW's retrofit profile (or the default one), runs
#    its setup, and puts bin/chai on PATH, which forwards to that profile.
#    Each profile handles its own CFW versions.
#
# Exports:
#   PATH                   with bin/ in front when retrofitting
#   CHAI_RETROFIT_PROFILE  the retrofit profile in use, or "native"
#
# Call chai_retrofit_teardown when the app exits. It undoes the profile's
# setup, and does nothing when the CFW has its own chai.

CHAI_RETRO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v chai >/dev/null 2>&1; then
	CHAI_RETROFIT_PROFILE="native"
else
	if [[ "$CFW_NAME" = "knulli" ]]; then
		CHAI_RETROFIT_PROFILE="knulli"
	# Moved spruce up because its reported as other cfw occasionally in portmaster
	elif [ -f /mnt/SDCARD/spruce/spruce ]; then
		CHAI_RETROFIT_PROFILE="Spruce"
	elif [[ "$CFW_NAME" = "muOS" ]]; then
		CHAI_RETROFIT_PROFILE="MustardOS"
	elif [[ "$CFW_NAME" = "ROCKNIX" ]]; then
		CHAI_RETROFIT_PROFILE="ROCKNIX"
	elif [ -f /mnt/SDCARD/.system/version.txt ] && grep -q "NextUI" /mnt/SDCARD/.system/version.txt; then
		CHAI_RETROFIT_PROFILE="NextUI"
	else
		CHAI_RETROFIT_PROFILE="default"
	fi

	sh "${CHAI_RETRO_DIR}/${CHAI_RETROFIT_PROFILE}/setup.sh" setup
	PATH="${CHAI_RETRO_DIR}/bin:${PATH}"
fi

chai_retrofit_teardown() {
	[ "$CHAI_RETROFIT_PROFILE" = "native" ] && return 0
	sh "${CHAI_RETRO_DIR}/${CHAI_RETROFIT_PROFILE}/setup.sh" teardown
}

echo "CHAI: using ${CHAI_RETROFIT_PROFILE} ($(command -v chai))"

export PATH
export CHAI_RETROFIT_PROFILE
