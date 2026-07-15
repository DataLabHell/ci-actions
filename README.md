# ci-actions

Shared, reusable GitHub Actions for the organization. This is a **monorepo**:
single actions (the building blocks) live under [`actions/`](./actions), and
ready-made combinations that chain them live under
[`pipelines/`](./pipelines). Each has its own `action.yml` and `README.md`, and
all are versioned together with a single set of tags.

## Available actions

| Action                               | Description                                                                                                            |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| [`s3-file-upload`](./actions/s3-file-upload) | Upload files/folders to any S3-compatible bucket (RustFS, AWS S3, MinIO, on-prem) with glob include/exclude filtering. |
| [`release/tag-and-alias`](./actions/release/tag-and-alias) | Create a `vX.Y.Z` tag and move the rolling `vX`/`vX.Y` aliases to it (no GitHub Release). |
| [`release/github-release`](./actions/release/github-release) | Publish a GitHub Release for an existing tag, with notes and optional assets. |
| [`versioning/auto-patch`](./actions/versioning/auto-patch) | Resolver: `MAJOR.MINOR` from a file + auto-incremented patch → next `vX.Y.Z` tag (feed into the release actions). |
| [`versioning/from-pyproject`](./actions/versioning/from-pyproject) | Resolver: `[project].version` from a `pyproject.toml` (uv / PEP 621) → `vX.Y.Z` tag (feed into the release actions). |

## Using an action

Reference an action by `<owner>/ci-actions/<action-folder>@<tag>`:

```yaml
jobs:
  build:
    runs-on: self-hosted # s3-file-upload needs the dlh AWS profile on the runner
    steps:
      - uses: actions/checkout@v4

      - uses: DataLabHell/ci-actions/actions/s3-file-upload@v0.1
        with:
          source: images
          bucket: reports
          destination: my-service/
          include: "*.html"
```

Always pin to a released tag (e.g. `@v0.1`) rather than `@main`, so downstream
pipelines are not affected by in-progress changes on the default branch.

## Premade pipelines

For the common cases, use a ready-made pipeline instead of wiring the steps
yourself. These are **composite actions that chain the smaller ones** (referenced
with `uses:` like any action — they just bundle several):

| Pipeline | Purpose |
|---|---|
| [`pipelines/release-from-version`](./pipelines/release-from-version) | Resolve the next version from a `VERSION` file, tag it, move `vX`/`vX.Y` aliases, and publish a GitHub Release — in one step. |

```yaml
jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: DataLabHell/ci-actions/pipelines/release-from-version@v0
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

A pipeline is still an action (a *step*), so the caller owns the job — runner,
`permissions: contents: write`, and checkout. For anything beyond the common
case, compose the individual actions yourself (below).

## Repository layout

```
ci-actions/
├── README.md                 # this file — index of all actions
├── VERSION                   # MAJOR.MINOR driving releases
├── .github/workflows/        # lint (shellcheck) + release
├── _template/                # scaffold to copy when adding an action
├── actions/                  # single actions (building blocks)
│   ├── s3-file-upload/       #   action.yml + upload.sh + README
│   ├── versioning/           #   resolvers: produce the next vX.Y.Z tag
│   │   ├── auto-patch/       #     MAJOR.MINOR file + auto patch
│   │   └── from-pyproject/   #     version from pyproject.toml
│   └── release/              #   consume a tag
│       ├── tag-and-alias/    #     create tag + move vX / vX.Y aliases
│       └── github-release/   #     publish a GitHub Release
└── pipelines/                # chained combos of the above
    └── release-from-version/ #   resolve + tag + release, in one step
```

## Adding a new action

Start from the [`_template/`](./_template) scaffold — it's a ready-to-fill
composite action plus README:

1. Copy `_template/` to `actions/<name>/` (kebab-case), e.g.
   `actions/slack-notify/`.
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

## Versioning

Releases are **automatic** and driven by the [`VERSION`](./VERSION) file, which
holds the `MAJOR.MINOR` (e.g. `0.1`). All actions share the same tags (a tag is a
snapshot of the whole repo), and consumers reference
`DataLabHell/ci-actions/<action>@<tag>`.

The [Release workflow](.github/workflows/release.yml) runs on every push to
`main` and chains this repo's own actions (dogfooding): a **resolver** produces
the next tag, then the **release** actions tag it and publish it.

1. [`versioning/auto-patch`](./actions/versioning/auto-patch) reads `MAJOR.MINOR` from
   `VERSION`, finds the highest existing `vMAJOR.MINOR.*` tag, and
   **auto-increments the patch** (starting at `.0` if the series is new) →
   outputs the next `vMAJOR.MINOR.PATCH` tag.
2. [`release/tag-and-alias`](./actions/release/tag-and-alias) creates that tag and moves
   the rolling `vMAJOR` / `vMAJOR.MINOR` aliases to it.
3. [`release/github-release`](./actions/release/github-release) publishes a GitHub
   Release for the tag.

Both halves are pluggable: swap step 1 for
[`versioning/from-pyproject`](./actions/versioning/from-pyproject) (or any step that
outputs a `vX.Y.Z` tag) to change the version source, and drop step 3 when you
only need tags (e.g. a container build) — the pieces compose.

### Everyday changes → patch bump

Merge a change to any action to `main`. You don't touch `VERSION`. Each such
push releases the next patch automatically: `v0.1.3` → `v0.1.4` → …

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

- `@v0` — rolling major alias; moves with every release (during `0.x` this can
  include breaking changes).
- `@v0.1` — rolling minor alias; the recommended pin while on `0.x` (patches
  only).
- `@v0.1.0` — an exact, immutable release.

Follow semver: while on `0.x`, breaking changes bump the **minor** (`0.1` →
`0.2`), so consumers pinned to `@v0.1` stay safe. Once the API is stable, bump
`VERSION` to `1.0`; after that, breaking changes bump the major and `@v1` users
are protected.

## Conventions

- **Inputs/outputs:** kebab-case names.
- **Secrets:** never echo credentials or write them to disk beyond an ephemeral,
  job-scoped file; pass them via `secrets`, not plain inputs.
- **Shell steps:** start bash scripts with `set -euo pipefail`.
- **Docs:** every action folder must have a `README.md` with an inputs table
  and a usage example.
