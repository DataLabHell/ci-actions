#!/usr/bin/env bash
set -euo pipefail

# Action logic lives in this script (not inline in action.yml) so it can be
# linted by CI (shellcheck + shfmt). Inputs are passed in as INPUT_*
# environment variables by action.yml — read them here, never interpolate
# ${{ }} expressions into a run: command (injection-safe).
EXAMPLE="${INPUT_EXAMPLE:-}"

echo "example input was: '$EXAMPLE'"

# ... action logic here ...

echo "result=ok" >>"$GITHUB_OUTPUT"
