#!/usr/bin/env bash
#
# Preview or apply dependency updates via renovate's read-only `local` platform.
# Renovate resolves the versions; this script reports them and, in `apply` mode,
# writes the new versions back into the manifests. Never opens PRs (CI does that).
#
#   (no arg)  list pending bumps with their renovate.json automerge verdict
#   check     exit 1 when any updates are available - for CI gating
#   apply [--force]
#             rewrite the version pins in place. Without --force only updates
#             renovate.json would automerge (verdict "auto") are applied; --force
#             also applies the "manual"/"default" ones, including major bumps.
#
# The verdict is derived from renovate.json: each automerging packageRule carries
# a groupName, matched by slug against the branch group renovate assigned each
# update. Ungrouped updates show "default".
#
# Requires: renovate, jq, perl. Set RENOVATE_REPORT to replay an existing report
# instead of running renovate.
#
# Exit codes: 1 = `check` found updates, 2 = renovate extracted nothing,
# 3 = a dep's replacement template uses a helper this script cannot render.
#
set -euo pipefail

mode=""
force=false
for arg in "$@"; do
  case "$arg" in
    --force) force=true ;;
    *) mode=$arg ;;
  esac
done

# mise [env] sets OTEL_EXPORTER_OTLP_ENDPOINT; renovate exports to it on exit
# and spams ECONNREFUSED. It triggers on the var's presence, so unset it.
unset OTEL_EXPORTER_OTLP_ENDPOINT

# Pad tab-separated columns to a common width. `column -t` would do this but is
# absent on some machines and aligns differently between BSD and GNU.
align() {
  awk -F'\t' '
    {
      for (i = 1; i <= NF; i++) {
        cell[NR, i] = $i
        if (length($i) > width[i]) width[i] = length($i)
      }
      if (NF > cols) cols = NF
    }
    END {
      for (r = 1; r <= NR; r++) {
        line = ""
        for (i = 1; i <= cols; i++) line = line sprintf("%-" width[i] "s ", cell[r, i])
        sub(/ +$/, "", line)
        print line
      }
    }
  '
}

if [ -n "${RENOVATE_REPORT:-}" ]; then
  report=$RENOVATE_REPORT
else
  report=$(mktemp)
  trap 'rm -f "$report"' EXIT
  echo "Fetching report..."
  renovate --platform=local --report-type=file --report-path="$report" >/dev/null 2>&1
fi

if [ ! -s "$report" ] || [ "$(jq -r '.repositories.local.packageFiles | length // 0' "$report" 2>/dev/null)" = 0 ]; then
  echo "renovate extracted no dependencies (network/rate-limit? check GITHUB_COM_TOKEN)" >&2
  exit 2
fi

# slug(groupName) -> verdict, read from renovate.json's own automerge flags
groupmap=$(jq -c '
  def slug: ascii_downcase | gsub("[^a-z0-9]+"; "-") | gsub("(^-|-$)"; "");
  [ .packageRules[]? | select(.groupName)
    | {(.groupName | slug): (if (.automerge // false) then "auto" else "manual" end)} ]
  | add // {}
' renovate.json)

# One row per dep and verdict, carrying the highest target of that verdict:
# separateMinorPatch reports a patch and a minor entry for the same dep, and
# `apply` takes the highest it is allowed to, so listing both would not say
# which one it picks.
rows=$(jq -r --argjson gm "$groupmap" '
  def slug: ascii_downcase | gsub("[^a-z0-9]+"; "-") | gsub("(^-|-$)"; "");
  def ver: [splits("[^0-9]+")] | map(select(length > 0) | tonumber);
  [ (.repositories.local.packageFiles // {})
    | to_entries[] | .key as $mgr
    | .value[]? | .packageFile as $f | (.deps // [])[]
    | select(.updates? and (.updates | length > 0))
    | .depName as $n | (.currentValue // .currentVersion // "?") as $cur
    | .updates[]
    # branch group renovate assigned, minus renovate/ + patch-/minor-/major- prefix
    | ((.branchName // "") | ltrimstr("renovate/") | sub("^(patch|minor|major)-"; "") | slug) as $grp
    | {f: $f, mgr: $mgr, verdict: ($gm[$grp] // "default"), dep: $n, cur: $cur,
       new: (.newVersion // .newValue // "-"), type: (.updateType // "")}
  ]
  | group_by([.f, .dep, .cur, .verdict])
  | map(max_by(.new | ver))
  | .[] | [.mgr, .verdict, .dep, .cur, "->", .new, .type] | @tsv
' "$report" | sort -u | sort -t$'\t' -k1,1 -k2,2 -k3,3 -k6,6 | align)

if [ -z "$rows" ]; then
  echo "All dependencies up to date."
  exit 0
fi

echo "Scheduled updates:"
echo "$rows"

if [ "$mode" = apply ]; then
  # Applies updates whose verdict is "auto" (what renovate.json would automerge);
  # --force also applies "manual"/"default" ones, including major bumps. Run the
  # repo's own install/lock refresh afterwards (mise install, cargo update, uv
  # sync, dbt deps).
  #
  # Each row carries a swap method matched to what renovate reported for the dep.
  # perl \Q..\E quotes every version metacharacter (dots, `+`) and every value
  # arrives through the environment, so no manifest string is read as a pattern:
  #   tpl  renovate supplied both the exact old substring (replaceString) and the
  #        template for the new one (autoReplaceStringTemplate). Rendering that
  #        template is what produces `owner/repo@<sha> # <tag>` for actions and
  #        `name:tag@sha256:...` for images, including pinning a floating ref.
  #   lit  literal swap, for a custom manager's replaceString (no template) or a
  #        bare version file. Base64'd to survive multi-line replaceStrings.
  #   key  key-anchored - swap the version on the `<dep> =` line, keeping any
  #        flavor prefix (e.g. temurin-) that lives outside the reported value.
  #   pep  swap `<dep>[extras]<op><ver>` - the dep+operator anchor disambiguates
  #        deps that share a version (sqlfluff vs sqlfluff-templater-dbt).
  #   chan rust-toolchain.toml, where the key (`channel`) is not the dep name, so
  #        the swap anchors on that key rather than on the version alone.
  echo
  echo "Applying ($([ "$force" = true ] && echo 'auto + manual, --force' || echo 'auto only')):"
  jq -r --argjson gm "$groupmap" --argjson force "$force" '
    def slug: ascii_downcase | gsub("[^a-z0-9]+"; "-") | gsub("(^-|-$)"; "");
    def ver: [splits("[^0-9]+")] | map(select(length > 0) | tonumber);
    [ (.repositories.local.packageFiles // {})
      | to_entries[] | .key as $mgr | .value[]?
      | .packageFile as $f | (.deps // [])[]
      | .depName as $dep | (.currentValue // .currentVersion) as $cur
      | (.replaceString // null) as $rs
      | (.autoReplaceStringTemplate // null) as $tpl
      | .currentDigest as $curdig
      | .updates[]?
      | (.newVersion // .newValue) as $new
      | (.newDigest // null) as $newdig
      | ((.branchName // "") | ltrimstr("renovate/") | sub("^(patch|minor|major)-"; "") | slug) as $grp
      | select($force or (($gm[$grp] // "default") == "auto"))
      # a digest-pinned dep with no new digest has nothing to rewrite
      | select($curdig == null or $newdig != null)
      # unused fields padded with "-": read collapses empty tab-delimited fields
      | (if $rs != null and $tpl != null then
           {method: "tpl", f1: ($rs | @base64), f2: ($tpl | @base64), f3: $dep,
            f4: ($new // "-"), f5: ($newdig // "-")}
         elif $rs != null then
           # Version and digest move independently, so each is swapped only when
           # renovate reported a new one. The null guards are load-bearing:
           # split(null) raises, which under set -e kills the whole run.
           {method: "lit", f1: ($rs | @base64),
            f2: (($rs
                  | if $new != null and $cur != null then split($cur) | join($new) else . end
                  | if $curdig != null then split($curdig) | join($newdig) else . end)
                 | @base64),
            f3: "-", f4: "-", f5: "-"}
         elif $mgr == "mise" or $mgr == "cargo" then
           {method: "key", f1: $dep, f2: $cur, f3: $new, f4: "-", f5: "-"}
         elif $mgr == "pep621" then
           ($cur | capture("^(?<op>[^0-9]*)(?<v>.*)$")) as $p
           | {method: "pep", f1: $dep, f2: $p.op, f3: $p.v, f4: $new, f5: "-"}
         elif $mgr == "rust-toolchain" then
           {method: "chan", f1: $cur, f2: $new, f3: "-", f4: "-", f5: "-"}
         else
           {method: "lit", f1: ($cur | @base64), f2: ($new | @base64),
            f3: "-", f4: "-", f5: "-"}
         end) + {f: $f, dep: $dep, cur: ($cur // "-"), new: ($new // "-")}
      # a swap that reproduces its own input has nothing to report
      | select(.method != "lit" or .f1 != .f2)
    ]
    # separateMinorPatch emits patch+minor per dep; the current version is part
    # of the key because one file can hold two pins of the same dep
    | group_by([.f, .dep, .cur])
    | map(max_by(.new | ver))       # keep the highest applicable target
    | .[] | [.method, .f, .f1, .f2, .f3, .f4, .f5, .dep, .cur, .new] | @tsv
  ' "$report" | while IFS=$'\t' read -r method file f1 f2 f3 f4 f5 dep cur new; do
    [ -f "$file" ] || continue
    case "$method" in
      tpl)
        # Render the handlebars subset these templates use ({{var}}, {{#if}},
        # {{#unless}}), innermost block first, then swap the old substring for the
        # result. An unrendered {{ means an unsupported helper: fail, never write.
        old=$(printf '%s' "$f1" | base64 -d)
        tpl=$(printf '%s' "$f2" | base64 -d)
        TPL="$tpl" DEP="$f3" NEWVAL="$f4" NEWDIG="$f5" OLD="$old" perl -0777 -i -pe '
          BEGIN {
            my %v = (depName => $ENV{DEP}, newValue => $ENV{NEWVAL}, newDigest => $ENV{NEWDIG});
            $v{$_} = "" for grep { $v{$_} eq "-" } keys %v;
            our $new = $ENV{TPL};
            1 while $new =~ s/\{\{#if\s+(\w+)\}\}((?:(?!\{\{#).)*?)\{\{\/if\}\}/$v{$1} ne "" ? $2 : ""/gse;
            1 while $new =~ s/\{\{#unless\s+(\w+)\}\}((?:(?!\{\{#).)*?)\{\{\/unless\}\}/$v{$1} eq "" ? $2 : ""/gse;
            $new =~ s/\{\{(\w+)\}\}/$v{$1}/g;
            die "unsupported template: $ENV{TPL}\n" if $new =~ /\{\{/;
            our $old = $ENV{OLD};
          }
          s/\Q$old\E/$new/g;
        ' "$file" || exit 3
        ;;
      lit)
        old=$(printf '%s' "$f1" | base64 -d)
        rep=$(printf '%s' "$f2" | base64 -d)
        OLD="$old" NEW="$rep" perl -0777 -i -pe 's/\Q$ENV{OLD}\E/$ENV{NEW}/g' "$file"
        ;;
      key)
        KEY="$f1" OLD="$f2" NEW="$f3" perl -i -pe \
          's/(^\s*"?\Q$ENV{KEY}\E"?\s*=\s*"[^"]*?)\Q$ENV{OLD}\E/$1$ENV{NEW}/' "$file"
        ;;
      pep)
        DEP="$f1" OP="$f2" OLD="$f3" NEW="$f4" perl -i -pe \
          's/(?<![\w.-])(\Q$ENV{DEP}\E(?:\[[^\]]*\])?\Q$ENV{OP}\E)\Q$ENV{OLD}\E/$1$ENV{NEW}/' "$file"
        ;;
      chan)
        OLD="$f1" NEW="$f2" perl -i -pe \
          's/(^\s*channel\s*=\s*")\Q$ENV{OLD}\E(")/$1$ENV{NEW}$2/' "$file"
        ;;
    esac
    echo "  $file: $dep $cur -> $new"

    # Cargo.toml's workspace rust-version tracks the toolchain but is deduped out
    # of the local report, so it is synced here off the same bump.
    if [ "$method" = chan ] && [ -f Cargo.toml ] &&
      grep -qE "^[[:space:]]*rust-version[[:space:]]*=[[:space:]]*\"${cur//./\\.}\"" Cargo.toml; then
      OLD="$cur" NEW="$new" perl -i -pe \
        's/(^\s*rust-version\s*=\s*")\Q$ENV{OLD}\E(")/$1$ENV{NEW}$2/' Cargo.toml
      echo "  Cargo.toml: rust-version $cur -> $new"
    fi
  done
  exit 0
fi

if [ "$mode" = check ]; then
  exit 1
fi
