# versioning/auto-patch

Reads `MAJOR.MINOR` from a version file (default `VERSION`) and
**auto-increments the patch** based on the existing `vMAJOR.MINOR.*` tags,
outputting the next **bare** version `X.Y.Z`. Feed it into the release actions
([`release/tag-and-alias`](../../release/tag-and-alias) +
[`release/github-release`](../../release/github-release)) — this is the default
versioning strategy: you set `MAJOR.MINOR`, the patch takes care of itself.

The resolver emits only the bare version;
[`release/tag-and-alias`](../../release/tag-and-alias) owns the tag format (the
`v` prefix). The `prefix` input here is used _only_ to find this series'
existing tags in the repo.

## Requirements

- Check out with full history and tags: `actions/checkout@v7` with
  `fetch-depth: 0` (needed to see existing tags).

## Inputs

| Input    | Required | Default   | Description                                                            |
| -------- | -------- | --------- | ---------------------------------------------------------------------- |
| `file`   | no       | `VERSION` | Path to the file holding `MAJOR.MINOR`.                                |
| `prefix` | no       | `v`       | Prefix on existing git tags, used only to find this series (`v0.1.*`). |

## Outputs

| Output    | Description                      |
| --------- | -------------------------------- |
| `version` | Next bare version, e.g. `0.1.3`. |

## Usage

```yaml
jobs:
  release:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0

      - id: ver
        uses: DataLabHell/ci-actions/versioning/auto-patch@versioning/auto-patch/vX.Y.Z

      - id: rel
        uses: DataLabHell/ci-actions/release/tag-and-alias@release/tag-and-alias/vX.Y.Z
        with:
          tag: ${{ steps.ver.outputs.version }} # bare; tag-and-alias adds the v

      - uses: DataLabHell/ci-actions/release/github-release@release/github-release/vX.Y.Z
        with:
          tag: ${{ steps.rel.outputs.tag }} # canonical v0.1.3 from tag-and-alias
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

Everyday changes → next patch (`v0.1.3` → `v0.1.4`). To start a new series, edit
the file (`0.1` → `0.2`); with no `v0.2.*` tags yet it starts at `v0.2.0`.
