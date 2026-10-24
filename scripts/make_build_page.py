#!/usr/bin/env python3
"""Create the GitHub Pages folder for one build.

The folder contains the IPA, manifest.plist for itms-services (with 57 px and 512 px icons),
an install page with the download button, and build.json with the build metadata.
Standard library only. The icons are resized with the macOS `sips` tool.
"""

from __future__ import annotations

import argparse
import datetime
import html
import json
import plistlib
import shutil
import subprocess
import urllib.parse
from pathlib import Path

IPA_NAME = "RandomPodcast.ipa"


def resolve_base_url(repo: str) -> str:
    """Return the GitHub Pages base URL (with a trailing slash) from the API, or the default host."""
    try:
        result = subprocess.run(
            ["gh", "api", f"repos/{repo}/pages", "--jq", ".html_url"],
            capture_output=True,
            text=True,
            check=True,
        )
        url = result.stdout.strip()
        if url:
            return url if url.endswith("/") else url + "/"
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    owner, name = repo.split("/", 1)
    return f"https://{owner.lower()}.github.io/{name}/"


def render_install_page(meta: dict) -> str:
    title = html.escape(meta['displayName'])
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} {html.escape(meta['tag'])}</title>
<style>
:root {{ color-scheme: light dark; --bg: #f5f5f7; --fg: #1c1c1e; --muted: #6e6e73; --card: #ffffff; --accent: #5b2ee0; }}
@media (prefers-color-scheme: dark) {{
  :root {{ --bg: #000000; --fg: #f5f5f7; --muted: #a1a1a6; --card: #1c1c1e; }}
}}
body {{ margin: 0; padding: 24px 16px; font-family: -apple-system, system-ui, sans-serif; background: var(--bg); color: var(--fg); }}
main {{ max-width: 640px; margin: 0 auto; }}
.card {{ background: var(--card); border-radius: 16px; padding: 20px; }}
.muted {{ color: var(--muted); font-size: 0.95rem; }}
.button {{ display: block; text-align: center; background: var(--accent); color: #fff; text-decoration: none; padding: 14px 20px; border-radius: 12px; font-weight: 600; margin: 20px 0; }}
dl {{ display: grid; grid-template-columns: max-content 1fr; gap: 6px 16px; }}
dt {{ color: var(--muted); }}
dd {{ margin: 0; word-break: break-word; }}
</style>
</head>
<body>
<main>
<p><a href="../">All builds</a></p>
<div class="card">
<h1>{title}</h1>
<p class="muted">Build {html.escape(meta['tag'])}</p>
<a class="button" href="{html.escape(meta['installUrl'])}">Install on iPhone</a>
<p class="muted">Open this page in Safari on the iPhone. The device must be registered in the Ad Hoc profile.</p>
<dl>
<dt>Version</dt><dd>{html.escape(meta['version'])} ({html.escape(str(meta['runNumber']))})</dd>
<dt>Commit</dt><dd>{html.escape(meta['commitTitle'])}</dd>
<dt>Commit SHA</dt><dd>{html.escape(meta['commitSha'])}</dd>
<dt>Built</dt><dd>{html.escape(meta['createdAt'])}</dd>
<dt>Devices</dt><dd>{html.escape(str(meta['deviceCount']))}</dd>
<dt>Bundle ID</dt><dd>{html.escape(meta['bundleId'])}</dd>
</dl>
<p><a href="{html.escape(meta['ipaUrl'])}">Download the IPA</a></p>
</div>
</main>
</body>
</html>
"""


def render_release_notes(meta: dict) -> str:
    return (
        f"Install on iPhone from Safari: {meta['pageUrl']}\n\n"
        f"Direct install link (open it in Safari on the iPhone):\n\n"
        f"    {meta['installUrl']}\n\n"
        f"Commit: {meta['commitTitle']} (`{meta['commitSha'][:7]}`)\n\n"
        f"Ad Hoc profile devices: {meta['deviceCount']}\n"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument("--summary", required=True, type=Path, help="Output of verify_adhoc.py")
    parser.add_argument("--icon", required=True, type=Path, help="Source icon, at least 512 px")
    parser.add_argument("--tag", required=True)
    parser.add_argument("--channel", required=True, choices=["stable", "prerelease"])
    parser.add_argument("--run-number", required=True, type=int)
    parser.add_argument("--commit-sha", required=True)
    parser.add_argument("--commit-title", required=True)
    parser.add_argument("--repo", required=True, help="owner/name")
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--notes", required=True, type=Path)
    args = parser.parse_args()

    summary = json.loads(args.summary.read_text(encoding="utf-8"))
    base_url = resolve_base_url(args.repo)
    folder_url = f"{base_url}{args.tag}/"
    manifest_url = folder_url + "manifest.plist"
    install_url = "itms-services://?action=download-manifest&url=" + urllib.parse.quote(manifest_url, safe="")

    if args.out.exists():
        shutil.rmtree(args.out)
    args.out.mkdir(parents=True)
    shutil.copy2(args.ipa, args.out / IPA_NAME)
    for size in (57, 512):
        subprocess.run(
            ["sips", "-z", str(size), str(size), str(args.icon), "--out", str(args.out / f"icon-{size}.png")],
            check=True,
            capture_output=True,
        )

    manifest = {
        "items": [
            {
                "assets": [
                    {"kind": "software-package", "url": folder_url + IPA_NAME},
                    {"kind": "display-image", "needs-shine": False, "url": folder_url + "icon-57.png"},
                    {"kind": "full-size-image", "needs-shine": False, "url": folder_url + "icon-512.png"},
                ],
                "metadata": {
                    "bundle-identifier": summary["bundleId"],
                    "bundle-version": str(summary["buildNumber"]),
                    "kind": "software",
                    "title": summary["displayName"],
                },
            }
        ]
    }
    with open(args.out / "manifest.plist", "wb") as handle:
        plistlib.dump(manifest, handle)

    meta = {
        "tag": args.tag,
        "channel": args.channel,
        "version": summary["shortVersion"],
        "runNumber": args.run_number,
        "buildNumber": summary["buildNumber"],
        "displayName": summary["displayName"],
        "bundleId": summary["bundleId"],
        "deviceCount": summary["deviceCount"],
        "profileName": summary["profileName"],
        "profileExpires": summary["profileExpires"],
        "commitSha": args.commit_sha,
        "commitTitle": args.commit_title,
        "createdAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
        "pageUrl": folder_url,
        "ipaUrl": folder_url + IPA_NAME,
        "manifestUrl": manifest_url,
        "installUrl": install_url,
    }
    (args.out / "build.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    (args.out / "index.html").write_text(render_install_page(meta), encoding="utf-8")
    args.notes.parent.mkdir(parents=True, exist_ok=True)
    args.notes.write_text(render_release_notes(meta), encoding="utf-8")
    print(f"Install page: {folder_url}")
    print(f"Install link: {install_url}")


if __name__ == "__main__":
    main()
