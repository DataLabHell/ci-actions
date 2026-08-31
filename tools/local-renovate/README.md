# local-renovate

Run [Renovate](https://docs.renovatebot.com) locally against the repo you are in
and, on request, write the resulting version bumps into the manifests. It uses
renovate's read-only `local` platform, so it never talks to the GitHub API about
branches and never opens a pull request. CI still does that.

## Requirements

- `renovate` on `PATH`, most simply pinned as `npm:renovate` in the repo's mise
  config.
- `jq` and `perl`.
- A `renovate.json` in the working directory. The script reads the automerge
  verdicts from it.

## Modes

| Invocation      | Effect                                                                  |
| --------------- | ----------------------------------------------------------------------- |
| _(no argument)_ | List the pending bumps with the verdict renovate.json implies. Exits 0. |
| `check`         | Same listing, but exits 1 when any update is pending. For CI gating.    |
| `apply`         | Rewrite the manifests to the highest `auto` target of each dependency.  |
| `apply --force` | Also rewrite the `manual` and `default` ones, including majors.         |

`separateMinorPatch` reports a patch and a minor entry for the same dependency.
`apply` takes the highest target it is allowed to, so a dependency whose patch
and minor both count as `auto` goes to the minor. The listing collapses to the
same choice: one row per dependency and verdict, carrying the target that row
would apply.

Exit codes beyond those: `2` when renovate extracted no dependencies at all
(usually a network or rate-limit problem, check `RENOVATE_GITHUB_COM_TOKEN`),
and `3` when a dependency's replacement template uses a helper this script
cannot render.

`apply` only touches the manifests. Run the repo's own refresh afterwards
(`mise install`, `cargo update`, `uv sync`, `dbt deps`) to bring locks and
installed tools in line. Here that is `mise run renovate` (aliased as
`dependencies`), which passes the mode through and then reinstalls, prunes and
relocks after an `apply`.

Set `RENOVATE_REPORT=<path>` to replay a report that was captured earlier
instead of running renovate. The tests use this.

## Verdicts

Each `packageRule` in `renovate.json` that carries a `groupName` contributes one
entry to a slug-to-verdict map, `auto` when the rule sets `automerge`, otherwise
`manual`. Every update renovate reports carries the branch it would use; that
branch name is stripped of the `renovate/` and `patch-`/`minor-`/`major-`
prefixes, slugged, and looked up in the map. An update in no group shows
`default`.

Slugging both sides matters. A group named `dev toolchain (mise + python)` slugs
to `dev-toolchain-mise-python`, while the branch renovate assigns is
`renovate/dev-toolchain-(mise-+-python)`. Compare them without slugging and the
verdict silently degrades to `default`, so `apply` skips an update the config
says to automerge.

## How the rewrites work

Renovate reports what to change, never how to edit the file, so each dependency
is matched to a swap method. Every value reaches `perl` through the environment
and is quoted with `\Q..\E`, so no manifest string is ever interpreted as a
pattern. Versions containing regex metacharacters (`21.0.11+10.0.LTS`) are
therefore safe.

| Method | Selected when                                                    | What it does                                                                                                                                                                                                                            |
| ------ | ---------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tpl`  | the dep has both `replaceString` and `autoReplaceStringTemplate` | Renders renovate's own replacement template and swaps the old substring for the result. This is what produces `owner/repo@<sha> # <tag>` for actions and `name:tag@sha256:...` for images, and what pins a floating ref like `@stable`. |
| `lit`  | the dep has a `replaceString` but no template, or neither        | Literal swap. Covers custom regex managers and bare version files. Base64'd through the loop so a multi-line `replaceString` survives.                                                                                                  |
| `key`  | manager `mise` or `cargo`                                        | Swaps the version on the `<dep> =` line, keeping any flavor prefix that sits outside the reported value, so `temurin-21.0.11+10.0.LTS` keeps its `temurin-`.                                                                            |
| `pep`  | manager `pep621`                                                 | Swaps `<dep>[extras]<op><ver>`. The dep-and-operator anchor keeps `sqlfluff` and `sqlfluff-templater-dbt` apart when they share a version.                                                                                              |
| `chan` | manager `rust-toolchain`                                         | Anchors on the `channel` key, since it is not the dep name, then syncs `Cargo.toml`'s `rust-version` off the same bump. Renovate dedupes that second occurrence out of the local report.                                                |

The `tpl` method covers whatever renovate supplies a template for, which today
means the GitHub Actions and docker managers. Only a small handlebars subset is
supported (`{{var}}`, `{{#if}}`, `{{#unless}}`); anything else exits 3 rather
than writing a half-rendered string.

Two guards apply to every method: updates for the same dep in the same file are
collapsed to the highest target that passes the verdict filter, and a
digest-pinned dep whose update carries no new digest is skipped since there is
nothing to write.

## Tests

```bash
mise run test
```

Each case under `tests/cases/` replays a report through `RENOVATE_REPORT`, then
compares the rewritten tree against `expected/`. One case per method plus the
edge cases: a tag bump with no digest, a floating ref being pinned, a
digest-pinned dep whose update has no digest, a manifest that is absent, a
multi-line `replaceString`, an unsupported template, and the `check` and
up-to-date exits.

`expected/` for the apply cases is derived from the values in the report, not
from running the script. The one exception is `list-only`, whose
`expected-list.txt` is a recorded snapshot; it exists to catch column-alignment
drift.

To add a case, capture a report with
`renovate --platform=local --report-type=file --report-path=report.json`, trim
it to the deps of interest, and put the manifests they reference under `in/`.

## Notes

- Alignment uses `awk`. `column` is absent on some machines and its `-t` output
  differs between BSD and GNU, so the listing would be neither portable nor
  testable.
- Distribution is not wired up yet. The script lives here as the single source;
  a later release process will publish it so mise can install it with the
  `github` backend as `local-renovate@vX.Y.Z`.
