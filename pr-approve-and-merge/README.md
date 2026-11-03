# pr-approve-and-merge

Composite action that approves pull requests as github-actions[bot] and
optionally merges them as a GitHub App. A bot or app can't approve its own PR,
so a second identity is what satisfies a required review. The merge runs as the
app because a push made with `GITHUB_TOKEN` doesn't trigger the repo's push
workflows, such as the release after a release-please PR merges.

## Requirements

- The calling job grants `contents: read` and `pull-requests: write`.
- The repo setting "Allow GitHub Actions to create and approve pull requests" is
  on.
- For `merge`: a GitHub App installed on the repo with Contents and Pull
  requests write, plus its App ID (or Client ID) and private key. Auto-merge
  must be allowed in the repo settings.

## Inputs

| Input             | Required | Default                                                            | Description                                                                                                                    |
| ----------------- | -------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| `number`          | no       | `""`                                                               | The PR to approve. Takes precedence over `search`.                                                                             |
| `search`          | no       | `head:release-please--branches--main label:"autorelease: pending"` | GitHub search qualifiers selecting open PRs in the calling repo. The default selects the pending release-please PR for `main`. |
| `merge`           | no       | `false`                                                            | Merge the approved PRs as the app, once required checks pass.                                                                  |
| `merge-method`    | no       | `rebase`                                                           | `merge`, `squash` or `rebase`.                                                                                                 |
| `app-id`          | no       | `""`                                                               | App ID or Client ID of the merging GitHub App. Needed for `merge`.                                                             |
| `app-private-key` | no       | `""`                                                               | Private key of the merging GitHub App. Needed for `merge`.                                                                     |

## Outputs

| Output    | Description                            |
| --------- | -------------------------------------- |
| `numbers` | JSON array of the selected PR numbers. |

## Usage

Approve and merge the pending release-please PR once a day:

```yaml
on:
  schedule:
    - cron: "0 6 * * *"
  workflow_dispatch:

jobs:
  release:
    runs-on: self-hosted
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: DataLabHell/ci-actions/pr-approve-and-merge@pr-approve-and-merge-vX.Y.Z
        with:
          merge: true
          app-id: ${{ vars.RELEASE_APP_ID }}
          app-private-key: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}
```

Give release-please the same app's token (its `token` input) so the release PR
it opens triggers CI.

Approve Renovate's PRs as they open; checks still gate the merge, which
Renovate's automerge performs:

```yaml
on:
  pull_request:
    types: [opened, reopened, synchronize]

jobs:
  approve:
    # github.actor is the pusher, so a human commit on a renovate branch skips
    # this. Needs "dismiss stale approvals on push" to drop the old approval.
    if: >-
      github.event.pull_request.user.login == 'datalabhell-renovate[bot]' &&
      github.event.pull_request.head.repo.full_name == github.repository &&
      github.actor == 'datalabhell-renovate[bot]'
    runs-on: self-hosted
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: DataLabHell/ci-actions/pr-approve-and-merge@pr-approve-and-merge-vX.Y.Z
        with:
          number: ${{ github.event.pull_request.number }}
```

## Notes

- A PR github-actions[bot] has already approved is not approved again.
- With `merge`, a PR that is already mergeable is merged directly; any other
  gets auto-merge enabled and merges once its required checks pass.
- `search` returns at most 50 PRs.
- For a release branch other than `main`, set `search` with that branch in the
  `head:release-please--branches--<branch>` qualifier.
