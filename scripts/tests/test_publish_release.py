import hashlib
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "publish_release.py"
SPEC = importlib.util.spec_from_file_location("publish_release", SCRIPT)
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)
SHA = "a" * 40
VERSION = "0.1.73"


class FakeGitHub:
    """An offline release server that records mutations and serves uploaded bytes."""
    def __init__(self):
        self.items = []
        self.files = {}
        self.tag = None
        self.calls = []
        self.fail_upload = False
        self.corrupt_download = False
        self.fail_read = False

    def __call__(self, *args):
        self.calls.append(args)
        if args[:2] == ("git", "ls-remote"):
            return "" if self.tag is None else f"{self.tag}\trefs/tags/v{VERSION}\n"
        if args[:2] == ("gh", "api"):
            if self.fail_read:
                raise subprocess.CalledProcessError(1, args)
            if args[-1].endswith("/latest"):
                return json.dumps(self.items[-1])
            return json.dumps([self.items])
        action = args[2]
        if action == "create":
            notes = Path(args[args.index("--notes-file") + 1]).read_text()
            self.items.append({"tag_name": "v" + VERSION, "draft": True,
                               "prerelease": False, "body": notes,
                               "target_commitish": SHA, "assets": [],
                               "html_url": "https://github.com/example/repo/releases/tag/v" + VERSION})
        elif action == "upload":
            for value in args[4:args.index("--repo")]:
                path = Path(value)
                self.files[path.name] = path.read_bytes()
                self.items[-1]["assets"].append({"name": path.name, "state": "uploaded", "size": path.stat().st_size})
                if self.fail_upload:
                    raise subprocess.CalledProcessError(1, args)
        elif action == "download":
            destination = Path(args[args.index("--dir") + 1])
            for name, data in self.files.items():
                (destination / name).write_bytes(data)
            if self.corrupt_download:
                (destination / release.asset_names(VERSION)[0]).write_bytes(b"corrupted")
        elif action == "edit":
            self.items[-1]["draft"] = False
            self.tag = SHA
        else:
            raise AssertionError(args)
        return ""

    def mutations(self):
        return [args[2] for args in self.calls if args[:2] == ("gh", "release") and args[2] != "download"]


class PublishReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        names = release.asset_names(VERSION)
        lines = []
        for name in names[:2]:
            data = ("verified build " + name).encode()
            (self.directory / name).write_bytes(data)
            lines.append(hashlib.sha256(data).hexdigest() + "  " + name)
        (self.directory / names[2]).write_text("\n".join(lines) + "\n")
        self.server = FakeGitHub()
        self.publisher = release.Publisher("example/repo", VERSION, SHA, self.server)

    def publish(self, mode="release"):
        return self.publisher.publish(self.directory, "# v0.1.73\n\nCompatibility fixes.\n", mode)

    def test_manual_release_publishes_only_after_download_verification(self):
        self.publish()
        self.assertEqual(self.server.mutations(), ["create", "upload", "edit"])
        actions = [c[2] for c in self.server.calls if c[:2] == ("gh", "release")]
        self.assertLess(actions.index("download"), actions.index("edit"))
        self.assertFalse(self.server.items[-1]["draft"])
        self.assertEqual(len(self.server.files), 3)

    def test_existing_correct_tag_is_supported(self):
        self.server.tag = SHA
        self.publish()
        self.assertFalse(self.server.items[-1]["draft"])

    def test_annotated_tag_resolves_to_commit(self):
        def remote(*args):
            return f"{'b' * 40}\trefs/tags/v{VERSION}\n{SHA}\trefs/tags/v{VERSION}^{{}}\n"
        self.publisher.command = remote
        self.assertEqual(self.publisher.tag_sha(), SHA)

    def test_tag_for_other_commit_never_writes(self):
        self.server.tag = "b" * 40
        with self.assertRaisesRegex(ValueError, "another commit"):
            self.publish()
        self.assertEqual(self.server.mutations(), [])

    def test_published_release_is_never_modified(self):
        self.publish()
        self.server.calls.clear()
        with self.assertRaisesRegex(ValueError, "already published"):
            self.publish()
        self.assertEqual(self.server.mutations(), [])

    def test_older_version_cannot_replace_latest(self):
        self.server.items = [{"tag_name": "v0.1.74", "draft": False, "prerelease": False}]
        with self.assertRaisesRegex(ValueError, "newer"):
            self.publish()
        self.assertEqual(self.server.mutations(), [])

    def test_unowned_draft_is_never_modified(self):
        self.server.items = [{"tag_name": "v" + VERSION, "draft": True, "prerelease": False,
                              "body": "Handwritten draft", "target_commitish": SHA}]
        with self.assertRaisesRegex(ValueError, "not staged"):
            self.publish()
        self.assertEqual(self.server.mutations(), [])

    def test_corrupt_local_package_never_writes(self):
        (self.directory / release.asset_names(VERSION)[0]).write_bytes(b"broken")
        with self.assertRaisesRegex(ValueError, "Checksum mismatch"):
            self.publish()
        self.assertEqual(self.server.mutations(), [])

    def test_incomplete_or_unsafe_manifest_never_writes(self):
        manifest = self.directory / release.asset_names(VERSION)[2]
        manifest.write_text("0" * 64 + "  ../other.zip\n")
        with self.assertRaisesRegex(ValueError, "manifest"):
            self.publish()
        self.assertEqual(self.server.mutations(), [])

    def test_upload_failure_stays_draft_and_retry_uploads_only_missing_files(self):
        self.server.fail_upload = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.publish()
        self.assertTrue(self.server.items[-1]["draft"])
        self.assertNotIn("edit", self.server.mutations())
        self.server.fail_upload = False
        self.publish()
        self.assertEqual(len(self.server.items[-1]["assets"]), 3)
        self.assertEqual(self.server.mutations().count("create"), 1)

    def test_corrupt_remote_package_never_publishes(self):
        self.server.corrupt_download = True
        with self.assertRaisesRegex(ValueError, "Checksum mismatch"):
            self.publish()
        self.assertTrue(self.server.items[-1]["draft"])
        self.assertNotIn("edit", self.server.mutations())

    def test_draft_mode_never_publishes(self):
        self.publish("draft")
        self.assertTrue(self.server.items[-1]["draft"])
        self.assertNotIn("edit", self.server.mutations())

    def test_existing_tag_proves_source_when_api_target_is_a_branch(self):
        self.publish("draft")
        self.server.tag = SHA
        self.server.items[-1]["target_commitish"] = "main"
        self.publish()
        self.assertFalse(self.server.items[-1]["draft"])

    def test_api_failure_is_not_treated_as_no_previous_release(self):
        self.server.fail_read = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.publish()
        self.assertEqual(self.server.mutations(), [])

    def test_version_rejects_paths_prereleases_and_leading_zeroes(self):
        for value in ("../0.1.73", "v0.1.73", "0.1.73-beta", "00.1.73", "0.1.73\n"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                release.version_tuple(value)


if __name__ == "__main__":
    unittest.main()
