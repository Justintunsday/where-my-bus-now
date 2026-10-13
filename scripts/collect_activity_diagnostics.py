"""Bound optional simulator logging so diagnostics never block build evidence."""
import os
import pathlib
import subprocess

output = pathlib.Path(os.environ["RUNNER_TEMP"]) / "activity-rendering.log"
with output.open("w", encoding="utf-8") as log:
    try:
        result = subprocess.run(
            ["xcrun", "simctl", "spawn", "booted", "log", "show", "--last", "2m", "--style", "compact",
             "--predicate", '(subsystem CONTAINS[c] "activity") OR (process CONTAINS[c] "widget")'],
            stdout=log, stderr=subprocess.STDOUT, timeout=30, check=False,
        )
        if result.returncode:
            print(f"::warning::Optional ActivityKit diagnostics returned {result.returncode}; see activity-rendering.log")
    except subprocess.TimeoutExpired:
        log.write("\nDiagnostic capture reached its 30-second limit. Build and UI tests are separate required checks.\n")
        print("::warning::Optional ActivityKit diagnostics reached the 30-second limit")
print(f"Saved diagnostic output: {output.name}")
rendering = output.read_text(encoding="utf-8")
if "Errors.noType" in rendering and "BusArrival" in rendering:
    raise SystemExit("ActivityKit remote renderer failed to decode the bus activity view; see activity-rendering.log")
