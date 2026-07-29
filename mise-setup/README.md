# mise-setup

Provision a repo's dev tools with [mise](https://mise.jdx.dev) so later steps in
the job can call them directly. It is a thin composite wrapper around
[`jdx/mise-action`](https://github.com/jdx/mise-action) that adds the two pieces
every caller otherwise repeats: an `actions/cache` entry over the mise install
dirs, and a `mise prune` pass afterwards.

Tool versions come from the project's own mise config (`mise.toml`,
`.mise.toml`, `.tool-versions`), so there is nothing to keep in sync between the
workflow and that config.

Installs land in a **per-repository directory**. The default for
`jdx/mise-action` is the runner-wide `~/.local/share/mise`, which causes
problems on a self-hosted runner: every repo's tool versions pile up in one tree
that nothing ever fully cleans, and `mise prune` runs against whatever tree it
is pointed at, so one repo's housekeeping can remove versions another repo
installed. A per-repository directory gives each repo its own set and limits
what `mise prune` can reach to that set.

## Requirements

- `actions/checkout@v4` before this step, so mise can see the project config.
- A mise config in the checked-out repo.
- Nothing preinstalled on the runner: `jdx/mise-action` installs mise itself.

## Inputs

| Input    | Required | Default | Description                                                             |
| -------- | -------- | ------- | ----------------------------------------------------------------------- |
| `global` | no       | `false` | Install into the runner-wide mise dirs instead of a per-repository dir. |

Where things land:

| `global` | Data dir                       | Cache dir                       |
| -------- | ------------------------------ | ------------------------------- |
| `false`  | `$RUNNER_WORKSPACE/.mise/data` | `$RUNNER_WORKSPACE/.mise/cache` |
| `true`   | `~/.local/share/mise`          | `~/.cache/mise`                 |

`$RUNNER_WORKSPACE` is the runner's per-repository work dir, one level above the
checkout, so nothing lands in the git tree and no `.gitignore` entry is needed.
The paths are exported as `MISE_DATA_DIR`, `MISE_CACHE_DIR` and `MISE_STATE_DIR`
through `GITHUB_ENV`. This makes every later `mise` call in the job agree with
what was cached.

Use `global: true` only when the goal is to share one set of tool versions
across every repo on the runner, for example a runner dedicated to a single
project family, where per-repository isolation isn't worth the extra downloads
it causes.

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

      - uses: DataLabHell/ci-actions/mise-setup@vX.Y

      - name: Run a project task
        shell: bash
        run: mise run build
```

To share one tool tree across every repo on the runner instead:

```yaml
- uses: DataLabHell/ci-actions/mise-setup@vX.Y
  with:
    global: "true"
```

## Notes

- **Caching is handled here, not by mise-action.** The wrapped action runs with
  `cache: false` and `actions/cache` covers `<data-dir>/installs`,
  `<data-dir>/plugins` and the cache dir instead, wherever the `global` input
  put them. Background:
  [jdx/mise-action#537](https://github.com/jdx/mise-action/issues/537).
- **The cache key is `mise-<repo>-<os>-<config-hash>`.** The hash covers
  `mise.lock`, `mise*.toml`, `.mise*.toml` and `.tool-versions`. GitHub only
  saves an entry when the key is new, so hashing the config lets an added tool
  reach the cache: edit the config, get a new key, and the updated tool set is
  written back. A `restore-keys` prefix of `mise-<repo>-<os>-` seeds that new
  key from the most recent previous entry, so a one-tool change installs one
  tool instead of all of them.
- **`experimental: true`** is passed to mise-action because mise needs it for
  features the org's projects use.
- **Pruning keeps the cache small.** `mise prune -y` drops versions the config
  no longer references, which matters because the cached install dirs are
  otherwise append-only. With the default per-repository dir it can only touch
  this repo's installs; under `global: true` it operates on the shared tree.
- **Third-party pins are SHAs.** Both wrapped actions are pinned to a commit, so
  a moved upstream tag cannot change what runs here.
