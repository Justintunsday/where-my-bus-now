#!/bin/bash
set -euo pipefail
set -x
source scripts/snapshot_helpers.sh
output="$RUNNER_TEMP/bus-screenshots"
mkdir -p "$output"
xcrun simctl list devices available --json > "$RUNNER_TEMP/sim-devices.json"
device=$(python3 - "$RUNNER_TEMP/sim-devices.json" <<'PY'
import json,sys
devices=json.load(open(sys.argv[1]))['devices']
candidates=[(runtime,d) for runtime,ds in devices.items() if 'iOS' in runtime for d in ds if 'iPhone' in d['name']]
assert candidates, 'No iOS simulator runtime installed'
candidates.sort(key=lambda x: ('iOS-26' in x[0], 'Pro' in x[1]['name']),reverse=True)
print(candidates[0][1]['udid'])
PY
)
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
xcrun simctl status_bar "$device" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl install "$device" "$RUNNER_TEMP/BusDerived/Build/Products/Debug-iphonesimulator/HKBusETA.app"
for appearance in light dark; do
  xcrun simctl ui "$device" appearance "$appearance"
  for screen in home search nearby saved route stop eta settings region empty error activity activity-stale; do
    capture_transit_screen "$device" "$screen" "$output/$screen-$appearance.png"
  done
done
xcrun simctl ui "$device" content_size accessibility-extra-extra-extra-large
capture_transit_screen "$device" eta "$output/eta-accessibility-reduced.png" --reduce-effects
xcrun simctl ui "$device" content_size large
for language in en zhHans; do
  capture_transit_screen "$device" eta "$output/eta-$language.png" --snapshot-language "$language"
done
printf '%s\n' "$device" > "$RUNNER_TEMP/bus-simulator-id"
xcrun simctl shutdown "$device"
ipad=$(python3 - "$RUNNER_TEMP/sim-devices.json" <<'PY'
import json,sys
devices=json.load(open(sys.argv[1]))['devices']
candidates=[(runtime,d) for runtime,ds in devices.items() if 'iOS' in runtime for d in ds if 'iPad' in d['name']]
candidates.sort(key=lambda x: 'iOS-26' in x[0],reverse=True)
print(candidates[0][1]['udid'] if candidates else '')
PY
)
if [ -n "$ipad" ]; then
  xcrun simctl boot "$ipad" || true
  xcrun simctl bootstatus "$ipad" -b
  xcrun simctl install "$ipad" "$RUNNER_TEMP/BusDerived/Build/Products/Debug-iphonesimulator/HKBusETA.app"
  for screen in home route eta; do
    capture_transit_screen "$ipad" "$screen" "$output/$screen-ipad.png"
  done
  xcrun simctl shutdown "$ipad"
fi
xcrun simctl list devices available > "$output/runtime-inventory.txt"
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
