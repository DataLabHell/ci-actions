# mise-setup

Provision a repo's dev tools with [mise](https://mise.jdx.dev) so later steps in
the job can call them directly. It is a thin composite wrapper around
[`jdx/mise-action`](https://github.com/jdx/mise-action) that adds the two pieces
every caller otherwise repeats: an `actions/cache` entry over the mise install
dirs, and a `mise prune` pass afterwards.

Tool versions come from the project's own mise config (`mise.toml`,
`.mise.toml`, `.tool-versions`). This action has no inputs, so there is nothing
to keep in sync between the workflow and that config.

## Requirements

- `actions/checkout@v4` before this step, so mise can see the project config.
- A mise config in the checked-out repo.
- Nothing preinstalled on the runner: `jdx/mise-action` installs mise itself.

## Inputs

None.

## Outputs

None. The effect is on the job: mise-managed tools are available to the steps
that follow.

## Usage

```yaml
jobs:
  build:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4

      - uses: DataLabHell/ci-actions/mise-setup@v0.2

      - name: Run a project task
        shell: bash
        run: mise run build
```

## Notes

- **Caching is handled here, not by mise-action.** The wrapped action runs with
  `cache: false` and `actions/cache` covers `~/.local/share/mise/installs`,
  `~/.local/share/mise/plugins` and `~/.cache/mise` instead. Background:
  [jdx/mise-action#537](https://github.com/jdx/mise-action/issues/537).
- **The cache key is `mise-<repo>-<os>`.** It holds no hash of the mise config,
  so it is a fixed key per repo and runner OS. GitHub only saves a cache entry
  when the key is new, so the first run of a repo populates it and later runs
  restore it. Tools added to the config after that are installed on each run and
  not written back to the cache until the key changes.
- **`experimental: true`** is passed to mise-action, which mise needs for the
  features the org's projects use.
- **Pruning keeps the cache small.** `mise prune -y` drops versions the config no
  longer references, which matters because the cached install dirs are otherwise
  append-only.
- **Third-party pins are SHAs.** Both wrapped actions are pinned to a commit, so
  a moved upstream tag cannot change what runs here.
