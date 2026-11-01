#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title ScreenBar Color Temp Warmer
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🔥
# @raycast.packageName BenQ ScreenBar Lite

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_screenbar_lib.sh"

load_state

# 1 = 2700K (Warmest), 8 = 6500K (Coolest)
if [[ "$COLORTEMP" -gt 1 ]]; then
  COLORTEMP=$(( COLORTEMP - 1 ))
fi
POWER=2
MODE=1

send_brightness_temp "$BRIGHTNESS" "$COLORTEMP"
save_state

echo "ScreenBar Lite: Color Temp ${TEMP_LABELS[$COLORTEMP]} (Brightness ${BRIGHTNESS}/15) 🔥"
