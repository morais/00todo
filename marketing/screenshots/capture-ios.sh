#!/usr/bin/env bash
# Reproducible, app-only iPhone and iPad screenshot capture. No Apple login,
# account data, widget layout, or distribution signing is used.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS="$ROOT/ios"
DERIVED="$IOS/build/ScreenshotDerivedData"
RAW="$ROOT/artifacts/screenshots/raw"
MODE="${1:-all}"
if [[ "$MODE" != all && "$MODE" != iphone && "$MODE" != ipad ]]; then
  echo "usage: $0 [all|iphone|ipad]" >&2
  exit 2
fi

if [[ -f "$IOS/project.yml" ]]; then
  xcodegen generate --spec "$IOS/project.yml" >/dev/null
else
  xcodegen generate --spec "$IOS/project.yml.sample" >/dev/null
fi

# The compile flag and launch argument are both required to enable the
# screenshot-only fixture. This code is absent from normal TestFlight builds.
xcodebuild build-for-testing \
  -project "$IOS/ZeroZeroTodo.xcodeproj" \
  -scheme ZeroZeroTodoScreenshots \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG TODO_SCREENSHOTS' \
  -quiet

XCTESTRUN="$DERIVED/Build/Products/ZeroZeroTodoScreenshots_iphonesimulator27.0-arm64.xctestrun"
if [[ ! -f "$XCTESTRUN" ]]; then
  echo "missing screenshot xctestrun: $XCTESTRUN" >&2
  exit 1
fi

capture() {
  local set="$1" device="$2" width="$3" height="$4"
  local work result
  work="$(mktemp -d "/private/tmp/00todo-capture-${set}-XXXXXXXX")"
  result="$work/capture.xcresult"

  if ! xcrun simctl list devices | grep -F "$device (" | grep -q '(Booted)'; then
    xcrun simctl boot "$device"
  fi
  xcrun simctl bootstatus "$device" -b >/dev/null
  xcrun simctl status_bar "$device" override \
    --time '9:41' --wifiBars 3 --batteryState charged --batteryLevel 100

  echo "→ capturing $set on $device"
  xcodebuild test-without-building \
    -xctestrun "$XCTESTRUN" \
    -destination "platform=iOS Simulator,name=$device" \
    -resultBundlePath "$result" \
    -only-testing:ZeroZeroTodoScreenshots/ScreenshotTests/testCaptureAppScreenshots \
    -parallel-testing-enabled NO \
    -collect-test-diagnostics never \
    -quiet

  xcrun xcresulttool export attachments --path "$result" --output-path "$work/attachments" >/dev/null
  python3 - "$work/attachments" "$RAW/$set" "$device" "$width" "$height" <<'PY'
import datetime
import hashlib
import json
import pathlib
import re
import shutil
import struct
import sys

source, destination, device, width, height = sys.argv[1:]
source = pathlib.Path(source)
destination = pathlib.Path(destination)
expected = {"01-available.png", "02-upcoming.png", "03-project.png"}
records = json.loads((source / "manifest.json").read_text())
attachments = [entry for record in records for entry in record.get("attachments", [])]
found = {}
for entry in attachments:
    name = re.sub(r"_\d+_[0-9A-Fa-f-]{36}(\.png)$", r"\1", entry["suggestedHumanReadableName"])
    if name in expected:
        if name in found:
            raise SystemExit(f"duplicate capture: {name}")
        found[name] = source / entry["exportedFileName"]
if set(found) != expected:
    raise SystemExit(f"missing captures: {sorted(expected - set(found))}")
destination.mkdir(parents=True, exist_ok=True)
checksums = {}
for name, path in sorted(found.items()):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"not a PNG: {name}")
    size = struct.unpack(">II", data[16:24])
    if size != (int(width), int(height)):
        raise SystemExit(f"unexpected {name} size: {size}")
    shutil.copy2(path, destination / name)
    checksums[name] = hashlib.sha256(data).hexdigest()
    print(f"  {destination / name}")
manifest = {
    "capturedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "device": device,
    "dimensions": [int(width), int(height)],
    "fixture": "TODO_SCREENSHOTS --screenshot-demo",
    "files": checksums,
}
(destination / ".capture-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
  xcrun simctl status_bar "$device" clear
}

if [[ "$MODE" == all || "$MODE" == iphone ]]; then
  capture iphone-6.3 'iPhone 17 Pro' 1206 2622
fi
if [[ "$MODE" == all || "$MODE" == ipad ]]; then
  capture ipad 'iPad Pro 13-inch (M4) iOS 27' 2064 2752
fi

python3 "$ROOT/marketing/screenshots/generate-promotional.py" --set "$MODE"
