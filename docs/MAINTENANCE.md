# macOS validation and release preparation

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

## Release drafts

After a release change updates `AppConstants.swift`, both bundle version fields,
and both READMEs consistently, run **Prepare macOS release draft** from `main`
with the matching version (without `v`). It reruns the full macOS workflow and
creates a GitHub Release **draft** with the verified ZIP, DMG and SHA256 manifest.
It refuses an existing release or tag. It does not automatically publish a
release, replace published assets, or bump versions.

Review the draft's user-visible release notes, source commit and assets, and
complete the installed-app smoke checks before explicitly publishing it. If a
draft upload fails, inspect the existing draft instead of blindly rerunning or
overwriting it. Existing automatic-update asset names remain unchanged.

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
credentials. Only the final, explicitly requested draft job receives repository
contents write permission. Third-party actions are pinned to reviewed commits.
No workflow uses `pull_request_target` to execute contributor code.

Installing or modifying workflow files may require the GitHub connection's
**Workflows: write** permission in addition to **Contents: write**. If GitHub
rejects a workflow update, an account owner must approve the required permission
or install the reviewed workflow through an authorized account. Do not bypass
repository access controls. Branch-protection rules should require the three
macOS checks above where available; enabling those rules requires repository
administration access.
