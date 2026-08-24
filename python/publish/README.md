# python/publish

Build a Python project with `uv` and publish it to a package index (the internal
devpi by default). Republishing an existing version is a no-op, not a failure
(`uv publish --check-url`).

Only `main` publishes, so the same workflow can run on feature branches without
pushing anything. Set `publish-other-branches: true` to publish from those too —
they go out as prereleases, `X.Y.Z.dev0+<short-sha>`, so a final version can
only ever come from `main`.

## Requirements

- Nothing preinstalled. The action installs `uv` itself via
  [`astral-sh/setup-uv`](https://github.com/astral-sh/setup-uv).
- `actions/checkout@v7` before this step (with `fetch-depth: 0` if the project
  uses setuptools-scm and you resolve the version from tags).

## Inputs

| Input                    | Required | Default                                        | Description                                                                                         |
| ------------------------ | -------- | ---------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `username`               | yes      | —                                              | Index username.                                                                                     |
| `password`               | yes      | —                                              | Index password / token.                                                                             |
| `version`                | no       | `''`                                           | Bare `X.Y.Z` from a `versioning/` action. Required for dynamic versioning, ignored for a fixed one. |
| `release-branch`         | no       | `main`                                         | The only branch that publishes a final version.                                                     |
| `publish-other-branches` | no       | `false`                                        | Also publish other refs, as `X.Y.Z.dev0+<short-sha>`.                                               |
| `publish-url`            | no       | `https://devpi.apps.dlh-k8s.com/root/internal` | Base URL of the index (no trailing `+simple`).                                                      |
| `build`                  | no       | `true`                                         | Run `uv build` before publishing.                                                                   |
| `build-args`             | no       | `''`                                           | Extra args passed to `uv build`.                                                                    |

## Outputs

| Output      | Description                                          |
| ----------- | ---------------------------------------------------- |
| `published` | `true` if the publish ran, `false` if it was skipped |
| `version`   | The version published (empty when skipped)           |

## Versioning

How the version is determined depends on the project:

- **Fixed version** — `[project].version` in `pyproject.toml`. Nothing to pass;
  the `version` input is ignored (a mismatch is warned about). Use
  [`versioning/from-pyproject`](../../versioning/from-pyproject) if a later step
  (tagging, a release) needs the same value.
- **Dynamic version** — `[project].dynamic` contains `version` (setuptools-scm
  and friends). Resolve it with
  [`versioning/auto-patch`](../../versioning/auto-patch) (or
  `versioning/from-pyproject` for a different file) and pass it as `version`;
  the action exports it as `SETUPTOOLS_SCM_PRETEND_VERSION` for the build.

Off the release branch (with `publish-other-branches: true`) the resolved
version gets `.dev0+<short-sha>` appended — via `SETUPTOOLS_SCM_PRETEND_VERSION`
for dynamic projects, and via `uv version` into the throwaway checkout's
`pyproject.toml` for fixed ones. Nothing is committed.

## Usage

Fixed version in `pyproject.toml`:

```yaml
jobs:
  publish:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v7

      - uses: DataLabHell/ci-actions/python/publish@python/publish/vX.Y.Z
        with:
          username: ${{ secrets.DEVPI_USERNAME }}
          password: ${{ secrets.DEVPI_PASSWORD }}
```

Dynamic version, resolved from a `VERSION` file plus the existing tags:

```yaml
jobs:
  publish:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0 # tags, for the patch bump

      - id: version
        uses: DataLabHell/ci-actions/versioning/auto-patch@versioning/auto-patch/vX.Y.Z

      - uses: DataLabHell/ci-actions/python/publish@python/publish/vX.Y.Z
        with:
          version: ${{ steps.version.outputs.version }}
          username: ${{ secrets.DEVPI_USERNAME }}
          password: ${{ secrets.DEVPI_PASSWORD }}
          publish-other-branches: true # feature branches get X.Y.Z.dev0+<sha>
```

## Notes

- The index URL is an input rather than a repository variable so the caller
  decides where it comes from — pass `${{ vars.DEVPI_URL }}` to keep overriding
  it per repo.
- `--check-url` points at `<publish-url>/+simple/`, the devpi/PEP 503 index of
  the same base URL.
