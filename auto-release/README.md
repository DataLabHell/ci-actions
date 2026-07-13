# auto-release

Composite action that releases a repo from a `VERSION` file. On each run it
auto-increments the **patch**, creates a `vMAJOR.MINOR.PATCH` tag, moves the
rolling `vMAJOR` / `vMAJOR.MINOR` alias tags to it, and publishes a GitHub
Release. Bump major/minor by editing the `VERSION` file.

Uses only `git` plus `softprops/action-gh-release` — **no `gh` CLI**, so it runs
on self-hosted runners too.

## How versioning works

The `VERSION` file holds `MAJOR.MINOR` (e.g. `0.1`). The patch number is derived
automatically from existing tags:

- **Everyday push** — highest `vMAJOR.MINOR.*` tag + 1 (`v0.1.3` → `v0.1.4`).
- **New series** (you edited `VERSION`) — no tags yet, so it starts at `.0`
  (`0.1` → `0.2` gives `v0.2.0`; `0.9` → `1.0` gives `v1.0.0`).

Pre-release tags (e.g. `v0.1.2-rc.1`) are ignored when picking the next patch.

## Requirements

- Check out with full history and tags: `actions/checkout@v4` with
  `fetch-depth: 0`.
- Grant `permissions: contents: write` in the job so tags and the release can be
  pushed.

## Inputs

| Input           | Required | Default   | Description                                                        |
| --------------- | -------- | --------- | ------------------------------------------------------------------ |
| `version-file`  | no       | `VERSION` | Path to the file holding `MAJOR.MINOR`.                            |
| `github-token`  | yes      | —         | Token to push tags and create the release. Pass `${{ secrets.GITHUB_TOKEN }}`. |
| `release-notes` | no       | `true`    | Auto-generate GitHub Release notes.                               |

## Outputs

| Output    | Description                                        |
| --------- | -------------------------------------------------- |
| `version` | Full version released, e.g. `0.1.3`.               |
| `tag`     | Tag created, e.g. `v0.1.3`.                        |

## Usage

```yaml
name: Release
on:
  push:
    branches: [main]

permissions:
  contents: write

concurrency:
  group: release
  cancel-in-progress: false

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: DataLabHell/ci-actions/auto-release@v0.1.2
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

Add a `VERSION` file containing `0.1` to the repo, and every push to `main`
releases the next patch automatically.
