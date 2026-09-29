#!/usr/bin/env bash
set -euo pipefail

# Inputs arrive as INPUT_* env vars from action.yml. Installs the project with
# uv and runs pytest, optionally pinned to a Python version. Word-splitting of
# SYNC_ARGS / PYTEST_ARGS is intentional (SC2086 disables below).
PYTHON_VERSION="${INPUT_PYTHON_VERSION:-}"
SYNC_ARGS="${INPUT_SYNC_ARGS:-}"
PYTEST_ARGS="${INPUT_PYTEST_ARGS:-}"

# UV_LOCKED fails sync and run if uv.lock is out of date.
export UV_LOCKED=1

# Pin the Python version for both sync and run when one is given.
PY_FLAG=()
if [ -n "$PYTHON_VERSION" ]; then
  PY_FLAG=(--python "$PYTHON_VERSION")
fi

echo "::group::uv sync"
# shellcheck disable=SC2086
uv sync $SYNC_ARGS "${PY_FLAG[@]}"
echo "::endgroup::"

# shellcheck disable=SC2086
uv run "${PY_FLAG[@]}" pytest $PYTEST_ARGS
