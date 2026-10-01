#!/usr/bin/env python3
"""Assign one processed 00Todo build to an existing internal TestFlight group.

Reads the App Store Connect API key and issuer ID from ~/.appstoreconnect.
Pass --app-id, --group-id, and --build explicitly; no account IDs are committed.
"""

import argparse
import base64
import glob
import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def der_to_raw(der):
    index = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    parts = []
    for _ in range(2):
        length = der[index + 1]
        parts.append(der[index + 2:index + 2 + length].lstrip(b"\0").rjust(32, b"\0"))
        index += 2 + length
    return b"".join(parts)


def authorization():
    credential_root = pathlib.Path.home() / ".appstoreconnect"
    candidates = glob.glob(str(credential_root / "private_keys" / "AuthKey_*.p8"))
    configured_key = os.environ.get("ASC_KEY_PATH")
    if not configured_key and len(candidates) != 1:
        sys.exit("Set ASC_KEY_PATH to the App Store Connect API key (the folder has multiple keys)")
    key = pathlib.Path(configured_key or candidates[0])
    issuer_path = credential_root / "issuer_id"
    if not key.is_file() or not issuer_path.is_file():
        sys.exit("App Store Connect API credentials are missing")
    key_id = os.environ.get("ASC_KEY_ID", key.stem.removeprefix("AuthKey_"))
    issuer_id = os.environ.get("ASC_ISSUER_ID", issuer_path.read_text().strip())
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    payload = b64url(json.dumps({"iss": issuer_id, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}).encode())
    signing_input = header + b"." + payload
    signature_der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(key)],
                                   input=signing_input, capture_output=True, check=True).stdout
    return (signing_input + b"." + b64url(der_to_raw(signature_der))).decode()


def request(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + authorization(),
                                          "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as response:
            return response.status, json.load(response) if response.status != 204 else {}
    except urllib.error.HTTPError as error:
        raw = error.read().decode()
        try:
            detail = json.loads(raw)
        except ValueError:
            detail = {"error": raw}
        return error.code, detail


def require_ok(status, result, action):
    if status < 200 or status >= 300:
        detail = "; ".join(item.get("detail", "") for item in result.get("errors", []))
        sys.exit(f"{action} failed ({status}): {detail or result}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-id", required=True)
    parser.add_argument("--group-id", required=True)
    parser.add_argument("--build", required=True)
    args = parser.parse_args()
    # App Store Connect's filter[version] selects the marketing version (for
    # example 1.0), not the CFBundleVersion build number supplied here.
    query = urllib.parse.urlencode({"filter[app]": args.app_id, "sort": "-uploadedDate",
                                    "limit": "200"})
    status, result = request("GET", "/v1/builds?" + query)
    require_ok(status, result, "Finding build")
    matches = [build for build in result.get("data", [])
               if build["attributes"]["version"] == args.build]
    if len(matches) != 1:
        sys.exit(f"Expected one App Store Connect build {args.build}, found {len(matches)}; it may still be processing")
    build = matches[0]
    state = build["attributes"]["processingState"]
    print(f"Build {args.build}: {state} ({build['id']})")
    if state != "VALID":
        sys.exit("Build is not yet ready for TestFlight assignment")
    group_path = f"/v1/betaGroups/{args.group_id}/relationships/builds"
    status, relationship = request("GET", group_path + "?limit=200")
    require_ok(status, relationship, "Reading beta group")
    if not any(item["id"] == build["id"] for item in relationship.get("data", [])):
        status, result = request("POST", group_path, {"data": [{"type": "builds", "id": build["id"]}]})
        require_ok(status, result, "Assigning build")
    status, relationship = request("GET", group_path + "?limit=200")
    require_ok(status, relationship, "Verifying beta group")
    if not any(item["id"] == build["id"] for item in relationship.get("data", [])):
        sys.exit("Build assignment was not visible on verification")
    print("Build is assigned to the internal TestFlight group")


if __name__ == "__main__":
    main()
