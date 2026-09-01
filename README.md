# ci-actions

Shared GitHub Actions for the organization. Each action lives in its own folder
at the repo root with its own `action.yml` and `README.md`, and is versioned and
released independently via release-please (see [Versioning](#versioning)).

Multi-step flows that vary too much between repos (releasing, building an image)
aren't shipped as actions; they stay copy-paste
[composition examples](#composition-examples).

## Available actions

| Action                                                     | Description                                                                                                                                   |
| ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| [`s3-file-upload`](./s3-file-upload)                       | Upload files/folders to any S3-compatible bucket (RustFS, AWS S3, MinIO, on-prem) with glob include/exclude filtering.                        |
| [`docker/build-push`](./docker/build-push)                 | Build a container image with Buildx and push it to a registry (GHCR or local/on-prem) with sha/latest/version tags and layer caching.         |
| [`release/tag-and-alias`](./release/tag-and-alias)         | Create a `vX.Y.Z` tag and move the rolling `vX`/`vX.Y` aliases to it (no GitHub Release).                                                     |
| [`release/github-release`](./release/github-release)       | Publish a GitHub Release for an existing tag, with notes and optional assets.                                                                 |
| [`versioning/auto-patch`](./versioning/auto-patch)         | Resolver: `MAJOR.MINOR` from a file + auto-incremented patch → next `vX.Y.Z` tag.                                                             |
| [`versioning/from-pyproject`](./versioning/from-pyproject) | Resolver: `[project].version` from a `pyproject.toml` (uv / PEP 621) → `vX.Y.Z` tag.                                                          |
| [`python/lint`](./python/lint)                             | Lint + type-check a Python project with ruff (`check` + `format`) and ty, via `uv`.                                                           |
| [`python/test`](./python/test)                             | Install with `uv` and run pytest, optionally pinned to a Python version.                                                                      |
| [`python/publish`](./python/publish)                       | Build with `uv` and publish to a package index (devpi by default), gated to `main` by default.                                                |
| [`mise-setup`](./mise-setup)                               | Provision a repo's tools with mise into a per-repository dir (cached installs, prune of unreferenced versions), so later steps can call them. |

## Using an action

```yaml
jobs:
  build:
    runs-on: self-hosted # s3-file-upload needs the dlh AWS profile on the runner
    steps:
      - uses: actions/checkout@v7

      - uses: DataLabHell/ci-actions/s3-file-upload@s3-file-upload-vX.Y.Z
        with:
          source: images
          bucket: reports
          destination: my-service/
          include: "*.html"
```

`@…/vX.Y.Z` is a placeholder throughout these docs: substitute the action's
current version from
[releases](https://github.com/DataLabHell/ci-actions/releases). Pin an exact tag
rather than `@main` and let Renovate bump it.

## Composition examples

Copy and adapt these; they aren't separate actions because the wiring varies per
repo. Each caller owns the job: runner, permissions, and checkout.

### Release from a VERSION file

Resolve the next version, tag it and move the rolling aliases, then publish a
Release. Drop the last step if you only need tags. Swap
[`versioning/auto-patch`](./versioning/auto-patch) for
[`versioning/from-pyproject`](./versioning/from-pyproject) to read the version
from `pyproject.toml`.

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
        uses: DataLabHell/ci-actions/versioning/auto-patch@versioning/auto-patch-vX.Y.Z
      - id: rel
        uses: DataLabHell/ci-actions/release/tag-and-alias@release/tag-and-alias-vX.Y.Z
        with:
          tag: ${{ steps.ver.outputs.version }}
      - uses: DataLabHell/ci-actions/release/github-release@release/github-release-vX.Y.Z
        with:
          tag: ${{ steps.rel.outputs.tag }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Build and push a versioned image

Same version resolution, tagging an image instead of publishing a Release. For
several images in one repo, see the matrix pattern in
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
        uses: DataLabHell/ci-actions/versioning/auto-patch@versioning/auto-patch-vX.Y.Z
      - id: rel
        uses: DataLabHell/ci-actions/release/tag-and-alias@release/tag-and-alias-vX.Y.Z
        with:
          tag: ${{ steps.ver.outputs.version }}
      - uses: DataLabHell/ci-actions/docker/build-push@docker/build-push-vX.Y.Z
        with:
          image: api
          registry: truenas
          cache: registry
          tags: |
            ${{ steps.rel.outputs.versions }}
            latest
```

### Python CI (lint + test matrix)

The matrix lives in the caller because a composite action can't fan one out.

```yaml
jobs:
  lint:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v7
      - uses: DataLabHell/ci-actions/python/lint@python/lint-vX.Y.Z
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
      - uses: DataLabHell/ci-actions/python/test@python/test-vX.Y.Z
        with:
          python-version: ${{ matrix.python-version }}
```

## Repository layout

```
ci-actions/
├── release-please-config.json       # per-action release config
├── .release-please-manifest.json    # current version of each action
├── mise.toml                        # dev tools (exact pins) + `mise run check` gate
├── renovate.json                    # what Renovate keeps updated here
├── .github/workflows/               # this repo's own CI (underscore-prefixed)
│   ├── _ci.yml                      #   the mise quality gate (on PRs)
│   └── _release-please.yml          #   per-action releases (release-please)
├── _template/                # scaffold to copy when adding an action
├── tools/                    # helpers we ship or use: programs, not actions
│   └── local-renovate/       #   run Renovate locally, preview or apply bumps
│
│   # single actions, each in its own root folder:
├── s3-file-upload/           #   action.yml + upload.sh + README
├── mise-setup/               #   provision project tools with mise
├── docker/build-push/        #   build + push an image (Buildx)
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

## Adding a new action

Start from the [`_template/`](./_template) scaffold, a ready-to-fill composite
action plus README. The leading underscore keeps it sorted first and signals it
isn't meant to be referenced.

1. Copy `_template/` to `<name>/` at the repo root (kebab-case). Group related
   actions in a subfolder if it helps (e.g. `docker/build-push/`).
2. Fill in `action.yml`. Prefer a composite action (the template's default): no
   build step, runs on any runner.
3. Put the shell logic in `main.sh`, which the template calls with inputs as
   `INPUT_*` env vars. Inline `run:` shell is not linted; a `.sh` file is.
4. Fill in `README.md`: inputs table, outputs, and a usage example.
5. Add a row to [Available actions](#available-actions) and register the action
   in [`release-please-config.json`](./release-please-config.json) and
   [`.release-please-manifest.json`](./.release-please-manifest.json).
6. Open a PR using [Conventional Commits](#commit-messages).

## Local development

[`mise.toml`](./mise.toml) pins the linters and defines the tasks, so the same
commands run locally and in CI:

```bash
mise install        # get the linters, jq and renovate
mise run check      # the full gate: format check + lint + test (what CI runs)
mise run format     # apply shfmt, prettier and taplo formatting
mise run test       # the local-renovate fixture tests on their own
mise run renovate   # list pending dependency bumps (alias: `dependencies`)
mise tasks          # list everything, including the per-language tasks
```

| Tool                        | Covers                                      |
| --------------------------- | ------------------------------------------- |
| `action-validator`          | every `action.yml` and workflow, by schema  |
| `actionlint`                | `.github/workflows/`                        |
| `shellcheck`, `shfmt`       | `*.sh`                                      |
| `renovate-config-validator` | `renovate.json` (strict)                    |
| `prettier`                  | YAML, Markdown, JSON                        |
| `taplo`                     | TOML                                        |
| `tools/local-renovate`      | the rewrite methods, against canned reports |

GitHub YAML goes through two tools. actionlint treats every file as a workflow,
so it can't read an `action.yml`; action-validator picks the right schema per
file. Workflows get both, since actionlint type-checks expressions, runs
shellcheck over `run:` blocks, and verifies the inputs passed to a referenced
local action.

Neither lints the steps inside an action as code, which is why each action's
logic lives in a `.sh` file where shellcheck and shfmt reach it.

CI runs the gate through this repo's own [`mise-setup`](./mise-setup) by local
path, so a PR is gated by the version of that action it contains.

## Dependency updates

Renovate keeps this repo current, driven by [`renovate.json`](./renovate.json).
Two things are tracked, both kept as exact pins:

- **mise tool versions** in [`mise.toml`](./mise.toml), never `latest` or `lts`,
  so the version CI installs is the version the file records.

  Node stays on LTS without a rule: the `node-version` datasource counts a
  release as unstable until its major reaches the LTS date in
  [nodejs/Release](https://github.com/nodejs/Release), and `ignoreUnstable`
  defaults to true. To lock to one line instead, `allowedVersions` accepts an
  LTS [codename](https://github.com/nodejs/Release/blob/main/CODENAMES.md), so
  `krypton` means `^24`.

- **Third-party action refs**, pinned to a commit SHA with the exact tag in a
  trailing comment (`@<sha> # v4.4.0`). The SHA is what runs; the comment is how
  Renovate knows which version it is. Keep it exact rather than `# v4`, which
  would hide patch updates.

A release must be 3 days old before Renovate proposes it (`minimumReleaseAge`).

| Group            | Covers                     | Automerge |
| ---------------- | -------------------------- | --------- |
| `github actions` | every action ref bump      | yes       |
| `mise tools`     | tool patch and minor bumps | yes       |
| `mise majors`    | tool major bumps           | no        |

Automerge lives on the groups, not the top level, so a tool major stops for
review while the rest flows through. Grouping the majors rather than leaving
them unmatched gives them an explicit `automerge: false`, which is also what
makes [`local-renovate`](./tools/local-renovate) report them as `manual`.

Two caveats:

- Automerge needs a `RENOVATE_TOKEN` secret. Without one the workflow falls back
  to `GITHUB_TOKEN`, whose PRs don't trigger `_ci.yml`, so there are no checks
  to wait on.
- The checks are lint-only. A green check on an action major means the YAML is
  well-formed, not that the action still behaves the same.

Editing `renovate.json` has no effect on a local run until it's committed:
Renovate's `local` platform reads the config through git, and an uncommitted
file leaves it reporting `Repo is not onboarded`.

An automerged bump only cuts a release when it touches an action's folder. A ref
bumped inside `docker/build-push/action.yml` releases that action; a bump to
`mise.toml` or `.github/workflows/` releases nothing.

### Running Renovate locally

[`tools/local-renovate/`](./tools/local-renovate) runs Renovate through its
read-only `local` platform, so you can preview pending bumps, gate on them, or
write them into the manifests without waiting for a scheduled run. See
[its README](./tools/local-renovate/README.md) for the modes and rewrite
methods.

It also ships as a program. Releases carry the script as an asset named
`local-renovate`, so another repo installs it as a mise tool:

```toml
[tools]
"github:DataLabHell/ci-actions" = { version = "1.0.0", version_prefix = "local-renovate-v", asset_pattern = "local-renovate" }
```

## Versioning

Each action is released independently with
[release-please](https://github.com/googleapis/release-please). A git tag is
repo-wide, so the action name is encoded in it:
`<action-path>-vMAJOR.MINOR.PATCH`, e.g. `docker/build-push-v0.2.1`.

### Commit messages

release-please is active on `main` and driven entirely by commit messages, so
every commit must follow
[Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<optional scope>): <description>
```

| Commit                                        | Bump  |
| --------------------------------------------- | ----- |
| `fix: …`                                      | patch |
| `feat: …`                                     | minor |
| any type with `!` (`feat!:`, `refactor!:`, …) | major |
| a `BREAKING CHANGE:` footer                   | major |

`chore:`, `docs:`, `ci:`, `refactor:` and `test:` land without producing a
release unless they carry a `!`. A commit that doesn't parse as a conventional
commit is ignored entirely. Squash-merge PRs so the PR title becomes the commit
message.

While an action is on `0.x`, a breaking change bumps the minor rather than
reaching `1.0.0`. Set `"bump-major-for-zero": true` on that package in
[`release-please-config.json`](./release-please-config.json) to change it.

The scope is documentation only. Paths decide which action bumps, so a
`fix(docker): …` that edits `python/test/` bumps `python/test`.

### How a release happens

release-please attributes each commit to an action by the file paths it touches.
On every push to `main` the
[Release Please workflow](./.github/workflows/_release-please.yml) maintains a
single release PR; merging it tags the changed actions and publishes a GitHub
Release for each.

[`tools/local-renovate`](./tools/local-renovate) is in the same rotation under
the `local-renovate-vX.Y.Z` tag. Being a program rather than an action, its
release also gets the script attached as an asset, uploaded by the same
workflow.

Current versions live in
[`.release-please-manifest.json`](./.release-please-manifest.json); the action
list is in [`release-please-config.json`](./release-please-config.json).

### What consumers pin to

```yaml
- uses: DataLabHell/ci-actions/docker/build-push@docker/build-push-v0.2.1
```

There are no rolling `vX` aliases. Exact tags are immutable, and Renovate opens
a PR when a new version ships.

### Keeping pins current with Renovate (consumer setup)

The tags carry the action name as a prefix, so a consumer's Renovate needs an
`extractVersion` rule to read the version out of them. Anchor it per action: all
actions share one repository, so an unanchored rule would reduce
`python/lint-v0.9.0` and `docker/build-push-v0.5.1` to bare versions alike and
offer one action's release as an upgrade for another.

```json
{
  "packageRules": [
    {
      "matchDepNames": ["DataLabHell/ci-actions/docker/build-push"],
      "extractVersion": "^docker/build-push-v(?<version>\\d+\\.\\d+\\.\\d+)$"
    },
    {
      "matchDepNames": ["DataLabHell/ci-actions/python/test"],
      "extractVersion": "^python/test-v(?<version>\\d+\\.\\d+\\.\\d+)$"
    }
  ]
}
```

With `helpers:pinGitHubActionDigests`, Renovate also rewrites the pin to a
commit SHA with the version in a trailing comment and keeps both current.

Validate this on one repo first. Two things decide whether it works, neither
confirmed yet: whether Renovate's `github-actions` manager includes the
subdirectory in the dependency name (if not, `matchDepNames` never matches), and
whether the anchored `extractVersion` really excludes the other components. Run
[`local-renovate`](./tools/local-renovate) against a consumer repo and read the
proposed bumps.

### The `versioning/*` and `release/*` actions

This repo does not use its own release actions (that's release-please). They are
products for consumer repos that prefer a VERSION-file flow: maintained here,
just not dogfooded.

## Conventions

- **Inputs/outputs:** kebab-case names.
- **Secrets:** never echo credentials or write them to disk beyond an ephemeral,
  job-scoped file; pass them via `secrets`, not plain inputs.
- **Shell steps:** start bash scripts with `set -euo pipefail`.
- **Docs:** every action folder must have a `README.md` with an inputs table and
  a usage example.
