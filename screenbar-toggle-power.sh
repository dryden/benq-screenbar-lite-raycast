#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title ScreenBar: Toggle Power
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 💡
# @raycast.packageName BenQ ScreenBar Lite

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_screenbar_lib.sh"

load_state

if [[ "$POWER" -eq 2 ]]; then
  # Currently ON -> Send Power Off (A7 FF FF FF FF 01 FF A3)
  send_hid_packet "0x00,0xA7,0xFF,0xFF,0xFF,0xFF,0x01,0xFF,0xA3" || die_hid
  POWER=1
  WAS_ON_BEFORE_SLEEP=1
  save_state
  echo "ScreenBar Lite: Power OFF 🌑"
else
  # Currently OFF -> Turn ON
  POWER=2
  WAS_ON_BEFORE_SLEEP=2
  # In hardware Auto mode (MODE=2) only power on: a 0xA7 B/T packet would leave Auto mode
  if [[ "${CIRCADIAN:-1}" -eq 1 && "${MODE:-1}" -ne 2 ]]; then
    COLORTEMP=$(get_circadian_temp)
    send_brightness_temp "$BRIGHTNESS" "$COLORTEMP" || die_hid
  else
    send_hid_packet "0x00,0xA7,0xFF,0xFF,0xFF,0xFF,0x02,0xFF,0xA4" || die_hid
  fi
  save_state
  echo "ScreenBar Lite: Power ON 💡 (${TEMP_LABELS[$COLORTEMP]})"
fi
