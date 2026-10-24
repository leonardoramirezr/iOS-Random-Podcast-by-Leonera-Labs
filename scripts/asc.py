#!/usr/bin/env python3
"""App Store Connect helper for the CI pipeline.

Uses only the Python standard library and the `openssl` CLI (for the ES256 signature).

Environment:
  ASC_KEY_ID, ASC_ISSUER_ID   Identifiers of the App Store Connect team API key.
  ASC_KEY_PATH                Path to the downloaded .p8 private key.

Commands:
  check                  Verify that the key works and that at least one iOS device is enabled.
  keychain-serials FILE  Save the serials of the "Apple Development" certificates in the keychain.
  revoke-new FILE        Revoke, through the API, the development certificates that were created
                         after the snapshot written to FILE.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API_BASE = "https://api.appstoreconnect.apple.com"


def fail(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)
    sys.exit(1)


def require_env(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        fail(f"Environment variable {name} is not set")
    return value


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def der_ecdsa_to_raw(der: bytes) -> bytes:
    """Convert a DER encoded ECDSA signature (SEQUENCE of two INTEGERs) to the raw r||s form that JWS needs."""
    if der[0] != 0x30:
        raise ValueError("signature is not a DER SEQUENCE")
    index = 2
    if der[1] & 0x80:
        index += der[1] & 0x7F
    values = []
    for _ in range(2):
        if der[index] != 0x02:
            raise ValueError("expected a DER INTEGER")
        length = der[index + 1]
        values.append(int.from_bytes(der[index + 2:index + 2 + length], "big"))
        index += 2 + length
    return b"".join(value.to_bytes(32, "big") for value in values)


def make_token() -> str:
    key_id = require_env("ASC_KEY_ID")
    issuer = require_env("ASC_ISSUER_ID")
    key_path = require_env("ASC_KEY_PATH")

    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    signing_input = (
        b64url(json.dumps(header, separators=(",", ":")).encode())
        + "."
        + b64url(json.dumps(payload, separators=(",", ":")).encode())
    )
    result = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input.encode(),
        capture_output=True,
        check=True,
    )
    return signing_input + "." + b64url(der_ecdsa_to_raw(result.stdout))


def request(method: str, url: str, token: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    http_request = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(http_request, timeout=60) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        fail(f"App Store Connect {method} {url} failed with HTTP {error.code}: {detail}")
    return {}


def list_all(path: str, token: str, query: dict) -> list:
    """Follow `links.next` until every page of a collection has been read."""
    url = API_BASE + path + "?" + urllib.parse.urlencode(query)
    items: list = []
    while url:
        page = request("GET", url, token)
        items.extend(page.get("data", []))
        url = page.get("links", {}).get("next")
    return items


def normalize_serial(value: str) -> str:
    return value.strip().upper().lstrip("0") or "0"


def keychain_serials() -> set[str]:
    result = subprocess.run(
        ["security", "find-certificate", "-a", "-c", "Apple Development", "-p"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return set()  # No matching certificates in the keychain.
    serials = set()
    for pem in re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", result.stdout, re.S):
        output = subprocess.run(
            ["openssl", "x509", "-noout", "-serial"],
            input=pem.encode(),
            capture_output=True,
            check=True,
        ).stdout.decode()
        serials.add(normalize_serial(output.strip().split("=", 1)[1]))
    return serials


def read_serials(path: str) -> set[str]:
    with open(path, encoding="utf-8") as handle:
        return {line.strip() for line in handle if line.strip()}


def command_check() -> None:
    token = make_token()
    devices = list_all(
        "/v1/devices",
        token,
        {"filter[platform]": "IOS", "filter[status]": "ENABLED", "limit": 200},
    )
    if not devices:
        fail("No enabled iOS devices are registered in App Store Connect. Register a UDID before building.")
    print(f"App Store Connect key is valid. Enabled iOS devices: {len(devices)}")


def command_keychain_serials(output_path: str) -> None:
    serials = sorted(keychain_serials())
    with open(output_path, "w", encoding="utf-8") as handle:
        handle.write("".join(f"{serial}\n" for serial in serials))
    print(f"Recorded {len(serials)} existing Apple Development certificate(s).")


def command_revoke_new(snapshot_path: str) -> None:
    if not os.path.exists(snapshot_path):
        # Without a snapshot we cannot tell new certificates from existing ones, so revoke nothing.
        print("::warning::No certificate snapshot found; no development certificate was revoked.")
        return

    new_serials = keychain_serials() - read_serials(snapshot_path)
    if not new_serials:
        print("No temporary development certificate to revoke.")
        return

    token = make_token()
    certificates = list_all("/v1/certificates", token, {"limit": 200})
    revoked = set()
    for certificate in certificates:
        serial = normalize_serial(certificate.get("attributes", {}).get("serialNumber", ""))
        if serial in new_serials:
            request("DELETE", f"{API_BASE}/v1/certificates/{certificate['id']}", token)
            revoked.add(serial)
            print(f"Revoked temporary development certificate {certificate['id']}.")

    missing = new_serials - revoked
    if missing:
        fail(f"{len(missing)} temporary development certificate(s) were not found in App Store Connect to revoke.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    subcommands = parser.add_subparsers(dest="command", required=True)
    subcommands.add_parser("check")
    serials_parser = subcommands.add_parser("keychain-serials")
    serials_parser.add_argument("file")
    revoke_parser = subcommands.add_parser("revoke-new")
    revoke_parser.add_argument("file")
    args = parser.parse_args()

    if args.command == "check":
        command_check()
    elif args.command == "keychain-serials":
        command_keychain_serials(args.file)
    elif args.command == "revoke-new":
        command_revoke_new(args.file)


if __name__ == "__main__":
    main()
