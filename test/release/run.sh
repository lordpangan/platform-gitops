#!/usr/bin/env bash
# Test harness for scripts/check-composition-release.sh. No Docker, no cluster.
# Each case builds a throwaway git repo with a tiny Composition and claim,
# commits a base on `main`, makes one change on a branch, and runs the check.
# The case says whether the check should pass (exit 0) or fail (exit 1).
# Needs: git, yq (mikefarah v4), jq. Run it with `make test-release`.
set -euo pipefail

CHECK="$(cd "$(dirname "$0")/../.." && pwd)/scripts/check-composition-release.sh"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass=0
bad=0

# --- fixtures ------------------------------------------------------------------

# write_comp <path> <release or ""> <replicas>
write_comp() {
  mkdir -p "$(dirname "$1")"
  {
    echo "# a comment"
    echo "apiVersion: apiextensions.crossplane.io/v1"
    echo "kind: Composition"
    echo "metadata:"
    echo "  name: xnetwork"
    if [ -n "$2" ]; then
      echo "  labels:"
      echo "    release: \"$2\""
    fi
    echo "spec:"
    echo "  compositeTypeRef:"
    echo "    apiVersion: platform.meridian.io/v1alpha1"
    echo "    kind: XNetwork"
    echo "  size: $3"
  } > "$1"
}

# write_claim <path> <release>
write_claim() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOT
apiVersion: platform.meridian.io/v1alpha1
kind: XNetwork
metadata:
  name: prd-vpc
spec:
  crossplane:
    compositionUpdatePolicy: Automatic
    compositionRevisionSelector:
      matchLabels:
        release: "$2"
EOT
}

# new_repo: a repo in $TMPROOT with a base on main. History: release 0.1.0, then 0.1.1.
# Also holds an unlabeled Composition (definitions/eks) and a claim pinned to 0.1.1.
new_repo() {
  repo="$(mktemp -d "$TMPROOT/case.XXXXXX")"
  cd "$repo"
  git init -q -b main
  git config user.name "test"
  git config user.email "test@example.com"
  write_comp definitions/network/composition.yaml 0.1.0 1
  echo "readme" > README.md
  git add -A && git commit -q -m "first release"
  write_comp definitions/network/composition.yaml 0.1.1 2
  write_comp definitions/eks/composition.yaml "" 1
  sed -i.bak 's/XNetwork/XEKS/; s/xnetwork/xeks/' definitions/eks/composition.yaml && rm definitions/eks/composition.yaml.bak
  write_claim infra-requests/atlas/prd/vpc.yaml 0.1.1
  git add -A && git commit -q -m "base"
  git checkout -q -b pr
}

# run_case <name> <expected exit: 0|1> <function that edits the repo>
run_case() {
  local name="$1" want="$2" change="$3" got
  new_repo
  "$change"
  git add -A && git commit -q --allow-empty -m "change"
  # The untracked-claim case writes a file after the commit.
  if declare -F "${change}_untracked" >/dev/null; then "${change}_untracked"; fi
  set +e
  "$CHECK" main > "$repo/out.txt" 2>&1
  got=$?
  set -e
  if [ "$got" -eq "$want" ]; then
    echo "ok: $name (exit $got)"
    if [ "$want" -eq 1 ]; then grep '^FAIL:' "$repo/out.txt" | sed 's/^/      /'; fi
    pass=$((pass + 1))
  else
    echo "FAIL: $name (wanted exit $want, got $got)"
    sed 's/^/      /' "$repo/out.txt"
    bad=$((bad + 1))
  fi
}

# --- cases ---------------------------------------------------------------------

c_content_no_bump()      { write_comp definitions/network/composition.yaml 0.1.1 3; }
c_content_patch_bump()   { write_comp definitions/network/composition.yaml 0.1.2 3; }
c_release_lowered()      { write_comp definitions/network/composition.yaml 0.1.0 3; }
c_comment_only()         { sed -i.bak 's/# a comment/# a different comment/' definitions/network/composition.yaml; rm definitions/network/composition.yaml.bak; }
c_new_comp_no_label()    { write_comp definitions/app/composition.yaml "" 1; sed -i.bak 's/XNetwork/XApp/; s/xnetwork/xapp/' definitions/app/composition.yaml; rm definitions/app/composition.yaml.bak; }
c_unlabeled_add_label()  { write_comp definitions/eks/composition.yaml 0.1.0 9; sed -i.bak 's/XNetwork/XEKS/; s/xnetwork/xeks/' definitions/eks/composition.yaml; rm definitions/eks/composition.yaml.bak; }
c_unlabeled_still_none() { write_comp definitions/eks/composition.yaml "" 9; sed -i.bak 's/XNetwork/XEKS/; s/xnetwork/xeks/' definitions/eks/composition.yaml; rm definitions/eks/composition.yaml.bak; }
c_pin_never_existed()    { write_claim infra-requests/atlas/prd/vpc.yaml 0.9.9; }
c_pin_back()             { write_claim infra-requests/atlas/prd/vpc.yaml 0.1.0; }
c_invalid_semver()       { write_comp definitions/network/composition.yaml 1.0 3; }
c_untracked_bad_claim()  { :; }
c_untracked_bad_claim_untracked() { write_claim infra-requests/atlas/dev/vpc.yaml 9.9.9; }
c_readme_only()          { echo "more" >> README.md; }
c_numeric_compare()      { write_comp definitions/network/composition.yaml 0.1.10 3; }
c_label_only_lowered()   { write_comp definitions/network/composition.yaml 0.1.0 2; }
c_label_only_bump()      { write_comp definitions/network/composition.yaml 0.1.2 2; }
c_name_changed()         { write_comp definitions/network/composition.yaml 0.1.2 2; sed -i.bak 's/name: xnetwork/name: xnetwork-v2/' definitions/network/composition.yaml; rm definitions/network/composition.yaml.bak; }

run_case "content change without bump fails"            1 c_content_no_bump
run_case "content change with patch bump passes"        0 c_content_patch_bump
run_case "release lowered fails"                        1 c_release_lowered
run_case "comment-only change without bump passes"      0 c_comment_only
run_case "new Composition without label fails"          1 c_new_comp_no_label
run_case "unlabeled Composition changed, label added passes" 0 c_unlabeled_add_label
run_case "unlabeled Composition changed, no label fails" 1 c_unlabeled_still_none
run_case "claim pins a release that never existed fails" 1 c_pin_never_existed
run_case "claim pins an older release (pin back) passes" 0 c_pin_back
run_case "invalid semver 1.0 fails"                     1 c_invalid_semver
run_case "untracked claim with a bad release is ignored" 0 c_untracked_bad_claim
run_case "no relevant change (README only) passes"      0 c_readme_only
run_case "0.1.10 is higher than 0.1.1 (numeric compare)" 0 c_numeric_compare
run_case "label lowered with no content change fails"    1 c_label_only_lowered
run_case "label bumped with no content change passes"    0 c_label_only_bump
run_case "Composition name changed fails"                1 c_name_changed

echo
echo "$pass passed, $bad failed"
[ "$bad" -eq 0 ]
