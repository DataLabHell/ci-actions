# python/flyte-deploy

Deploy a Flyte environment with the `flyte` CLI (run through `uv`). The deploy
client id, oauth scope and secret come from the inputs; the action writes them
into a throwaway config file (merged on top of the repo's own, if it has one) so
the CLI authenticates with the client credentials grant instead of falling back
to its default browser (PKCE) flow. Everything else the CLI needs — endpoint,
org, project, domain, version — is passed as a command option, so a repo needs
no `flyte` config file in the checkout. `domain` takes a list, so one step can
deploy the same version to several domains (`development,production`).

On a pull request the deploy runs with `--dry-run` (nothing is registered); on
any other event it registers for real with the version exactly as given. Set
`register-on-pr: true` to register from a pull request too — those deploys
always get `-<short-sha>` appended so they never collide with a main deploy.

## Requirements

- Nothing preinstalled. The action installs `uv` itself via
  [`astral-sh/setup-uv`](https://github.com/astral-sh/setup-uv).
- `actions/checkout@v7` before this step.
- The project's environment must provide the `flyte` package (`uv run` resolves
  it from the checkout's `pyproject.toml`/lockfile).
- The deploy client's credentials, passed from the org secrets
  `FLYTE_DEPLOY_CLIENT_ID`, `FLYTE_DEPLOY_CLIENT_SECRET` and
  `FLYTE_DEPLOY_CLIENT_SCOPE`.

## Inputs

| Input               | Required | Default                         | Description                                                                                 |
| ------------------- | -------- | ------------------------------- | ------------------------------------------------------------------------------------------- |
| `environment`       | yes      | —                               | Trailing args of `flyte deploy`, e.g. `my_pkg/workflows.py` or `--all my_pkg/workflows.py`. |
| `project`           | yes      | —                               | Flyte project to deploy into.                                                               |
| `domain`            | no       | `development`                   | Flyte domain(s), as a comma/space/newline separated list (`development,production`).        |
| `endpoint`          | no       | `dns:///flyte.apps.dlh-k8s.com` | Flyte admin endpoint.                                                                       |
| `org`               | no       | `flyte`                         | Flyte organization.                                                                         |
| `version`           | no       | `''`                            | Version to deploy; empty means the commit sha.                                              |
| `register-on-pr`    | no       | `false`                         | Register for real on pull requests; the short sha is always appended to the version.        |
| `dry-run`           | no       | `auto`                          | `auto` (dry run on pull requests unless `register-on-pr`), `true`, or `false`.              |
| `extra-args`        | no       | `''`                            | Extra args appended to `flyte deploy` before the environment.                               |
| `working-directory` | no       | `.`                             | Directory to run the deploy from.                                                           |
| `client-id`         | yes      | —                               | OAuth client id of the deploy client.                                                       |
| `client-secret`     | yes      | —                               | OAuth client secret of the deploy client.                                                   |
| `client-scope`      | no       | `''`                            | OAuth scope for the client credentials grant; empty uses what the endpoint advertises.      |

## Outputs

| Output    | Description                               |
| --------- | ----------------------------------------- |
| `version` | The version that was deployed             |
| `dry-run` | `true` if the deploy ran with `--dry-run` |
| `domains` | The domains deployed to, space separated  |

## Usage

```yaml
jobs:
  deploy:
    runs-on: self-hosted
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v7

      - uses: DataLabHell/ci-actions/python/flyte-deploy@python/flyte-deploy-vX.Y.Z
        with:
          project: flyte-otel-demo
          domain: production
          environment: --all flyte_otel_demo/hello_otel.py
          client-id: ${{ secrets.FLYTE_DEPLOY_CLIENT_ID }}
          client-secret: ${{ secrets.FLYTE_DEPLOY_CLIENT_SECRET }}
          client-scope: ${{ secrets.FLYTE_DEPLOY_CLIENT_SCOPE }}
```

Run the same workflow on pull requests to get a `--dry-run` validation of the
deploy, and on `main` to register it:

```yaml
on:
  pull_request:
  push:
    branches: [main]
```

### Development on pull requests, development + production on main

One workflow that validates against `development` on a pull request and, on
`main`, registers to both `development` and `production` under a version from
[`versioning/auto-patch`](../../versioning/auto-patch):

```yaml
on:
  pull_request:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: self-hosted
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0 # auto-patch needs the tags

      - id: ver
        uses: DataLabHell/ci-actions/versioning/auto-patch@versioning/auto-patch-vX.Y.Z

      - uses: DataLabHell/ci-actions/python/flyte-deploy@python/flyte-deploy-vX.Y.Z
        with:
          project: flyte-otel-demo
          environment: --all flyte_otel_demo/hello_otel.py
          version: ${{ steps.ver.outputs.version }}
          domain:
            ${{ github.event_name == 'pull_request' && 'development' ||
            'development,production' }}
          client-id: ${{ secrets.FLYTE_DEPLOY_CLIENT_ID }}
          client-secret: ${{ secrets.FLYTE_DEPLOY_CLIENT_SECRET }}
          client-scope: ${{ secrets.FLYTE_DEPLOY_CLIENT_SCOPE }}
```

On a pull request that is a `--dry-run` against `development` only; on `main`
the same version is registered to `development` and then `production`.

## Notes

- The CLI is invoked as
  `uv run python -c "import ssl; ssl.create_default_context(); from flyte.cli.main import main; main()"`.
  Currently needed due to bug in cpython openssl.
- The generated config is passed with `--config` and deleted when the step ends.
  It carries `admin.clientId`, `admin.authType`, `admin.scopes` and
  `admin.clientSecretEnvVar`; the secret itself stays in the environment and is
  never written to disk. Env vars alone are not enough here — `Config.auto()`
  only reads the environment once it has found a config file.
- The credentials are handed only to the deploy step, so they do not end up in
  the environment of the caller's later steps.
