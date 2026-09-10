#!/usr/bin/env bash
set -euo pipefail

# Deploy for python/flyte-deploy. Inputs come in as INPUT_* env vars; the client
# secret is already in FLYTE_CLIENT_SECRET, which the flyte CLI picks up itself.
ENVIRONMENT="${INPUT_ENVIRONMENT:-}"
PROJECT="${INPUT_PROJECT:-}"
DOMAIN="${INPUT_DOMAIN:-development}"
ENDPOINT="${INPUT_ENDPOINT:-}"
ORG="${INPUT_ORG:-}"
VERSION="${INPUT_VERSION:-}"
REGISTER_ON_PR="${INPUT_REGISTER_ON_PR:-false}"
DRY_RUN="${INPUT_DRY_RUN:-auto}"
EXTRA_ARGS="${INPUT_EXTRA_ARGS:-}"

for required in ENVIRONMENT PROJECT DOMAIN ENDPOINT ORG; do
  if [ -z "${!required}" ]; then
    echo "::error::input '$(echo "$required" | tr '[:upper:]_' '[:lower:]-')' is required"
    exit 1
  fi
done

if [ -z "${FLYTE_CLIENT_SECRET:-}" ]; then
  echo "::error::FLYTE_CLIENT_SECRET is empty — the Vault step returned nothing for vault-secret" >&2
  exit 1
fi

case "$REGISTER_ON_PR" in
  true | false) ;;
  *)
    echo "::error::input 'register-on-pr' must be true or false (got '$REGISTER_ON_PR')"
    exit 1
    ;;
esac

IS_PR=false
if [ "${GITHUB_EVENT_NAME:-}" = "pull_request" ] || [ "${GITHUB_EVENT_NAME:-}" = "pull_request_target" ]; then
  IS_PR=true
fi

# Pull requests only validate the deploy, unless register-on-pr asks for a real
# registration; anything else always registers.
case "$DRY_RUN" in
  auto)
    if [ "$IS_PR" = "true" ] && [ "$REGISTER_ON_PR" != "true" ]; then
      DRY_RUN=true
    else
      DRY_RUN=false
    fi
    ;;
  true | false) ;;
  *)
    echo "::error::input 'dry-run' must be one of auto, true, false (got '$DRY_RUN')"
    exit 1
    ;;
esac

SHORT_SHA="${GITHUB_SHA:0:7}"
if [ -z "$VERSION" ]; then
  # No version given: the commit is the version.
  VERSION="${GITHUB_SHA:-$SHORT_SHA}"
elif [ "$IS_PR" = "true" ] && [ "$DRY_RUN" != "true" ]; then
  # A PR that really registers must not collide with the version main deploys,
  # so it is always made distinct per commit. Off a PR the version is used as
  # passed, and a dry run registers nothing either way.
  VERSION="${VERSION}-${SHORT_SHA}"
fi

# domain takes a list: comma, whitespace or newline separated, so one call can
# deploy the same version to several domains.
DOMAINS=()
while read -r domain; do
  [ -n "$domain" ] && DOMAINS+=("$domain")
done < <(echo "$DOMAIN" | tr -s ',[:space:]' '\n')

if [ "${#DOMAINS[@]}" -eq 0 ]; then
  echo "::error::input 'domain' is required"
  exit 1
fi

for domain in "${DOMAINS[@]}"; do
  args=(--endpoint "$ENDPOINT" --org "$ORG" --no-progress deploy
    --project "$PROJECT" --domain "$domain" --version "$VERSION")
  if [ "$DRY_RUN" = "true" ]; then
    args+=(--dry-run)
  fi

  echo "deploying $ENVIRONMENT as $VERSION to $PROJECT/$domain (dry-run=$DRY_RUN)"
  # The ssl.create_default_context() call warms the system trust store before
  # flyte's gRPC client is imported, so the internal CA is picked up.
  # shellcheck disable=SC2086
  uv run python -c "import ssl; ssl.create_default_context(); from flyte.cli.main import main; main()" \
    "${args[@]}" $EXTRA_ARGS $ENVIRONMENT
done

{
  echo "version=${VERSION}"
  echo "dry-run=${DRY_RUN}"
  echo "domains=${DOMAINS[*]}"
} >>"$GITHUB_OUTPUT"
