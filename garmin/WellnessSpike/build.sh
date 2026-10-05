#!/usr/bin/env bash
# Build the Wellness Spike (a throwaway hardware probe — see README.md).
#
#   DEVICE=fenix947mm ./build.sh --device   release build to sideload -> bin/<device>/WSPIKE.prg
#   ./build.sh                              debug build for the simulator -> bin/WSPIKE.prg (nothing is launched)
#   ./build.sh --check [device ...]         compile with type checking level 2 for a spread of devices
#   ./build.sh --list [text]                devices the manifest lists: id, name, API level, background memory, part numbers
#
# The file keeps the name WSPIKE.prg on every path, so what you copy to GARMIN/APPS/ is the same
# file whichever build made it.
# Requires the Connect IQ SDK and a developer key; detection matches ../TrainingCompanionCIQ/build.sh.
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

KEY="${CIQ_KEY:-$HOME/.garmin-keys/developer_key}"
DEVICE="${DEVICE:-fenix947mm}"
# One round and one AMOLED/MIP watch of each generation, the oldest API the manifest allows with
# the smaller (32 KB) background budget, a touch device and a rectangular one.
CHECK_SPREAD="fenix947mm fenix943mm fenix9prosolar47mm fenix7 fenix6 fr245 venu edge540 instinct3solar45mm"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/bin"

if [ -f "$SDK/bin/monkeyc" ]; then
  MONKEYC="$SDK/bin/monkeyc"
else
  MONKEYC="$SDK/bin/monkeyc.bat"
fi

if [ "${1:-}" == "--list" ]; then
  python3 "$HERE/tools/gen_products.py" --list 2>&1 | grep -i -- "${2:-.}"
  exit 0
fi

[ -f "$MONKEYC" ] || { echo "ERROR: monkeyc not found at $MONKEYC (set CIQ_SDK)."; exit 1; }
[ -f "$KEY" ]     || { echo "ERROR: developer key not found at $KEY (set CIQ_KEY)."; exit 1; }

case "${1:-}" in
  --device)
    mkdir -p "$OUT/$DEVICE"
    echo "Building the sideloadable release for $DEVICE ..."
    "$MONKEYC" -o "$OUT/$DEVICE/WSPIKE.prg" -f "$HERE/monkey.jungle" -y "$KEY" -d "$DEVICE" -r -w
    echo "Built: $OUT/$DEVICE/WSPIKE.prg   (copy to GARMIN/APPS/ on the watch)"
    ;;
  --check)
    shift
    devices="${*:-$CHECK_SPREAD}"
    mkdir -p "$OUT/check"
    failed=0
    for d in $devices; do
      echo "== $d"
      if ! "$MONKEYC" -o "$OUT/check/WSPIKE-$d.prg" -f "$HERE/monkey.jungle" -y "$KEY" -d "$d" -w -l 2; then
        failed=$((failed + 1))
      fi
    done
    [ "$failed" -eq 0 ] || { echo "FAILED on $failed device(s)"; exit 1; }
    echo "All compiled."
    ;;
  "")
    mkdir -p "$OUT"
    echo "Building the simulator .prg for $DEVICE ..."
    "$MONKEYC" -o "$OUT/WSPIKE.prg" -f "$HERE/monkey.jungle" -y "$KEY" -d "$DEVICE" -w
    echo "Built: $OUT/WSPIKE.prg"
    ;;
  *)
    echo "usage: ./build.sh [--device | --check [device ...] | --list [text]]"; exit 2
    ;;
esac
