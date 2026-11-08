#!/bin/bash
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
CIRCADIAN_LABEL="io.github.dryden.screenbar-circadian"
POWER_LABEL="io.github.dryden.screenbar-power-monitor"
CIRCADIAN_PLIST="${LAUNCH_AGENTS_DIR}/${CIRCADIAN_LABEL}.plist"
POWER_PLIST="${LAUNCH_AGENTS_DIR}/${POWER_LABEL}.plist"
# Legacy labels used by earlier versions (migrated automatically)
for legacy in com.benq.screenbar-circadian com.benq.screenbar-power-monitor; do
  touch /tmp/screenbar-skip-shutdown
  launchctl bootout "gui/$(id -u)/${legacy}" 2>/dev/null || true
  rm -f "${LAUNCH_AGENTS_DIR}/${legacy}.plist" /tmp/screenbar-skip-shutdown
done

echo "==> [1/4] Checking hidapitester..."
if ! command -v hidapitester >/dev/null 2>&1 && [[ ! -x "/opt/homebrew/bin/hidapitester" ]] && [[ ! -x "/usr/local/bin/hidapitester" ]]; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installing hidapitester via Homebrew..."
    brew install hidapitester
  else
    echo "Error: Homebrew not found. Please install Homebrew first (https://brew.sh) and run: brew install hidapitester"
    exit 1
  fi
else
  echo "hidapitester is already installed."
fi

if ! xcode-select -p >/dev/null 2>&1 || ! command -v clang >/dev/null 2>&1; then
  echo "Error: clang not found. Install Xcode Command Line Tools first: xcode-select --install"
  exit 1
fi

echo "==> [2/4] Compiling native macOS power monitor (screenbar-power-monitor)..."
clang -O2 -fobjc-arc -framework Cocoa -framework CoreGraphics -framework IOKit \
  "${REPO_DIR}/screenbar-power-monitor.m" \
  -o "${REPO_DIR}/screenbar-power-monitor"
chmod +x "${REPO_DIR}/screenbar-power-monitor" "${REPO_DIR}"/*.sh

echo "==> [3/4] Installing LaunchAgents (Circadian Worker & Sleep/Wake Power Monitor)..."
mkdir -p "$LAUNCH_AGENTS_DIR"

cat > "$CIRCADIAN_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${CIRCADIAN_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${REPO_DIR}/_screenbar_circadian_worker.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/screenbar-circadian.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/screenbar-circadian.log</string>
</dict>
</plist>
EOF

cat > "$POWER_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${POWER_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${REPO_DIR}/screenbar-power-monitor</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ExitTimeOut</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>/tmp/screenbar-power.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/screenbar-power.log</string>
</dict>
</plist>
EOF

touch /tmp/screenbar-skip-shutdown
launchctl bootout "gui/$(id -u)" "$CIRCADIAN_PLIST" 2>/dev/null || true
launchctl bootout "gui/$(id -u)" "$POWER_PLIST" 2>/dev/null || true
sleep 1
rm -f /tmp/screenbar-skip-shutdown
launchctl bootstrap "gui/$(id -u)" "$CIRCADIAN_PLIST"
launchctl bootstrap "gui/$(id -u)" "$POWER_PLIST"

echo "==> [4/4] Done!"
echo "Next step: Open Raycast -> Settings -> Extensions -> Script Commands -> Add Directories:"
echo "  ${REPO_DIR}"
