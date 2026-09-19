#!/usr/bin/env bash
# Launch the Connect IQ simulator and load the built app.
#
#   ./run-sim.sh                 -> build (if needed) + start sim + load on fenix947mm
#   DEVICE=fenix943mm ./run-sim.sh
#
# Leaves the simulator (ConnectIQ.app / connectiq) running; monkeydo pushes the .prg into it.
set -euo pipefail

SDK_MAC="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"
SDK_WIN="$HOME/AppData/Roaming/Garmin/ConnectIQ/Sdks/connectiq-sdk-win-9.2.0-2026-06-09-92a1605b2"

if [ -n "${CIQ_SDK:-}" ]; then
  SDK="$CIQ_SDK"
elif [ -d "$SDK_MAC" ]; then
  SDK="$SDK_MAC"
else
  SDK="$SDK_WIN"
fi

DEVICE="${DEVICE:-fenix947mm}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRG="$HERE/bin/TrainingCompanion.prg"

# Use native binaries on Mac
if [ -f "$SDK/bin/connectiq" ]; then
  CONNECTIQ="$SDK/bin/connectiq"
  MONKEYDO="$SDK/bin/monkeydo"
else
  CONNECTIQ="$SDK/bin/connectiq.bat"
  MONKEYDO="$SDK/bin/monkeydo.bat"
fi

[ -f "$PRG" ] || { echo "No build found — running build.sh first..."; "$HERE/build.sh"; }

echo "Starting Connect IQ simulator (leave this window; it stays open)..."
"$CONNECTIQ" &
sleep 4   # give the simulator UI time to come up

echo "Loading $PRG on $DEVICE ..."
"$MONKEYDO" "$PRG" "$DEVICE"
