# docker/build-push

Build a container image with Docker **Buildx** and push it to a registry, with
consistent tagging and layer caching. It's a thin composite wrapper around the
official [`docker/setup-buildx-action`](https://github.com/docker/setup-buildx-action),
[`docker/login-action`](https://github.com/docker/login-action) and
[`docker/build-push-action`](https://github.com/docker/build-push-action) — it
just removes the boilerplate those three always need (login, buildx setup,
lowercased ref, cache config, tag assembly).

Works with **GHCR** out of the box and with **any other registry** (including a
local/on-prem one like the org RustFS/registry) by pointing `registry` at it and
passing credentials.

> **Why Buildx and not `docker build`/`push`?** With `push: true`, Buildx pushes
> straight to the registry and never loads the image into the runner's local
> daemon — so there's **no cleanup step** (`docker rmi` / `image prune`) needed,
> even on persistent self-hosted runners.

## Requirements

The **caller owns the job**. A composite action can't set `runs-on`, `matrix`,
`permissions`, or triggers — provide those yourself:

- `runs-on` any runner with Docker available.
- For **GHCR**: `permissions: { packages: write }` (and the default
  `GITHUB_TOKEN` is enough — no extra secret).
- `actions/checkout@v4` before this step.
- **You never pass credentials.** Authentication is decided by the `registry`:
  - `ghcr.io` → logs in with the workflow's `GITHUB_TOKEN` (needs
    `permissions: packages: write`).
  - `truenas` (local) → no login step; the push uses the credentials configured
    on the runner (`~/.docker/config.json`), which are **provisioned by Ansible**
    when the runner is set up. Just run on a `self-hosted` runner (see
    [Local registry](#example-3--local-registry)). The action **fails fast** if
    it detects a GitHub-hosted runner here, since it won't have those credentials.

## Inputs

| Input        | Required | Default                    | Description                                                                                          |
| ------------ | -------- | -------------------------- | ---------------------------------------------------------------------------------------------------- |
| `image`      | yes      | —                          | Final path segment, e.g. `api` → `<registry>/<namespace>/api`.                                       |
| `namespace`  | no       | `${{ github.repository }}` | Path between registry and image. Defaults to `owner/name` (matches GHCR).                             |
| `registry`   | no       | `ghcr.io`                  | Allowlisted registry: `ghcr.io` (alias `ghcr`) or `truenas.dlh-k8s.com:5000` (alias `truenas`). Anything else errors. |
| `tags`       | no       | `latest`                   | Newline-separated tag **suffixes** (each becomes `<ref>:<suffix>`). Blank lines skipped.              |
| `context`    | no       | `.`                        | Build context directory.                                                                             |
| `dockerfile` | no       | `''`                       | Dockerfile path (empty = default `Dockerfile` in the context, e.g. set `Dockerfile.api`).            |
| `cache`      | no       | `gha`                      | Layer cache backend: `gha`, `registry`, or `none` (see [Caching](#caching)).                          |
| `push`       | no       | `true`                     | Push the image; set `"false"` for PR validation builds.                                              |

## Output

| Output | Description                                                     |
| ------ | --------------------------------------------------------------- |
| `ref`  | The fully-qualified image ref without tag, e.g. `ghcr.io/org/repo/api`. |

## Caching

| `cache`    | Use when                       | Behavior                                                                                 |
| ---------- | ------------------------------ | ---------------------------------------------------------------------------------------- |
| `gha`      | GitHub-hosted runners          | GitHub Actions cache, scoped per `image`. The default.                                    |
| `registry` | self-hosted / local registry   | Cache stored as a `<ref>:buildcache` image. Only written when `push: true`.               |
| `none`     | —                              | No layer cache.                                                                          |

## Example 1 — GHCR, matrix build (sha + latest)

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
      - uses: actions/checkout@v4
      - uses: DataLabHell/ci-actions/docker/build-push@v0.2
        with:
          image: ${{ matrix.service }}
          dockerfile: Dockerfile.${{ matrix.service }}
          push: ${{ github.event_name != 'pull_request' }}
          tags: |
            latest
            ${{ github.sha }}
```

## Example 2 — GHCR with a version tag from `pyproject.toml`

Reuse the repo's [`versioning/from-pyproject`](../../versioning/from-pyproject)
resolver, then feed its version in as a tag suffix (strip the leading `v`, since
image tags are usually bare):

```yaml
steps:
  - uses: actions/checkout@v4

  - id: ver
    uses: DataLabHell/ci-actions/versioning/from-pyproject@v0.2
    with:
      file: api/pyproject.toml

  - uses: DataLabHell/ci-actions/docker/build-push@v0.2
    with:
      image: api
      context: ./api
      tags: |
        latest
        ${{ github.sha }}
        ${{ steps.ver.outputs.version }}   # e.g. 2.3.4 (blank lines are skipped)
```

## Example 3 — Local registry

Point `registry` at the alias and run on a `self-hosted` runner. **No
credentials in the workflow** — the push uses the docker credentials configured
on the runner. Use `cache: registry` since there's no GitHub-hosted cache there:

```yaml
jobs:
  build:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - uses: DataLabHell/ci-actions/docker/build-push@v0.2
        with:
          image: my-service
          registry: truenas             # alias -> truenas.dlh-k8s.com:5000
          namespace: my-team            # -> truenas.dlh-k8s.com:5000/my-team/my-service
          cache: registry
          tags: |
            latest
            ${{ github.sha }}
```

The registry credentials are **provisioned by Ansible** as part of runner setup
— it runs `docker login` for the user the runner service runs as, so the
credential is already in `~/.docker/config.json` on the node. Nothing to do in
the workflow or per repo.

> Same trade-off as the S3 action's runner profile: the credential lives once on
> the runner instead of as a per-repo secret — convenient, but any job on that
> runner can push to that registry.

## Matrix + release (two jobs)

To build **several images** and tag them with a **single release version**, split
into two jobs: tag **once**, then fan the build out over a matrix. Running
`tag-and-alias` inside the matrix would make every cell try to create the same
tag and collide — so it lives in its own job, and the version crosses to the
build job as a job output.

```yaml
jobs:
  release:                       # runs once
    runs-on: self-hosted
    permissions:
      contents: write
    outputs:
      tags: ${{ steps.rel.outputs.versions }}   # 0.1.3 / 0.1 / 0 (bare, newline-separated)
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

  build:                         # fans out over the images
    needs: release
    runs-on: self-hosted
    strategy:
      matrix:
        service: [api, mcp, worker]
    steps:
      - uses: actions/checkout@v4
      - uses: DataLabHell/ci-actions/docker/build-push@v0.2
        with:
          image: ${{ matrix.service }}
          registry: truenas
          cache: registry
          tags: |
            ${{ needs.release.outputs.tags }}
            latest
```

The multiline `tags` output survives the job boundary, so it drops straight into
each matrix cell's `tags`. For a **single** image you can do this in one job; see
the [build-and-push-a-versioned-image example](../../README.md#build-and-push-a-versioned-image)
in the top README.

## Notes

- **No manual cleanup.** With `push: true` the image is pushed directly and not
  loaded into the local daemon, so persistent self-hosted runners don't
  accumulate images — no `docker rmi`/`prune` step required.
- **Tags are suffixes.** You pass `latest` / a sha / a version; the action
  prefixes each with the lowercased `<registry>/<namespace>/<image>` ref. Empty
  lines are dropped, so an optional `${{ ... }}` version that resolves to `''`
  simply adds no tag.
- **Mirror your release tags.** In a release job, feed
  [`release/tag-and-alias`](../../release/tag-and-alias)'s `versions` output
  (bare — or `tags` for the `v`-prefixed form) straight into this action's `tags`
  input to tag the image with the same rolling `0.1.3` / `0.1` / `0` set as the
  git refs.
- **PR builds.** Set `push: ${{ github.event_name != 'pull_request' }}` to build
  (validate) on PRs without pushing. With `cache: registry`, the cache is only
  written when pushing, so PRs won't try to mutate the registry.
- **Whole-job duplication?** If several repos repeat the *entire* build job
  (matrix + needs + permissions) identically, that's the one case a reusable
  workflow (`workflow_call`) fits better than this action — it can own the job.
  This action is the right tool when you want a single, composable build step.
