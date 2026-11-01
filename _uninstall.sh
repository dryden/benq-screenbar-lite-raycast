#!/bin/bash
set -e

LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
CIRCADIAN_PLIST="${LAUNCH_AGENTS_DIR}/com.benq.screenbar-circadian.plist"
POWER_PLIST="${LAUNCH_AGENTS_DIR}/com.benq.screenbar-power-monitor.plist"

echo "==> Unloading and removing LaunchAgents..."
launchctl bootout "gui/$(id -u)" "$CIRCADIAN_PLIST" 2>/dev/null || true
launchctl bootout "gui/$(id -u)" "$POWER_PLIST" 2>/dev/null || true
rm -f "$CIRCADIAN_PLIST" "$POWER_PLIST"
echo "==> Uninstalled background services successfully."
