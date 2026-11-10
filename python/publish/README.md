# python/publish

Build a Python project with `uv` and publish it to a devpi index. Republishing
an existing version is a no-op, not a failure (`uv publish --check-url`).

Only `main` publishes, so the same workflow can run on feature branches without
pushing anything. Set `publish-other-branches: true` to publish from those too —
they go out as prereleases, `X.Y.Z.dev<pr>+<short-sha>` (branch builds are
expected to be pull-request triggered; a non-PR ref falls back to `dev0`), so a
final version can only ever come from `main`.

## Requirements

- Nothing preinstalled. The action installs `uv` itself via
  [`astral-sh/setup-uv`](https://github.com/astral-sh/setup-uv).
- `actions/checkout@v7` before this step (with `fetch-depth: 0` if the project
  uses setuptools-scm and you resolve the version from tags).
- The devpi index URL and the publishing user's credentials, passed as `url`,
  `username` and `password`.

## Inputs

| Input                    | Required | Default | Description                                                                                         |
| ------------------------ | -------- | ------- | --------------------------------------------------------------------------------------------------- |
| `version`                | no       | `''`    | Bare `X.Y.Z` from a `versioning/` action. Required for dynamic versioning, ignored for a fixed one. |
| `release-branch`         | no       | `main`  | The only branch that publishes a final version.                                                     |
| `publish-other-branches` | no       | `false` | Also publish other refs, as `X.Y.Z.dev<pr>+<short-sha>`.                                            |
| `build`                  | no       | `true`  | Run `uv build` before publishing.                                                                   |
| `build-args`             | no       | `''`    | Extra args passed to `uv build`.                                                                    |
| `url`                    | yes      |         | Base URL of the devpi index.                                                                        |
| `username`               | yes      |         | devpi user to publish as.                                                                           |
| `password`               | yes      |         | Password of the devpi user.                                                                         |

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
version gets `.dev<pr>+<short-sha>` appended — via
`SETUPTOOLS_SCM_PRETEND_VERSION` for dynamic projects, and via `uv version` into
the throwaway checkout's `pyproject.toml` for fixed ones. Nothing is committed.

## Usage

Fixed version in `pyproject.toml`:

```yaml
jobs:
  publish:
    runs-on: self-hosted
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v7

      - uses: DataLabHell/ci-actions/python/publish@python/publish-vX.Y.Z
        with:
          url: ${{ secrets.INTERNAL_PYPI_INDEX_URL }}
          username: ${{ secrets.INTERNAL_PYPI_PUBLISH_USERNAME }}
          password: ${{ secrets.INTERNAL_PYPI_PUBLISH_PASSWORD }}
```

Dynamic version, resolved from a `VERSION` file plus the existing tags:

```yaml
jobs:
  publish:
    runs-on: self-hosted
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0 # tags, for the patch bump

      - id: version
        uses: DataLabHell/ci-actions/versioning/auto-patch@versioning/auto-patch-vX.Y.Z

      - uses: DataLabHell/ci-actions/python/publish@python/publish-vX.Y.Z
        with:
          url: ${{ secrets.INTERNAL_PYPI_INDEX_URL }}
          username: ${{ secrets.INTERNAL_PYPI_PUBLISH_USERNAME }}
          password: ${{ secrets.INTERNAL_PYPI_PUBLISH_PASSWORD }}
          version: ${{ steps.version.outputs.version }}
          publish-other-branches: true # feature branches get X.Y.Z.dev<pr>+<sha>
```

## Notes

- `--check-url` points at `<index URL>/+simple/`, the devpi/PEP 503 index of the
  same base URL.
