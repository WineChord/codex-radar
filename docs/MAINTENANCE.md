# macOS validation and releases

Code can be edited from any operating system. The application and its complete
test suite require macOS; the core module also uses Darwin and Apple frameworks.
Use GitHub Actions for macOS validation when the editing machine is not a Mac.

## Candidate changes

1. Work on an isolated branch named `codex/<topic>`. Run the available source,
   script and documentation checks before pushing the candidate branch.
2. Open a pull request to `main`. The **macOS CI** workflow runs on pull requests,
   pushes to `main` or `codex/**`, and manual requests.
3. Wait for **Tests (macos-15)**, **Tests (macos-15-intel)**, and
   **Live contracts and universal package** to succeed for the current candidate.
   Review the logs and screenshot artifacts. If `main` changes, validate the
   updated candidate before merging.
4. Merge only after relevant checks pass. A branch push for remote validation is
   not a release or evidence that tests have already passed.

The workflow uses standard hosted macOS runners. Both native architectures run
the unit tests and a production build. The packaging job runs the existing live
contract and screenshot checks and produces a universal arm64/x86_64 application.
It verifies the extracted ZIP application, version/build numbers, both executable
architectures, ad-hoc signature, SHA256 manifest and DMG integrity. Installation
packages and bilingual screenshots are retained as Actions artifacts for 7 days.
These candidate packages are not published updates; they may carry the current
source version and must not replace an existing release.

Live source outages or schema changes fail the contract check. Inspect the exact
failure and preserve deterministic unit tests; do not weaken assertions merely
to turn a failing check green. No job needs a personal Codex login or real reset
credits. Real-account login, notifications, launch-at-login, sleep/wake behavior
and installation/update smoke tests still require a representative Mac session.

## Publish a release

Prepare the version once, then use either the Actions button or a Git tag.
Both entry points run the same native macOS checks and publish the same assets.
Ordinary branch pushes and pull requests only validate code; they do not publish.

### Prepare the source

1. Set `appVersion` in `Sources/CodexRadarCore/AppConstants.swift` and
   `CFBundleShortVersionString` in `Resources/Info.plist` to the next version.
   Increment the positive integer `CFBundleVersion` as well.
2. Update both READMEs' user-visible release notes and create
   `releases/vVERSION.md` with a matching `# vVERSION` heading and the Chinese
   and English release notes. See [the release-note template](../releases/README.md).
3. Merge the prepared source into `main` after relevant checks pass. For changes
   to account access, installation, notifications or updating, also perform the
   corresponding installed-app checks on a representative Mac.

Versions use stable `major.minor.patch` numbers and must be newer than every
published stable release. Entering a version in Actions checks the source;
it does not silently change source files or create a version-bump commit.

### Recommended: publish from the web

Open [Release macOS](https://github.com/WineChord/codex-radar/actions/workflows/release.yml),
click **Run workflow**, select **main**, leave **version** blank to use the
prepared source version, and leave **mode** as **release**. Click **Run workflow**.
After validation, the workflow creates the tag at the exact tested commit and
publishes a stable GitHub Release marked **Latest**. Existing installations can
discover it through the current automatic-update mechanism.

The optional modes are **draft** (upload and verify without publishing) and
**verify** (run the full Mac checks and keep only the temporary Actions artifacts).
Verification mode also works when the current source version is already released.

### Alternative: push a version tag

From an up-to-date, clean `main` containing the prepared release:

```bash
git switch main
git pull --ff-only
python3 scripts/release_version.py 0.1.73
git tag -a v0.1.73 -m 'Release v0.1.73'
git push origin v0.1.73
```

Replace `0.1.73` with the prepared version. Pushing `v*` starts the release
workflow automatically; it requires the tag version to match the app and the
tag's commit to belong to `main`. Both annotated and lightweight tags work.
An automation that creates tags with the repository's `GITHUB_TOKEN` does not
trigger another push workflow; use the manual workflow entry point in that case.
No personal access token or Apple credentials are required for the existing
ad-hoc signed distribution path.

### Publication and retry behavior

The publishing job downloads the universal package from its own workflow run,
checks the ZIP/DMG checksum manifest, uploads all three files to a staging draft,
then downloads them again and verifies their bytes before publishing. A failed
upload or verification leaves the draft unpublished. Only a complete, validated
release becomes **Latest**; the updater does not consume drafts or Actions artifacts.

For a temporary upload/download failure, use **Re-run failed jobs** so the retry
uses the same verified build artifacts. It resumes only a draft created by this
workflow for the same source commit and uploads missing files without replacing
existing assets. Conflicting bytes, a manually created draft, a moved tag, or an
already published version stop the run for inspection. Published assets and tags
are never overwritten. A full rebuild may produce different bytes; use a new
version or inspect the unpublished draft instead of replacing published files.

The release page receives the authored `releases/vVERSION.md` text and the
existing ZIP, DMG and SHA256 asset names. The workflow summary links to the result.
There is no second publication confirmation after explicitly choosing
**release** or pushing a prepared version tag.

Builds retain the project's existing ad-hoc signing. They are not Apple Developer
ID signed or notarized. Adding that distribution path requires the appropriate
Apple account, certificate and securely configured signing credentials.

## Local macOS commands

```bash
swift test
swift build -c release
python3 scripts/release_version.py
CODEX_RADAR_UNIVERSAL=1 ./scripts/check_release_readiness.sh 0.1.72
```

Replace the example version with the source version printed by the Python
command. Screenshot rendering requires Pillow, which the workflow installs into
an isolated environment. `CODEX_RADAR_UNIVERSAL=1` also works with `build_app.sh`
and `package_release.sh`; without it, local builds retain native architecture.

## Permissions

Validation jobs use read-only repository credentials and do not persist checkout
credentials. Only the final, explicitly requested publishing job receives repository
contents write permission. Third-party actions are pinned to reviewed commits.
No workflow uses `pull_request_target` to execute contributor code.

Installing or modifying workflow files may require the GitHub connection's
**Workflows: write** permission in addition to **Contents: write**. If GitHub
rejects a workflow update, an account owner must approve the required permission
or install the reviewed workflow through an authorized account. Do not bypass
repository access controls. Branch-protection rules should require the three
macOS checks above where available; enabling those rules requires repository
administration access.
