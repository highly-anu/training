#!/usr/bin/env bash
# Run the iOS unit tests (TrainingCompanionTests) on a booted simulator.
#
#   ./ios/run_tests.sh                        # the whole bundle
#   ./ios/run_tests.sh ProgramCodableTests    # one class, or Class/testMethod
#
# Picks the booted iOS simulator the way run_sim.sh does, booting SIM_DEVICE
# (default "iPhone 17 Pro") when nothing is. The test bundle is hosted by the
# app, so this builds the app too; the watch app and widgets are built because
# the scheme lists them, not because the tests need them.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEME="TrainingCompanion"
TESTS="TrainingCompanionTests"
SIM_DEVICE="${SIM_DEVICE:-iPhone 17 Pro}"
ONLY="${1:-}"

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

target="$TESTS"
[ -n "$ONLY" ] && target="$TESTS/$ONLY"

echo "Testing $target on $udid"
log="$(mktemp -t xctest)"
trap 'rm -f "$log"' EXIT

# xcodebuild's own output is a compile log; keep the lines that say what happened.
xcodebuild test -project "$PROJECT_DIR/$SCHEME.xcodeproj" -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$udid" \
    -only-testing:"$target" >"$log" 2>&1 || true
grep -E 'error:|Test Case .* failed|Test Suite .*(failed|passed)|Executed|Restarting after|malloc: \*\*\*|\*\* TEST (SUCCEEDED|FAILED) \*\*' "$log" || true

# "Restarting after unexpected exit" means the host crashed mid-run and the
# totals span two launches; treat that as a failure even if the rerun passed.
if grep -q '\*\* TEST SUCCEEDED \*\*' "$log" && ! grep -q 'Restarting after unexpected exit' "$log"; then
    exit 0
fi
echo "Full log: $log"; trap - EXIT
exit 1
