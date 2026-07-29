#!/usr/bin/env bash
# Decide where mise keeps its installs for this job, then publish the choice to
# the rest of the job via GITHUB_ENV so every later `mise` call - including the
# prune step and whatever the caller runs - agrees with what was cached.
set -euo pipefail

if [ "${INPUT_GLOBAL:-false}" = "true" ]; then
  # Runner-wide dirs: every repo on this runner shares one set of tool versions.
  data_dir="$HOME/.local/share/mise"
  cache_dir="$HOME/.cache/mise"
  state_dir="$HOME/.local/state/mise"
  scope="global (runner-wide)"
else
  # RUNNER_WORKSPACE is the per-repository work dir (.../_work/<repo>), one level
  # above the checkout, so nothing lands in the git tree and nothing is shared
  # with another repo. RUNNER_TEMP is the fallback for runners that don't set it.
  base="${RUNNER_WORKSPACE:-${RUNNER_TEMP:-$HOME}}/.mise"
  data_dir="$base/data"
  cache_dir="$base/cache"
  state_dir="$base/state"
  scope="repository-local"
fi

{
  echo "MISE_DATA_DIR=$data_dir"
  echo "MISE_CACHE_DIR=$cache_dir"
  echo "MISE_STATE_DIR=$state_dir"
} >>"$GITHUB_ENV"

{
  echo "data-dir=$data_dir"
  echo "cache-dir=$cache_dir"
} >>"$GITHUB_OUTPUT"

echo "mise scope: $scope"
echo "  data:  $data_dir"
echo "  cache: $cache_dir"
