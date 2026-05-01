#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="app.pingpong.rollhdr"

echo "Process:"
pgrep -fl 'RollHDR|NaturalXDR|BrightIntosh' || true

echo
echo "LaunchAgent:"
launchctl print "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null | sed -n '1,35p' || echo "not loaded"

echo
echo "Display:"
swift -e 'import AppKit; for s in NSScreen.screens { print(s.localizedName, String(format: "potential=%.3f current=%.3f", s.maximumPotentialExtendedDynamicRangeColorComponentValue, s.maximumExtendedDynamicRangeColorComponentValue)) }'
swift -e 'import CoreGraphics; var count: UInt32 = 0; CGGetActiveDisplayList(0, nil, &count); var ids = [CGDirectDisplayID](repeating: 0, count: Int(count)); CGGetActiveDisplayList(count, &ids, &count); for id in ids { var r=[CGGammaValue](repeating:0,count:256), g=r, b=r; var samples: UInt32=0; _=CGGetDisplayTransferByTable(id, 256, &r, &g, &b, &samples); print("display=\(id) maxGamma=\(String(format: "%.3f", (r+g+b).max() ?? 0)) builtin=\(CGDisplayIsBuiltin(id))") }'
