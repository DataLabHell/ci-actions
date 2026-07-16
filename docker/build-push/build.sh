#!/usr/bin/env bash
set -euo pipefail

# Inputs are passed in as INPUT_* environment variables by action.yml. This
# script only *computes* values (image ref, tag list, cache args) for the
# docker/* actions that follow — it does not build or push anything itself, so
# there is no credential handling here.
REGISTRY="${INPUT_REGISTRY:-}"
NAMESPACE="${INPUT_NAMESPACE:-}"
IMAGE="${INPUT_IMAGE:-}"
TAGS_IN="${INPUT_TAGS:-}"
CACHE="${INPUT_CACHE:-gha}"
PUSH="${INPUT_PUSH:-true}"

if [ -z "$IMAGE" ]; then
  echo "::error::'image' is required"
  exit 1
fi

# Only the two org registries are allowed for now. Each accepts its short alias
# or its full host; anything else fails clearly instead of building a broken ref.
# Each registry has a fixed auth model, so we also decide here whether a login
# step runs — the caller never passes credentials:
#   ghcr.io  -> log in with the workflow's GITHUB_TOKEN
#   truenas  -> no login step; use the credentials configured on the runner
case "$REGISTRY" in
  ghcr | ghcr.io)
    REGISTRY="ghcr.io"
    LOGIN="true"
    ;;
  truenas | truenas.dlh-k8s.com:5000)
    REGISTRY="truenas.dlh-k8s.com:5000"
    LOGIN="false"
    ;;
  *)
    echo "::error::unsupported registry '$REGISTRY': allowed values are 'ghcr.io' (alias 'ghcr') and 'truenas.dlh-k8s.com:5000' (alias 'truenas')"
    exit 1
    ;;
esac

# When we rely on the runner's own docker credentials (LOGIN=false, i.e. the
# local registry), a GitHub-hosted runner won't have them — fail fast with a
# clear cause instead of a confusing push auth error. RUNNER_ENVIRONMENT is set
# automatically by the runner (github-hosted | self-hosted).
if [ "$LOGIN" = "false" ] && [ "${RUNNER_ENVIRONMENT:-}" = "github-hosted" ]; then
  echo "::error::registry '$REGISTRY' uses the docker credentials configured on the runner, but this is a GitHub-hosted runner. Run this job on a self-hosted runner where 'docker login $REGISTRY' has been set up."
  exit 1
fi

# Compose the fully-qualified image ref and lowercase it (registries require
# lowercase repositories; the repo name often isn't). Collapse any doubled
# slash left by an empty namespace.
REF="$REGISTRY/$NAMESPACE/$IMAGE"
REF="$(echo "$REF" | tr -s '/' | tr '[:upper:]' '[:lower:]')"

# One "<ref>:<suffix>" per non-empty input line. Blank lines are skipped so
# callers can pass an optional version with ${{ ... }} that may be empty.
TAGS=()
while IFS= read -r suffix; do
  suffix="$(echo "$suffix" | xargs)" # trim surrounding whitespace
  [ -n "$suffix" ] && TAGS+=("$REF:$suffix")
done <<<"$TAGS_IN"

if [ "${#TAGS[@]}" -eq 0 ]; then
  echo "::error::no tags resolved; pass at least one non-empty tag suffix (e.g. 'latest')"
  exit 1
fi

# Cache backend. gha = GitHub-hosted runners; registry = self-hosted / local
# registry (cache lives as a buildcache image); none = disable.
CACHE_FROM=""
CACHE_TO=""
case "$CACHE" in
  gha)
    CACHE_FROM="type=gha,scope=$IMAGE"
    CACHE_TO="type=gha,mode=max,scope=$IMAGE"
    ;;
  registry)
    CACHE_FROM="type=registry,ref=$REF:buildcache"
    # Only write the cache back when actually pushing: a PR build has no push
    # rights and must not mutate the registry.
    if [ "$PUSH" = "true" ]; then
      CACHE_TO="type=registry,ref=$REF:buildcache,mode=max"
    fi
    ;;
  none) ;;
  *)
    echo "::error::cache must be one of: gha, registry, none (got '$CACHE')"
    exit 1
    ;;
esac

{
  echo "registry=$REGISTRY"
  echo "login=$LOGIN"
  echo "ref=$REF"
  echo "tags<<__TAGS_EOF__"
  printf '%s\n' "${TAGS[@]}"
  echo "__TAGS_EOF__"
  echo "cache-from=$CACHE_FROM"
  echo "cache-to=$CACHE_TO"
} >>"$GITHUB_OUTPUT"

echo "Image ref: $REF"
printf 'Tags:\n'
printf '  %s\n' "${TAGS[@]}"
