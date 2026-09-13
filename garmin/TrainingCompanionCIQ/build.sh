#!/usr/bin/env bash
# Build the Training Companion Connect IQ app.
#
#   ./build.sh              -> build a runnable .prg for the simulator (default device)
#   ./build.sh --device     -> build a signed .iq / sideloadable .prg for a real watch
#   DEVICE=fenix943mm ./build.sh   -> override target device
#
# Requires: a JDK on PATH (java), the Connect IQ SDK, and a developer key.
set -euo pipefail

# --- config (auto-detected; override via env) --------------------------------
SDK="${CIQ_SDK:-$HOME/AppData/Roaming/Garmin/ConnectIQ/Sdks/connectiq-sdk-win-9.2.0-2026-06-09-92a1605b2}"
KEY="${CIQ_KEY:-$HOME/.garmin-keys/developer_key}"
DEVICE="${DEVICE:-fenix947mm}"     # also try fenix943mm

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/bin"
mkdir -p "$OUT"

MONKEYC="$SDK/bin/monkeyc.bat"

# --- preflight ---------------------------------------------------------------
command -v java >/dev/null 2>&1 || { echo "ERROR: java not found on PATH. Install a JDK (e.g. Temurin 17) first."; exit 1; }
[ -f "$MONKEYC" ] || { echo "ERROR: monkeyc not found at $MONKEYC (set CIQ_SDK)."; exit 1; }
[ -f "$KEY" ]     || { echo "ERROR: developer key not found at $KEY (set CIQ_KEY)."; exit 1; }

# --- build -------------------------------------------------------------------
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
