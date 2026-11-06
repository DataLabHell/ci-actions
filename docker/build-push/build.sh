#!/usr/bin/env bash
set -euo pipefail

# Inputs are passed in as INPUT_* environment variables by action.yml. This
# script only *computes* values (image ref, tag list, cache args) for the
# docker/* actions that follow. It does not build, push or log in itself.
REGISTRY="${INPUT_REGISTRY:-}"
NAMESPACE="${INPUT_NAMESPACE:-}"
IMAGE="${INPUT_IMAGE:-}"
TAGS_IN="${INPUT_TAGS:-}"
CACHE="${INPUT_CACHE:-gha}"
PUSH="${INPUT_PUSH:-true}"
PLATFORMS_IN="${INPUT_PLATFORMS:-}"
USERNAME="${INPUT_USERNAME:-}"
PASSWORD="${INPUT_PASSWORD:-}"

if [ -z "$IMAGE" ]; then
  echo "::error::'image' is required"
  exit 1
fi

# Decide which login step runs:
#   ghcr.io     -> log in with the workflow's GITHUB_TOKEN    (login=ghcr)
#   other host  -> log in with the username/password inputs  (login=password)
case "$REGISTRY" in
  ghcr | ghcr.io)
    REGISTRY="ghcr.io"
    LOGIN="ghcr"
    ;;
  "")
    echo "::error::'registry' is empty"
    exit 1
    ;;
  *)
    if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
      echo "::error::registry '$REGISTRY' needs the 'username' and 'password' inputs"
      exit 1
    fi
    LOGIN="password"
    ;;
esac

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

# Target platforms. Accepts newline- and/or comma-separated values so callers can
# write a YAML block or a one-liner. Empty = let buildx pick the runner's native
# platform (linux/amd64 here).
#
# The runners are x86-64, so any non-amd64 platform is built through QEMU
# emulation: we emit `qemu=true` and action.yml then runs setup-qemu-action.
# Emulated builds are slow, which is why QEMU is only installed when needed.
PLATFORMS=()
QEMU="false"
while IFS= read -r platform; do
  platform="$(echo "$platform" | xargs)"
  [ -z "$platform" ] && continue
  case "$platform" in
    */*) ;;
    *)
      echo "::error::invalid platform '$platform': expected '<os>/<arch>', e.g. linux/amd64 or linux/arm64"
      exit 1
      ;;
  esac
  PLATFORMS+=("$platform")
  # linux/amd64 (and its aliases) is native; everything else needs emulation.
  case "$platform" in
    linux/amd64 | linux/x86_64 | linux/386) ;;
    *) QEMU="true" ;;
  esac
done <<<"$(echo "$PLATFORMS_IN" | tr ',' '\n')"

PLATFORMS_OUT=""
if [ "${#PLATFORMS[@]}" -gt 0 ]; then
  PLATFORMS_OUT="$(
    IFS=,
    echo "${PLATFORMS[*]}"
  )"
fi

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
  echo "platforms=$PLATFORMS_OUT"
  echo "qemu=$QEMU"
} >>"$GITHUB_OUTPUT"

echo "Image ref: $REF"
printf 'Tags:\n'
printf '  %s\n' "${TAGS[@]}"
echo "Platforms: ${PLATFORMS_OUT:-<runner native>}"
if [ "$QEMU" = "true" ]; then
  echo "Non-amd64 platform requested: building under QEMU emulation (slower)."
fi
