#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title ScreenBar: Toggle Circadian Mode
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🌅
# @raycast.packageName BenQ ScreenBar Lite

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_screenbar_lib.sh"

load_state

if [[ "$CIRCADIAN" -eq 1 ]]; then
  CIRCADIAN=0
  save_state
  echo "ScreenBar Lite: Circadian Mode OFF ⏸️"
else
  CIRCADIAN=1
  save_state
  release_lock
  "${SCRIPT_DIR}/_screenbar_circadian_worker.sh" --force
fi
