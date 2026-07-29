# versioning/from-pyproject

Reads the static `[project].version` from a `pyproject.toml` (uv / PEP 621) and
outputs it as a **bare** `version` (e.g. `1.2.3`). Pair it with the release
actions ([`release/tag-and-alias`](../../release/tag-and-alias) +
[`release/github-release`](../../release/github-release)) to release the version
declared in your project config instead of a separate `VERSION` file.
[`release/tag-and-alias`](../../release/tag-and-alias) owns the tag format (the
`v` prefix), so this resolver stays purely about _reading_ the version.

## Requirements

- **Python 3.11+** on the runner (uses the standard-library `tomllib` to parse
  the file). uv projects run modern Python, so this is normally already present.

## Inputs

| Input  | Required | Default          | Description                           |
| ------ | -------- | ---------------- | ------------------------------------- |
| `file` | no       | `pyproject.toml` | Path to the `pyproject.toml` to read. |

## Outputs

| Output    | Description                        |
| --------- | ---------------------------------- |
| `version` | Bare version string, e.g. `1.2.3`. |

## Usage

Release the version from `pyproject.toml`:

```yaml
jobs:
  release:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - id: ver
        uses: DataLabHell/ci-actions/versioning/from-pyproject@vX.Y

      - id: rel
        uses: DataLabHell/ci-actions/release/tag-and-alias@vX.Y
        with:
          tag: ${{ steps.ver.outputs.version }} # bare; tag-and-alias adds the v

      - uses: DataLabHell/ci-actions/release/github-release@vX.Y
        with:
          tag: ${{ steps.rel.outputs.tag }} # canonical v1.2.3 from tag-and-alias
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

Bump `version` in `pyproject.toml` (e.g. `uv version --bump patch`), merge, and
the release is cut for that version.

## Notes

- Only **static** versions are read. If your project uses
  `[project] dynamic = ["version"]`, the version isn't in the file and the
  action fails with a clear error — resolve it a different way in that case.
- The version must be `MAJOR.MINOR.PATCH` for `release/tag-and-alias` to accept the tag.
- Add `pyproject.toml` to the release workflow's `paths` filter so a version
  bump there triggers the release.
