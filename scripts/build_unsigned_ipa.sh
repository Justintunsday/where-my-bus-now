#!/bin/bash
# Explicit manual preview path. Compile only; the full workflow owns runtime validation.
set -euo pipefail
archive="$RUNNER_TEMP/HKBusETA.xcarchive"
xcodebuild -project HKBusETA.xcodeproj -scheme HKBusETA -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive" \
  CODE_SIGNING_ALLOWED=NO LIVE_ACTIVITY_SERVER_URL="${LIVE_ACTIVITY_SERVER_URL:-}" archive
app="$archive/Products/Applications/HKBusETA.app"
test -d "$app/PlugIns/BusArrivalWidget.appex"
/usr/libexec/PlistBuddy -c 'Print NSSupportsLiveActivities' "$app/Info.plist" | grep true
mkdir -p "$RUNNER_TEMP/Payload"
cp -R "$app" "$RUNNER_TEMP/Payload/"
cd "$RUNNER_TEMP"
zip -qry HKBusETA-unsigned.ipa Payload
python3 "$GITHUB_WORKSPACE/scripts/verify_unsigned_ipa.py" HKBusETA-unsigned.ipa
ls -lh HKBusETA-unsigned.ipa
