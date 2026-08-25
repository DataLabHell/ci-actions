#!/usr/bin/env bash
set -euo pipefail

# Build + publish for python/publish. Inputs come in as INPUT_* env vars; the
# credentials are already in UV_PUBLISH_USERNAME / UV_PUBLISH_PASSWORD, which
# uv publish picks up on its own.
VERSION="${INPUT_VERSION:-}"
RELEASE_BRANCH="${INPUT_RELEASE_BRANCH:-main}"
PUBLISH_OTHER_BRANCHES="${INPUT_PUBLISH_OTHER_BRANCHES:-false}"
BUILD="${INPUT_BUILD:-true}"
BUILD_ARGS="${INPUT_BUILD_ARGS:-}"

# Branch gate: only the release branch publishes by default. Anything else (a
# feature branch, a tag/PR ref where GITHUB_REF_NAME isn't a branch name)
# publishes only with publish-other-branches, and then as a prerelease.
IS_RELEASE_BRANCH=false
if [ "${GITHUB_REF_TYPE:-}" = "branch" ] && [ "${GITHUB_REF_NAME:-}" = "$RELEASE_BRANCH" ]; then
  IS_RELEASE_BRANCH=true
elif [ "$PUBLISH_OTHER_BRANCHES" != "true" ]; then
  echo "Not on branch '$RELEASE_BRANCH' (ref ${GITHUB_REF:-unknown}) — skipping publish."
  echo "published=false" >>"$GITHUB_OUTPUT"
  exit 0
fi

if [ ! -f pyproject.toml ]; then
  echo "::error::pyproject.toml not found in $(pwd)"
  exit 1
fi

# Dynamic versioning (setuptools-scm et al.) has no version in pyproject.toml,
# so the version has to be pretended in; a fixed [project].version is read from
# the file and the version input is ignored.
DYNAMIC=false
if uv run --no-project python -c '
import sys, tomllib
with open("pyproject.toml", "rb") as f:
    data = tomllib.load(f)
dynamic = "version" in data.get("project", {}).get("dynamic", [])
sys.exit(0 if dynamic else 1)
'; then
  DYNAMIC=true
  if [ -z "$VERSION" ]; then
    echo "::error::this project uses dynamic versioning, so the 'version' input is required (resolve it with versioning/auto-patch or versioning/from-pyproject)"
    exit 1
  fi
else
  fixed="$(uv version --short)"
  if [ -n "$VERSION" ] && [ "$VERSION" != "$fixed" ]; then
    echo "::warning::version input '$VERSION' ignored; pyproject.toml pins $fixed"
  fi
  VERSION="$fixed"
fi

# Off the release branch, mark the build as a prerelease so only the release
# branch ever publishes a final version. .dev0 keeps it sorted below X.Y.Z and
# the short sha (a PEP 440 local segment) keeps every branch build distinct.
if [ "$IS_RELEASE_BRANCH" != "true" ]; then
  VERSION="${VERSION}.dev0+${GITHUB_SHA:0:7}"
  echo "Not on '$RELEASE_BRANCH' — publishing prerelease $VERSION"
fi

if [ "$DYNAMIC" = "true" ]; then
  echo "Dynamic versioning — pretending version $VERSION"
  export SETUPTOOLS_SCM_PRETEND_VERSION="$VERSION"
elif [ "$IS_RELEASE_BRANCH" != "true" ]; then
  # Fixed version: the build reads pyproject.toml, so the prerelease version has
  # to be written into it (the checkout is throwaway, nothing is committed).
  uv version "$VERSION" >/dev/null
fi

if [ "$BUILD" = "true" ]; then
  echo "::group::uv build"
  # shellcheck disable=SC2086
  uv build $BUILD_ARGS
  echo "::endgroup::"
fi

# Publishes only when this version is not yet on the index; --check-url makes an
# already-published version a no-op instead of a failure.
DEVPI_URL="${DEVPI_URL:-}"
if [ -z "$DEVPI_URL" ]; then
  echo "::error::DEVPI_URL is empty — the Vault step did not return kv/data/k8s/devpi/config:url" >&2
  exit 1
fi
base="${DEVPI_URL%/}"
echo "publishing $VERSION to ${base}/"
uv publish \
  --publish-url "${base}/" \
  --check-url "${base}/+simple/"

echo "published=true" >>"$GITHUB_OUTPUT"
echo "version=${VERSION}" >>"$GITHUB_OUTPUT"
