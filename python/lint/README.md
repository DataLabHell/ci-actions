# python/lint

Lint and type-check a Python project with [ruff](https://docs.astral.sh/ruff/)
(`ruff check` + `ruff format --check`) and
[ty](https://github.com/astral-sh/ty), all run through `uv`. ruff issues fail
the job; ty is soft by default (reports a warning) so you can adopt typing
gradually.

## Requirements

- `uv` on the runner (self-hosted). ruff and ty are fetched on demand by `uvx`,
  so they don't need to be preinstalled — only `uv` does. The action fails fast
  if `uv` is missing.
- `actions/checkout@v4` before this step.

## Inputs

| Input              | Required | Default        | Description                                                                   |
| ------------------ | -------- | -------------- | ----------------------------------------------------------------------------- |
| `paths`            | no       | `.`            | Space-separated paths for `ruff check` + `ruff format --check`.               |
| `type-check`       | no       | `warn`         | `warn` (soft-fail with a `::warning`), `error` (hard fail), or `off` (skip).  |
| `type-check-paths` | no       | `.`            | Space-separated paths for `ty` (used only when `type-check` is not `off`).    |
| `sync-args`        | no       | `--all-groups` | Args for the `uv sync` run before `ty` (ty resolves against the project env). |

## Usage

```yaml
jobs:
  lint:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - uses: DataLabHell/ci-actions/python/lint@vX.Y
        with:
          paths: datalabhell scripts tests
          type-check-paths: datalabhell # ruff over everything, ty only on the package
```

Make typing block the build once it's clean:

```yaml
- uses: DataLabHell/ci-actions/python/lint@vX.Y
  with:
    type-check: error
```

## Notes

- ruff `check` and `format --check` are hard failures. `ty` follows
  `type-check`: `warn` prints a `::warning` and continues, `error` fails the
  job, `off` skips it (and skips the `uv sync` that ty needs).
- `type-check-paths` is separate from `paths` because you often want ruff to
  cover tests and scripts while ty checks only the package.
