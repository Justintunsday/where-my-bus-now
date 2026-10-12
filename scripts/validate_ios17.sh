#!/bin/bash
set -euo pipefail
source scripts/snapshot_helpers.sh
output="$RUNNER_TEMP/ios17-screenshots"
mkdir -p "$output"
xcrun simctl list runtimes available --json > "$output/runtimes.json"
runtime=$(python3 - "$output/runtimes.json" <<'PY'
import json,sys
runtimes=[r for r in json.load(open(sys.argv[1]))['runtimes'] if r['isAvailable'] and r['version'].startswith('17.') and 'iOS' in r['name']]
assert runtimes, 'An actual iOS 17 runtime is required; compile-only is not a passing runtime check'
print(runtimes[-1]['identifier'])
PY
)
device=$(xcrun simctl create 'Transit iOS 17' com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro "$runtime")
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
xcodebuild build -project HKBusETA.xcodeproj -scheme HKBusETA -configuration Debug \
  -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$RUNNER_TEMP/BusDerived17" CODE_SIGNING_ALLOWED=NO
xcrun simctl install "$device" "$RUNNER_TEMP/BusDerived17/Build/Products/Debug-iphonesimulator/HKBusETA.app"
for screen in home route eta activity; do
  capture_transit_screen "$device" "$screen" "$output/$screen-ios17.png"
done
xcodebuild test -project HKBusETA.xcodeproj -scheme HKBusETA -configuration Debug \
  -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$RUNNER_TEMP/BusDerived17" \
  -resultBundlePath "$RUNNER_TEMP/iOS17Tests.xcresult" -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
