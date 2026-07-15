# pipelines/release-from-version

One-step release for the common case: resolve the next version from a
`MAJOR.MINOR` file (auto-incrementing the patch), create the tag, move the
rolling `vX` / `vX.Y` aliases, and publish a GitHub Release.

It's a **composite action that chains this repo's smaller actions** — the same
pattern `github-release` uses to wrap `softprops`. Because it's an action (not a
reusable workflow) it can live in this folder and is referenced with `uses:`
like everything else. It collapses the release wiring into one step; the caller
still provides the job (runner, permissions, checkout).

## Requirements

- `runs-on` a runner, with `permissions: contents: write`.
- `actions/checkout@v4` with `fetch-depth: 0` (needed to see existing tags).

## Inputs

| Input            | Required | Default   | Description                                                       |
| ---------------- | -------- | --------- | ----------------------------------------------------------------- |
| `version-file`   | no       | `VERSION` | Path to the `MAJOR.MINOR` file.                                   |
| `github-token`   | no       | `''`      | Token for the GitHub Release. Required when `create-release` is true. Pass `${{ secrets.GITHUB_TOKEN }}`. |
| `create-release` | no       | `true`    | Publish a GitHub Release; set `"false"` to only create the tag (e.g. a container build). |

## Outputs

| Output | Description                    |
| ------ | ------------------------------ |
| `tag`  | The tag released, e.g. `v0.1.3`. |

## Usage

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

Need a different version source or finer control? Skip this and compose the
underlying actions yourself: a [`versioning/*`](../../actions/versioning) resolver →
[`release/tag-and-alias`](../../actions/release/tag-and-alias) →
[`release/github-release`](../../actions/release/github-release).
