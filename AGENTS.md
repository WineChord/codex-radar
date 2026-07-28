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

## Product restraint

- Rank information by frequency, urgency, and user value. Put the current
  result, the most important state, and the next useful action before supporting
  explanation or low-frequency controls.
- Prefer progressive disclosure. Keep secondary radar detail, background
  context, long explanations, and rarely changed settings behind one clear,
  accessible disclosure instead of making every capability permanently visible.
- Remove or combine duplicate labels, summaries, controls, and decoration before
  adding another surface. Every visible block must justify the attention and
  space it consumes.
- Keep the product calm, concise, direct, and visually consistent. Favor a small
  number of obvious choices over feature accumulation or dense dashboards.
- Never hide critical failures, irreversible-action warnings, privacy or safety
  state, or the action needed to recover. Simplicity must preserve
  discoverability, accessibility, and safe defaults.
- Validate hierarchy changes in both languages and at every supported text size.
  Check the collapsed state, expanded state, keyboard/accessibility labels, and
  representative normal and warning data.

## Issue and pull-request stewardship

- During repository maintenance, inspect open Issues and pull requests in
  recently updated order before inventing new work. Read the full discussion,
  attachments, patch, review state, checks, and divergence from current `main`.
- Treat feedback as product evidence, not an automatic command or a popularity
  vote. Reproduce the behavior, identify the underlying user need, compare it
  with product consistency and safety, and choose the smallest durable response.
- Acknowledge a clear Issue briefly and respectfully. If it is safely
  deliverable, implement and verify the complete fix; reply with the exact
  released version and evidence, then close it as completed only after that
  release is available. Keep ambiguous or unverified reports open and ask only
  the question that materially unblocks the next decision.
- Review pull requests promptly with one consolidated, actionable review. Use
  inline comments only for line-specific defects, mention the author in the
  review summary, request changes for blocking issues, and re-review after the
  author updates the branch.
- Approval requires compatibility with current `main`, passing relevant checks,
  and adequate evidence for logic, edge cases, security, privacy, performance,
  accessibility, documentation, packaging, and supported platforms. Never merge
  unverified code or silently rewrite a contributor's branch.
- Do not repeat comments or mentions when there is no new evidence. If a
  proposal is declined, explain the product tradeoff plainly and appreciatively
  instead of dismissing the contributor.

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
- Keep the project-history surface separate from the README. Do not reproduce
  its entries in the README or turn the main user path into a development log.
  The generic installation text above is the only request-style block intended
  for README readers.
- Prefer a product-page flow: install, latest changes, core features, usage,
  privacy and security, data sources, manual install, then contributor details.
- Keep technical detail only when it helps users understand behavior, privacy,
  safety, compatibility, or recovery. Move low-level implementation narration
  out of the primary user path.
- Describe only implemented behavior. Verify version numbers, defaults,
  thresholds, intervals, endpoints, release assets, and platform requirements
  against the current repository before editing.

## Prompt history

- Preserve `PROMPTS.md`, its prompt-to-commit mapping, its ongoing maintenance
  workflow, and the in-app `Prompts` entry that opens it. Do not delete, rename,
  hide, or disable these surfaces merely to simplify the README.
- Treat Prompt History as a separate, explicitly selected project-provenance
  surface. Its continued existence does not change the user-focused README
  contract above.
- Keep new entries aligned with the maintenance format in `PROMPTS.md`, including
  the applicable `Prompt-Id` trailer and clickable commit mapping.
- Curate every new entry for public release. Remove credentials, authentication
  data, account or environment details, private paths, private third-party data,
  hidden instructions, and unrelated conversation context. Use a concise
  audience-safe summary when verbatim text would disclose private context.
- Do not copy Prompt History entries into release notes, the README, screenshots,
  issues, or other public surfaces unless that separate artifact independently
  benefits its intended readers.

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
