#!/usr/bin/env bash
set -euo pipefail

# Reads [project].version from a pyproject.toml (uv / PEP 621) and emits it as
# version + a prefixed tag. Inputs come in as INPUT_* env vars from action.yml.
FILE="${INPUT_FILE:-pyproject.toml}"
PREFIX="${INPUT_PREFIX:-v}"

if [ ! -f "$FILE" ]; then
  echo "::error::pyproject file '$FILE' not found"
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "::error::python3 not found on the runner (needed to parse '$FILE')"
  exit 1
fi

# tomllib ships with Python 3.11+ (uv projects run modern Python). Returns the
# static [project].version, or empty if it's missing/dynamic.
if ! version="$(python3 -c '
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    print(tomllib.load(f).get("project", {}).get("version", ""))
' "$FILE")"; then
  echo "::error::failed to parse '$FILE' (needs Python 3.11+ with tomllib)"
  exit 1
fi

if [ -z "$version" ]; then
  echo "::error::no static [project].version in '$FILE' (is the version dynamic?)"
  exit 1
fi

echo "version=$version" >>"$GITHUB_OUTPUT"
echo "tag=${PREFIX}${version}" >>"$GITHUB_OUTPUT"
echo "Resolved version: ${PREFIX}${version}"
