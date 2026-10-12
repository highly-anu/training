#!/usr/bin/env bash
# Archive the app for TestFlight, and upload it when an App Store Connect key is set.
#
#   ./ios/archive.sh                 # Release archive into ios/build/TrainingCompanion.xcarchive
#   ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=~/AuthKey_….p8 ./ios/archive.sh   # …and upload
#
# Every upload needs a build number App Store Connect has not seen, and the
# watch app and both widgets must carry the same one as the phone app. The
# project keeps CURRENT_PROJECT_VERSION at 1; this script overrides it for all
# targets with the commit count (BUILD_NUMBER= wins), so nothing is edited per
# release. The version shown to testers is MARKETING_VERSION in the project.
#
# Without the key the archive is left for Xcode: Window ▸ Organizer ▸
# Distribute App ▸ TestFlight & App Store.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEME="TrainingCompanion"
OUT="$PROJECT_DIR/build"
ARCHIVE="$OUT/TrainingCompanion.xcarchive"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$PROJECT_DIR" rev-list --count HEAD)}"

if [ -n "$(git -C "$PROJECT_DIR" status --porcelain -- .)" ]; then
    echo "warning: ios/ has uncommitted changes; build $BUILD_NUMBER will not match a commit" >&2
fi

auth=()
if [ -n "${ASC_KEY_ID:-}" ]; then
    : "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required with ASC_KEY_ID}"
    : "${ASC_KEY_PATH:?ASC_KEY_PATH is required with ASC_KEY_ID}"
    auth=(-authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"
          -authenticationKeyPath "$ASC_KEY_PATH")
fi

echo "Archiving $SCHEME, build $BUILD_NUMBER"
rm -rf "$ARCHIVE"
xcodebuild archive \
    -project "$PROJECT_DIR/TrainingCompanion.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates ${auth[@]+"${auth[@]}"} \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    -quiet

echo "Archive: $ARCHIVE"
if [ ${#auth[@]} -eq 0 ]; then
    echo "No ASC_KEY_ID set — upload from Xcode's Organizer (Distribute App ▸ TestFlight & App Store)."
    exit 0
fi

OPTIONS="$OUT/ExportOptions.plist"
cat > "$OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>upload</string>
    <key>signingStyle</key><string>automatic</string>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$OPTIONS" \
    -exportPath "$OUT/export" \
    -allowProvisioningUpdates ${auth[@]+"${auth[@]}"}
echo "Uploaded build $BUILD_NUMBER — it appears in App Store Connect ▸ TestFlight once processed."
