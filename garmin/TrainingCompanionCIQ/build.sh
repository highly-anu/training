#!/usr/bin/env bash
# Build the Training Companion Connect IQ app.
#
#   ./build.sh              -> build a runnable .prg for the simulator (default device)
#   ./build.sh --device     -> build a signed .iq / sideloadable .prg for a real watch
#   DEVICE=fenix943mm ./build.sh   -> override target device
#   ./build.sh --test       -> build the core's (:test) functions and run them in the open simulator
#   ./build.sh --release    -> the real app as a store upload (all devices): bin/TrainingCompanion.iq
#   ./build.sh --demo       -> the real app (same id and name, so it uploads as a new version) with the
#                              demo programmes (SOF, Kettlebell, Uphill) and no pairing. Writes bin/TrainingCompanionDemo.iq
#                              (store test upload, all devices) and the sideload .prg for $DEVICE.
#                              The real app's sources are untouched; demoProgrammes stays false there.
#
# Requires: the Connect IQ SDK and a developer key.
set -euo pipefail

# --- config (auto-detected; override via env) --------------------------------
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
DEVICE="${DEVICE:-fenix947mm}"     # also try fenix943mm

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/bin"
mkdir -p "$OUT"

# Use the native binary (no .bat on Mac/Linux)
if [ -f "$SDK/bin/monkeyc" ]; then
  MONKEYC="$SDK/bin/monkeyc"
else
  MONKEYC="$SDK/bin/monkeyc.bat"
fi

# --- preflight ---------------------------------------------------------------
[ -f "$MONKEYC" ] || { echo "ERROR: monkeyc not found at $MONKEYC (set CIQ_SDK)."; exit 1; }
[ -f "$KEY" ]     || { echo "ERROR: developer key not found at $KEY (set CIQ_KEY)."; exit 1; }

# --- build -------------------------------------------------------------------
if [ "${1:-}" == "--demo" ]; then
  # Staged beside this directory, so the jungle's ../core still resolves.
  STAGE="$(dirname "$HERE")/.demo-stage"
  rm -rf "$STAGE"; mkdir -p "$STAGE"
  cp -R "$HERE/source" "$HERE/resources" "$HERE/manifest.xml" "$HERE/monkey.jungle" "$STAGE/"
  perl -pi -e 's|(<property id="demoProgrammes" type="boolean">)false|${1}true|' "$STAGE/resources/properties/properties.xml"
  perl -pi -e 's|"stamp": "dev"|"stamp": "'"$(date +%H%M)"'"|' "$STAGE"/resources/jsonData/demo_*.json
  grep -q 'id="demoProgrammes" type="boolean">true' "$STAGE/resources/properties/properties.xml" \
    || { echo "ERROR: demoProgrammes not enabled"; exit 1; }
  echo "Building demo .iq (all devices) ..."
  "$MONKEYC" -e -o "$OUT/TrainingCompanionDemo.iq" -f "$STAGE/monkey.jungle" -y "$KEY" -r
  echo "Building demo sideload .prg for $DEVICE ..."
  "$MONKEYC" -o "$OUT/TrainingCompanionDemo-$DEVICE.prg" -f "$STAGE/monkey.jungle" -y "$KEY" -d "$DEVICE" -r
  rm -rf "$STAGE"
  echo "Built: $OUT/TrainingCompanionDemo.iq  and  $OUT/TrainingCompanionDemo-$DEVICE.prg"
  exit 0
fi

if [ "${1:-}" == "--test" ]; then
  # The core's (:test) functions (../core/test), run in the simulator.
  TJ="$HERE/.test.jungle"   # beside monkey.jungle, so ../core/test resolves
  printf 'base.sourcePath = $(base.sourcePath);../core/test\n' > "$TJ"
  echo "Building unit tests for $DEVICE ..."
  (cd "$HERE" && "$MONKEYC" --unit-test -o "$OUT/Tests-$DEVICE.prg" -f "monkey.jungle;$TJ" -y "$KEY" -d "$DEVICE")
  echo "Running (the simulator must be open: ./run-sim.sh) ..."
  rm -f "$TJ"
  "$SDK/bin/monkeydo" "$OUT/Tests-$DEVICE.prg" "$DEVICE" -t
  exit 0
fi

if [ "${1:-}" == "--release" ]; then
  grep -q 'id="demoProgrammes" type="boolean">false' "$HERE/resources/properties/properties.xml" \
    || { echo "ERROR: demoProgrammes must default to false in a release"; exit 1; }
  echo "Building release .iq (all devices) ..."
  "$MONKEYC" -e -o "$OUT/TrainingCompanion.iq" -f "$HERE/monkey.jungle" -y "$KEY" -r
  echo "Built: $OUT/TrainingCompanion.iq  (store upload)"
  exit 0
fi

if [ "${1:-}" == "--device" ]; then
  echo "Building sideloadable .prg for $DEVICE ..."
  "$MONKEYC" \
    -o "$OUT/TrainingCompanion-$DEVICE.prg" \
    -f "$HERE/monkey.jungle" \
    -y "$KEY" \
    -d "$DEVICE" \
    -r
  echo "Built: $OUT/TrainingCompanion-$DEVICE.prg  (copy to GARMIN/APPS/ on the watch)"
else
  echo "Building simulator .prg for $DEVICE ..."
  "$MONKEYC" \
    -o "$OUT/TrainingCompanion.prg" \
    -f "$HERE/monkey.jungle" \
    -y "$KEY" \
    -d "$DEVICE"
  echo "Built: $OUT/TrainingCompanion.prg   (run ./run-sim.sh)"
fi
