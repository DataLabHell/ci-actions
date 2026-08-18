#!/usr/bin/env bash
set -euo pipefail

# Inputs are passed in as INPUT_* environment variables by action.yml.
PROFILE="${INPUT_PROFILE:-}"
ACCESS_KEY_ID="${INPUT_ACCESS_KEY_ID:-}"
SECRET_ACCESS_KEY="${INPUT_SECRET_ACCESS_KEY:-}"
SESSION_TOKEN="${INPUT_SESSION_TOKEN:-}"
ENDPOINT_URL="${INPUT_ENDPOINT_URL:-}"
REGION="${INPUT_REGION:-}"
BUCKET="${INPUT_BUCKET:-}"
SOURCE="${INPUT_SOURCE:-}"
DEST_PREFIX="${INPUT_DESTINATION:-}"
INCLUDE="${INPUT_INCLUDE:-}"
EXCLUDE="${INPUT_EXCLUDE:-}"
DELETE_REMOVED="${INPUT_DELETE_REMOVED:-false}"

# The AWS CLI must already be on the runner; we never install at CI time.
if ! command -v aws &>/dev/null; then
  echo "::error::aws CLI not found on this runner. Install AWS CLI v2 (see https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)"
  exit 1
fi
aws --version

# Explicit keys win, then a named runner profile. With neither, the CLI falls
# back to its own chain. We never write to the AWS config.
AWS_ARGS=()
if [ -n "$ACCESS_KEY_ID" ] || [ -n "$SECRET_ACCESS_KEY" ]; then
  if [ -z "$ACCESS_KEY_ID" ] || [ -z "$SECRET_ACCESS_KEY" ]; then
    echo "::error::'access-key-id' and 'secret-access-key' must be given together."
    exit 1
  fi
  # Exported, not passed as flags, to keep them out of the process list.
  export AWS_ACCESS_KEY_ID="$ACCESS_KEY_ID"
  export AWS_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY"
  if [ -n "$SESSION_TOKEN" ]; then
    export AWS_SESSION_TOKEN="$SESSION_TOKEN"
  fi
  echo "Authenticating with credentials passed to the action"
elif [ -z "$PROFILE" ]; then
  # The CLI finds its own credentials. Passing --profile would override them.
  echo "Authenticating with the ambient AWS environment"
else
  # Fail fast when the profile isn't on the runner, rather than with a
  # confusing error deep inside 'aws s3 sync'.
  if ! aws configure list-profiles 2>/dev/null | grep -qx "$PROFILE"; then
    echo "::error::AWS profile '$PROFILE' not found on this runner. Configure it in ~/.aws (config + credentials), pass 'access-key-id' and 'secret-access-key', or drop the 'profile' input to let the AWS CLI resolve credentials itself."
    exit 1
  fi
  AWS_ARGS+=(--profile "$PROFILE")
  echo "Authenticating with runner profile '$PROFILE'"
fi

# Applied in both modes; with a profile these override what it configures.
if [ -n "$ENDPOINT_URL" ]; then
  AWS_ARGS+=(--endpoint-url "$ENDPOINT_URL")
fi
if [ -n "$REGION" ]; then
  AWS_ARGS+=(--region "$REGION")
fi

DEST="s3://${BUCKET}"
if [ -n "$DEST_PREFIX" ]; then
  DEST="$DEST/${DEST_PREFIX#/}"
fi

if [ ! -d "$SOURCE" ]; then
  echo "::error::source folder '$SOURCE' does not exist"
  exit 1
fi

# Filters apply in order: exclude everything, re-include the requested
# patterns, then layer explicit excludes on top.
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
  # --delete at the bucket root would wipe other pipelines' files.
  if [ -z "$DEST_PREFIX" ]; then
    echo "::error::delete-removed=true requires a non-empty 'destination' prefix; refusing to run --delete against the bucket root '$DEST'"
    exit 1
  fi
  DELETE_ARGS+=(--delete)
fi

echo "Uploading '$SOURCE' -> '$DEST'"
aws s3 sync "$SOURCE" "$DEST" \
  "${AWS_ARGS[@]}" \
  "${FILTER_ARGS[@]}" \
  "${DELETE_ARGS[@]}"

echo "s3-path=$DEST" >>"$GITHUB_OUTPUT"
