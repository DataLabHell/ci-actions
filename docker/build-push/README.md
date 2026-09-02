# docker/build-push

Build a container image with Docker Buildx and push it to a registry, with
consistent tagging and layer caching. It's a thin composite wrapper around the
official
[`docker/setup-buildx-action`](https://github.com/docker/setup-buildx-action),
[`docker/login-action`](https://github.com/docker/login-action) and
[`docker/build-push-action`](https://github.com/docker/build-push-action). It
removes the boilerplate those three always need: login, buildx setup, lowercased
ref, cache config, tag assembly.

Works with GHCR out of the box, and with the local/on-prem org registry by
setting `registry: truenas` — its host and credentials come from Vault, so no
secrets go in the workflow.

> Why Buildx and not `docker build`/`push`? With `push: true`, Buildx pushes
> straight to the registry and never loads the image into the runner's local
> daemon, so no cleanup step (`docker rmi` / `image prune`) is needed, even on
> persistent self-hosted runners.

## Requirements

The caller owns the job. A composite action can't set `runs-on`, `matrix`,
`permissions` or triggers, so provide those yourself:

- `runs-on` any runner with Docker available.
- For GHCR: `permissions: { packages: write }`. The default `GITHUB_TOKEN` is
  enough, with no extra secret.
- `actions/checkout@v7` before this step.
- You never pass credentials. Authentication is decided by the `registry`:
  - `ghcr.io` → logs in with the workflow's `GITHUB_TOKEN` (needs
    `permissions: packages: write`).
  - `truenas` (local) → host **and** credentials are read from Vault
    (`kv/data/k8s/oci-registry/ci-actions`, keys `url`, `user`, `password`), the
    same way [`python/publish`](../../python/publish) gets its devpi
    credentials. Needs `permissions: { id-token: write }` (see
    [Local registry](#example-3-local-registry)).

## Inputs

| Input        | Required | Default                    | Description                                                                                                    |
| ------------ | -------- | -------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `image`      | yes      | n/a                        | Final path segment, e.g. `api` → `<registry>/<namespace>/api`.                                                 |
| `namespace`  | no       | `${{ github.repository }}` | Path between registry and image. Defaults to `owner/name` (matches GHCR).                                      |
| `registry`   | no       | `ghcr.io`                  | Allowlisted registry: `ghcr.io` (alias `ghcr`) or `truenas` (host from Vault). Anything else errors.           |
| `tags`       | no       | `latest`                   | Newline-separated tag suffixes (each becomes `<ref>:<suffix>`). Blank lines skipped.                           |
| `context`    | no       | `.`                        | Build context directory.                                                                                       |
| `dockerfile` | no       | `''`                       | Dockerfile path (empty = default `Dockerfile` in the context, e.g. set `Dockerfile.api`).                      |
| `cache`      | no       | `gha`                      | Layer cache backend: `gha`, `registry`, or `none` (see [Caching](#caching)).                                   |
| `push`       | no       | `true`                     | Push the image; set `"false"` for PR validation builds.                                                        |
| `platforms`  | no       | `''`                       | Target platforms, newline- or comma-separated (e.g. `linux/arm64`). Empty = the runner's native platform only. |

## Output

| Output | Description                                                             |
| ------ | ----------------------------------------------------------------------- |
| `ref`  | The fully-qualified image ref without tag, e.g. `ghcr.io/org/repo/api`. |

## Caching

| `cache`    | Use when                     | Behavior                                                                    |
| ---------- | ---------------------------- | --------------------------------------------------------------------------- |
| `gha`      | GitHub-hosted runners        | GitHub Actions cache, scoped per `image`. The default.                      |
| `registry` | self-hosted / local registry | Cache stored as a `<ref>:buildcache` image. Only written when `push: true`. |
| `none`     | anywhere                     | No layer cache.                                                             |

## Multi-arch builds (Raspberry Pi 5 & co.)

By default the image is built for the runner's own platform only. The runners
are x86-64, so that means `linux/amd64`. To also run the image on an arm64
device such as a Raspberry Pi 5, list both platforms:

```yaml
- uses: DataLabHell/ci-actions/docker/build-push@docker/build-push-vX.Y.Z
  with:
    image: api
    platforms: |
      linux/amd64
      linux/arm64
    tags: |
      latest
      ${{ github.sha }}
```

A comma-separated one-liner (`platforms: linux/amd64,linux/arm64`) works too.
Each tag then points at a manifest list, and `docker pull` on the Pi picks the
arm64 variant automatically.

How it works and what to watch out for:

- Because the runner is x86-64, any non-amd64 platform is built through QEMU
  emulation. The action installs it (`docker/setup-qemu-action`) only when a
  foreign platform is actually requested, so native-only builds are unaffected.
- Emulated builds are slow. Compile-heavy steps (native Python wheels, Go/Rust
  builds) can take several times longer than the amd64 build. Keep the layer
  cache on, and prefer prebuilt arm64 wheels/base images where you can.
- Your base images must have arm64 variants (most official ones do). Avoid
  pinning a digest, which pins a single architecture.
- If you build for arm64 only, the resulting image can't run on the runner. That
  is fine for pushing, but any in-workflow smoke test of it will fail.
- With `push: false` a multi-platform build is validated but produces no local
  image (buildx can't load a manifest list into the daemon). That's exactly what
  you want for PR validation.

## Example 1: GHCR, matrix build (sha + latest)

```yaml
jobs:
  build:
    runs-on: self-hosted
    permissions:
      contents: read
      packages: write
    strategy:
      matrix:
        service: [api, mcp]
    steps:
      - uses: actions/checkout@v7
      - uses: DataLabHell/ci-actions/docker/build-push@docker/build-push-vX.Y.Z
        with:
          image: ${{ matrix.service }}
          dockerfile: Dockerfile.${{ matrix.service }}
          push: ${{ github.event_name != 'pull_request' }}
          tags: |
            latest
            ${{ github.sha }}
```

## Example 2: GHCR with a version tag from `pyproject.toml`

Reuse the repo's [`versioning/from-pyproject`](../../versioning/from-pyproject)
resolver, then feed its version in as a tag suffix (strip the leading `v`, since
image tags are usually bare):

```yaml
steps:
  - uses: actions/checkout@v7

  - id: ver
    uses: DataLabHell/ci-actions/versioning/from-pyproject@versioning/from-pyproject-vX.Y.Z
    with:
      file: api/pyproject.toml

  - uses: DataLabHell/ci-actions/docker/build-push@docker/build-push-vX.Y.Z
    with:
      image: api
      context: ./api
      tags: |
        latest
        ${{ github.sha }}
        ${{ steps.ver.outputs.version }}   # e.g. 2.3.4 (blank lines are skipped)
```

## Example 3: local registry

With `registry: truenas` the action adds one step before the build that reads
`kv/data/k8s/oci-registry/ci-actions` from Vault and uses its `url` as the
registry host and its `user` / `password` for the login. No credentials go in
the workflow and nothing is configured per repo — the job just needs an OIDC
token. Use `cache: registry`, since there's no GitHub-hosted cache there:

```yaml
jobs:
  build:
    runs-on: self-hosted
    permissions:
      contents: read
      id-token: write # for the Vault login
    steps:
      - uses: actions/checkout@v7
      - uses: DataLabHell/ci-actions/docker/build-push@docker/build-push-vX.Y.Z
        with:
          image: my-service
          registry: truenas # host from the secret's "url" key
          namespace: my-team # -> <host>/my-team/my-service
          cache: registry
          tags: |
            latest
            ${{ github.sha }}
```

The credentials stay in that step's outputs (`exportEnv: false`), so they aren't
exported into the environment of the caller's other steps.

## Matrix + release (two jobs)

To build several images and tag them with a single release version, split into
two jobs: tag once, then fan the build out over a matrix. Running
`tag-and-alias` inside the matrix would make every cell try to create the same
tag and collide, so it lives in its own job and the version crosses to the build
job as a job output.

```yaml
jobs:
  release: # runs once
    runs-on: self-hosted
    permissions:
      contents: write
    outputs:
      tags: ${{ steps.rel.outputs.versions }} # 0.1.3 / 0.1 / 0 (bare, newline-separated)
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

  build: # fans out over the images
    needs: release
    runs-on: self-hosted
    permissions:
      contents: read
      id-token: write # registry credentials from Vault
    strategy:
      matrix:
        service: [api, mcp, worker]
    steps:
      - uses: actions/checkout@v7
      - uses: DataLabHell/ci-actions/docker/build-push@docker/build-push-vX.Y.Z
        with:
          image: ${{ matrix.service }}
          registry: truenas
          cache: registry
          tags: |
            ${{ needs.release.outputs.tags }}
            latest
```

The multiline `tags` output survives the job boundary, so it drops straight into
each matrix cell's `tags`. For a single image you can do this in one job; see
the
[build-and-push-a-versioned-image example](../../README.md#build-and-push-a-versioned-image)
in the top README.

## Notes

- No manual cleanup. With `push: true` the image is pushed directly and not
  loaded into the local daemon, so persistent self-hosted runners don't
  accumulate images and no `docker rmi`/`prune` step is required.
- Tags are suffixes. You pass `latest`, a sha or a version, and the action
  prefixes each with the lowercased `<registry>/<namespace>/<image>` ref. Empty
  lines are dropped, so an optional `${{ ... }}` version that resolves to `''`
  simply adds no tag.
- Mirror your release tags. In a release job, feed
  [`release/tag-and-alias`](../../release/tag-and-alias)'s `versions` output
  (bare, or `tags` for the `v`-prefixed form) straight into this action's `tags`
  input to tag the image with the same rolling `0.1.3` / `0.1` / `0` set as the
  git refs.
- For PR builds, set `push: ${{ github.event_name != 'pull_request' }}` to build
  (validate) on PRs without pushing. With `cache: registry`, the cache is only
  written when pushing, so PRs won't try to mutate the registry.
- If several repos repeat the entire build job (matrix, needs, permissions)
  identically, that's the one case where a reusable workflow (`workflow_call`)
  fits better than this action, because it can own the job. This action is the
  right tool when you want a single composable build step.
