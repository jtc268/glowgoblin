#!/usr/bin/env bash
set -euo pipefail

APP_NAME="RollHDR"
EXECUTABLE="RollHDR"
BUNDLE_ID="app.pingpong.rollhdr"
APP_DIR="$HOME/Applications/$APP_NAME.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT" 2>/dev/null || true
pkill -x "$EXECUTABLE" 2>/dev/null || true
swift -e 'import CoreGraphics; CGDisplayRestoreColorSyncSettings()' 2>/dev/null || true
rm -f "$LAUNCH_AGENT"
rm -rf "$APP_DIR"

echo "$APP_NAME removed and ColorSync display tables restored."
