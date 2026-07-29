# ci-actions

Shared, reusable GitHub Actions for the organization. This is a **monorepo**:
each action (the building blocks) lives in its own folder at the repo root, with
its own `action.yml` and `README.md`, and all are versioned together with a
single set of tags. Common multi-step flows (releasing, building an image) are
shown as copy-paste [examples](#common-workflows) rather than shipped as extra
actions, since they vary too much between repos to bundle cleanly.

## Available actions

| Action                               | Description                                                                                                            |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| [`s3-file-upload`](./s3-file-upload) | Upload files/folders to any S3-compatible bucket (RustFS, AWS S3, MinIO, on-prem) with glob include/exclude filtering. |
| [`docker/build-push`](./docker/build-push) | Build a container image with Buildx and push it to a registry (GHCR or local/on-prem) with sha/latest/version tags and layer caching. |
| [`release/tag-and-alias`](./release/tag-and-alias) | Create a `vX.Y.Z` tag and move the rolling `vX`/`vX.Y` aliases to it (no GitHub Release). |
| [`release/github-release`](./release/github-release) | Publish a GitHub Release for an existing tag, with notes and optional assets. |
| [`versioning/auto-patch`](./versioning/auto-patch) | Resolver: `MAJOR.MINOR` from a file + auto-incremented patch → next `vX.Y.Z` tag (feed into the release actions). |
| [`versioning/from-pyproject`](./versioning/from-pyproject) | Resolver: `[project].version` from a `pyproject.toml` (uv / PEP 621) → `vX.Y.Z` tag (feed into the release actions). |
| [`python/lint`](./python/lint) | Lint + type-check a Python project with ruff (`check` + `format`) and ty, via `uv`. |
| [`python/test`](./python/test) | Install with `uv` and run pytest, optionally pinned to a Python version. |
| [`mise-setup`](./mise-setup) | Provision a repo's tools with mise into a per-repository dir (cached installs, prune of unreferenced versions), so later steps can call them. |

## Using an action

Reference an action by `<owner>/ci-actions/<action-folder>@<tag>`:

```yaml
jobs:
  build:
    runs-on: self-hosted # s3-file-upload needs the dlh AWS profile on the runner
    steps:
      - uses: actions/checkout@v4

      - uses: DataLabHell/ci-actions/s3-file-upload@v0.2
        with:
          source: images
          bucket: reports
          destination: my-service/
          include: "*.html"
```

Always pin to a released tag (e.g. `@v0.2`) rather than `@main`, so downstream
workflows are not affected by in-progress changes on the default branch.

## Common workflows

The building blocks compose into a few recurring flows. These are **examples to
copy and adapt**, not separate actions, because the wiring varies per repo
(matrix builds, different version sources, and so on). Each caller owns the job:
runner, permissions, and checkout.

### Release from a VERSION file

Resolve the next version, create the tag and move the rolling `vX` / `vX.Y`
aliases, then publish a GitHub Release. Drop the last step if you only need tags.

```yaml
jobs:
  release:
    runs-on: self-hosted
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - id: ver
        uses: DataLabHell/ci-actions/versioning/auto-patch@v0.2
      - id: rel
        uses: DataLabHell/ci-actions/release/tag-and-alias@v0.2
        with:
          tag: ${{ steps.ver.outputs.version }}
      - uses: DataLabHell/ci-actions/release/github-release@v0.2
        with:
          tag: ${{ steps.rel.outputs.tag }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

Swap [`versioning/auto-patch`](./versioning/auto-patch) for
[`versioning/from-pyproject`](./versioning/from-pyproject) to read the version
from `pyproject.toml` instead of a `VERSION` file.

### Build and push a versioned image

Same version resolution, but tag a container image with the rolling set instead
of publishing a Release. This is the single-image shape; for several images in
one repo, see the matrix pattern in
[`docker/build-push`](./docker/build-push/README.md#matrix--release-two-jobs).

```yaml
jobs:
  publish:
    runs-on: self-hosted
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - id: ver
        uses: DataLabHell/ci-actions/versioning/auto-patch@v0.2
      - id: rel
        uses: DataLabHell/ci-actions/release/tag-and-alias@v0.2
        with:
          tag: ${{ steps.ver.outputs.version }}
      - uses: DataLabHell/ci-actions/docker/build-push@v0.2
        with:
          image: api
          registry: truenas
          cache: registry
          tags: |
            ${{ steps.rel.outputs.versions }}
            latest
```

### Python CI (lint + test matrix)

Lint and type-check once, then run pytest across Python versions. The matrix
lives in the caller because a composite action can't fan one out.

```yaml
jobs:
  lint:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - uses: DataLabHell/ci-actions/python/lint@v0.2
        with:
          paths: datalabhell scripts tests
          type-check-paths: datalabhell   # ruff over everything, ty only on the package

  test:
    runs-on: self-hosted
    strategy:
      fail-fast: true
      matrix:
        python-version: ["3.12", "3.13", "3.14"]
    steps:
      - uses: actions/checkout@v4
      - uses: DataLabHell/ci-actions/python/test@v0.2
        with:
          python-version: ${{ matrix.python-version }}
```

## Repository layout

```
ci-actions/
├── README.md                 # this file — index of all actions
├── VERSION                   # MAJOR.MINOR driving releases
├── mise.toml                 # dev tools + `mise run check` quality gate
├── .github/workflows/        # ci (mise quality gate) + release
├── _template/                # scaffold to copy when adding an action
│
│   # single actions (building blocks) — each in its own root folder:
├── s3-file-upload/           #   action.yml + upload.sh + README
├── mise-setup/               #   provision project tools with mise
├── docker/                   #   container image actions
│   └── build-push/           #     build + push an image (Buildx)
├── versioning/               #   resolvers: produce the next bare version X.Y.Z
│   ├── auto-patch/           #     MAJOR.MINOR file + auto patch
│   └── from-pyproject/       #     version from pyproject.toml
├── release/                  #   consume a tag
│   ├── tag-and-alias/        #     create tag + move vX / vX.Y aliases
│   └── github-release/       #     publish a GitHub Release
└── python/                   #   Python CI (uv-based)
    ├── lint/                 #     ruff check + format + ty
    └── test/                 #     uv sync + pytest
```

Multi-step flows (release, image build) are shown as
[copy-paste examples](#common-workflows), not as separate action folders.

## Adding a new action

Start from the [`_template/`](./_template) scaffold — it's a ready-to-fill
composite action plus README:

1. Copy `_template/` to `<name>/` at the repo root (kebab-case), e.g.
   `slack-notify/`. Group related actions in a subfolder if it helps (e.g.
   `docker/build-push/`).
2. Fill in `action.yml` — replace the `TODO` name/description and the example
   inputs/outputs. Prefer a **composite** action (the template's default): no
   build step, runs on any runner. Use Docker/JavaScript only if you
   specifically need them.
3. Put the shell logic in `main.sh` (the template calls it and passes inputs as
   `INPUT_*` env vars). Keeping shell in a `.sh` file lets CI lint it with
   shellcheck + shfmt — inline `run:` shell is not linted.
4. Fill in `README.md` — inputs table, outputs, and at least one usage example.
   Reference the action as `DataLabHell/ci-actions/<folder>@<tag>`.
5. Add a row to the [Available actions](#available-actions) table above.
6. Open a PR. Merging to `main` releases automatically (patch bump). If the new
   action warrants a minor bump, also edit [`VERSION`](#versioning) in the PR.

> The `_template/` folder is a scaffold, not a published action — the leading
> underscore keeps it sorted first and signals it isn't meant to be referenced.

## Local development

Tooling is managed by [mise](https://mise.jdx.dev). [`mise.toml`](./mise.toml)
pins the linters and defines the tasks, so the same commands run locally and in
CI:

```bash
mise install        # get shellcheck, shfmt and taplo
mise run check      # the full gate: format check + lint (what CI runs)
mise run format     # apply shfmt + taplo formatting
mise tasks          # list everything, including the per-language tasks
```

CI runs `mise run check` through this repo's own
[`mise-setup`](./mise-setup) action by local path, so a pull request is gated by
the version of that action it contains.

## Versioning

Releases are **automatic** and driven by the [`VERSION`](./VERSION) file, which
holds the `MAJOR.MINOR` (e.g. `0.1`). All actions share the same tags (a tag is a
snapshot of the whole repo), and consumers reference
`DataLabHell/ci-actions/<action>@<tag>`.

The [Release workflow](.github/workflows/release.yml) runs on every push to
`main` and chains this repo's own actions (dogfooding): a **resolver** produces
the next bare version, then the **release** actions tag it and publish it.

1. [`versioning/auto-patch`](./versioning/auto-patch) reads `MAJOR.MINOR` from
   `VERSION`, finds the highest existing `vMAJOR.MINOR.*` tag, and
   **auto-increments the patch** (starting at `.0` if the series is new) →
   outputs the next **bare** version `MAJOR.MINOR.PATCH`.
2. [`release/tag-and-alias`](./release/tag-and-alias) takes that version, owns
   the tag format (adds the `v`), creates the `vMAJOR.MINOR.PATCH` tag, and moves
   the rolling `vMAJOR` / `vMAJOR.MINOR` aliases to it — outputting the canonical tag.
3. [`release/github-release`](./release/github-release) publishes a GitHub
   Release for the tag from step 2.

Both halves are pluggable: swap step 1 for
[`versioning/from-pyproject`](./versioning/from-pyproject) (or any step that
outputs a bare `X.Y.Z` version) to change the version source, and drop step 3 when
you only need tags (e.g. a container build) — the pieces compose.

### Everyday changes → patch bump

Merge a change to any action to `main`. You don't touch `VERSION`. Each such
push releases the next patch automatically: `v0.2.0` → `v0.2.1` → …

Only changes to action files cut a release — an `action.yml`, an action script
(`*.sh`), or the `VERSION` file. **README/docs-only changes do not** (the
workflow's `paths` filter skips them), so you don't get empty patch bumps for
documentation edits.

### Bumping major or minor

Edit `VERSION` and merge it. Because the new series has no tags yet, the next
release starts at patch `0`, and the alias tags follow:

| `VERSION` change | Next release | Aliases moved |
| ---------------- | ------------ | ------------- |
| `0.1` → `0.2`    | `v0.2.0`     | `v0`, `v0.2`  |
| `0.9` → `1.0`    | `v1.0.0`     | `v1`, `v1.0`  |

Follow semver: bump **minor** for new features, **major** for breaking changes
to an action's inputs or behavior.

### What consumers pin to

Using the current `0.2` series as the example:

- `@v0.2` — rolling minor alias; **the recommended pin** while on `0.x` (moves on
  patches only, never breaking).
- `@v0.2.0` — an exact, immutable release.
- `@v0` — rolling major alias; **not recommended during `0.x`**, because it moves
  with every release including the next minor (`0.2` → `0.3`), which may be breaking.

Follow semver: while on `0.x`, breaking changes bump the **minor** (`0.2` →
`0.3`), so consumers pinned to `@v0.2` stay safe — the break lands on `0.3`, which
`@v0.2` never follows. You don't need a `1.0` for this; stay on `0.x` as long as
you like. Once the API is stable, bump `VERSION` to `1.0`; after that, breaking
changes bump the major and `@v1` users are protected, and `@v1` becomes a safe pin.

## Conventions

- **Inputs/outputs:** kebab-case names.
- **Secrets:** never echo credentials or write them to disk beyond an ephemeral,
  job-scoped file; pass them via `secrets`, not plain inputs.
- **Shell steps:** start bash scripts with `set -euo pipefail`.
- **Docs:** every action folder must have a `README.md` with an inputs table
  and a usage example.
