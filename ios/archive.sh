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
# release.
#
# The version testers see — "1.1.0 (383)" — is ios/VERSION, passed to every
# target as MARKETING_VERSION the same way, so the five targets cannot drift.
# MAJOR.MINOR.PATCH: minor for a batch of features, patch for a fixes-only
# build. The project's MARKETING_VERSION is kept equal to it for local builds;
# the script refuses to archive when they differ. Tag what you upload:
# ios-v<VERSION> (the script prints the command).
#
# Without the key the archive is left for Xcode: Window ▸ Organizer ▸
# Distribute App ▸ TestFlight & App Store.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEME="TrainingCompanion"
OUT="$PROJECT_DIR/build"
ARCHIVE="$OUT/TrainingCompanion.xcarchive"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$PROJECT_DIR" rev-list --count HEAD)}"
VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: ios/VERSION must be MAJOR.MINOR.PATCH, not '$VERSION'" >&2
    exit 1
fi
if grep "MARKETING_VERSION = " "$PROJECT_DIR/TrainingCompanion.xcodeproj/project.pbxproj" \
        | grep -qv "MARKETING_VERSION = $VERSION;"; then
    echo "error: the project's MARKETING_VERSION differs from ios/VERSION ($VERSION); set every target to it" >&2
    exit 1
fi

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

echo "Archiving $SCHEME $VERSION ($BUILD_NUMBER)"
rm -rf "$ARCHIVE"
xcodebuild archive \
    -project "$PROJECT_DIR/TrainingCompanion.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates ${auth[@]+"${auth[@]}"} \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    MARKETING_VERSION="$VERSION" \
    -quiet

echo "Archive: $ARCHIVE — $VERSION ($BUILD_NUMBER)"
echo "After the upload, tag it: git tag ios-v$VERSION && git push origin ios-v$VERSION"
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
