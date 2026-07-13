# s3-file-upload

Reusable composite GitHub Action that uploads files/folders from a repo to an
S3-compatible bucket (the org RustFS store) using the AWS CLI. Credentials and
connection settings come from a named AWS profile configured on the runner, so
it runs on **self-hosted runners** that have that profile.

No Docker required (composite action, not a container action).

## Requirements

- **Self-hosted runner** with the `dlh` AWS profile configured (see
  [Connection & credentials](#connection--credentials)). GitHub-hosted runners
  won't have the profile.
- **AWS CLI v2.13+** on the runner (needed for `endpoint_url` in the profile
  config). Our self-hosted runners already include it; the action installs
  nothing at CI time — it just checks `aws` is present and fails clearly if not.

## Using it from another repo

This action lives in the shared [`ci-actions`](../README.md) monorepo, so it is
referenced by its path within the repo plus a tag:

```yaml
- uses: DataLabHell/ci-actions/s3-file-upload@v0.1
```

Pin to a released tag (e.g. `@v0.1`) rather than `@main` so pipelines are not
broken by in-progress changes.

## Connection & credentials

By default the action uses the **`dlh` AWS profile configured on the runner**.
That profile supplies everything needed to reach the org store — endpoint,
region, addressing style, and credentials — so a normal upload needs **no
credentials in the workflow at all**:

```yaml
- uses: DataLabHell/ci-actions/s3-file-upload@v0.1
  with:
    source: outputs
    destination: my-service/${{ github.run_id }}
```

The `dlh` profile is configured once per runner (as the user the runner service
runs as), in `~/.aws/config` and `~/.aws/credentials`:

```ini
# ~/.aws/config
[profile dlh]
endpoint_url = https://truenas.dlh-k8s.com:9000
region = at-west-1
s3 =
    addressing_style = path
```

```ini
# ~/.aws/credentials
[dlh]
aws_access_key_id = AKIA...
aws_secret_access_key = wJalr...
```

Because the endpoint lives in the profile, there is no `endpoint-url` input —
point at a different store by using a different `profile`. The action never
touches the runner's AWS config, so the profile's own settings take effect, and
credentials never appear in the workflow. It fails fast if the profile isn't
set.

## Inputs

| Input            | Required | Default                            | Description                                                                                                                                                       |
| ---------------- | -------- | ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bucket`         | no       | `reports`   | Target bucket name.                                                                                                                                               |
| `profile`        | yes      | `dlh`       | AWS CLI profile configured on the runner; supplies endpoint, region, addressing style and credentials.                                                           |
| `source`         | no       | `outputs`   | Folder in the repo to upload from (may be a nested subpath).                                                                                                      |
| `destination`    | no       | `''`        | Prefix/subfolder inside the bucket.                                                                                                                               |
| `include`        | no       | `*.html`    | Comma-separated glob(s) to include, relative to `source`. AWS CLI `*` matches across `/`, so `*.html` covers every depth; use `*` for everything.                 |
| `exclude`        | no       | `''`        | Comma-separated glob(s) to exclude (applied after include).                                                                                                       |
| `delete-removed` | no       | `false`     | Mirror deletions (adds `--delete`). Scoped to `destination`; **requires a non-empty `destination`** so it can't delete other pipelines' files at the bucket root. |
| `extra-args`     | no       | `''`        | Any extra raw `aws s3 sync` flags.                                                                                                                                |

## Output

| Output    | Description                                          |
| --------- | ---------------------------------------------------- |
| `s3-path` | The resulting `s3://bucket/prefix` path uploaded to. |

## Example 1 — Upload a pytest HTML report to the org S3

Uses the default `dlh` profile on the self-hosted runner — no credentials in the
workflow:

```yaml
jobs:
  test:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4

      - name: Run tests
        run: pytest --html=report/index.html --self-contained-html

      - name: Upload report to S3
        uses: DataLabHell/ci-actions/s3-file-upload@v0.1
        with:
          source: report
          destination: my-service/${{ github.run_id }}
          include: "*.html,*.css,*.png"
```

## Example 2 — Upload a whole folder and mirror deletions

Uploads everything under `coverage/html`, into a per-branch prefix, and mirrors
deletions so the destination matches the source exactly:

```yaml
jobs:
  coverage:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4

      - name: Generate coverage report
        run: npm run coverage:html

      - name: Upload coverage report
        uses: DataLabHell/ci-actions/s3-file-upload@v0.1
        with:
          bucket: coverage
          source: coverage/html
          include: "*"
          destination: frontend/${{ github.ref_name }}
          delete-removed: "true"
```

## Notes

- `include`/`exclude` use AWS CLI's `s3 sync` filter syntax. Note that `*`
  matches **across `/`** (unlike normal shell globs), so `*.html` matches HTML
  files at any depth and `*` matches everything. A pattern with a literal slash
  like `sub/*.html` only matches that subpath. Filters are applied in order:
  exclude everything, then re-include your patterns, then apply explicit
  excludes on top.
- `delete-removed` only affects objects **under the `destination` prefix**, and
  only those matching the include/exclude filters. Because the default bucket is
  shared, the action refuses to run `--delete` when `destination` is empty — give
  each pipeline its own prefix (e.g. `my-service/`) before enabling it.
- Credentials are never inputs and never appear in the workflow (see
  [Connection & credentials](#connection--credentials)): they stay in the
  runner's `~/.aws/credentials` under the profile. The action doesn't read,
  echo, or write any credentials or AWS config.
