#!/usr/bin/env bash
set -euo pipefail

# Creates TAG and force-moves the rolling major / major.minor aliases derived
# from it. TAG comes in as an environment variable from action.yml.
# Accept either a bare version (0.1.3) or a v-prefixed one (v0.1.3): this action
# is the single authority on the tag format, so it normalizes and always creates
# a v-prefixed git tag. Resolvers emit the bare version.
if ! [[ "$TAG" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "::error::version '$TAG' is not MAJOR.MINOR.PATCH (an optional leading 'v' is allowed)"
  exit 1
fi
MAJOR_NUM="${BASH_REMATCH[1]}"
MINOR_NUM="${BASH_REMATCH[2]}"
PATCH_NUM="${BASH_REMATCH[3]}"
TAG="v${MAJOR_NUM}.${MINOR_NUM}.${PATCH_NUM}"    # canonical v-prefixed git tag
MAJOR="v${MAJOR_NUM}"                            # rolling major alias, e.g. v0
MINOR="v${MAJOR_NUM}.${MINOR_NUM}"               # rolling minor alias, e.g. v0.1
VERSION="${MAJOR_NUM}.${MINOR_NUM}.${PATCH_NUM}" # bare version, e.g. 0.1.3

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

git tag -a "$TAG" -m "$TAG"
git push origin "$TAG"

for ref in "$MAJOR" "$MINOR"; do
  echo "Moving $ref -> $TAG"
  git tag -f "$ref" "$TAG"
  git push origin "$ref" --force
done

# Expose the tag and its rolling aliases so downstream steps can reuse the exact
# same set — e.g. tag a container image v0.1.3 / v0.1 / v0 to mirror the git
# refs. Both v-prefixed (matching the git tags) and bare (conventional image
# tags) variants are provided.
{
  echo "tag=$TAG"
  echo "version=$VERSION"
  echo "major=$MAJOR"
  echo "minor=$MINOR"
  echo "tags<<__TAGS__"
  printf '%s\n' "$TAG" "$MINOR" "$MAJOR"
  echo "__TAGS__"
  echo "versions<<__VERSIONS__"
  printf '%s\n' "$VERSION" "${MAJOR_NUM}.${MINOR_NUM}" "${MAJOR_NUM}"
  echo "__VERSIONS__"
} >>"$GITHUB_OUTPUT"
