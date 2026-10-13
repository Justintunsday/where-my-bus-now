#!/bin/bash
set -euo pipefail
kind="${1:-phone}"
xcrun simctl list devices available --json > "$RUNNER_TEMP/sim-devices.json"
device=$(python3 - "$RUNNER_TEMP/sim-devices.json" "$kind" "${BUS_IOS_MAJOR:-26}" <<'PY'
import json,sys
kind='iPad' if sys.argv[2]=='ipad' else 'iPhone'
major=sys.argv[3]
candidates=[(runtime,d) for runtime,ds in json.load(open(sys.argv[1]))['devices'].items()
            if f'iOS-{major}-' in runtime for d in ds if kind in d['name']]
assert candidates, f'No iOS {major} {kind} runtime: cannot substitute another OS for visual evidence'
# Choose an actual Dynamic Island iPhone, not an alphabetically earlier 16e.
# Keep iPad mini for a useful narrow regular-width canvas.
preferred=['iPhone 17','iPhone 16','iPhone 15 Pro','iPhone 17 Pro']
candidates.sort(key=lambda x: ('iOS-26' not in x[0],
    ('mini' not in x[1]['name']) if kind=='iPad' else (preferred.index(x[1]['name']) if x[1]['name'] in preferred else 99),
    'Max' in x[1]['name'], x[1]['name']))
print(candidates[0][1]['udid'])
PY
)
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
xcrun simctl status_bar "$device" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl install "$device" "$RUNNER_TEMP/BusDerived/Build/Products/Debug-iphonesimulator/HKBusETA.app"
printf '%s\n' "$device" > "$RUNNER_TEMP/bus-simulator-id"
