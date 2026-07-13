#!/usr/bin/env bash
set -euo pipefail

# Creates the new tag and force-moves the rolling major / major.minor aliases.
# NEW_TAG / MAJOR / MINOR come in as environment variables from action.yml.
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

git tag -a "$NEW_TAG" -m "$NEW_TAG"
git push origin "$NEW_TAG"

for ref in "$MAJOR" "$MINOR"; do
  echo "Moving $ref -> $NEW_TAG"
  git tag -f "$ref" "$NEW_TAG"
  git push origin "$ref" --force
done
