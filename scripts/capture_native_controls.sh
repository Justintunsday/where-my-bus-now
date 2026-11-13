#!/bin/bash
set -euo pipefail
source scripts/snapshot_helpers.sh
device=$(cat "$RUNNER_TEMP/bus-simulator-id")
output="$RUNNER_TEMP/native-controls"
mkdir -p "$output"
xcrun simctl list runtimes available --json > "$output/runtimes.json"
xcrun simctl ui "$device" content_size large
xcrun simctl ui "$device" appearance light
for screen in home eta route stop search saved nearby home-tracking-eal; do
  capture_transit_screen "$device" "$screen" "$output/$screen-light.png"
done
xcrun simctl ui "$device" appearance dark
for screen in home eta stop home-tracking-eal; do
  capture_transit_screen "$device" "$screen" "$output/$screen-dark.png"
done
xcrun simctl ui "$device" content_size accessibility-extra-extra-extra-large
for screen in home eta home-tracking-eal; do
  capture_transit_screen "$device" "$screen" "$output/$screen-accessibility.png" --reduce-effects
done
xcrun simctl ui "$device" content_size large
xcrun simctl ui "$device" appearance light
