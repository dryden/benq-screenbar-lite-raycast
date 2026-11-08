#!/bin/bash

# Handles macOS sleep / wake / shutdown / boot events for BenQ ScreenBar Lite
# Usage: _screenbar_power_event.sh [sleep|wake|shutdown|boot]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_screenbar_lib.sh"

# Never skip a sleep/wake/shutdown event because another command holds the state lock
LOCK_OPTIONAL=1

# Ignore termination signals during power transitions so launchd/loginwindow
# teardown during shutdown cannot abort an in-flight USB HID power-off packet.
trap '' TERM INT HUP

EVENT="$1"
if [[ "$EVENT" == "wake" ]]; then
  # Wait briefly for USB HID bus to settle after wake before querying/sending HID packets
  sleep 0.5
elif [[ "$EVENT" == "shutdown" ]]; then
  HID_RETRIES=2
  HID_RETRY_DELAY=0.15
fi

load_state

case "$EVENT" in
  sleep|shutdown)
    if [[ "$POWER" -eq 2 ]]; then
      WAS_ON_BEFORE_SLEEP=2
    fi
    POWER=1
    # Always send HID Power Off packet immediately before system sleeps or shuts down
    send_hid_packet "0x00,0xA7,0xFF,0xFF,0xFF,0xFF,0x01,0xFF,0xA3" || echo "[$(date)] $EVENT: failed to power off lamp" >&2
    save_state
    ;;
  wake|boot)
    if [[ "$EVENT" == "boot" && "$POWER" -eq 2 ]]; then
      exit 0
    fi
    if [[ "${WAS_ON_BEFORE_SLEEP:-2}" -eq 2 ]]; then
      POWER=2
      if ! send_hid_packet "0x00,0xA7,0xFF,0xFF,0xFF,0xFF,0x02,0xFF,0xA4"; then
        echo "[$(date)] $EVENT: failed to power on lamp" >&2
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
