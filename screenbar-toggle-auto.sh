#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Toggle ScreenBar Auto Mode
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🤖
# @raycast.packageName BenQ ScreenBar Lite

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_screenbar_lib.sh"

load_state

if [[ "$MODE" -eq 2 ]]; then
  # Switch to Manual Mode (A7 FF FF FF 01 02 FF A6)
  send_hid_packet "0x00,0xA7,0xFF,0xFF,0xFF,0x01,0x02,0xFF,0xA6"
  MODE=1
  POWER=2
  save_state
  echo "ScreenBar Lite: Manual Mode ✋"
else
  # Switch to Auto Dimming Mode (A7 FF 05 FF 02 02 FF AD)
  send_hid_packet "0x00,0xA7,0xFF,0x05,0xFF,0x02,0x02,0xFF,0xAD"
  MODE=2
  POWER=2
  save_state
  echo "ScreenBar Lite: Auto Dimming Mode 🤖"
fi
