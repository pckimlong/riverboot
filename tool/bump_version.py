#!/usr/bin/env python3
"""Utility to bump the package version and update the changelog."""
from __future__ import annotations

import datetime as _dt
import os
import re
import subprocess
import sys
from typing import Iterable, Optional, Tuple

Commit = Tuple[str, str]


def _run(cmd: list[str]) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        raise RuntimeError(f"Command failed: {' '.join(cmd)}")
    return result.stdout.strip()


def _latest_tag() -> Optional[str]:
    tags = _run(["git", "tag", "--list", "v*", "--sort=-v:refname"])
    for tag in tags.splitlines():
        tag = tag.strip()
        if tag:
            return tag
    return None


def _collect_commits(tag: Optional[str]) -> list[Commit]:
    range_arg = f"{tag}..HEAD" if tag else "HEAD"
    output = _run(["git", "log", range_arg, "--pretty=format:%s%x1f%b%x1e"])
    commits: list[Commit] = []
    for entry in output.split("\x1e"):
        if not entry.strip():
            continue
        subject, _, body = entry.partition("\x1f")
        subject = subject.strip()
        body = body.strip()
        if not subject or subject.startswith("chore(release)"):
            continue
        commits.append((subject, body))
    return commits


def _determine_bump(commits: Iterable[Commit]) -> str:
    level = "patch"
    for subject, body in commits:
        normalized = f"{subject}\n{body}".upper()
        if re.search(r"!:", subject):
            return "major"
        if "BREAKING CHANGE" in normalized or "BREAKING-CHANGE" in normalized:
            return "major"
        if level != "minor" and re.match(r"^feat(\(|:|!)", subject, flags=re.IGNORECASE):
            level = "minor"
    return level


def _bump_version(current: str, release_type: str) -> str:
    major, minor, patch = (int(x) for x in current.split("."))
    if release_type == "major":
        major += 1
        minor = 0
        patch = 0
    elif release_type == "minor":
        minor += 1
        patch = 0
    else:
        patch += 1
    return f"{major}.{minor}.{patch}"


def _replace_version(path: str, new_version: str) -> None:
    with open(path, "r", encoding="utf-8") as fh:
        content = fh.read()
    updated = re.sub(r"(^version:\s*)([0-9]+\.[0-9]+\.[0-9]+)",
                     rf"\g<1>{new_version}", content, count=1, flags=re.MULTILINE)
    if content == updated:
        raise RuntimeError("Failed to update version in pubspec.yaml")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(updated)


def _update_changelog(path: str, new_version: str, commits: list[Commit]) -> str:
    today = _dt.date.today().isoformat()
    bullet_lines = [c[0] for c in commits] or ["No notable changes"]
    new_entry_lines = [f"## {new_version} - {today}", ""]
    new_entry_lines.extend(f"- {line}" for line in bullet_lines)
    new_entry_lines.append("")
    new_entry = "\n".join(new_entry_lines)

    previous = ""
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as fh:
            previous = fh.read().strip()

    combined = new_entry + ("\n\n" + previous if previous else "\n")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(combined)
    return new_entry


def _set_output(key: str, value: str) -> None:
    output_path = os.environ.get("GITHUB_OUTPUT")
    if not output_path:
        return
    with open(output_path, "a", encoding="utf-8") as fh:
        if "\n" in value:
            fh.write(f"{key}<<EOF\n{value}\nEOF\n")
        else:
            fh.write(f"{key}={value}\n")


def main() -> int:
    pubspec_path = "pubspec.yaml"
    changelog_path = "CHANGELOG.md"
    with open(pubspec_path, "r", encoding="utf-8") as fh:
        content = fh.read()
    match = re.search(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)", content, re.MULTILINE)
    if not match:
        raise RuntimeError("Could not find version in pubspec.yaml")
    current_version = match.group(1)

    tag = _latest_tag()
    commits = _collect_commits(tag)

    if not commits:
        _set_output("skip", "true")
        print("No new commits eligible for release.")
        return 0

    release_type = _determine_bump(commits)
    new_version = _bump_version(current_version, release_type)

    _replace_version(pubspec_path, new_version)
    changelog_entry = _update_changelog(changelog_path, new_version, commits)

    _set_output("skip", "false")
    _set_output("version", new_version)
    _set_output("release_notes", changelog_entry)

    print(f"Bumped {current_version} -> {new_version} ({release_type}).")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001 - surface failure in CI
        sys.stderr.write(f"Error: {exc}\n")
        raise
