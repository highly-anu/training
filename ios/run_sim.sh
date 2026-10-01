#!/usr/bin/env bash
# Build the iOS app, install it on a booted simulator and relaunch it.
#
# Run this after every iOS change — a clean `xcodebuild` says the code compiles,
# not that the screen still works. Pass a path to also save a screenshot:
#
#   ./ios/run_sim.sh                      # build, install, launch
#   ./ios/run_sim.sh /tmp/after.png       # …and screenshot the result
#
# The simulator's copy points at production unless told otherwise. To see
# every screen with the local dev program (the Flask server on :8000, which
# needs no account), point it at the local API — the choice persists in the
# simulator's defaults until cleared — and open a section before the shot:
#
#   LOCAL_API=1 ./ios/run_sim.sh /tmp/today.png
#   LOCAL_API=1 ROUTE='trainingcompanion://analytics?section=program' ./ios/run_sim.sh /tmp/program.png
#   LOCAL_API=0 ./ios/run_sim.sh          # back to production
#
# Routes: today · program · analytics?section=program|overview|workouts|
# progress|recovery · profile (DeepLink.swift). Override the device with
# SIM_DEVICE="iPhone 16e" when nothing is booted.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEME="TrainingCompanion"
BUNDLE_ID="haerdsoft.TrainingCompanion"
SIM_DEVICE="${SIM_DEVICE:-iPhone 17 Pro}"
SHOT="${1:-}"
LOCAL_API="${LOCAL_API:-}"
ROUTE="${ROUTE:-}"
LOCAL_BASE_URL="${LOCAL_BASE_URL:-http://localhost:8000/api}"

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

# The API target lives in the app's defaults (APITarget.swift). LOCAL_API=1
# points it at the local server, LOCAL_API=0 clears the override; unset
# leaves whatever was chosen last.
case "$LOCAL_API" in
    1|true|yes)
        xcrun simctl spawn "$udid" defaults write "$BUNDLE_ID" apiBaseURLOverride "$LOCAL_BASE_URL"
        echo "API target: $LOCAL_BASE_URL" ;;
    0|false|no)
        xcrun simctl spawn "$udid" defaults delete "$BUNDLE_ID" apiBaseURLOverride >/dev/null 2>&1 || true
        echo "API target: production" ;;
esac

# A route is handed over in the launch environment (DeepLink.swift reads
# TC_ROUTE): opening the URL from outside would make iOS ask "Open in
# Training Companion?", and nothing can tap that.
if [ -n "$ROUTE" ]; then
    SIMCTL_CHILD_TC_ROUTE="$ROUTE" xcrun simctl launch "$udid" "$BUNDLE_ID"
    echo "Route: $ROUTE"
else
    xcrun simctl launch "$udid" "$BUNDLE_ID"
fi
open -a Simulator

if [ -n "$SHOT" ]; then
    sleep 3
    xcrun simctl io "$udid" screenshot "$SHOT"
    echo "Screenshot: $SHOT"
fi
