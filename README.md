# ci-actions

Shared GitHub Actions and workflows for the organization. This is a
**monorepo**: each action (the building blocks) lives in its own folder at the
repo root, with its own `action.yml` and `README.md`, and each is **versioned
and released independently** via release-please (see [Versioning](#versioning)).

Each action is one step you drop into a job you own (see
[Available actions](#available-actions)). Multi-step flows that vary too much
between repos to bundle cleanly (releasing, building an image) aren't shipped as
actions; they stay copy-paste [composition examples](#composition-examples).

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
      - uses: actions/checkout@v7

      - uses: DataLabHell/ci-actions/s3-file-upload@s3-file-upload/vX.Y.Z
        with:
          source: images
          bucket: reports
          destination: my-service/
          include: "*.html"
```

Each action is versioned **independently** and tagged
`<action-path>/vMAJOR.MINOR.PATCH` (see [Versioning](#versioning)). `@…/vX.Y.Z`
throughout these docs is a placeholder: substitute the action's current version
from the [Available actions](#available-actions) table or the
[releases](https://github.com/DataLabHell/ci-actions/releases) page. Pin an
exact tag rather than `@main` and let Renovate bump it.

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
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0
      - id: ver
        uses: DataLabHell/ci-actions/versioning/auto-patch@versioning/auto-patch/vX.Y.Z
      - id: rel
        uses: DataLabHell/ci-actions/release/tag-and-alias@release/tag-and-alias/vX.Y.Z
        with:
          tag: ${{ steps.ver.outputs.version }}
      - uses: DataLabHell/ci-actions/release/github-release@release/github-release/vX.Y.Z
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
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0
      - id: ver
        uses: DataLabHell/ci-actions/versioning/auto-patch@versioning/auto-patch/vX.Y.Z
      - id: rel
        uses: DataLabHell/ci-actions/release/tag-and-alias@release/tag-and-alias/vX.Y.Z
        with:
          tag: ${{ steps.ver.outputs.version }}
      - uses: DataLabHell/ci-actions/docker/build-push@docker/build-push/vX.Y.Z
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
      - uses: actions/checkout@v7
      - uses: DataLabHell/ci-actions/python/lint@python/lint/vX.Y.Z
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
      - uses: actions/checkout@v7
      - uses: DataLabHell/ci-actions/python/test@python/test/vX.Y.Z
        with:
          python-version: ${{ matrix.python-version }}
```

## Repository layout

```
ci-actions/
├── README.md                        # this file — index of all actions
├── release-please-config.json       # per-action release config
├── .release-please-manifest.json    # current version of each action
├── mise.toml                        # dev tools (exact pins) + `mise run check` gate
├── renovate.json                    # what Renovate keeps updated here
├── .github/workflows/               # this repo's own CI (underscore-prefixed)
│   ├── _ci.yml                      #   the mise quality gate (on PRs)
│   └── _release-please.yml          #   per-action releases (release-please)
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
5. Add a row to the [Available actions](#available-actions) table above, and
   register the action in
   [`release-please-config.json`](./release-please-config.json) and
   [`.release-please-manifest.json`](./.release-please-manifest.json).
6. Open a PR using [Conventional Commits](#versioning). On merge, release-please
   versions and tags the new action from your commit types.

> The `_template/` folder is a scaffold, not a published action. The leading
> underscore keeps it sorted first and signals it isn't meant to be referenced.

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

Renovate keeps this repo current, driven by [`renovate.json`](./renovate.json).
Preview or apply updates locally with the
[local-renovate tool](#running-renovate-locally).

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

Each action is released **independently** with
[release-please](https://github.com/googleapis/release-please) and
[Conventional Commits](https://www.conventionalcommits.org/). A git tag is
repo-wide, so the action name is encoded in it: releases are tagged
`<action-path>/vMAJOR.MINOR.PATCH`, e.g. `docker/build-push/v0.2.1`.

### How a release happens

release-please attributes each commit to an action by the **file paths it
touches**, so a `fix:` under `docker/build-push/` bumps only that action. On
every push to `main` the
[Release Please workflow](./.github/workflows/_release-please.yml) maintains a
single **release PR**; merging it tags the changed actions and publishes a
GitHub Release for each. The bump follows the commit type:

| Commit                                    | Bump  |
| ----------------------------------------- | ----- |
| `fix: …`                                  | patch |
| `feat: …`                                 | minor |
| `feat!: …` or a `BREAKING CHANGE:` footer | major |

Current versions live in
[`.release-please-manifest.json`](./.release-please-manifest.json); the action
list is in [`release-please-config.json`](./release-please-config.json). Add a
new action to both when you create it.

### What consumers pin to

Pin an **exact** per-action tag and let Renovate bump it:

```yaml
- uses: DataLabHell/ci-actions/docker/build-push@docker/build-push/v0.2.1
```

There are **no rolling `vX` aliases**. Exact tags are immutable, and Renovate
opens a PR when a new version ships — the reviewable, security-friendly way to
stay current. Find the current version of each action in the
[Available actions](#available-actions) table or under
[releases](https://github.com/DataLabHell/ci-actions/releases).

### Keeping pins current with Renovate (consumer setup)

Because the tags are path-prefixed (`docker/build-push/v0.2.1`), a consumer's
Renovate needs an `extractVersion` rule to read the version out of them —
otherwise it can't tell which tag is newer and won't raise bumps. Add this to
the **consuming** repo's `renovate.json`:

```json
{
  "packageRules": [
    {
      "matchPackageNames": ["DataLabHell/ci-actions/**"],
      "extractVersion": "/v(?<version>\\d+\\.\\d+\\.\\d+)$"
    }
  ]
}
```

With `helpers:pinGitHubActionDigests` (recommended), Renovate also rewrites the
pin to an immutable commit SHA with the version in a trailing comment
(`@<sha> # docker/build-push/v0.2.1`) and keeps both current. Validate this on
one repo before relying on it — monorepo path-prefixed action tags are the one
part of this that Renovate can be finicky about.

### The `versioning/*` and `release/*` actions

Note that this repo does **not** use its own release actions for its releases
(that's release-please). [`versioning/auto-patch`](./versioning/auto-patch),
[`versioning/from-pyproject`](./versioning/from-pyproject),
[`release/tag-and-alias`](./release/tag-and-alias) and
[`release/github-release`](./release/github-release) are **products for consumer
repos** that prefer a VERSION-file flow over release-please. They're maintained
here, just not dogfooded.

## Conventions

- **Inputs/outputs:** kebab-case names.
- **Secrets:** never echo credentials or write them to disk beyond an ephemeral,
  job-scoped file; pass them via `secrets`, not plain inputs.
- **Shell steps:** start bash scripts with `set -euo pipefail`.
- **Docs:** every action folder must have a `README.md` with an inputs table and
  a usage example.
