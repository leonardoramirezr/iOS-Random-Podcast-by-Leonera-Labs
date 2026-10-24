#!/usr/bin/env python3
"""Maintain the GitHub Pages site, which holds one folder per build.

Subcommands:
  prune DIR --keep-branch-builds N  Remove entries that are not build folders, and branch
                                    builds beyond the newest N. Stable (main) builds are always kept.
  index DIR                         Regenerate index.html and .nojekyll at the site root.

Standard library only.
"""

from __future__ import annotations

import argparse
import html
import json
import shutil
from pathlib import Path


def is_build_folder(path: Path) -> bool:
    return path.is_dir() and (path / "build.json").is_file()


def load_builds(site: Path) -> list[tuple[Path, dict]]:
    return [
        (folder, json.loads((folder / "build.json").read_text(encoding="utf-8")))
        for folder in sorted(site.iterdir())
        if is_build_folder(folder)
    ]


def remove(path: Path) -> None:
    if path.is_dir():
        shutil.rmtree(path)
    else:
        path.unlink()


def prune(site: Path, keep_branch_builds: int) -> None:
    for entry in site.iterdir():
        if not is_build_folder(entry):
            remove(entry)

    branch_builds = [
        (folder, meta) for folder, meta in load_builds(site) if meta.get("channel") != "stable"
    ]
    branch_builds.sort(key=lambda item: item[1]["runNumber"], reverse=True)
    for folder, _ in branch_builds[keep_branch_builds:]:
        shutil.rmtree(folder)


def render_row(meta: dict) -> str:
    tag = html.escape(meta["tag"])
    channel = "Stable" if meta.get("channel") == "stable" else "Branch build"
    return (
        '<li class="build">'
        f'<a href="./{tag}/"><strong>{tag}</strong></a> '
        f'<span class="badge">{html.escape(channel)}</span>'
        f'<div class="meta">{html.escape(meta.get("commitTitle", ""))}</div>'
        f'<div class="meta">{html.escape(meta.get("createdAt", ""))} · '
        f'{html.escape(str(meta.get("deviceCount", "")))} device(s)</div>'
        "</li>"
    )


def render_index(builds: list[dict]) -> str:
    stable = [meta for meta in builds if meta.get("channel") == "stable"]
    latest_button = ""
    if stable:
        latest = html.escape(stable[0]["tag"])
        latest_button = f'<p><a class="button" href="./{latest}/">Latest stable: {latest}</a></p>'
    rows = "\n".join(render_row(meta) for meta in builds) or "<li>No builds have been published yet.</li>"
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Random Podcast by Leonera Labs - Builds</title>
<style>
:root {{ color-scheme: light dark; --bg: #f5f5f7; --fg: #1c1c1e; --muted: #6e6e73; --card: #ffffff; --accent: #5b2ee0; }}
@media (prefers-color-scheme: dark) {{
  :root {{ --bg: #000000; --fg: #f5f5f7; --muted: #a1a1a6; --card: #1c1c1e; }}
}}
body {{ margin: 0; padding: 24px 16px; font-family: -apple-system, system-ui, sans-serif; background: var(--bg); color: var(--fg); }}
main {{ max-width: 640px; margin: 0 auto; }}
h1 {{ font-size: 1.6rem; }}
ul {{ list-style: none; padding: 0; }}
.build {{ background: var(--card); border-radius: 12px; padding: 14px 16px; margin-bottom: 12px; }}
.meta {{ color: var(--muted); font-size: 0.9rem; margin-top: 4px; }}
.badge {{ font-size: 0.75rem; color: var(--muted); border: 1px solid var(--muted); border-radius: 999px; padding: 1px 8px; }}
.button {{ display: inline-block; background: var(--accent); color: #fff; text-decoration: none; padding: 12px 20px; border-radius: 12px; font-weight: 600; }}
</style>
</head>
<body>
<main>
<h1>Random Podcast by Leonera Labs</h1>
<p class="meta">Every published build. Open a build and tap Install on your iPhone.</p>
{latest_button}
<ul>
{rows}
</ul>
</main>
</body>
</html>
"""


def index(site: Path) -> None:
    builds = [meta for _, meta in sorted(load_builds(site), key=lambda item: item[1]["runNumber"], reverse=True)]
    (site / "index.html").write_text(render_index(builds), encoding="utf-8")
    # Disable Jekyll so GitHub Pages serves every file, including the IPA, exactly as stored.
    (site / ".nojekyll").write_text("", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    subcommands = parser.add_subparsers(dest="command", required=True)
    prune_parser = subcommands.add_parser("prune")
    prune_parser.add_argument("site", type=Path)
    prune_parser.add_argument("--keep-branch-builds", type=int, required=True)
    index_parser = subcommands.add_parser("index")
    index_parser.add_argument("site", type=Path)
    args = parser.parse_args()

    if args.command == "prune":
        prune(args.site, args.keep_branch_builds)
    elif args.command == "index":
        index(args.site)


if __name__ == "__main__":
    main()
