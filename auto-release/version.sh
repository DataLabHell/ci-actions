#!/usr/bin/env bash
set -euo pipefail

# Reads MAJOR.MINOR from the version file and derives the next patch from the
# existing tags. Emits version/new_tag/major/minor as step outputs.
# INPUT_VERSION_FILE comes in as an environment variable from action.yml.
VERSION_FILE="${INPUT_VERSION_FILE:-VERSION}"

if [ ! -f "$VERSION_FILE" ]; then
  echo "::error::version file '$VERSION_FILE' not found. Create it containing MAJOR.MINOR, e.g. 0.1"
  exit 1
fi

MM="$(tr -d ' \t\n\r' <"$VERSION_FILE")" # e.g. 0.1
if ! [[ "$MM" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "::error::$VERSION_FILE must be MAJOR.MINOR (e.g. 0.1); got '$MM'"
  exit 1
fi
MAJOR="${MM%%.*}"

# Highest existing patch for this major.minor series (-1 if none yet).
HIGHEST=-1
prefix="v${MM}."
while read -r t; do
  [ -z "$t" ] && continue
  p="${t#"$prefix"}"                 # strip "v0.1." -> patch
  [[ "$p" =~ ^[0-9]+$ ]] || continue # ignore pre-releases etc.
  if ((p > HIGHEST)); then
    HIGHEST="$p"
  fi
done < <(git tag -l "v${MM}.*")

PATCH=$((HIGHEST + 1))
NEW="v${MM}.${PATCH}"

{
  echo "version=${MM}.${PATCH}"
  echo "new_tag=$NEW"
  echo "major=v${MAJOR}"
  echo "minor=v${MM}"
} >>"$GITHUB_OUTPUT"
echo "Next version: $NEW"
