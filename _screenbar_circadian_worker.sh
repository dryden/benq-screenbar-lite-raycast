#!/bin/bash

# Background worker for Circadian Color Temperature (not a standalone Raycast command)
# Maps current local hour (00..23) to ScreenBar Lite color temperature index (1..8)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_screenbar_lib.sh"

load_state

# Exit if circadian mode is disabled (unless --force is passed)
if [[ "$CIRCADIAN" -ne 1 && "$1" != "--force" ]]; then
  exit 0
fi

TARGET_TEMP=$(get_circadian_temp)
PREV_TEMP="$COLORTEMP"
COLORTEMP="$TARGET_TEMP"
save_state

# Only send HID command if the lamp is currently ON (POWER=2)
# (Sending 0xA7 brightness/temp when lamp is OFF would turn it ON)
# Also skip when hardware Auto Dimming (MODE=2) is active: the 0xA7 B/T packet would switch it back to manual.
if [[ "$POWER" -eq 2 && "$MODE" -ne 2 ]]; then
  if [[ "$PREV_TEMP" -ne "$TARGET_TEMP" || "$1" == "--force" ]]; then
    send_brightness_temp "$BRIGHTNESS" "$COLORTEMP" || die_hid
  fi
fi

if [[ "$1" == "--force" ]]; then
  echo "ScreenBar Lite: Circadian Mode ON 🌅 (${TEMP_LABELS[$COLORTEMP]})"
fi
