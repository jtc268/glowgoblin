#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="GlowGoblin"
EXECUTABLE="GlowGoblin"
BUNDLE_ID="app.glowgoblin"
APP_DIR="$HOME/Applications/$APP_NAME.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

cd "$ROOT"
swift build -c release

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cp ".build/release/$EXECUTABLE" "$APP_DIR/Contents/MacOS/$EXECUTABLE"
cp "Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
if [[ -f "Assets/GlowGoblin.icns" ]]; then
  cp "Assets/GlowGoblin.icns" "$APP_DIR/Contents/Resources/GlowGoblin.icns"
fi
chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE"
codesign --force --deep --sign - "$APP_DIR" >/dev/null

launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT" 2>/dev/null || true
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.husky.NaturalXDR.plist" 2>/dev/null || true
pkill -x "$EXECUTABLE" 2>/dev/null || true
pkill -x NaturalXDR 2>/dev/null || true
swift -e 'import CoreGraphics; CGDisplayRestoreColorSyncSettings()' 2>/dev/null || true

cat > "$LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$BUNDLE_ID</string>
	<key>ProgramArguments</key>
	<array>
		<string>$APP_DIR/Contents/MacOS/$EXECUTABLE</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>StandardOutPath</key>
	<string>$HOME/Library/Logs/GlowGoblin.out.log</string>
	<key>StandardErrorPath</key>
	<string>$HOME/Library/Logs/GlowGoblin.err.log</string>
</dict>
</plist>
PLIST

launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT"
launchctl kickstart -k "gui/$(id -u)/$BUNDLE_ID"

echo "$APP_NAME installed and running."
echo "Status: Scripts/status.sh"
echo "Uninstall: Scripts/uninstall.sh"
