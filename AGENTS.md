# Codex Radar Repository Instructions

These rules apply to the entire repository. More specific `AGENTS.md` files may
add narrower requirements without weakening these rules.

## Public-content boundary

- Write public artifacts for users and maintainers. Explain the product,
  observable behavior, setup, safety boundaries, and verified results.
- Never publish private prompts, personal intent, conversation history,
  feedback transcripts, credentials, authentication material, chain-of-thought,
  hidden memory, internal approval mechanics, or execution traces.
- Do not describe a change as compliance with a private request. Convert the
  underlying need into durable, reader-facing product or maintenance language.
- Sanitize examples and fixtures. Do not expose real account data, tokens,
  cookies, email addresses, full reset-credit identifiers, or local private
  paths.
- Public commits, releases, issues, documentation, and screenshots follow the
  same boundary.

## README contract

- Keep `README.md` and `README.en.md` structurally equivalent and factually
  aligned. Update both in the same change.
- Keep the opening concise and user-oriented: product summary, representative
  image, and useful navigation only.
- Place `让 Codex 帮你安装` / `Install With Codex` immediately after the
  opening block and before News. It must remain a prominent quick-start path.
- The install text must use the public latest-release URL, verify the published
  SHA256, install into `/Applications`, launch the app, and confirm the installed
  version. It must not include secrets or destructive shortcuts.
- Show exactly the three newest releases directly in News. Put every older
  release summary inside one closed `<details>` block and link to GitHub Releases
  for the complete history. When adding a new release, move the former fourth
  entry into that block.
- Keep release summaries focused on user-visible behavior and safety. Omit
  internal test failures, automation narration, private feedback, raw product
  requests, and development transcripts.
- Do not link the README to raw prompt archives or summarize their private
  contents. The generic installation text above is the only request-style block
  intended for end users.
- Prefer a product-page flow: install, latest changes, core features, usage,
  privacy and security, data sources, manual install, then contributor details.
- Keep technical detail only when it helps users understand behavior, privacy,
  safety, compatibility, or recovery. Move low-level implementation narration
  out of the primary user path.
- Describe only implemented behavior. Verify version numbers, defaults,
  thresholds, intervals, endpoints, release assets, and platform requirements
  against the current repository before editing.

## Documentation validation

Before considering a README change complete:

1. Protect unrelated working-tree changes and inspect the full README diff.
2. Confirm that only three release headings are visible outside the historical
   `<details>` block.
3. Search both READMEs for private prompts, intent, conversation or feedback
   traces, credentials, and internal workflow narration.
4. Verify local image paths and changed links.
5. Render both files as GitHub-flavored Markdown and confirm matching section,
   table, image, and disclosure structure.
6. Run `git diff --check` and the smallest relevant repository tests.

## Git completion

- After an authorized repository change is complete, reviewed, and validated,
  automatically stage only the intended files, create a concise public-safe
  commit, and push the current branch to its configured upstream. A separate
  confirmation is not required.
- Treat this as standing repository-level authorization for `git add`,
  `git commit`, and a normal non-force `git push` only.
- Never use `git add -A` or a broad path when unrelated work exists. Resolve the
  exact intended paths and preserve every unrelated tracked or untracked change.
- Do not commit or push when required checks fail, the diff contains unresolved
  private material, the working tree has conflicting user changes, the branch
  has no safe upstream, or remote policy or permissions reject the operation.
- Never force-push, rewrite published history, bypass branch protection, or
  silently include generated packages, credentials, local state, or unrelated
  files.
- Tags, GitHub Releases, deployments, and other publication steps still require
  authorization from the current task or the repository's established release
  workflow.
