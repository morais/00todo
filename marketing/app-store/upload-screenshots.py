#!/usr/bin/env python3
"""Upload verified 00Todo promo captures to the iOS 1.0 App Store listing.

Uses the same external ASC_KEY_PATH / ~/.appstoreconnect credentials as the
TestFlight helper. Never stores signed upload URLs or credentials in the repo.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import runpy
import struct
import urllib.request


ROOT = Path(__file__).resolve().parents[2]
SCREENSHOTS = ROOT / "artifacts/screenshots/promotional"
API = runpy.run_path(str(ROOT / "ios/scripts/assign-testflight.py"))
SETS = {
    "iphone-6.9": ((1320, 2868), "APP_IPHONE_67"),
    "ipad": ((2064, 2752), "APP_IPAD_PRO_3GEN_129"),
}
NAMES = ("01-available.png", "02-upcoming.png", "03-project.png")


def api(method: str, path: str, body=None):
    status, result = API["request"](method, path, body)
    API["require_ok"](status, result, method + " " + path)
    return result


def one(items: list, label: str):
    if len(items) != 1:
        raise SystemExit(f"Expected one {label}; found {len(items)}")
    return items[0]


def source_files(device_set: str) -> list[Path]:
    expected_size, _ = SETS[device_set]
    directory = SCREENSHOTS / device_set
    manifest = json.loads((directory / ".composition-manifest.json").read_text())
    if manifest["deviceSet"] != device_set or set(manifest["files"]) != set(NAMES):
        raise SystemExit(f"Incomplete composition manifest: {directory}")
    files = []
    for name in NAMES:
        path = directory / name
        content = path.read_bytes()
        if hashlib.sha256(content).hexdigest() != manifest["files"][name]["sha256"]:
            raise SystemExit(f"Composition checksum mismatch: {path}")
        if content[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", content[16:24]) != expected_size:
            raise SystemExit(f"Unexpected PNG size: {path}")
        if content[25] != 2:  # PNG color type 2 = RGB, no alpha channel.
            raise SystemExit(f"PNG must be RGB without an alpha channel: {path}")
        files.append(path)
    return files


def screenshot_set(localization_id: str, display_type: str) -> str:
    path = f"/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets"
    sets = api("GET", path)["data"]
    matches = [item for item in sets if item["attributes"]["screenshotDisplayType"] == display_type]
    if matches:
        return one(matches, display_type)["id"]
    body = {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display_type},
                     "relationships": {"appStoreVersionLocalization": {"data": {
                         "type": "appStoreVersionLocalizations", "id": localization_id}}}}}
    result = api("POST", "/v1/appScreenshotSets", body)
    print(f"Created screenshot set {display_type}")
    return result["data"]["id"]


def upload(path: Path, set_id: str, existing: list[dict]) -> str:
    content = path.read_bytes()
    checksum = hashlib.md5(content).hexdigest()
    matches = [item for item in existing if item["attributes"].get("fileName") == path.name]
    for item in matches:
        attributes = item["attributes"]
        if attributes.get("sourceFileChecksum", "").lower() == checksum:
            print(f"Already uploaded {path.name}")
            return item["id"]
    if matches:
        raise SystemExit(f"Existing {path.name} differs; inspect it before replacing screenshots")

    body = {"data": {"type": "appScreenshots", "attributes": {
        "fileName": path.name, "fileSize": len(content)}, "relationships": {
        "appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}}
    reservation = api("POST", "/v1/appScreenshots", body)["data"]
    screenshot_id = reservation["id"]
    operations = reservation["attributes"]["uploadOperations"]
    if not operations:
        raise SystemExit(f"No upload operations for {path.name}")
    for operation in operations:
        headers = {item["name"]: item["value"] for item in operation["requestHeaders"]}
        offset, length = operation["offset"], operation["length"]
        request = urllib.request.Request(operation["url"], data=content[offset:offset + length],
                                         method=operation["method"], headers=headers)
        with urllib.request.urlopen(request, timeout=120) as response:
            if response.status < 200 or response.status >= 300:
                raise SystemExit(f"Upload failed for {path.name}: HTTP {response.status}")
    commit = {"data": {"type": "appScreenshots", "id": screenshot_id,
                       "attributes": {"uploaded": True, "sourceFileChecksum": checksum}}}
    api("PATCH", f"/v1/appScreenshots/{screenshot_id}", commit)
    print(f"Uploaded {path.name} ({len(content)} bytes)")
    return screenshot_id


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-id", required=True)
    parser.add_argument("--version", default="1.0")
    args = parser.parse_args()
    versions = api("GET", f"/v1/apps/{args.app_id}/appStoreVersions?limit=20")["data"]
    version = one([item for item in versions if item["attributes"]["versionString"] == args.version
                   and item["attributes"]["platform"] == "IOS"], f"iOS {args.version} version")
    localizations = api("GET", f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]
    localization = one([item for item in localizations if item["attributes"]["locale"] == "en-US"],
                       "en-US localization")
    for device_set, (_, display_type) in SETS.items():
        files = source_files(device_set)
        set_id = screenshot_set(localization["id"], display_type)
        existing = api("GET", f"/v1/appScreenshotSets/{set_id}/appScreenshots")["data"]
        for path in files:
            upload(path, set_id, existing)
        result = api("GET", f"/v1/appScreenshotSets/{set_id}/appScreenshots")["data"]
        print(f"{display_type}: {len(result)} screenshots visible in App Store Connect")


if __name__ == "__main__":
    main()
