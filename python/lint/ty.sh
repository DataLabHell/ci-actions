#!/usr/bin/env bash
set -euo pipefail

# ty type-checking for python/lint. ruff runs separately via ruff-action; this
# script only handles ty, which has no official action. The action guards this
# step so it runs only when type-check is not "off". Word-splitting of the
# *_PATHS / *_ARGS vars is intentional (SC2086 disables below).
TYPE_CHECK="${INPUT_TYPE_CHECK:-warn}"
TYPE_CHECK_PATHS="${INPUT_TYPE_CHECK_PATHS:-.}"
SYNC_ARGS="${INPUT_SYNC_ARGS:-}"

# ty resolves imports against the project environment, so sync it first.
echo "::group::uv sync (for ty)"
# shellcheck disable=SC2086
uv sync $SYNC_ARGS
echo "::endgroup::"

echo "::group::ty check"
case "$TYPE_CHECK" in
  error)
    # shellcheck disable=SC2086
    uvx ty check $TYPE_CHECK_PATHS
    ;;
  warn)
    # shellcheck disable=SC2086
    uvx ty check $TYPE_CHECK_PATHS || echo "::warning::ty reported type issues (non-blocking; set type-check: error to fail the job)"
    ;;
  *)
    echo "::error::type-check must be one of: warn, error, off (got '$TYPE_CHECK')"
    exit 1
    ;;
esac
echo "::endgroup::"
