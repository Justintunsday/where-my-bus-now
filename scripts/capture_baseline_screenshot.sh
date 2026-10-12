#!/bin/bash
set -euo pipefail
device=$(cat "$RUNNER_TEMP/bus-simulator-id")
container=$(xcrun simctl get_app_container "$device" app.hkbus.swiftui data)
cp "$container/tmp/bus-snapshot-db.json" "$RUNNER_TEMP/baseline-db.json"
cp "$container/tmp/bus-snapshot-bookmarks.json" "$RUNNER_TEMP/baseline-bookmarks.json"
git fetch origin "${GITHUB_BASE_REF:-main}" --depth=1
mkdir -p "$RUNNER_TEMP/bus-before"
git archive FETCH_HEAD | tar -x -C "$RUNNER_TEMP/bus-before"
xcodebuild -project "$RUNNER_TEMP/bus-before/HKBusETA.xcodeproj" -scheme HKBusETA \
  -configuration Debug -destination "platform=iOS Simulator,id=$device" \
  -derivedDataPath "$RUNNER_TEMP/BusBeforeDerived" CODE_SIGNING_ALLOWED=NO build > "$RUNNER_TEMP/bus-screenshots/baseline-build.log" 2>&1
xcrun simctl terminate "$device" app.hkbus.swiftui || true
xcrun simctl install "$device" "$RUNNER_TEMP/BusBeforeDerived/Build/Products/Debug-iphonesimulator/HKBusETA.app"
container=$(xcrun simctl get_app_container "$device" app.hkbus.swiftui data)
mkdir -p "$container/Library/Application Support/HKBusETA/hk"
cp "$RUNNER_TEMP/baseline-db.json" "$container/Library/Application Support/HKBusETA/hk/routeFareList.min.json"
cp "$RUNNER_TEMP/baseline-bookmarks.json" "$container/Library/Application Support/HKBusETA/bookmarks.json"
xcrun simctl ui "$device" appearance light
xcrun simctl launch "$device" app.hkbus.swiftui -AppleLanguages '(zh-Hant)'
sleep 5
xcrun simctl io "$device" screenshot "$RUNNER_TEMP/bus-screenshots/before-launch-search.png"
git rev-parse FETCH_HEAD > "$RUNNER_TEMP/bus-screenshots/baseline-commit.txt"
# Restore the PR app before navigation tests.
xcrun simctl terminate "$device" app.hkbus.swiftui || true
xcrun simctl install "$device" "$RUNNER_TEMP/BusDerived/Build/Products/Debug-iphonesimulator/HKBusETA.app"
