# Release notes

Before releasing a new version, add `vVERSION.md` in this directory and commit it
with the matching source/bundle version and bilingual README changes. Replace
the example version and all placeholders below. Keep notes about user-visible
changes, compatibility and recovery; do not copy development transcripts.

```markdown
# v0.1.73

## 更新内容

- TODO: 写明用户可见的修复或改进。

## Changes

- TODO: Describe the same user-visible changes in English.

## 下载 / Downloads

适用于 Apple 芯片与 Intel Mac。安装包沿用临时签名，未经 Apple 公证。
For Apple silicon and Intel Macs. Ad-hoc signed; not Apple notarized.
```

The workflow rejects missing notes, a mismatched heading, or remaining
`TODO`, `TBD` and `PLACEHOLDER` markers. To publish, open
[Release macOS](https://github.com/WineChord/codex-radar/actions/workflows/release.yml),
select `main` and mode `release`, or push the matching `vVERSION` tag.
See the [maintenance guide](../docs/MAINTENANCE.md) for verification and retries.
