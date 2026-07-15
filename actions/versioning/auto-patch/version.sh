#!/usr/bin/env bash
set -euo pipefail

# Reads MAJOR.MINOR from a version file and auto-increments the patch from the
# existing tags, emitting version + tag. Inputs come in as INPUT_* env vars.
FILE="${INPUT_FILE:-VERSION}"
PREFIX="${INPUT_PREFIX:-v}"

if [ ! -f "$FILE" ]; then
  echo "::error::version file '$FILE' not found. Create it containing MAJOR.MINOR, e.g. 0.1"
  exit 1
fi

MM="$(tr -d ' \t\n\r' <"$FILE")" # e.g. 0.1
if ! [[ "$MM" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "::error::$FILE must be MAJOR.MINOR (e.g. 0.1); got '$MM'"
  exit 1
fi

# Highest existing patch for this major.minor series (-1 if none yet).
HIGHEST=-1
strip="${PREFIX}${MM}."
while read -r t; do
  [ -z "$t" ] && continue
  p="${t#"$strip"}"                  # strip "v0.1." -> patch
  [[ "$p" =~ ^[0-9]+$ ]] || continue # ignore pre-releases etc.
  if ((p > HIGHEST)); then
    HIGHEST="$p"
  fi
done < <(git tag -l "${PREFIX}${MM}.*")

PATCH=$((HIGHEST + 1))
NEW="${PREFIX}${MM}.${PATCH}"

echo "version=${MM}.${PATCH}" >>"$GITHUB_OUTPUT"
echo "tag=$NEW" >>"$GITHUB_OUTPUT"
echo "Next version: $NEW"
