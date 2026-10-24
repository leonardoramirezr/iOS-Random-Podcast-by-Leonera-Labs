#!/usr/bin/env python3
"""Check that every bundle inside an IPA carries an Ad Hoc provisioning profile.

Prints the number of devices in each profile and writes a summary of the main app
that make_build_page.py uses for the manifest and build.json.
Standard library only. Uses `security cms` on macOS and `openssl cms` elsewhere.
"""

from __future__ import annotations

import argparse
import json
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

PROFILE_NAME = "embedded.mobileprovision"


def fail(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)
    sys.exit(1)


def decode_profile(data: bytes) -> dict:
    """Strip the CMS envelope of a provisioning profile and parse the property list inside."""
    with tempfile.NamedTemporaryFile(suffix=".mobileprovision") as handle:
        handle.write(data)
        handle.flush()
        if shutil.which("security"):
            command = ["security", "cms", "-D", "-i", handle.name]
        else:
            command = ["openssl", "cms", "-verify", "-inform", "DER", "-noverify", "-in", handle.name]
        output = subprocess.run(command, capture_output=True, check=True).stdout
    return plistlib.loads(output)


def check_adhoc(profile: dict, bundle_id: str, label: str) -> int:
    """Fail unless the profile is an Ad Hoc profile for this bundle. Returns the device count."""
    devices = profile.get("ProvisionedDevices") or []
    if not devices:
        fail(f"{label}: the profile has no ProvisionedDevices, so it is not Ad Hoc")
    if profile.get("ProvisionsAllDevices"):
        fail(f"{label}: the profile is an Enterprise profile, not Ad Hoc")

    entitlements = profile.get("Entitlements", {})
    if entitlements.get("get-task-allow"):
        fail(f"{label}: the profile is a development profile (get-task-allow is true)")
    app_identifier = entitlements.get("application-identifier", "")
    if not app_identifier.endswith("." + bundle_id):
        fail(f"{label}: the profile is for {app_identifier}, not for {bundle_id}")

    print(f"{label}: Ad Hoc profile '{profile.get('Name')}' with {len(devices)} device(s)")
    return len(devices)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--summary", required=True, type=Path)
    args = parser.parse_args()

    with zipfile.ZipFile(args.ipa) as archive:
        names = archive.namelist()
        app_info_paths = [
            name for name in names
            if name.startswith("Payload/") and name.endswith(".app/Info.plist") and name.count("/") == 2
        ]
        if len(app_info_paths) != 1:
            fail(f"Expected exactly one app bundle in the IPA, found {len(app_info_paths)}")

        app_info = plistlib.loads(archive.read(app_info_paths[0]))
        if app_info.get("CFBundleIdentifier") != args.bundle_id:
            fail(f"The app bundle identifier is {app_info.get('CFBundleIdentifier')}, expected {args.bundle_id}")

        profile_paths = [name for name in names if name.endswith("/" + PROFILE_NAME)]
        if not profile_paths:
            fail("The IPA has no embedded.mobileprovision")

        main_profile = None
        main_devices = 0
        for profile_path in profile_paths:
            bundle_dir = profile_path[: -len("/" + PROFILE_NAME)]
            bundle_info = plistlib.loads(archive.read(f"{bundle_dir}/Info.plist"))
            profile = decode_profile(archive.read(profile_path))
            devices = check_adhoc(profile, bundle_info["CFBundleIdentifier"], bundle_dir)
            if bundle_dir == app_info_paths[0][: -len("/Info.plist")]:
                main_profile, main_devices = profile, devices

    if main_profile is None:
        fail("The main app bundle has no embedded.mobileprovision")

    summary = {
        "bundleId": args.bundle_id,
        "displayName": app_info.get("CFBundleDisplayName") or app_info.get("CFBundleName"),
        "shortVersion": app_info.get("CFBundleShortVersionString"),
        "buildNumber": app_info.get("CFBundleVersion"),
        "deviceCount": main_devices,
        "profileName": main_profile.get("Name"),
        "profileExpires": str(main_profile.get("ExpirationDate", "")),
    }
    args.summary.parent.mkdir(parents=True, exist_ok=True)
    args.summary.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"Ad Hoc IPA verified: {main_devices} device(s) are provisioned.")


if __name__ == "__main__":
    main()
