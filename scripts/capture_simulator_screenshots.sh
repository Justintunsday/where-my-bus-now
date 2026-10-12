#!/bin/bash
set -euo pipefail
set -x
source scripts/snapshot_helpers.sh
kind="${1:-phone}"
output="$RUNNER_TEMP/bus-screenshots"
mkdir -p "$output"
bash scripts/prepare_simulator.sh "$kind"
device=$(cat "$RUNNER_TEMP/bus-simulator-id")
if [ "$kind" = ipad ]; then
  for screen in home route eta activity; do
    capture_transit_screen "$device" "$screen" "$output/$screen-ipad.png"
  done
else
  xcrun simctl ui "$device" appearance light
  for screen in home search nearby saved route stop eta settings region empty error activity activity-networkError activity-cancelled activity-long; do
    capture_transit_screen "$device" "$screen" "$output/$screen-light.png"
  done
  xcrun simctl ui "$device" appearance dark
  for screen in home route eta activity; do
    capture_transit_screen "$device" "$screen" "$output/$screen-dark.png"
  done
  capture_transit_screen "$device" activity "$output/activity-dimmed.png" --dimmed --reduce-effects
  xcrun simctl ui "$device" content_size accessibility-extra-extra-extra-large
  for screen in eta activity; do
    capture_transit_screen "$device" "$screen" "$output/$screen-accessibility-reduced.png" --reduce-effects
  done
  xcrun simctl ui "$device" content_size large
  xcrun simctl ui "$device" appearance light
  for language in en zhHans; do
    capture_transit_screen "$device" eta "$output/eta-$language.png" --snapshot-language "$language"
  done
fi
xcrun simctl list devices available > "$output/runtime-inventory.txt"
if [ "$kind" = ipad ]; then xcrun simctl shutdown "$device"; fi
