#!/bin/bash

# Handles macOS sleep / wake / shutdown events for BenQ ScreenBar Lite
# Usage: _screenbar_power_event.sh [sleep|wake|shutdown]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_screenbar_lib.sh"

load_state

EVENT="$1"

case "$EVENT" in
  sleep|shutdown)
    if [[ "$POWER" -eq 2 ]]; then
      WAS_ON_BEFORE_SLEEP=2
    fi
    POWER=1
    save_state
    # Always send HID Power Off packet before system sleeps or shuts down
    send_hid_packet "0x00,0xA7,0xFF,0xFF,0xFF,0xFF,0x01,0xFF,0xA3" || echo "[$(date)] $EVENT: failed to power off lamp" >&2
    ;;
  wake)
    # Wait briefly for USB HID bus to settle after wake
    sleep 0.5
    if [[ "${WAS_ON_BEFORE_SLEEP:-2}" -eq 2 ]]; then
      POWER=2
      if ! send_hid_packet "0x00,0xA7,0xFF,0xFF,0xFF,0xFF,0x02,0xFF,0xA4"; then
        echo "[$(date)] wake: failed to power on lamp" >&2
      fi
      if [[ "${CIRCADIAN:-1}" -eq 1 && "${MODE:-1}" -ne 2 ]]; then
        sleep 0.1
        COLORTEMP=$(get_circadian_temp)
        send_brightness_temp "$BRIGHTNESS" "$COLORTEMP" || true
      fi
      save_state
    fi
    ;;
esac
