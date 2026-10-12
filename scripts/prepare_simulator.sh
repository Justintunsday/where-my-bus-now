#!/bin/bash
set -euo pipefail
kind="${1:-phone}"
xcrun simctl list devices available --json > "$RUNNER_TEMP/sim-devices.json"
device=$(python3 - "$RUNNER_TEMP/sim-devices.json" "$kind" <<'PY'
import json,sys
kind='iPad' if sys.argv[2]=='ipad' else 'iPhone'
candidates=[(runtime,d) for runtime,ds in json.load(open(sys.argv[1]))['devices'].items()
            if 'iOS' in runtime for d in ds if kind in d['name']]
assert candidates, 'No compatible simulator runtime'
# Smaller native canvas also exercises compact route width. Avoid expensive Pro Max/13-inch boots.
candidates.sort(key=lambda x: ('iOS-26' not in x[0], 'mini' not in x[1]['name'] if kind=='iPad' else 'Pro' in x[1]['name'], x[1]['name']))
print(candidates[0][1]['udid'])
PY
)
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
xcrun simctl status_bar "$device" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl install "$device" "$RUNNER_TEMP/BusDerived/Build/Products/Debug-iphonesimulator/HKBusETA.app"
printf '%s\n' "$device" > "$RUNNER_TEMP/bus-simulator-id"
