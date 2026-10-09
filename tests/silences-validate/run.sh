#!/usr/bin/env bash
# Runs silences-validate.sh against each fixture directory, the way a pull
# request adding the fixture's files to a silences directory would be checked.
# Needs bin/yq at the repository root (make bin/yq).

set -euo pipefail

# silences-validate.sh parses `git remote show` output, which is localised.
export LC_ALL=C

repo_root="$(git rev-parse --show-toplevel)"
fixtures="$repo_root/tests/silences-validate"
script="$repo_root/.github/actions/silences-validate/silences-validate.sh"

failed=false

# run_fixture <fixture> prints the validator's output for the fixture and
# returns its exit code. The fixture is added on a branch of a scratch
# repository whose origin's main holds an empty silences directory.
run_fixture() {
  local work
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' RETURN
  git init --quiet --bare --initial-branch=main "$work/origin.git"
  git clone --quiet "$work/origin.git" "$work/repo" 2>/dev/null
  (
    cd "$work/repo"
    git config user.email test@example.com
    git config user.name test
    git config commit.gpgsign false
    mkdir silences
    printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nresources: []\n' > silences/kustomization.yaml
    git add silences && git commit --quiet -m init && git push --quiet origin HEAD:main
    git remote set-head origin main
    git checkout --quiet -b test
    cp "$fixtures/$1/"*.yaml silences/
    git add silences && git commit --quiet -m fixture
    ln -s "$repo_root/bin" bin
    "$script" silences 2>&1
  )
}

# expect <fixture> <exit code> <section> <pattern>... checks the exit code and
# that every pattern is found in the output from the first line matching
# <section> on, so an error is attributed to the document it follows.
expect() {
  local fixture="$1" want="$2" section="$3" got=0 output pattern
  shift 3
  output="$(run_fixture "$fixture")" || got=$?
  if [[ "$got" != "$want" ]]; then
    echo "FAIL $fixture: exit code $got, want $want"
    failed=true
  fi
  for pattern in "$@"; do
    if ! sed -n "/$section/,\$p" <<< "$output" | grep -qE -- "$pattern"; then
      echo "FAIL $fixture: output lacks /$pattern/"
      failed=true
    fi
  done
  echo "--- $fixture"
  echo "$output"
}

expect valid-two-documents 0 '> start' \
  'checking document 1/2 \(first-silence\)' \
  'checking document 2/2 \(second-silence\)' \
  '> success'

expect invalid-second-document 1 'checking document 2\/2 (invalid-silence)' \
  'invalid apiVersion: observability.giantswarm.io/v1alpha1' \
  "can't parse valid until" \
  'cluster_id matcher not found'

# The first document is valid: no error precedes the second document's header.
if run_fixture invalid-second-document | sed '/checking document 2\/2/q' | grep -q '\[err\]'; then
  echo "FAIL invalid-second-document: error reported for the valid first document"
  failed=true
fi

if $failed; then
  echo "> silences-validate tests failed"
  exit 1
fi
echo "> silences-validate tests passed"
