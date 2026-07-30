#!/usr/bin/env bash
#
# Fixture tests for local-renovate.sh. Each case feeds a canned renovate report
# through the RENOVATE_REPORT seam, so no network and no renovate binary needed.
#
# cases/<name>/
#   renovate.json       the automerge verdicts the script reads from the cwd
#   report.json         the renovate report to replay
#   args                optional argv, one line (default: "apply")
#   in/                 manifests before
#   expected/           manifests after (compared with diff -r)
#   expected-list.txt   optional stdout of list mode (no argv)
#   expect-exit         optional expected exit status (default: 0)
#
set -euo pipefail

tests_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
script=$tests_dir/../local-renovate.sh
cases_dir=$tests_dir/cases

pass=0
fail=0

fail_case() {
  # $1 case name, $2 what went wrong, rest: detail lines
  local name=$1 reason=$2
  shift 2
  echo "FAIL $name: $reason"
  local line
  for line in "$@"; do echo "    $line"; done
  fail=$((fail + 1))
}

run_case() {
  local dir=$1
  local name
  name=$(basename "$dir")

  local args=apply
  [ -f "$dir/args" ] && args=$(cat "$dir/args")
  local want_exit=0
  [ -f "$dir/expect-exit" ] && want_exit=$(cat "$dir/expect-exit")

  local work
  work=$(mktemp -d)
  # shellcheck disable=SC2064 # expand $work now, it is gone by trap time otherwise
  trap "rm -rf '$work'" RETURN

  cp -R "$dir/in/." "$work/"
  cp "$dir/renovate.json" "$work/renovate.json"

  # stdout is the contract; stderr is kept aside because tooling in the work dir
  # can add warnings of its own (mise resolving a fixture's fake tool name).
  local out status=0
  local errlog=$work.stderr
  # shellcheck disable=SC2086 # $args is intentionally word-split into argv
  out=$(cd "$work" && RENOVATE_REPORT="$dir/report.json" "$script" $args 2>"$errlog") || status=$?

  if [ "$status" != "$want_exit" ]; then
    fail_case "$name" "exit $status, want $want_exit" "$out" "$(cat "$errlog")"
    rm -f "$errlog"
    return
  fi
  rm -f "$errlog"

  if [ -f "$dir/expected-list.txt" ]; then
    local want_list
    want_list=$(cat "$dir/expected-list.txt")
    if [ "$out" != "$want_list" ]; then
      fail_case "$name" "output mismatch" "$(diff <(echo "$want_list") <(echo "$out") || true)"
      return
    fi
  fi

  if [ -d "$dir/expected" ]; then
    rm -f "$work/renovate.json"
    local d
    if ! d=$(diff -r "$dir/expected" "$work" 2>&1); then
      fail_case "$name" "manifests differ (expected vs actual)" "$d"
      return
    fi
  fi

  echo "ok   $name"
  pass=$((pass + 1))
}

if [ ! -d "$cases_dir" ]; then
  echo "no cases directory at $cases_dir" >&2
  exit 1
fi

for dir in "$cases_dir"/*/; do
  [ -d "$dir" ] || continue
  run_case "${dir%/}"
done

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
