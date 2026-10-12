"""Offline checks for localization coverage and extension configuration, no dependencies."""
import json
import pathlib
import plistlib
import re

root = pathlib.Path(__file__).resolve().parents[1]
catalog = json.loads((root / "HKBusETA/Resources/Localizable.xcstrings").read_text(encoding="utf-8"))
keys = set()
for file in (root / "HKBusETA").rglob("*.swift"):
    keys.update(re.findall(r'L10n\.t\("([^"\\]+)"\)', file.read_text(encoding="utf-8")))
missing = keys - catalog["strings"].keys()
assert not missing, f"Missing UI strings: {sorted(missing)}"
for key in keys:
    localized = catalog["strings"][key]["localizations"]
    assert {"en", "zh-Hant", "zh-Hans"} <= localized.keys(), key
host = plistlib.loads((root / "HKBusETA/Info.plist").read_bytes())
assert host["NSSupportsLiveActivities"] is True
assert "busnow" in host["CFBundleURLTypes"][0]["CFBundleURLSchemes"]
widget = plistlib.loads((root / "BusArrivalWidget/Info.plist").read_bytes())
assert widget["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.widgetkit-extension"
for file in (root / "BusArrivalWidget").glob("*.swift"):
    source = file.read_text(encoding="utf-8")
    assert "URLSession" not in source and "CLLocationManager" not in source
print(f"PASS: {len(keys)} literal UI keys in three languages; host/extension plists; no extension networking")
