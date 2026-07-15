#!/usr/bin/env bash
set -euo pipefail

# Creates TAG and force-moves the rolling major / major.minor aliases derived
# from it. TAG comes in as an environment variable from action.yml.
if ! [[ "$TAG" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "::error::tag '$TAG' is not of the form vMAJOR.MINOR.PATCH"
  exit 1
fi
MAJOR="v${BASH_REMATCH[1]}"
MINOR="v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

git tag -a "$TAG" -m "$TAG"
git push origin "$TAG"

for ref in "$MAJOR" "$MINOR"; do
  echo "Moving $ref -> $TAG"
  git tag -f "$ref" "$TAG"
  git push origin "$ref" --force
done
