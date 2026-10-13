"""Verify the packaged artifact, not just the archive directory. No dependencies."""
import json
import plistlib
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as ipa:
    names = set(ipa.namelist())
    host = "Payload/HKBusETA.app/"
    widget = host + "PlugIns/BusArrivalWidget.appex/"
    app_info = plistlib.loads(ipa.read(host + "Info.plist"))
    widget_info = plistlib.loads(ipa.read(widget + "Info.plist"))
    for base, info in [(host, app_info), (widget, widget_info)]:
        assert info["MinimumOSVersion"] == "17.0", (base, info.get("MinimumOSVersion"))
        executable = base + info["CFBundleExecutable"]
        assert executable in names and ipa.getinfo(executable).file_size > 0, executable
    assert app_info["NSSupportsLiveActivities"] is True
    assert app_info["CFBundleIdentifier"] == "app.hkbus.swiftui"
    assert widget_info["CFBundleIdentifier"] == "app.hkbus.swiftui.BusArrivalWidget"
    assert widget_info["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.widgetkit-extension"
    assert app_info["CFBundleShortVersionString"] == widget_info["CFBundleShortVersionString"]
    assert app_info["CFBundleVersion"] == widget_info["CFBundleVersion"]
    assert "busnow" in app_info["CFBundleURLTypes"][0]["CFBundleURLSchemes"]
    assert not any(n.endswith("embedded.mobileprovision") for n in names), "Expected an unsigned artifact"
    print(json.dumps({"verified": sys.argv[1], "minimumOS": "17.0",
                      "host": app_info["CFBundleIdentifier"], "embeddedExtension": widget_info["CFBundleIdentifier"],
                      "signing": "unsigned; requires signing before installation and APNs use"}, indent=2))
