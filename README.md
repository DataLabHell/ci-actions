# ci-actions

Shared, reusable GitHub Actions for the organization. This is a **monorepo** —
each action lives in its own top-level folder with its own `action.yml` and
`README.md`, and all of them are versioned together with a single set of tags.

## Available actions

| Action | Description |
|---|---|
| [`s3-file-upload`](./s3-file-upload) | Upload files/folders to any S3-compatible bucket (RustFS, AWS S3, MinIO, on-prem) with glob include/exclude filtering. |
| [`auto-release`](./auto-release) | VERSION-file driven releases: auto-increment patch, tag, move `vX`/`vX.Y` aliases, publish a GitHub Release. |

## Using an action

Reference an action by `<owner>/ci-actions/<action-folder>@<tag>`:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: DataLabHell/ci-actions/s3-file-upload@v1
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        with:
          source: out
          destination: my-service/${{ github.run_id }}
```

Always pin to a released tag (e.g. `@v1`) rather than `@main`, so downstream
pipelines are not affected by in-progress changes on the default branch.

## Repository layout

```
ci-actions/
├── README.md                 # this file — index of all actions
├── VERSION                   # MAJOR.MINOR driving releases
├── _template/                # scaffold to copy when adding an action
├── s3-file-upload/           # one folder per action
│   ├── action.yml            # the action definition
│   └── README.md             # action-specific docs
└── <next-action>/
    ├── action.yml
    └── README.md
```

## Adding a new action

Start from the [`_template/`](./_template) scaffold — it's a ready-to-fill
composite action plus README:

1. Copy `_template/` to a kebab-case folder named after the action, e.g.
   `slack-notify/`.
2. Fill in `action.yml` — replace the `TODO` name/description and the
   example inputs/outputs/steps. Prefer a **composite** action (the template's
   default): no build step, runs on any runner. Use Docker/JavaScript only if
   you specifically need them.
3. Fill in `README.md` — inputs table, outputs, and at least one usage example.
   Reference the action as `DataLabHell/ci-actions/<folder>@<tag>`.
4. Add a row to the [Available actions](#available-actions) table above.
5. Open a PR. Merging to `main` releases automatically (patch bump). If the new
   action warrants a minor bump, also edit [`VERSION`](#versioning) in the PR.

> The `_template/` folder is a scaffold, not a published action — the leading
> underscore keeps it sorted first and signals it isn't meant to be referenced.

## Versioning

Releases are **automatic** and driven by the [`VERSION`](./VERSION) file, which
holds the `MAJOR.MINOR` (e.g. `1.0`). All actions share the same tags (a tag is a
snapshot of the whole repo), and consumers reference
`DataLabHell/ci-actions/<action>@<tag>`.

The [Release workflow](.github/workflows/release.yml) runs on every push to
`main` and delegates to this repo's own [`auto-release`](./auto-release) action
(dogfooding). It:

1. reads `MAJOR.MINOR` from `VERSION`,
2. finds the highest existing `vMAJOR.MINOR.*` tag and **auto-increments the
   patch** (starting at `.0` if the series is new),
3. creates the new `vMAJOR.MINOR.PATCH` tag,
4. moves the rolling `vMAJOR` and `vMAJOR.MINOR` alias tags to it,
5. publishes a GitHub Release with generated notes.

### Everyday changes → patch bump

Just merge to `main`. You don't touch `VERSION`. Each push releases the next
patch automatically: `v1.0.3` → `v1.0.4` → …

### Bumping major or minor

Edit `VERSION` and merge it. Because the new series has no tags yet, the next
release starts at patch `0`, and the alias tags follow:

| `VERSION` change | Next release | Aliases moved     |
| ---------------- | ------------ | ----------------- |
| `1.0` → `1.1`    | `v1.1.0`     | `v1`, `v1.1`      |
| `1.4` → `2.0`    | `v2.0.0`     | `v2`, `v2.0`      |

Follow semver: bump **minor** for new features, **major** for breaking changes
to an action's inputs or behavior.

### What consumers pin to

- `@v1` — rolling major alias; auto-updates within the major version.
  Recommended for most pipelines.
- `@v1.1` — rolling minor alias.
- `@v1.1.0` — an exact, immutable release.

Because the major alias moves on each release, a breaking change **must** go out
as a new major (bump `VERSION` to `2.0`) so `@v1` users are never broken.

## Conventions

- **Inputs/outputs:** kebab-case names.
- **Secrets:** never echo credentials or write them to disk beyond an ephemeral,
  job-scoped file; pass them via `secrets`, not plain inputs.
- **Shell steps:** start bash scripts with `set -euo pipefail`.
- **Docs:** every action folder must have a `README.md` with an inputs table
  and a usage example.
