#!/bin/bash
set -e

LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
CIRCADIAN_PLIST="${LAUNCH_AGENTS_DIR}/io.github.dryden.screenbar-circadian.plist"
POWER_PLIST="${LAUNCH_AGENTS_DIR}/io.github.dryden.screenbar-power-monitor.plist"
LEGACY_CIRCADIAN_PLIST="${LAUNCH_AGENTS_DIR}/com.benq.screenbar-circadian.plist"
LEGACY_POWER_PLIST="${LAUNCH_AGENTS_DIR}/com.benq.screenbar-power-monitor.plist"

echo "==> Unloading and removing LaunchAgents..."
launchctl bootout "gui/$(id -u)" "$CIRCADIAN_PLIST" 2>/dev/null || true
launchctl bootout "gui/$(id -u)" "$POWER_PLIST" 2>/dev/null || true
launchctl bootout "gui/$(id -u)" "$LEGACY_CIRCADIAN_PLIST" 2>/dev/null || true
launchctl bootout "gui/$(id -u)" "$LEGACY_POWER_PLIST" 2>/dev/null || true
rm -f "$CIRCADIAN_PLIST" "$POWER_PLIST" "$LEGACY_CIRCADIAN_PLIST" "$LEGACY_POWER_PLIST"
echo "==> Uninstalled background services successfully."

if [[ "$1" == "--purge" ]]; then
  echo "==> Removing state file and logs..."
  rm -rf "${HOME}/.screenbar_lite_state" "${HOME}/.screenbar_lite_state.lock"
  rm -f /tmp/screenbar-circadian.log /tmp/screenbar-power.log
fi
