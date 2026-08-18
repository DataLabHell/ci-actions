# python/test

Install a Python project with `uv` and run pytest, optionally pinned to a
specific Python version. One version per invocation; run several by putting the
versions in a matrix in the caller (see below).

## Requirements

- Nothing preinstalled. The action installs `uv` itself via
  [`astral-sh/setup-uv`](https://github.com/astral-sh/setup-uv).
- `actions/checkout@v7` before this step.

## Inputs

| Input            | Required | Default                     | Description                                                           |
| ---------------- | -------- | --------------------------- | --------------------------------------------------------------------- |
| `python-version` | no       | `''`                        | Python version to test against, e.g. `3.13`. Empty = project default. |
| `sync-args`      | no       | `--all-groups --all-extras` | Args passed to `uv sync`.                                             |
| `pytest-args`    | no       | `''`                        | Extra args passed to pytest (e.g. `-q tests/unit`).                   |

## Usage: matrix over Python versions

`python-version` is a single value, so the matrix lives in the caller's job:

```yaml
jobs:
  test:
    runs-on: self-hosted
    strategy:
      fail-fast: true
      matrix:
        python-version: ["3.12", "3.13", "3.14"]
    steps:
      - uses: actions/checkout@v7
      - uses: DataLabHell/ci-actions/python/test@python/test/vX.Y.Z
        with:
          python-version: ${{ matrix.python-version }}
```

## Notes

- When `python-version` is set, it's passed to both `uv sync` and `uv run` so
  the environment and the test run use the same interpreter.
- The matrix (and its `fail-fast`) belongs to the caller, because a composite
  action can't fan one out itself.
