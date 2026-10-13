#!/bin/bash
set -euo pipefail
source scripts/snapshot_helpers.sh
device=$(cat "$RUNNER_TEMP/bus-simulator-id")
baseline=d180c558d82583929d19cd1291c18b21be5558c7
git fetch origin "$baseline" --depth=1
mkdir -p "$RUNNER_TEMP/bus-before"
git archive "$baseline" | tar -x -C "$RUNNER_TEMP/bus-before"
xcodebuild -project "$RUNNER_TEMP/bus-before/HKBusETA.xcodeproj" -scheme HKBusETA \
  -configuration Debug -destination "platform=iOS Simulator,id=$device" \
  -derivedDataPath "$RUNNER_TEMP/BusBeforeDerived" CODE_SIGNING_ALLOWED=NO build > "$RUNNER_TEMP/bus-screenshots/baseline-build.log" 2>&1
xcrun simctl terminate "$device" app.hkbus.swiftui || true
xcrun simctl install "$device" "$RUNNER_TEMP/BusBeforeDerived/Build/Products/Debug-iphonesimulator/HKBusETA.app"
xcrun simctl ui "$device" appearance light
capture_transit_screen "$device" eta "$RUNNER_TEMP/bus-screenshots/before-route-eta.png"
printf '%s\n' "$baseline" > "$RUNNER_TEMP/bus-screenshots/baseline-commit.txt"
xcrun simctl terminate "$device" app.hkbus.swiftui || true
xcrun simctl install "$device" "$RUNNER_TEMP/BusDerived/Build/Products/Debug-iphonesimulator/HKBusETA.app"
