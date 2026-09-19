#!/usr/bin/env python3
"""Publish verified macOS assets via a staging draft, using GitHub CLI authentication."""
import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def version_tuple(value):
    if not re.fullmatch(VERSION, value):
        raise ValueError("Expected a stable version such as 0.1.73, without v")
    return tuple(map(int, value.split(".")))


def asset_names(version):
    prefix = f"CodexRadarSentinel-{version}-macOS"
    return [prefix + suffix for suffix in (".zip", ".dmg", ".sha256")]


def verify_assets(directory, version):
    names = asset_names(version)
    for name in names:
        path = directory / name
        if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"Missing, empty or linked release asset: {name}")
    hashes = {}
    for line in (directory / names[2]).read_text().splitlines():
        match = re.fullmatch(r"([0-9a-fA-F]{64}) [ *](.+)", line)
        if not match or match[2] not in names[:2] or match[2] in hashes:
            raise ValueError("Checksum manifest must contain exactly the ZIP and DMG")
        hashes[match[2]] = match[1].lower()
    if set(hashes) != set(names[:2]):
        raise ValueError("Incomplete checksum manifest")
    for name, expected in hashes.items():
        if hashlib.sha256((directory / name).read_bytes()).hexdigest() != expected:
            raise ValueError(f"Checksum mismatch: {name}")
    return {name: hashlib.sha256((directory / name).read_bytes()).hexdigest() for name in names}


class Publisher:
    def __init__(self, repo, version, sha, command=run):
        version_tuple(version)
        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
            raise ValueError("GH_REPO must identify owner/repository")
        if not re.fullmatch(r"[0-9a-f]{40}", sha):
            raise ValueError("A full source commit SHA is required")
        self.repo, self.version, self.sha = repo, version, sha
        self.tag = "v" + version
        self.marker = f"<!-- codex-radar-release-source: {sha} -->"
        self.command = command

    def gh(self, *args):
        return self.command("gh", *args)

    def releases(self):
        pages = json.loads(self.gh("api", "--paginate", "--slurp", f"repos/{self.repo}/releases?per_page=100"))
        return [release for page in pages for release in page]

    def tag_sha(self):
        ref = f"refs/tags/{self.tag}"
        lines = self.command("git", "ls-remote", "origin", ref, ref + "^{}").splitlines()
        refs = {line.split()[1]: line.split()[0] for line in lines}
        return refs.get(ref + "^{}", refs.get(ref))

    def check(self):
        tag_sha = self.tag_sha()
        if tag_sha is not None and tag_sha != self.sha:
            raise ValueError("Existing tag points to another commit; tags are never moved")
        existing = None
        for release in self.releases():
            if release["tag_name"] == self.tag:
                if not release["draft"]:
                    raise ValueError("This version is already published; choose a new version")
                source_matches = tag_sha == self.sha or release.get("target_commitish") == self.sha
                if self.marker not in (release.get("body") or "") or not source_matches:
                    raise ValueError("Existing draft was not staged by this workflow for this commit")
                existing = release
            elif not release["draft"] and not release["prerelease"]:
                tag = release["tag_name"].removeprefix("v")
                if re.fullmatch(VERSION, tag) and version_tuple(tag) >= version_tuple(self.version):
                    raise ValueError("Release version must be newer than every published stable version")
        return existing

    def current_release(self):
        matches = [r for r in self.releases() if r["tag_name"] == self.tag]
        if len(matches) != 1:
            raise ValueError("Expected exactly one staged release")
        return matches[0]

    def publish(self, directory, notes, mode):
        if mode not in ("release", "draft"):
            raise ValueError("Unsupported publication mode")
        hashes = verify_assets(directory, self.version)
        existing = self.check()
        with tempfile.TemporaryDirectory(prefix="radar-release-") as temporary:
            temporary = Path(temporary)
            notes_path = temporary / "notes.md"
            notes_path.write_text(notes.rstrip() + "\n\n" + self.marker + "\n")
            if existing is None:
                self.gh("release", "create", self.tag, "--repo", self.repo,
                        "--target", self.sha, "--title", self.tag,
                        "--notes-file", str(notes_path), "--draft")
            staged = self.current_release()
            if not staged["draft"] or self.marker not in (staged.get("body") or ""):
                raise ValueError("Release staging state changed; stopping")
            present = {asset["name"] for asset in staged["assets"]}
            if not present.issubset(hashes):
                raise ValueError("Draft contains unexpected assets; inspect it before retrying")
            missing = [str(directory / name) for name in hashes if name not in present]
            if missing:
                self.gh("release", "upload", self.tag, *missing, "--repo", self.repo)
            staged = self.current_release()
            assets = staged["assets"]
            if len(assets) != len(hashes) or {a["name"] for a in assets} != set(hashes):
                raise ValueError("Uploaded release asset list is incomplete")
            for asset in assets:
                if asset["state"] != "uploaded" or asset["size"] != (directory / asset["name"]).stat().st_size:
                    raise ValueError("Uploaded asset state or size is incorrect")
            downloaded = temporary / "downloaded"
            downloaded.mkdir()
            self.gh("release", "download", self.tag, "--repo", self.repo, "--dir", str(downloaded))
            if verify_assets(downloaded, self.version) != hashes:
                raise ValueError("Downloaded assets differ from the tested build; draft remains unpublished")
            # Recheck tag, version order and ownership immediately before publication.
            if self.check() is None:
                raise ValueError("Staged release disappeared")
            if mode == "release":
                self.gh("release", "edit", self.tag, "--repo", self.repo,
                        "--draft=false", "--prerelease=false", "--latest")
                published = self.current_release()
                if published["draft"] or published["prerelease"] or self.tag_sha() != self.sha:
                    raise ValueError("Published release state or source tag could not be verified")
                latest = json.loads(self.gh("api", f"repos/{self.repo}/releases/latest"))
                if latest["tag_name"] != self.tag:
                    raise ValueError("Release is published but is not Latest")
            result = self.current_release()
            print(result["html_url"])
            return result["html_url"]


def release_notes(version):
    path = ROOT / "releases" / f"v{version}.md"
    notes = path.read_text().strip()
    if not notes.startswith(f"# v{version}\n") or len(notes.splitlines()) < 3:
        raise ValueError(f"{path.relative_to(ROOT)} needs a matching version heading and release notes")
    if re.search(r"\b(?:TODO|TBD|PLACEHOLDER)\b", notes, re.IGNORECASE):
        raise ValueError("Replace release-note placeholders before publishing")
    return notes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("--sha", required=True)
    parser.add_argument("--mode", choices=("release", "draft"), default="release")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    os.chdir(ROOT)
    publisher = Publisher(os.environ.get("GH_REPO", ""), args.version, args.sha)
    run("python3", "scripts/release_version.py", args.version)
    notes = release_notes(args.version)
    if args.check:
        publisher.check()
        print(f"Release {publisher.tag} is eligible for {args.sha}")
    else:
        url = publisher.publish(ROOT / "dist", notes, args.mode)
        if os.environ.get("GITHUB_STEP_SUMMARY"):
            with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
                summary.write(f"Release mode: {args.mode}\n\n[{publisher.tag}]({url})\n")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) and error.stderr else str(error)
        raise SystemExit(f"Release stopped: {detail}")
