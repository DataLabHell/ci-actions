# versioning/from-pyproject

Reads the static `[project].version` from a `pyproject.toml` (uv / PEP 621) and
outputs it as a `version` and a prefixed `tag` (e.g. `v1.2.3`). Pair it with
the release actions ([`release/tag-and-alias`](../../release/tag-and-alias) +
[`release/github-release`](../../release/github-release)) to release the version
declared in your project config instead of a separate `VERSION` file.

## Requirements

- **Python 3.11+** on the runner (uses the standard-library `tomllib` to parse
  the file). uv projects run modern Python, so this is normally already present.

## Inputs

| Input    | Required | Default          | Description                                    |
| -------- | -------- | ---------------- | ---------------------------------------------- |
| `file`   | no       | `pyproject.toml` | Path to the `pyproject.toml` to read.          |
| `prefix` | no       | `v`              | Prefix prepended to the version to form `tag`. |

## Outputs

| Output    | Description                    |
| --------- | ------------------------------ |
| `version` | Version string, e.g. `1.2.3`.  |
| `tag`     | Prefixed tag, e.g. `v1.2.3`.   |

## Usage

Release the version from `pyproject.toml`:

```yaml
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - id: ver
        uses: DataLabHell/ci-actions/actions/versioning/from-pyproject@v0.1

      - uses: DataLabHell/ci-actions/actions/release/tag-and-alias@v0.1
        with:
          tag: ${{ steps.ver.outputs.tag }}

      - uses: DataLabHell/ci-actions/actions/release/github-release@v0.1
        with:
          tag: ${{ steps.ver.outputs.tag }}
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
