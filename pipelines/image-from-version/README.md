# pipelines/image-from-version

One-step versioned container image: resolve the next version from a
`MAJOR.MINOR` file (auto-incrementing the patch), create the git tag + move the
rolling `vX` / `vX.Y` aliases, and build & push a container image tagged with the
same rolling set (`0.1.3`, `0.1`, `0`, and `latest`).

It's a **composite action that chains this repo's smaller actions** —
[`versioning/auto-patch`](../../versioning/auto-patch) →
[`release/tag-and-alias`](../../release/tag-and-alias) →
[`docker/build-push`](../../docker/build-push). The sibling of
[`release-from-version`](../release-from-version): same version resolution, but
it produces a container image instead of a GitHub Release.

## Single image only

This pipeline builds **one image per call**. For a repo that builds several
images in parallel (a matrix), a single-step action can't fan out — use the
**two-job pattern** (tag once, then matrix-build) documented in
[`docker/build-push`](../../docker/build-push/README.md#matrix--release-two-jobs).

## Requirements

- `runs-on` a runner, with:
  - `permissions: contents: write` (tag-and-alias pushes git tags), and
  - `permissions: packages: write` when pushing to GHCR.
- `actions/checkout@v4` with `fetch-depth: 0` (needed to see existing tags).
- Authentication is by registry — you never pass credentials: **GHCR** uses the
  workflow's `GITHUB_TOKEN`; the **local registry** uses the credentials
  configured on the runner (run it on a `self-hosted` runner).

## Inputs

| Input          | Required | Default                    | Description                                                               |
| -------------- | -------- | -------------------------- | ------------------------------------------------------------------------- |
| `image`        | yes      | —                          | Final path segment, e.g. `api` → `<registry>/<namespace>/api`.            |
| `version-file` | no       | `VERSION`                  | Path to the `MAJOR.MINOR` file.                                           |
| `registry`     | no       | `ghcr.io`                  | `ghcr.io` (alias `ghcr`) or `truenas.dlh-k8s.com:5000` (alias `truenas`). |
| `namespace`    | no       | `${{ github.repository }}` | Path between registry and image.                                          |
| `context`      | no       | `.`                        | Build context directory.                                                  |
| `dockerfile`   | no       | `''`                       | Dockerfile path (empty = default in context).                             |
| `cache`        | no       | `gha`                      | Layer cache backend: `gha`, `registry`, or `none`.                        |
| `latest`       | no       | `true`                     | Also tag the image `:latest`.                                             |

## Outputs

| Output | Description                                                 |
| ------ | ----------------------------------------------------------- |
| `tag`  | The git tag released, e.g. `v0.1.3`.                        |
| `ref`  | The image ref pushed (no tag), e.g. `ghcr.io/org/repo/api`. |

## Usage — GHCR

```yaml
jobs:
  publish:
    runs-on: self-hosted
    permissions:
      contents: write
      packages: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: DataLabHell/ci-actions/pipelines/image-from-version@v0.2
        with:
          image: api
```

## Usage — local registry

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
      - uses: DataLabHell/ci-actions/pipelines/image-from-version@v0.2
        with:
          image: api
          registry: truenas # push uses the runner's configured credentials
          cache: registry
```

The image lands as `…/api:0.1.3`, `:0.1`, `:0`, `:latest` — the rolling tags
mirror the git `v0.1.3` / `v0.1` / `v0` refs, so `…/api:0` follows the major just
like a `@v0` pin. Need a different version source (e.g. `pyproject.toml`), no git
tags, or a matrix? Compose the underlying actions yourself; see
[`docker/build-push`](../../docker/build-push).
