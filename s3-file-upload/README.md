# s3-file-upload

Reusable composite GitHub Action that uploads files/folders from a repo to any
S3-compatible bucket (RustFS, AWS S3, MinIO, on-prem S3, etc.) using the AWS CLI.
By default it uses the `dlh` AWS profile on the runner to reach the org store;
it can also target real AWS S3 with environment credentials.

No Docker required (composite action, not a container action).

## Requirements

The **AWS CLI** must be available on the runner. Both GitHub-hosted runners and
our self-hosted runners already include it, so there's nothing to set up. The
action does not install anything at CI time — it checks that `aws` is present
and fails with a clear error if it isn't.

## Using it from another repo

This action lives in the shared [`ci-actions`](../README.md) monorepo, so it is
referenced by its path within the repo plus a tag:

```yaml
- uses: DataLabHell/ci-actions/s3-file-upload@v1
```

Pin to a released tag (e.g. `@v1`) rather than `@main` so pipelines are not
broken by in-progress changes.

## Connection & credentials

By default the action uses the **`dlh` AWS profile configured on the runner**.
That profile supplies everything needed to reach the org store — endpoint,
region, addressing style, and credentials — so a normal upload needs **no
credentials in the workflow at all**:

```yaml
- uses: DataLabHell/ci-actions/s3-file-upload@v1
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
point at a different store by using a different profile. When a profile is used
the action does **not** touch the runner's AWS config, so the profile's own
settings take effect.

### Alternative: credentials from the environment

Set `profile: ''` to fall back to the standard AWS environment variables (the
AWS CLI reads them natively). With no profile there's no endpoint, so this
targets **real AWS S3**, and `region` / `path-style` come from the inputs:

```yaml
- uses: DataLabHell/ci-actions/s3-file-upload@v1
  env:
    AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
    AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
  with:
    profile: ''
    bucket: my-bucket
    source: outputs
```

The action fails fast if neither a profile nor the two env vars are set.

## Inputs

| Input            | Required | Default                            | Description                                                                                                                                                       |
| ---------------- | -------- | ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bucket`         | no       | `reports`  | Target bucket name.                                                                                                                                               |
| `profile`        | no       | `dlh`      | AWS CLI profile configured on the runner; supplies endpoint, region, addressing style and credentials. Set to `''` to use `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` instead. |
| `region`         | no       | `at-west-1` | S3 region. Only used when `profile` is `''` (otherwise the region comes from the profile).                                                                       |
| `source`         | no       | `outputs`  | Folder in the repo to upload from (may be a nested subpath).                                                                                                      |
| `destination`    | no       | `''`       | Prefix/subfolder inside the bucket.                                                                                                                               |
| `include`        | no       | `**/*.html` | Comma-separated glob(s) to include, relative to `source`. Defaults to HTML only; use `**/*` for everything.                                                       |
| `exclude`        | no       | `''`       | Comma-separated glob(s) to exclude (applied after include).                                                                                                       |
| `path-style`     | no       | `true`     | Path-style addressing. Only used when `profile` is `''` (otherwise it comes from the profile).                                                                    |
| `delete-removed` | no       | `false`                            | Mirror deletions (adds `--delete`). Scoped to `destination`; **requires a non-empty `destination`** so it can't delete other pipelines' files at the bucket root. |
| `extra-args`     | no       | `''`                               | Any extra raw `aws s3 sync` flags.                                                                                                                                |

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
        uses: DataLabHell/ci-actions/s3-file-upload@v1
        with:
          source: report
          destination: my-service/${{ github.run_id }}
          include: "**/*.html,**/*.css,**/*.png"
```

## Example 2 — Upload a whole folder to real AWS S3 (no profile)

Set `profile: ''` and pass credentials via the environment:

```yaml
jobs:
  coverage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Generate coverage report
        run: npm run coverage:html

      - name: Upload coverage report
        uses: DataLabHell/ci-actions/s3-file-upload@v1
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        with:
          profile: "" # no profile -> env credentials, real AWS S3
          bucket: my-org-coverage-reports
          region: eu-central-1
          path-style: "false"
          source: coverage/html
          include: "**/*"
          destination: frontend/${{ github.ref_name }}
          delete-removed: "true"
```

## Notes

- `include`/`exclude` use AWS CLI's `s3 sync` filter syntax (glob-style, e.g.
  `*`, `**/*.html`). Filters are applied in order: exclude everything, then
  re-include your patterns, then apply any explicit excludes on top.
- `delete-removed` only affects objects **under the `destination` prefix**, and
  only those matching the include/exclude filters. Because the default bucket is
  shared, the action refuses to run `--delete` when `destination` is empty — give
  each pipeline its own prefix (e.g. `my-service/`) before enabling it.
- Credentials are never inputs (see [Connection & credentials](#connection--credentials)):
  with a profile they stay in the runner's `~/.aws/credentials`; without one they
  come from `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in the environment. They
  are never echoed, and the only file the action writes is an ephemeral job-scoped
  AWS config (no-profile mode only), deleted at the end of the step.
