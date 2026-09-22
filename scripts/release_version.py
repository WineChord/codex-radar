#!/usr/bin/env python3
"""Validate the source and bundle versions without requiring macOS tools."""
import argparse
import plistlib
import re
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("expected", nargs="?")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    source = (root / "Sources/CodexRadarCore/AppConstants.swift").read_text()
    versions = re.findall(r'public static let appVersion = "([^"]+)"', source)
    if len(versions) != 1 or not re.fullmatch(r"\d+\.\d+\.\d+", versions[0]):
        parser.error("expected one stable appVersion in AppConstants.swift")
    version = versions[0]
    with (root / "Resources/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    if info.get("CFBundleShortVersionString") != version:
        parser.error("source and Info.plist versions do not match")
    if not re.fullmatch(r"[1-9]\d*", str(info.get("CFBundleVersion", ""))):
        parser.error("CFBundleVersion must be a positive integer")
    if args.expected is not None and args.expected != version:
        parser.error(f"expected {args.expected!r}, source version is {version}")
    print(version)


if __name__ == "__main__":
    main()
