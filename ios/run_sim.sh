#!/usr/bin/env bash
# Build the iOS app, install it on a booted simulator and relaunch it.
#
# Run this after every iOS change — a clean `xcodebuild` says the code compiles,
# not that the screen still works. Pass a path to also save a screenshot:
#
#   ./ios/run_sim.sh                      # build, install, launch
#   ./ios/run_sim.sh /tmp/after.png       # …and screenshot the result
#
# Override the device with SIM_DEVICE="iPhone 16e" when nothing is booted.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEME="TrainingCompanion"
BUNDLE_ID="haerdsoft.TrainingCompanion"
SIM_DEVICE="${SIM_DEVICE:-iPhone 17 Pro}"
SHOT="${1:-}"

# An already-booted iOS simulator, if there is one (ignore booted watchOS sims).
udid="$(xcrun simctl list devices booted -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
print(next((d["udid"] for rt, ds in devices.items() if "iOS" in rt for d in ds), ""))' 2>/dev/null || true)"

if [ -z "$udid" ]; then
    echo "No simulator booted — booting $SIM_DEVICE"
    udid="$(xcrun simctl list devices available -j | SIM_DEVICE="$SIM_DEVICE" python3 -c '
import json, os, sys
want = os.environ["SIM_DEVICE"]
devices = json.load(sys.stdin)["devices"]
print(next(d["udid"] for rt, ds in devices.items() if "iOS" in rt for d in ds if d["name"] == want))')"
    xcrun simctl boot "$udid"
fi

echo "Building for $udid"
xcodebuild -project "$PROJECT_DIR/$SCHEME.xcodeproj" -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$udid" -quiet build

app="$(xcodebuild -project "$PROJECT_DIR/$SCHEME.xcodeproj" -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$udid" -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')/$SCHEME.app"

xcrun simctl install "$udid" "$app"
xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl launch "$udid" "$BUNDLE_ID"
open -a Simulator

if [ -n "$SHOT" ]; then
    sleep 3
    xcrun simctl io "$udid" screenshot "$SHOT"
    echo "Screenshot: $SHOT"
fi
