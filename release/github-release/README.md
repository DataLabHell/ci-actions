# release/github-release

Publishes a GitHub Release for an existing tag, with auto-generated notes and
optional attached assets. A thin wrapper over `softprops/action-gh-release` with
our defaults. Pair it after [`release/tag-and-alias`](../tag-and-alias) when you
want a Release page in addition to the tags.

## Requirements

- The tag must already exist (create it first with `release/tag-and-alias`).
- Grant `permissions: contents: write` so the release can be created.

## Inputs

| Input           | Required | Default | Description                                                      |
| --------------- | -------- | ------- | ---------------------------------------------------------------- |
| `tag`           | yes      | n/a     | Existing tag to publish a Release for, e.g. `v1.2.3`.            |
| `github-token`  | yes      | n/a     | Token to create the release. Pass `${{ secrets.GITHUB_TOKEN }}`. |
| `release-notes` | no       | `true`  | Auto-generate release notes.                                     |
| `files`         | no       | `''`    | Newline- or comma-separated glob(s) of assets to attach.         |

## Usage

```yaml
- id: ver
  uses: DataLabHell/ci-actions/versioning/auto-patch@versioning/auto-patch-vX.Y.Z

- id: rel
  uses: DataLabHell/ci-actions/release/tag-and-alias@release/tag-and-alias-vX.Y.Z
  with:
    tag: ${{ steps.ver.outputs.version }} # bare; tag-and-alias adds the v

- uses: DataLabHell/ci-actions/release/github-release@release/github-release-vX.Y.Z
  with:
    tag: ${{ steps.rel.outputs.tag }} # canonical v1.2.3 from tag-and-alias
    github-token: ${{ secrets.GITHUB_TOKEN }}
    # files: dist/*.tgz        # optionally attach build artifacts
```

## Notes

- This only creates the Release; it does not create or move tags. Run
  `release/tag-and-alias` first so the tag exists.
