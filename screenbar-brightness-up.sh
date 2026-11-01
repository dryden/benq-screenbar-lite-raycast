#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title ScreenBar Brightness Up
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🔆
# @raycast.packageName BenQ ScreenBar Lite

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_screenbar_lib.sh"

load_state

if [[ "$BRIGHTNESS" -lt 15 ]]; then
  BRIGHTNESS=$(( BRIGHTNESS + 1 ))
fi
POWER=2
MODE=1

send_brightness_temp "$BRIGHTNESS" "$COLORTEMP"
save_state

echo "ScreenBar Lite: Brightness ${BRIGHTNESS}/15 (${TEMP_LABELS[$COLORTEMP]}) 🔆"
