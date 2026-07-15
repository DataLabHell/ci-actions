# versioning/auto-patch

Reads `MAJOR.MINOR` from a version file (default `VERSION`) and **auto-increments
the patch** based on the existing `vMAJOR.MINOR.*` tags, outputting the next
`vX.Y.Z` tag. Feed it into the release actions
([`release/tag-and-alias`](../../release/tag-and-alias) +
[`release/github-release`](../../release/github-release)) — this is the default
versioning strategy: you set `MAJOR.MINOR`, the patch takes care of itself.

## Requirements

- Check out with full history and tags: `actions/checkout@v4` with
  `fetch-depth: 0` (needed to see existing tags).

## Inputs

| Input    | Required | Default   | Description                                        |
| -------- | -------- | --------- | -------------------------------------------------- |
| `file`   | no       | `VERSION` | Path to the file holding `MAJOR.MINOR`.            |
| `prefix` | no       | `v`       | Prefix prepended to the version to form the tag.   |

## Outputs

| Output    | Description                   |
| --------- | ----------------------------- |
| `version` | Full version, e.g. `0.1.3`.   |
| `tag`     | Next tag, e.g. `v0.1.3`.      |

## Usage

```yaml
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - id: ver
        uses: DataLabHell/ci-actions/actions/versioning/auto-patch@v0.1

      - uses: DataLabHell/ci-actions/actions/release/tag-and-alias@v0.1
        with:
          tag: ${{ steps.ver.outputs.tag }}

      - uses: DataLabHell/ci-actions/actions/release/github-release@v0.1
        with:
          tag: ${{ steps.ver.outputs.tag }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

Everyday changes → next patch (`v0.1.3` → `v0.1.4`). To start a new series, edit
the file (`0.1` → `0.2`); with no `v0.2.*` tags yet it starts at `v0.2.0`.
