# s3-file-upload

Reusable composite GitHub Action that uploads files/folders from a repo to an
S3-compatible bucket (the org RustFS store) using the AWS CLI. Credentials come
from a named AWS profile on the runner, from inputs you pass in, or from the
ambient AWS environment (see
[Connection & credentials](#connection--credentials)).

No Docker required (composite action, not a container action).

## Requirements

- AWS CLI v2.13+ on the runner (needed for `endpoint_url` in the profile
  config). Our self-hosted runners already include it, and GitHub-hosted runners
  ship it preinstalled. The action installs nothing at CI time, it just checks
  `aws` is present and fails clearly if not. On a bare self-hosted runner, add
  an install step such as `unfor19/install-aws-cli-action` first.
- For the profile mode, a self-hosted runner with that AWS profile configured.
  GitHub-hosted runners won't have one, so use another mode there.

## Using it from another repo

This action lives in the shared [`ci-actions`](../README.md) monorepo, so it is
referenced by its path within the repo plus a tag:

```yaml
- uses: DataLabHell/ci-actions/s3-file-upload@s3-file-upload-vX.Y.Z
```

`@s3-file-upload-vX.Y.Z` is a placeholder. Each action is versioned
independently and tagged `<action-path>-vMAJOR.MINOR.PATCH` (see
[Versioning](../README.md#versioning)). Substitute the current version and pin
an exact tag rather than `@main`; Renovate keeps it current.

## Connection & credentials

Three ways to authenticate, checked in this order:

| Given                                 | Effect                                       |
| ------------------------------------- | -------------------------------------------- |
| `access-key-id` + `secret-access-key` | Those keys are used; `profile` is ignored.   |
| `profile`                             | `--profile <name>` is passed to the AWS CLI. |
| neither (the default)                 | The AWS CLI resolves credentials itself.     |

### The default: let the AWS CLI resolve credentials

With no `profile` and no keys, the action passes no credentials of its own, so
the CLI falls back to its usual chain: `AWS_*` environment variables, an OIDC
role, an instance profile. That composes with
[`aws-actions/configure-aws-credentials`](https://github.com/aws-actions/configure-aws-credentials):

```yaml
- uses: aws-actions/configure-aws-credentials@<sha>
  with:
    role-to-assume: arn:aws:iam::123456789012:role/ci-upload
    aws-region: eu-central-1

- uses: DataLabHell/ci-actions/s3-file-upload@s3-file-upload-vX.Y.Z
  with:
    bucket: reports
    source: outputs
    destination: my-service
```

Setting `profile` here would break it: `--profile` takes precedence over the
environment.

### A profile on the runner

Name a profile and it supplies the endpoint, region and credentials, so nothing
sensitive goes in the workflow. Inside the org that profile is `dlh`:

```yaml
- uses: DataLabHell/ci-actions/s3-file-upload@s3-file-upload-vX.Y.Z
  with:
    profile: dlh
    source: outputs
    destination: my-service
```

It is configured once per runner (as the user the runner service runs as), in
`~/.aws/config` and `~/.aws/credentials`:

```ini
# ~/.aws/config
[profile dlh]
region = at-west-1
output = json
endpoint_url = https://truenas.dlh-k8s.com:9000
```

```ini
# ~/.aws/credentials
[dlh]
aws_access_key_id = AKIA...
aws_secret_access_key = wJalr...
```

The action never touches the runner's AWS config, so the profile's own settings
take effect. It fails fast if the named profile isn't configured, which usually
means the job landed on a GitHub-hosted runner.

> **Why the profile lives on the runner (not GitHub secrets):** the free GitHub
> plan doesn't offer organization-wide secrets/variables for private repos, so
> sharing credentials that way would mean re-adding them as secrets in every
> repo. Configuring `dlh` once per self-hosted runner keeps the credentials in
> one place and every repo on that runner uses them with no per-repo setup.

### Keys passed in

For a store the runner knows nothing about, pass `access-key-id` and
`secret-access-key`. They take precedence over `profile`:

```yaml
- uses: DataLabHell/ci-actions/s3-file-upload@s3-file-upload-vX.Y.Z
  with:
    bucket: reports
    source: outputs
    destination: my-service
    access-key-id: ${{ secrets.S3_ACCESS_KEY_ID }}
    secret-access-key: ${{ secrets.S3_SECRET_ACCESS_KEY }}
    endpoint-url: https://truenas.dlh-k8s.com:9000
    region: at-west-1
```

`endpoint-url` is what points the CLI at a non-AWS store; omit it for real AWS
S3. `region` is what a profile would otherwise supply, and the CLI errors out
without one unless the runner sets `AWS_DEFAULT_REGION`. Add `session-token` for
temporary credentials. Both keys must be given together, and the values are read
from the environment rather than passed as CLI flags so they don't land in the
process list. Always pass them from `secrets`, never inline.

`endpoint-url` and `region` work in all three modes, overriding whatever a
profile configures.

## Inputs

| Input               | Required | Default   | Description                                                                                                                                                       |
| ------------------- | -------- | --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bucket`            | no       | `reports` | Target bucket name.                                                                                                                                               |
| `profile`           | no       | `''`      | AWS CLI profile on the runner; supplies endpoint, region and credentials. Ignored when `access-key-id` is given. Empty lets the AWS CLI resolve credentials.      |
| `access-key-id`     | no       | `''`      | Access key to use instead of a runner profile. Requires `secret-access-key`. Pass from `secrets`.                                                                 |
| `secret-access-key` | no       | `''`      | Secret key matching `access-key-id`. Pass from `secrets`.                                                                                                         |
| `session-token`     | no       | `''`      | Session token, for temporary credentials.                                                                                                                         |
| `endpoint-url`      | no       | `''`      | S3 endpoint URL. Needed with `access-key-id` for non-AWS stores; overrides the profile's endpoint when both are given.                                            |
| `region`            | no       | `''`      | AWS region. Overrides the profile's region when both are given.                                                                                                   |
| `source`            | no       | `outputs` | Folder in the repo to upload from (may be a nested subpath).                                                                                                      |
| `destination`       | no       | `''`      | Prefix/subfolder inside the bucket.                                                                                                                               |
| `include`           | no       | `*.html`  | Comma-separated glob(s) to include, relative to `source`. AWS CLI `*` matches across `/`, so `*.html` covers every depth; use `*` for everything.                 |
| `exclude`           | no       | `''`      | Comma-separated glob(s) to exclude (applied after include).                                                                                                       |
| `delete-removed`    | no       | `false`   | Mirror deletions (adds `--delete`). Scoped to `destination`; **requires a non-empty `destination`** so it can't delete other pipelines' files at the bucket root. |

## Output

| Output    | Description                                          |
| --------- | ---------------------------------------------------- |
| `s3-path` | The resulting `s3://bucket/prefix` path uploaded to. |

## Example 1: just the step

Add the step to any job running on a self-hosted runner. With the org's `dlh`
profile, no credentials are needed in the workflow:

```yaml
- name: Upload report to S3
  uses: DataLabHell/ci-actions/s3-file-upload@s3-file-upload-vX.Y.Z
  with:
    profile: dlh
    source: report
    destination: my-service
    include: "*.html,*.css,*.png"
```

## Example 2: upload a whole folder and mirror deletions

Uploads everything under `coverage/html` and mirrors deletions so the
destination matches the source exactly:

```yaml
jobs:
  coverage:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v7

      - name: Generate coverage report
        run: npm run coverage:html

      - name: Upload coverage report
        uses: DataLabHell/ci-actions/s3-file-upload@s3-file-upload-vX.Y.Z
        with:
          profile: dlh
          bucket: coverage
          source: coverage/html
          include: "*"
          destination: frontend
          delete-removed: "true"
```

## Example 3: upload several sources

The action uploads one source folder per invocation; there is no multi-source
input. To upload from more than one folder, add the step several times in the
same job. Each step is independent, so give each its own `source` (and usually
its own `destination` prefix):

```yaml
jobs:
  publish:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v7

      - name: Upload docs
        uses: DataLabHell/ci-actions/s3-file-upload@s3-file-upload-vX.Y.Z
        with:
          profile: dlh
          source: docs
          destination: my-service/docs
          include: "*"

      - name: Upload HTML reports
        uses: DataLabHell/ci-actions/s3-file-upload@s3-file-upload-vX.Y.Z
        with:
          profile: dlh
          source: htmls
          destination: my-service/htmls
          include: "*.html"
```

If instead you want several folders **merged under one prefix**, point `source`
at their common parent and select them with `include` (comma-separated globs),
e.g. `source: .` with `include: "docs/*, htmls/*"`, a single step. Don't enable
`delete-removed` on this form: with a broad `source` (like the repo root) the
mirror-delete is compared against the whole source tree, not just your included
folders. If you need `delete-removed`, use the repeat-the-step form above, where
each step's `source`/`destination` is tightly scoped.

## Notes

- `include`/`exclude` use AWS CLI's `s3 sync` filter syntax. Note that `*`
  matches **across `/`** (unlike normal shell globs), so `*.html` matches HTML
  files at any depth and `*` matches everything. A pattern with a literal slash
  like `sub/*.html` only matches that subpath. Filters are applied in order:
  exclude everything, then re-include your patterns, then apply explicit
  excludes on top.
- `destination` is a plain prefix. The examples use a fixed service name
  (`my-service`), which overwrites the same location each run. If you'd rather
  keep uploads separate per run/branch/commit, put a GitHub context expression
  in it, e.g. `my-service/${{ github.run_id }}`,
  `my-service/${{ github.ref_name }}`, or `my-service/${{ github.sha }}`.
- `delete-removed` only affects objects **under the `destination` prefix**, and
  only those matching the include/exclude filters. Because the default bucket is
  shared, the action refuses to run `--delete` when `destination` is empty. Give
  each pipeline its own prefix (e.g. `my-service/`) before enabling it.
- With the profile mode, credentials never appear in the workflow: they stay in
  the runner's `~/.aws/credentials`. The action never writes to the AWS config
  in either mode, and never echoes a credential.
- One `source` per step. To upload from multiple folders, repeat the step (see
  [Example 3](#example-3-upload-several-sources)); the action is a composite
  action, so calling it several times in one job is expected usage.
