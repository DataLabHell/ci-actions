# release/tag-and-alias

Creates a `vMAJOR.MINOR.PATCH` tag and force-moves the rolling `vMAJOR` /
`vMAJOR.MINOR` alias tags to it. **No GitHub Release** — use this when you only
need the git tags (e.g. a container build that tags the commit and pushes an
image), and add [`release/github-release`](../github-release) afterwards if you
also want a Release page.

Uses only `git` — no `gh` CLI — so it runs on self-hosted runners.

## Requirements

- Check out with `actions/checkout@v4` and `fetch-depth: 0`.
- Grant `permissions: contents: write` so the tags can be pushed (the checkout
  token is used for `git push`).

## Inputs

| Input | Required | Default | Description                                              |
| ----- | -------- | ------- | -------------------------------------------------------- |
| `tag` | yes      | —       | Tag to create, `vMAJOR.MINOR.PATCH` (from a resolver step). |

## Outputs

| Output | Description       |
| ------ | ----------------- |
| `tag`  | The tag created.  |

## Usage

```yaml
jobs:
  tag:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - id: ver
        uses: DataLabHell/ci-actions/actions/versioning/auto-patch@v0.1

      - uses: DataLabHell/ci-actions/actions/release/tag-and-alias@v0.1
        with:
          tag: ${{ steps.ver.outputs.tag }}

      # ... build & push your container image tagged ${{ steps.ver.outputs.tag }} ...
```

## Notes

- The `tag` must be `vMAJOR.MINOR.PATCH`; the `vX` / `vX.Y` aliases are derived
  from it and force-moved, so consumers pinned to `@vX` / `@vX.Y` follow along.
