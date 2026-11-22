#!/usr/bin/env bash
# Check that Composition release labels stay honest (ADR 0010, ADR 0009).
# Usage: scripts/check-composition-release.sh <base-ref>   (run from the repo root)
#
# Claims pin a Composition by its `release` label with compositionUpdatePolicy
# Automatic. If someone changes a Composition and keeps the same label, every
# claim pinned to that label rolls to the new content with no PR on its folder.
# This check stops that. It compares the merge-base of <base-ref> and HEAD
# against HEAD, and runs two checks.
#
# 1. Each Composition under definitions/ that the PR added, changed or renamed:
#    - It must have a release label in strict semver (1.2.3).
#    - If its content changed (comments, formatting and the label itself do not
#      count), the label must be higher than on the base. A Composition that had
#      no label on the base may take any valid label as its first one.
#    - The label can never go down, even with no content change.
#    - Its metadata.name must not change. A rename deletes its revisions.
#
# 2. Each claim in infra-requests/ and app-requests/ (tracked files only) that
#    pins a release:
#    - A Composition for its kind must exist.
#    - That Composition must have had the pinned release at some point in its
#      history. A pin to a release that never existed matches no revision.
#      Pinning back to an older release is fine.
#
# It prints one ok or FAIL line per item and exits 1 if any item failed. It
# cannot judge whether the bump is the right size (major, minor or patch). The
# reviewer does that.
# Needs: git, yq (mikefarah v4), jq. Works on macOS bash 3.2 and Linux bash 5.
set -euo pipefail

base="${1:-}"
if [ -z "$base" ]; then
  echo "usage: $0 <base-ref>" >&2
  exit 2
fi
if ! mb="$(git merge-base "$base" HEAD)"; then
  echo "cannot find a merge-base of $base and HEAD: fetch the base branch first (fetch-depth: 0 in CI)" >&2
  exit 2
fi

SEMVER='^[0-9]+\.[0-9]+\.[0-9]+$'
failed=0
checked=0

# report <ok|FAIL> <path> <message>
report() {
  if [ "$1" = "ok" ]; then
    echo "ok: $3"
  else
    failed=1
    echo "FAIL: $3"
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
      echo "::error file=$2::$3"
    fi
  fi
}

# Read from git at a revision: show <rev> <path>
show() { git show "$1:$2"; }

# release_of <rev> <path>: the release label, or empty if none.
release_of() {
  show "$1" "$2" 2>/dev/null | yq -r '.metadata.labels.release // ""' 2>/dev/null | sed -n 1p || true
}

# normalized <rev> <path>: content without the release label, as sorted compact JSON.
normalized() {
  show "$1" "$2" | yq -o=json '.' | jq -S -c 'del(.metadata.labels.release) | if .metadata.labels == {} then del(.metadata.labels) else . end'
}

# semver_gt A B: true if A is strictly higher than B (numeric compare).
semver_gt() {
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<EOT
$1
EOT
  IFS=. read -r b1 b2 b3 <<EOT
$2
EOT
  [ "$a1" -ne "$b1" ] && { [ "$a1" -gt "$b1" ]; return; }
  [ "$a2" -ne "$b2" ] && { [ "$a2" -gt "$b2" ]; return; }
  [ "$a3" -gt "$b3" ]
}

# --- 1. changed Compositions --------------------------------------------------

changes="$(git diff --name-status -M --diff-filter=AMR "$mb" HEAD -- definitions/)"
while IFS="$(printf '\t')" read -r status p1 p2; do
  [ -n "${status:-}" ] || continue
  old="$p1"; new="$p1"
  case "$status" in R*) new="$p2" ;; esac
  case "$new" in *.yaml|*.yml) ;; *) continue ;; esac
  kind="$(show HEAD "$new" | yq -r '.kind // ""' | sed -n 1p)"
  [ "$kind" = "Composition" ] || continue
  checked=$((checked + 1))

  head_rel="$(release_of HEAD "$new")"
  if ! printf '%s' "$head_rel" | grep -Eq "$SEMVER"; then
    if [ -z "$head_rel" ]; then
      report FAIL "$new" "$new has no release label: add metadata.labels.release with a semver such as \"0.1.0\" (ADR 0010)"
    else
      report FAIL "$new" "$new has release \"$head_rel\", which is not semver: use three numbers such as \"0.1.0\" (ADR 0010)"
    fi
    continue
  fi

  # Did the file exist on the base? (A rename counts as existing under its old path.)
  if ! git cat-file -e "$mb:$old" 2>/dev/null; then
    report ok "$new" "$new is new with release $head_rel"
    continue
  fi
  # A new name is a new Composition. The old one, and every revision it owns,
  # would be deleted, and claims pinned to its releases would match nothing.
  base_name="$(show "$mb" "$old" | yq -r '.metadata.name // ""' | sed -n 1p)"
  head_name="$(show HEAD "$new" | yq -r '.metadata.name // ""' | sed -n 1p)"
  if [ "$base_name" != "$head_name" ]; then
    report FAIL "$new" "$new renames the Composition ($base_name -> $head_name): that deletes its revisions; keep the name, or add a new Composition next to it"
    continue
  fi
  base_rel="$(release_of "$mb" "$old")"
  # A label change alone also makes a new revision. A lower label would then
  # match an older release's claims, so it fails even with no content change.
  if [ -n "$base_rel" ] && [ "$head_rel" != "$base_rel" ] && ! semver_gt "$head_rel" "$base_rel"; then
    report FAIL "$new" "$new release went down ($base_rel -> $head_rel): a new release must be higher than the old one (ADR 0010)"
    continue
  fi
  if [ "$(normalized "$mb" "$old")" = "$(normalized HEAD "$new")" ]; then
    report ok "$new" "$new has no content change (release ${base_rel:-none} -> $head_rel)"
    continue
  fi
  if [ -z "$base_rel" ]; then
    report ok "$new" "$new changed and now has its first release label, $head_rel"
  elif [ "$head_rel" = "$base_rel" ]; then
    report FAIL "$new" "$new changed but release is still $base_rel: bump it (ADR 0010)"
  else
    report ok "$new" "$new changed and release went $base_rel -> $head_rel"
  fi
done <<EOT
$changes
EOT

# --- 2. claims pin a release that exists --------------------------------------

# Index of Compositions at HEAD: one "<compositeTypeRef kind><TAB><path>" line each.
comp_index=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in *.yaml|*.yml) ;; *) continue ;; esac
  kind="$(show HEAD "$f" | yq -r '.kind // ""' | sed -n 1p)"
  [ "$kind" = "Composition" ] || continue
  ckind="$(show HEAD "$f" | yq -r '.spec.compositeTypeRef.kind // ""' | sed -n 1p)"
  comp_index="$comp_index$ckind	$f
"
done <<EOT
$(git ls-files definitions/)
EOT

# releases_ever <path>: every release label the file has had, one per line.
releases_ever() {
  local sha
  release_of HEAD "$1"
  for sha in $(git log --format=%H -- "$1"); do
    release_of "$sha" "$1"
  done
}

while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in *.yaml|*.yml) ;; *) continue ;; esac
  pins="$(show HEAD "$f" | yq -r 'select(.spec.crossplane.compositionRevisionSelector.matchLabels.release != null) | [(.kind // "none"), .spec.crossplane.compositionRevisionSelector.matchLabels.release] | @tsv')"
  while IFS="$(printf '\t')" read -r ckind pin; do
    [ -n "${pin:-}" ] || continue
    checked=$((checked + 1))
    comp="$(printf '%s' "$comp_index" | awk -F '\t' -v k="$ckind" '$1 == k { print $2; exit }')"
    if [ -z "$comp" ]; then
      report FAIL "$f" "$f pins release $pin for kind $ckind, but no Composition under definitions/ serves that kind: fix the kind or add the Composition"
      continue
    fi
    # Collect first: grep -q stops at the first match and would break the pipe.
    ever="$(releases_ever "$comp")"
    if printf '%s\n' "$ever" | grep -Fxq -- "$pin"; then
      report ok "$f" "$f pins release $pin of $comp, which exists"
    else
      report FAIL "$f" "$f pins release $pin, but $comp never had that release: pin a release it has had, or release it first (ADR 0009)"
    fi
  done <<EOT
$pins
EOT
done <<EOT
$(git ls-files infra-requests app-requests)
EOT

if [ "$checked" -eq 0 ]; then
  echo "ok: no Composition changes and no pinned claims to check"
fi
exit "$failed"
