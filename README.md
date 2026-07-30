# ci-actions

Shared GitHub Actions and workflows for the organization. This is a
**monorepo**: each action (the building blocks) lives in its own folder at the
repo root, with its own `action.yml` and `README.md`, and everything is
versioned together with a single set of tags.

Two kinds of things ship from here:

- **[Actions](#available-actions)**: one step you drop into a job you own.
- **[Reusable workflows](#available-workflows)**: a whole job, triggers
  excepted, for flows where the job body itself is the value (Renovate is the
  first). They live flat in `.github/workflows/`, because GitHub does not
  resolve a workflow `uses:` reference in a subfolder.

Multi-step flows that vary too much between repos to bundle cleanly (releasing,
building an image) are neither: they stay copy-paste
[composition examples](#composition-examples).

## Available actions

| Action                                                     | Description                                                                                                                                   |
| ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| [`s3-file-upload`](./s3-file-upload)                       | Upload files/folders to any S3-compatible bucket (RustFS, AWS S3, MinIO, on-prem) with glob include/exclude filtering.                        |
| [`docker/build-push`](./docker/build-push)                 | Build a container image with Buildx and push it to a registry (GHCR or local/on-prem) with sha/latest/version tags and layer caching.         |
| [`release/tag-and-alias`](./release/tag-and-alias)         | Create a `vX.Y.Z` tag and move the rolling `vX`/`vX.Y` aliases to it (no GitHub Release).                                                     |
| [`release/github-release`](./release/github-release)       | Publish a GitHub Release for an existing tag, with notes and optional assets.                                                                 |
| [`versioning/auto-patch`](./versioning/auto-patch)         | Resolver: `MAJOR.MINOR` from a file + auto-incremented patch → next `vX.Y.Z` tag (feed into the release actions).                             |
| [`versioning/from-pyproject`](./versioning/from-pyproject) | Resolver: `[project].version` from a `pyproject.toml` (uv / PEP 621) → `vX.Y.Z` tag (feed into the release actions).                          |
| [`python/lint`](./python/lint)                             | Lint + type-check a Python project with ruff (`check` + `format`) and ty, via `uv`.                                                           |
| [`python/test`](./python/test)                             | Install with `uv` and run pytest, optionally pinned to a Python version.                                                                      |
| [`mise-setup`](./mise-setup)                               | Provision a repo's tools with mise into a per-repository dir (cached installs, prune of unreferenced versions), so later steps can call them. |

## Using an action

Reference an action by `<owner>/ci-actions/<action-folder>@<tag>`:

```yaml
jobs:
  build:
    runs-on: self-hosted # s3-file-upload needs the dlh AWS profile on the runner
    steps:
      - uses: actions/checkout@v4

      - uses: DataLabHell/ci-actions/s3-file-upload@vX.Y
        with:
          source: images
          bucket: reports
          destination: my-service/
          include: "*.html"
```

`@vX.Y` throughout these docs is a placeholder, not a tag: substitute the
current minor alias, which is the `MAJOR.MINOR` in [`VERSION`](./VERSION) and
the newest entry under
[releases](https://github.com/DataLabHell/ci-actions/releases). Always pin to a
released tag rather than `@main`, so downstream workflows are not affected by
in-progress changes on the default branch.

## Available workflows

| Workflow                                           | Description                                                                                                                   |
| -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| [`renovate.yml`](./.github/workflows/renovate.yml) | Run Renovate against the calling repo, with ghcr credentials wired up. [Inputs and secrets](#renovateyml-inputs-and-secrets). |

## Using a workflow

Reference a workflow by `<owner>/ci-actions/.github/workflows/<file>.yml@<tag>`,
the full path, including `.github/workflows/`, because that is the only place
GitHub resolves one from. It replaces the whole job, so the caller supplies just
the triggers and the secrets:

```yaml
name: Renovate

on:
  schedule:
    - cron: "0 */6 * * *" # every 6 hours
  workflow_dispatch: # allow manual triggering

jobs:
  renovate:
    uses: DataLabHell/ci-actions/.github/workflows/renovate.yml@vX.Y
    secrets:
      RENOVATE_TOKEN: ${{ secrets.RENOVATE_TOKEN }}
```

Two things a shared workflow cannot do for you:

- **Triggers.** A called workflow's own `on:` block is ignored, so the `cron`
  and `workflow_dispatch` above have to live in your repo. Note that `schedule`
  only fires on the default branch, so the stub has to be merged before it runs.
- **Tool config.** Renovate's rules stay in your repo's `renovate.json`. This
  workflow runs the bot; it does not decide what the bot does.

### `renovate.yml` inputs and secrets

| Input       | Required | Default       | Description                                                                           |
| ----------- | -------- | ------------- | ------------------------------------------------------------------------------------- |
| `runs-on`   | no       | `self-hosted` | Runner label for the job. Pass `ubuntu-latest` on a repo without self-hosted runners. |
| `log-level` | no       | `info`        | Renovate `LOG_LEVEL`. Set to `debug` to trace a run that finds nothing.               |

| Secret           | Required | Description                                                                       |
| ---------------- | -------- | --------------------------------------------------------------------------------- |
| `RENOVATE_TOKEN` | no       | PAT with contents + pull-request write. Falls back to `GITHUB_TOKEN` when absent. |

Secret names stay `UPPER_SNAKE` while inputs are kebab-case, because a hyphen in
`${{ secrets.x-y }}` reads as an operator.

The secret is optional on purpose. The free plan has no organization-wide
secrets for private repos, so requiring a PAT would mean re-adding it to every
calling repo, the same constraint that keeps the
[`s3-file-upload` credentials on the runner](./s3-file-upload/README.md#connection--credentials).
Omit it and the job uses its own `GITHUB_TOKEN`, which needs no setup and can
open pull requests; the catch is that those pull requests do not trigger your
CI. GitHub blocks that, and Renovate cannot work around it. Add the PAT to the
repos where you want Renovate's pull requests to run the pipeline.

## Composition examples

The building blocks compose into a few recurring flows. These are **examples to
copy and adapt**, not separate actions, because the wiring varies per repo
(matrix builds, different version sources, and so on). Each caller owns the job:
runner, permissions, and checkout.

### Release from a VERSION file

Resolve the next version, create the tag and move the rolling `vX` / `vX.Y`
aliases, then publish a GitHub Release. Drop the last step if you only need
tags.

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
        uses: DataLabHell/ci-actions/versioning/auto-patch@vX.Y
      - id: rel
        uses: DataLabHell/ci-actions/release/tag-and-alias@vX.Y
        with:
          tag: ${{ steps.ver.outputs.version }}
      - uses: DataLabHell/ci-actions/release/github-release@vX.Y
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
        uses: DataLabHell/ci-actions/versioning/auto-patch@vX.Y
      - id: rel
        uses: DataLabHell/ci-actions/release/tag-and-alias@vX.Y
        with:
          tag: ${{ steps.ver.outputs.version }}
      - uses: DataLabHell/ci-actions/docker/build-push@vX.Y
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
      - uses: DataLabHell/ci-actions/python/lint@vX.Y
        with:
          paths: datalabhell scripts tests
          type-check-paths: datalabhell # ruff over everything, ty only on the package

  test:
    runs-on: self-hosted
    strategy:
      fail-fast: true
      matrix:
        python-version: ["3.12", "3.13", "3.14"]
    steps:
      - uses: actions/checkout@v4
      - uses: DataLabHell/ci-actions/python/test@vX.Y
        with:
          python-version: ${{ matrix.python-version }}
```

## Repository layout

```
ci-actions/
├── README.md                 # this file — index of all actions
├── VERSION                   # MAJOR.MINOR driving releases
├── mise.toml                 # dev tools (exact pins) + `mise run check` gate
├── renovate.json             # what Renovate keeps updated here
├── .github/workflows/        # a leading _ marks this repo's own CI; the rest are published
│   ├── _ci.yml               #   internal: the mise quality gate
│   ├── _release.yml          #   internal: tag + GitHub Release
│   ├── _renovate.yml         #   internal: calls renovate.yml below on a cron
│   └── renovate.yml          #   PUBLISHED reusable workflow
├── _template/                # scaffold to copy when adding an action
├── tools/                    # helpers we ship or use — programs, not actions
│   └── local-renovate/       #   run Renovate locally, preview or apply bumps
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
[copy-paste examples](#composition-examples), not as separate action folders.

## Adding a new action

Start from the [`_template/`](./_template) scaffold, a ready-to-fill composite
action plus README:

1. Copy `_template/` to `<name>/` at the repo root (kebab-case), e.g.
   `slack-notify/`. Group related actions in a subfolder if it helps (e.g.
   `docker/build-push/`).
2. Fill in `action.yml`: replace the `TODO` name/description and the example
   inputs/outputs. Prefer a **composite** action (the template's default): no
   build step, runs on any runner. Use Docker/JavaScript only if you
   specifically need them.
3. Put the shell logic in `main.sh` (the template calls it and passes inputs as
   `INPUT_*` env vars). Keeping shell in a `.sh` file lets CI lint it with
   shellcheck + shfmt. Inline `run:` shell is not linted.
4. Fill in `README.md`: inputs table, outputs, and at least one usage example.
   Reference the action as `DataLabHell/ci-actions/<folder>@<tag>`.
5. Add a row to the [Available actions](#available-actions) table above.
6. Open a PR. Merging to `main` releases automatically (patch bump). If the new
   action warrants a minor bump, also edit [`VERSION`](#versioning) in the PR.

> The `_template/` folder is a scaffold, not a published action. The leading
> underscore keeps it sorted first and signals it isn't meant to be referenced.

## Adding a new workflow

Reach for a reusable workflow instead of an action when the value is the job
body (the runner, permissions, concurrency and pinned third-party SHAs) and only
the triggers differ per repo. There is no scaffold; copy
[`renovate.yml`](./.github/workflows/renovate.yml).

1. Add `<name>.yml` **flat** in `.github/workflows/`, with no leading
   underscore. Subfolders do not work: GitHub only resolves a workflow reference
   at `.github/workflows/<file>.yml`. The underscore is reserved for this repo's
   own CI, the same signal `_template/` uses.
2. Use `on: workflow_call` only. Declare every knob as a typed `input` with a
   `description` and a default, and every credential under `secrets`. Input
   names are kebab-case as elsewhere in this repo; secret names cannot contain
   hyphens, so those are `UPPER_SNAKE`.
3. Set `permissions` and `concurrency` in the workflow itself rather than
   leaving them to the caller. Capping its own token is the point of shipping
   the job.
4. Add a row to the [Available workflows](#available-workflows) table, and a
   stub the caller can paste (triggers + secrets) if the trigger is not obvious.
5. Open a PR. Merging to `main` releases automatically, same as an action: the
   release trigger covers `.github/workflows/*.yml` but skips the `_`-prefixed
   files.

## Local development

Tooling is managed by [mise](https://mise.jdx.dev). [`mise.toml`](./mise.toml)
pins the linters and defines the tasks, so the same commands run locally and in
CI:

```bash
mise install        # get the linters, jq and renovate
mise run check      # the full gate: format check + lint + test (what CI runs)
mise run format     # apply shfmt, prettier and taplo formatting
mise run test       # the local-renovate fixture tests on their own
mise run renovate   # list pending dependency bumps (alias: `dependencies`)
mise tasks          # list everything, including the per-language tasks
```

What the gate covers, so that everything this repo ships is checked:

| Tool                        | Covers                                      |
| --------------------------- | ------------------------------------------- |
| `action-validator`          | every `action.yml` and workflow, by schema  |
| `actionlint`                | `.github/workflows/`                        |
| `shellcheck`, `shfmt`       | `*.sh`                                      |
| `renovate-config-validator` | `renovate.json` (strict)                    |
| `prettier`                  | YAML, Markdown, JSON                        |
| `taplo`                     | TOML                                        |
| `tools/local-renovate`      | the rewrite methods, against canned reports |

GitHub YAML goes through two tools because neither covers the other's ground.
actionlint parses whatever it is given as a workflow, so it cannot read an
`action.yml` at all; action-validator picks the right schema per file and is
what checks the 10 actions this repo ships. Workflows then get both: actionlint
is the stronger check there, since it type-checks expressions, runs shellcheck
over `run:` blocks, and resolves a reference into a local action or reusable
workflow to verify the inputs and secrets passed to it. action-validator is a
cheap second opinion on top.

Neither one lints the steps inside an action as code. That is what keeping each
action's logic in a `.sh` file buys: shellcheck and shfmt reach it, and would
not reach inline `run:` shell.

CI runs `mise run check` through this repo's own [`mise-setup`](./mise-setup)
action by local path, so a pull request is gated by the version of that action
it contains.

## Dependency updates

Renovate keeps this repo current, driven by [`renovate.json`](./renovate.json)
and run by [`_renovate.yml`](./.github/workflows/_renovate.yml), which calls
this repo's own published [`renovate.yml`](./.github/workflows/renovate.yml) by
local path. So the shared workflow is exercised here before consumers get it.

Two things are tracked, both kept as exact pins:

- **mise tool versions** in [`mise.toml`](./mise.toml). Every entry is an exact
  version, never `latest` or `lts`, so the version a CI run installs is the
  version the file records. Renovate's mise manager covers the `core`, `aqua`
  and `npm` backends this repo uses.
- **Node stays on LTS with no rule needed.** The mise manager resolves `node`
  through the `node-version` datasource, whose default versioning scheme counts
  a release as unstable until its major line reaches the LTS date published in
  [nodejs/Release](https://github.com/nodejs/Release). `ignoreUnstable` defaults
  to true, so a Current release such as 25.x is never proposed, and neither is
  an even major during the months before it enters LTS. To lock to a single line
  rather than follow LTS to LTS, `allowedVersions` accepts an LTS
  [codename](https://github.com/nodejs/Release/blob/main/CODENAMES.md) and
  expands it to that major, so `krypton` means `^24`.
- **Third-party action refs**, pinned to a commit SHA with the exact tag in a
  trailing comment (`@<sha> # v4.4.0`). The SHA is what runs, so a moved
  upstream tag cannot change it; the comment is how Renovate knows which version
  that SHA is. Keep the comment exact rather than a major alias like `# v4`,
  because a major alias hides patch updates from Renovate.

Update policy: a release has to be **3 days old** before Renovate proposes it
(`minimumReleaseAge`), and three grouped rules decide what merges itself.

| Group            | Covers                     | Automerge |
| ---------------- | -------------------------- | --------- |
| `github actions` | every action ref bump      | yes       |
| `mise tools`     | tool patch and minor bumps | yes       |
| `mise majors`    | tool major bumps           | no        |

Automerge lives on the groups rather than at the top level, so a tool major
stops for review while the rest flows through. Action majors do automerge: the
refs are SHA-pinned, so the change is a reviewable diff and CI still gates it.

Grouping the majors instead of leaving them unmatched is deliberate. It gives
them an explicit `automerge: false`, which is also what makes
[`local-renovate`](./tools/local-renovate) report them as `manual` rather than
`default`, since that verdict is read from rules carrying a `groupName`.

Two caveats worth knowing before you rely on any of it:

- **Automerge needs a `RENOVATE_TOKEN` secret on this repo.** Without one the
  workflow falls back to `GITHUB_TOKEN`, and pull requests opened with that
  token do not trigger `_ci.yml`, so there are no checks for automerge to wait
  on.
- **The checks are lint-only.** `mise run check` runs the linters and the
  `local-renovate` fixture tests; it does not execute the actions against a real
  registry, runner or release. A green check on an action major means the YAML
  is well-formed, not that the action still behaves the same.

Editing `renovate.json` has no effect on a local run until the change is
committed. Renovate's `local` platform reads the config through git, and an
uncommitted file leaves it reporting `Repo is not onboarded` and quietly falling
back to its own onboarding defaults.

Because the release workflow triggers on `**/action.yml`, an automerged bump to
a pinned action ref cuts a new release, which is how consumers pick the update
up.

### Running Renovate locally

[`tools/local-renovate/`](./tools/local-renovate) holds a script that runs
Renovate through its read-only `local` platform, so you can see the pending
bumps for a repo, gate on them, or write them into the manifests without waiting
for a scheduled run. It is a development script rather than an action, so there
is no `uses:` reference for it. Distribution comes later: a release process will
publish it for mise's `github` backend as `local-renovate@vX.Y.Z`.

See [its README](./tools/local-renovate/README.md) for the modes and the rewrite
methods.

## Versioning

Releases are **automatic** and driven by the [`VERSION`](./VERSION) file, which
holds the `MAJOR.MINOR` (e.g. `0.1`). Actions and reusable workflows share the
same tags (a tag is a snapshot of the whole repo), and consumers reference
`DataLabHell/ci-actions/<action>@<tag>`.

The [Release workflow](./.github/workflows/_release.yml) runs on every push to
`main` and chains this repo's own actions (dogfooding): a **resolver** produces
the next bare version, then the **release** actions tag it and publish it.

1. [`versioning/auto-patch`](./versioning/auto-patch) reads `MAJOR.MINOR` from
   `VERSION`, finds the highest existing `vMAJOR.MINOR.*` tag, and
   **auto-increments the patch** (starting at `.0` if the series is new) →
   outputs the next **bare** version `MAJOR.MINOR.PATCH`.
2. [`release/tag-and-alias`](./release/tag-and-alias) takes that version, owns
   the tag format (adds the `v`), creates the `vMAJOR.MINOR.PATCH` tag, and
   moves the rolling `vMAJOR` / `vMAJOR.MINOR` aliases to it, outputting the
   canonical tag.
3. [`release/github-release`](./release/github-release) publishes a GitHub
   Release for the tag from step 2.

Both halves are pluggable: swap step 1 for
[`versioning/from-pyproject`](./versioning/from-pyproject) (or any step that
outputs a bare `X.Y.Z` version) to change the version source, and drop step 3
when you only need tags (e.g. a container build). The pieces compose.

### Everyday changes → patch bump

Merge a change to any action to `main`. You don't touch `VERSION`. Each such
push releases the next patch automatically: `v0.2.0` → `v0.2.1` → …

Only changes to action files cut a release: an `action.yml`, an action script
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

Three pins are available, in decreasing order of movement:

- `@vX.Y`: rolling minor alias; **the recommended pin** while on `0.x` (moves on
  patches only, never breaking).
- `@vX.Y.Z`: an exact, immutable release.
- `@vX`: rolling major alias; **not recommended during `0.x`**, because it moves
  with every release including the next minor, which may be breaking.

Follow semver: while on `0.x`, breaking changes bump the **minor**, so a
consumer pinned to `@v0.3` stays safe. The break lands on `0.4`, which `@v0.3`
never follows. You don't need a `1.0` for this; stay on `0.x` as long as you
like. Once the API is stable, bump `VERSION` to `1.0`; after that, breaking
changes bump the major, `@v1` users are protected, and `@v1` becomes a safe pin.

## Conventions

- **Inputs/outputs:** kebab-case names.
- **Secrets:** never echo credentials or write them to disk beyond an ephemeral,
  job-scoped file; pass them via `secrets`, not plain inputs.
- **Shell steps:** start bash scripts with `set -euo pipefail`.
- **Docs:** every action folder must have a `README.md` with an inputs table and
  a usage example.
