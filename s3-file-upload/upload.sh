#!/usr/bin/env bash
set -euo pipefail

# Inputs are passed in as INPUT_* environment variables by action.yml.
PROFILE="${INPUT_PROFILE:-}"
BUCKET="${INPUT_BUCKET:-}"
SOURCE="${INPUT_SOURCE:-}"
DEST_PREFIX="${INPUT_DESTINATION:-}"
INCLUDE="${INPUT_INCLUDE:-}"
EXCLUDE="${INPUT_EXCLUDE:-}"
DELETE_REMOVED="${INPUT_DELETE_REMOVED:-false}"

# The AWS CLI must already be on the runner (we never install at CI time).
if ! command -v aws &>/dev/null; then
  echo "::error::aws CLI not found on this runner. Install AWS CLI v2 (see https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)"
  exit 1
fi
aws --version

# All connection settings (endpoint, region) and credentials come from this AWS
# profile, configured on the runner in ~/.aws/config and ~/.aws/credentials. We
# don't touch the AWS config, so its settings apply as-is.
if [ -z "$PROFILE" ]; then
  echo "::error::'profile' is required. Configure an AWS profile on the runner (endpoint, region, credentials) and pass its name."
  exit 1
fi

# The profile must actually exist on this runner. If it doesn't, this is almost
# always a job running on a GitHub-hosted runner (e.g. self-hosted) instead of
# a self-hosted one where ~/.aws is set up. Fail fast with a clear cause rather
# than a confusing credentials error deep inside 'aws s3 sync'.
if ! aws configure list-profiles 2>/dev/null | grep -qx "$PROFILE"; then
  echo "::error::AWS profile '$PROFILE' not found on this runner. s3-file-upload must run on a self-hosted runner where the profile is configured in ~/.aws (config + credentials)."
  exit 1
fi

DEST="s3://${BUCKET}"
if [ -n "$DEST_PREFIX" ]; then
  DEST="$DEST/${DEST_PREFIX#/}"
fi

if [ ! -d "$SOURCE" ]; then
  echo "::error::source folder '$SOURCE' does not exist"
  exit 1
fi

# Build include/exclude filters. AWS CLI applies filters in the given order, so
# exclude everything first, re-include the requested patterns, then apply any
# explicit excludes on top.
FILTER_ARGS=(--exclude "*")
IFS=',' read -ra INCLUDES <<<"$INCLUDE"
for pattern in "${INCLUDES[@]}"; do
  pattern="$(echo "$pattern" | xargs)"
  [ -n "$pattern" ] && FILTER_ARGS+=(--include "$pattern")
done
if [ -n "$EXCLUDE" ]; then
  IFS=',' read -ra EXCLUDES <<<"$EXCLUDE"
  for pattern in "${EXCLUDES[@]}"; do
    pattern="$(echo "$pattern" | xargs)"
    [ -n "$pattern" ] && FILTER_ARGS+=(--exclude "$pattern")
  done
fi

DELETE_ARGS=()
if [ "$DELETE_REMOVED" = "true" ]; then
  # --delete against a bare bucket root would mirror-delete every other
  # pipeline's files in this (shared) bucket. Require a destination prefix.
  if [ -z "$DEST_PREFIX" ]; then
    echo "::error::delete-removed=true requires a non-empty 'destination' prefix; refusing to run --delete against the bucket root '$DEST'"
    exit 1
  fi
  DELETE_ARGS+=(--delete)
fi

echo "Uploading '$SOURCE' -> '$DEST'"
aws s3 sync "$SOURCE" "$DEST" \
  --profile "$PROFILE" \
  "${FILTER_ARGS[@]}" \
  "${DELETE_ARGS[@]}"

echo "s3-path=$DEST" >>"$GITHUB_OUTPUT"
