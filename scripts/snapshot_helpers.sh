#!/bin/bash
# Debug fixtures signal first appearance; never deliver a blank launch frame as a UI screenshot.
capture_transit_screen() {
  local device="$1" screen="$2" destination="$3"
  shift 3
  local container
  container=$(xcrun simctl get_app_container "$device" app.hkbus.swiftui data)
  rm -f "$container/tmp/bus-snapshot-ready"
  xcrun simctl terminate "$device" app.hkbus.swiftui || true
  xcrun simctl launch "$device" app.hkbus.swiftui --ui-snapshot "$screen" "$@"
  python3 - "$container/tmp/bus-snapshot-ready" "$screen" <<'PY'
import pathlib,sys,time
marker=pathlib.Path(sys.argv[1])
deadline=time.monotonic()+45
while time.monotonic()<deadline:
    if marker.exists() and marker.read_text()==sys.argv[2]: break
    time.sleep(0.2)
else: raise SystemExit('Fixture did not render; refusing to capture a launch screen')
PY
  sleep 2
  xcrun simctl io "$device" screenshot "$destination"
}
