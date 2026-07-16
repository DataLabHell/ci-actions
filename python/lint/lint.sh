#!/usr/bin/env bash
set -euo pipefail

# Inputs arrive as INPUT_* env vars from action.yml. Runs ruff (check + format)
# and optionally ty, all via uv. Word-splitting of the *_PATHS / *_ARGS vars is
# intentional (they hold multiple space-separated tokens), hence the SC2086
# disables below.
PATHS="${INPUT_PATHS:-.}"
TYPE_CHECK="${INPUT_TYPE_CHECK:-warn}"
TYPE_CHECK_PATHS="${INPUT_TYPE_CHECK_PATHS:-.}"
SYNC_ARGS="${INPUT_SYNC_ARGS:-}"

if ! command -v uv &>/dev/null; then
  echo "::error::uv not found on the runner. Install uv (https://docs.astral.sh/uv/), e.g. via the runner's Ansible setup."
  exit 1
fi

echo "::group::ruff check"
# shellcheck disable=SC2086
uvx ruff check $PATHS
echo "::endgroup::"

echo "::group::ruff format --check"
# shellcheck disable=SC2086
uvx ruff format --check $PATHS
echo "::endgroup::"

case "$TYPE_CHECK" in
off)
  echo "Type check disabled (type-check: off)."
  ;;
warn | error)
  # ty resolves imports against the project environment, so sync it first.
  echo "::group::uv sync (for ty)"
  # shellcheck disable=SC2086
  uv sync $SYNC_ARGS
  echo "::endgroup::"

  echo "::group::ty check"
  if [ "$TYPE_CHECK" = "error" ]; then
    # shellcheck disable=SC2086
    uvx ty check $TYPE_CHECK_PATHS
  else
    # shellcheck disable=SC2086
    uvx ty check $TYPE_CHECK_PATHS || echo "::warning::ty reported type issues (non-blocking; set type-check: error to fail the job)"
  fi
  echo "::endgroup::"
  ;;
*)
  echo "::error::type-check must be one of: warn, error, off (got '$TYPE_CHECK')"
  exit 1
  ;;
esac
