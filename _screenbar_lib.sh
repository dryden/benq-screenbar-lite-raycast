#!/bin/bash

# Shared helper library for BenQ ScreenBar Lite (VID: 0x04A5, PID: 0x2500)
# Not a standalone Raycast command (no @raycast headers)

if [[ -x "/opt/homebrew/bin/hidapitester" ]]; then
  HIDAPITESTER="/opt/homebrew/bin/hidapitester"
elif [[ -x "/usr/local/bin/hidapitester" ]]; then
  HIDAPITESTER="/usr/local/bin/hidapitester"
else
  HIDAPITESTER="$(command -v hidapitester 2>/dev/null || echo /opt/homebrew/bin/hidapitester)"
fi
VIDPID="04A5:2500"
STATE_FILE="${HOME}/.screenbar_lite_state"

# Color temperature lookup table (1..8 -> Kelvin)
TEMP_LABELS=("" "2700K" "3000K" "3500K" "4000K" "4500K" "5000K" "5700K" "6500K")

LOCK_DIR="${STATE_FILE}.lock"
LOCK_HELD=0

acquire_lock() {
  [[ "$LOCK_HELD" -eq 1 ]] && return 0
  local i=0 mtime now
  until mkdir "$LOCK_DIR" 2>/dev/null; do
    # Break stale locks older than 10 seconds
    mtime=$(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0)
    now=$(date +%s)
    if (( mtime > 0 && now - mtime > 10 )); then
      rmdir "$LOCK_DIR" 2>/dev/null
      continue
    fi
    i=$(( i + 1 ))
    if (( i > 100 )); then
      if [[ "${LOCK_OPTIONAL:-0}" -eq 1 ]]; then
        echo "ScreenBar Lite: state lock busy, continuing without it" >&2
        return 0
      fi
      echo "ScreenBar Lite: could not acquire state lock ❌" >&2
      exit 1
    fi
    sleep 0.05
  done
  LOCK_HELD=1
  trap release_lock EXIT
}

release_lock() {
  if [[ "$LOCK_HELD" -eq 1 ]]; then
    rmdir "$LOCK_DIR" 2>/dev/null
    LOCK_HELD=0
  fi
}

# Print an error and abort (state is NOT saved, Raycast shows failure)
die_hid() {
  if [[ "${HID_NACK:-0}" -eq 1 ]]; then
    echo "ScreenBar Lite: device is stuck (FIFO full), unplug and replug the USB cable ❌" >&2
  else
    echo "ScreenBar Lite: device not responding, is it plugged in? ❌" >&2
  fi
  exit 1
}

load_state() {
  acquire_lock
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
  POWER="${POWER:-2}"           # 1=Off, 2=On
  BRIGHTNESS="${BRIGHTNESS:-8}" # 1..15 (0x01..0x0F)
  COLORTEMP="${COLORTEMP:-5}"   # 1..8  (0x01..0x08: 2700K..6500K)
  MODE="${MODE:-1}"             # 1=Manual, 2=Auto, 3=Favorite
  CIRCADIAN="${CIRCADIAN:-1}"   # 1=Enabled (follow time of day), 0=Disabled
  WAS_ON_BEFORE_SLEEP="${WAS_ON_BEFORE_SLEEP:-2}" # 1=Off, 2=On before sleep
}

save_state() {
  if [[ "$POWER" -eq 2 ]]; then
    WAS_ON_BEFORE_SLEEP=2
  fi
  local tmp="${STATE_FILE}.tmp.$$"
  cat > "$tmp" <<EOF
POWER=$POWER
BRIGHTNESS=$BRIGHTNESS
COLORTEMP=$COLORTEMP
MODE=$MODE
CIRCADIAN=$CIRCADIAN
WAS_ON_BEFORE_SLEEP=$WAS_ON_BEFORE_SLEEP
EOF
  mv -f "$tmp" "$STATE_FILE"
}

# Calculate target ColorTemp index (1..8) based on current local hour (00..23)
get_circadian_temp() {
  local hour
  hour=$(date +%H)
  hour=$(( 10#$hour ))
  if   (( hour >= 7  && hour < 8  )); then echo 4 # 07:00-07:59 -> 4000K (晨間柔和)
  elif (( hour >= 8  && hour < 9  )); then echo 6 # 08:00-08:59 -> 5000K (早晨清醒)
  elif (( hour >= 9  && hour < 12 )); then echo 8 # 09:00-11:59 -> 6500K (上午專注白光)
  elif (( hour >= 12 && hour < 16 )); then echo 7 # 12:00-15:59 -> 5700K (午後自然日光)
  elif (( hour >= 16 && hour < 18 )); then echo 6 # 16:00-17:59 -> 5000K (下午舒適光)
  elif (( hour >= 18 && hour < 20 )); then echo 4 # 18:00-19:59 -> 4000K (傍晚微暖光)
  elif (( hour >= 20 && hour < 22 )); then echo 3 # 20:00-21:59 -> 3500K (夜間放鬆暖光)
  elif (( hour >= 22 && hour < 23 )); then echo 2 # 22:00-22:59 -> 3000K (睡前暖黃光)
  else                                     echo 1 # 23:00-06:59 -> 2700K (深夜極暖燭光)
  fi
}

# Returns non-zero if the device could not be reached after HID_RETRIES attempts
send_hid_packet() {
  local packet="$1"
  local attempt out
  HID_NACK=0
  for (( attempt = 1; attempt <= ${HID_RETRIES:-3}; attempt++ )); do
    out=$("$HIDAPITESTER" --vidpid "$VIDPID" --quiet --open \
      --length 9 --send-output "$packet" \
      --timeout 40 --length 8 --read-input \
      --length 9 --read-input-report 0 \
      --close 2>&1)
    # NOTE: hidapitester exits 0 even when the device is missing; with --quiet it
    # then prints nothing, so an empty output means the device could not be opened.
    if [[ $? -eq 0 && -n "$out" ]]; then
      if [[ "$out" == *"C3 1F"* ]]; then
        # MCU FIFO full (NACK): it ignores commands until USB is power-cycled
        HID_NACK=1
        return 1
      fi
      return 0
    fi
    sleep 0.5
  done
  return 1
}

# Send dynamic Brightness + ColorTemp packet:
# [0x00, 0xA7, brightness, colorTemp, 0xFF, 0x04, 0x02, 0xFF, checksum]
# Checksum = (0xA7 + brightness + colorTemp + 0xFF + 0x04 + 0x02 + 0xFF) & 0xFF
send_brightness_temp() {
  local b="$1"
  local t="$(( 9 - $2 ))" # Hardware index is inverted: 0x01 = 6500K (coolest), 0x08 = 2700K (warmest)
  local cksum=$(( (0xA7 + b + t + 0xFF + 0x04 + 0x02 + 0xFF) & 0xFF ))
  local packet
  packet=$(printf "0x00,0xA7,0x%02X,0x%02X,0xFF,0x04,0x02,0xFF,0x%02X" "$b" "$t" "$cksum")
  send_hid_packet "$packet"
}
