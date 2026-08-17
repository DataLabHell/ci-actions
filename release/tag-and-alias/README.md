# release/tag-and-alias

Creates a `vMAJOR.MINOR.PATCH` tag and force-moves the rolling `vMAJOR` /
`vMAJOR.MINOR` alias tags to it. **No GitHub Release** — use this when you only
need the git tags (e.g. a container build that tags the commit and pushes an
image), and add [`release/github-release`](../github-release) afterwards if you
also want a Release page.

Uses only `git` — no `gh` CLI — so it runs on self-hosted runners.

## Requirements

- Check out with `actions/checkout@v7` and `fetch-depth: 0`.
- Grant `permissions: contents: write` so the tags can be pushed (the checkout
  token is used for `git push`).

## Inputs

| Input | Required | Default | Description                                                                                                                                                           |
| ----- | -------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tag` | yes      | —       | Version to tag, `MAJOR.MINOR.PATCH` with an optional leading `v` (resolvers emit the bare form). This action normalizes it and always creates a `v`-prefixed git tag. |

## Outputs

The tag and its rolling aliases are exposed so a later step can reuse the exact
same set — e.g. tagging a container image to mirror the git refs. Naming follows
one rule: **`tag`/`tags` carry the `v`** (git-ref form), **`version`/`versions`
are bare** (no `v`).

| Output     | Example              | Description                                                 |
| ---------- | -------------------- | ----------------------------------------------------------- |
| `tag`      | `v0.1.3`             | The full tag created (`v`-prefixed).                        |
| `version`  | `0.1.3`              | Bare version (no `v`).                                      |
| `major`    | `v0`                 | Rolling major alias.                                        |
| `minor`    | `v0.1`               | Rolling minor alias.                                        |
| `tags`     | `v0.1.3` `v0.1` `v0` | Newline-separated tag + aliases, `v`-prefixed.              |
| `versions` | `0.1.3` `0.1` `0`    | Newline-separated tag + aliases, bare. Handy as image tags. |

## Usage

```yaml
jobs:
  tag:
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
          tag: ${{ steps.ver.outputs.version }} # bare; this action adds the v

      # Tag the image with the same rolling set as the git refs (bare form):
      - uses: DataLabHell/ci-actions/docker/build-push@docker/build-push/vX.Y.Z
        with:
          image: api
          tags: |
            ${{ steps.rel.outputs.versions }}   # 0.1.3 + 0.1 + 0
            latest
```

## Notes

- The `tag` input is `MAJOR.MINOR.PATCH` (an optional leading `v` is accepted
  and normalized). The `vX` / `vX.Y` aliases are derived from it and
  force-moved, so consumers pinned to `@vX` / `@vX.Y` follow along.
