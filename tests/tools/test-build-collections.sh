#!/usr/bin/env bash
# Checks the collections build targets of the shared Makefile
# (bases/tools/Makefile.custom.mk) that every GitOps repo pulls from here.
#
# Run it with:
#
#     ./tests/tools/test-build-collections.sh
#
# It needs `kustomize` on PATH and does not touch the network: the fixture
# GitOps repo it builds uses local resources only.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
shared_makefile="${repo_root}/bases/tools/Makefile.custom.mk"

command -v kustomize >/dev/null || { echo "need kustomize on PATH"; exit 1; }

fixture="$(mktemp -d)"
trap 'rm -rf "${fixture}"' EXIT

failures=0

assert() { # assert <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    echo "ok    $1"
  else
    echo "FAIL  $1: expected '$2', got '$3'"
    failures=$((failures + 1))
  fi
}

collection() { # collection <mc> <resource-file>
  mkdir -p "${fixture}/management-clusters/$1/collections"
  cat >"${fixture}/management-clusters/$1/collections/kustomization.yaml" <<EOF
resources:
  - $2
EOF
  cat >"${fixture}/management-clusters/$1/collections/ocirepository.yaml" <<EOF
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: OCIRepository
metadata:
  name: $1-app
  namespace: giantswarm
spec:
  url: oci://gsoci.azurecr.io/charts/giantswarm/$1-app
EOF
}

# A GitOps repo, as the shared Makefile expects to find one.
mkdir -p "${fixture}/bin"
cp "$(command -v kustomize)" "${fixture}/bin/kustomize" # so no target downloads one
printf 'include Makefile.*.mk\n' >"${fixture}/Makefile"
cp "${shared_makefile}" "${fixture}/Makefile.custom.mk"
collection alpha ocirepository.yaml
collection beta ocirepository.yaml

git -C "${fixture}" init --quiet
git -C "${fixture}" add -A
git -C "${fixture}" -c user.email=t@t -c user.name=t commit --quiet -m baseline

run() { # run <make-goal...>; prints the exit code
  local rc=0
  (cd "${fixture}" && make "$@" >/dev/null 2>&1) || rc=$?
  echo "${rc}"
}

# A developer can render one cluster's collections.
assert "build-alpha-collections succeeds" 0 "$(run build-alpha-collections)"
assert "build-alpha-collections writes the rendered overlay" 1 \
  "$(grep -c '^  name: alpha-app$' "${fixture}/output/alpha-collections.yaml" 2>/dev/null || echo 0)"

# A malformed collections change fails, rather than rendering nothing.
collection beta component-that-does-not-exist
assert "build-beta-collections fails on a malformed overlay" 2 "$(run build-beta-collections)"

# CI renders the clusters a pull request touches, and only those.
collection beta ocirepository.yaml # back to a clean tree
git -C "${fixture}" add -A
git -C "${fixture}" -c user.email=t@t -c user.name=t commit --quiet -m clean
baseline="$(git -C "${fixture}" rev-parse HEAD)"

rm -rf "${fixture}/output"
assert "build-changed-collections is a no-op when nothing is touched" 0 \
  "$(run build-changed-collections DIFF_BASE="${baseline}")"
assert "build-changed-collections renders nothing when nothing is touched" 0 \
  "$(find "${fixture}/output" -type f 2>/dev/null | wc -l | tr -d ' ')"

echo '# touched' >>"${fixture}/management-clusters/alpha/collections/kustomization.yaml"
assert "build-changed-collections succeeds for a touched cluster" 0 \
  "$(run build-changed-collections DIFF_BASE="${baseline}")"
assert "build-changed-collections renders the touched cluster" 1 \
  "$([ -f "${fixture}/output/alpha-collections.yaml" ] && echo 1 || echo 0)"
assert "build-changed-collections skips the untouched cluster" 0 \
  "$([ -f "${fixture}/output/beta-collections.yaml" ] && echo 1 || echo 0)"

# A malformed change in a touched cluster fails the check.
collection beta component-that-does-not-exist
assert "build-changed-collections fails on a malformed touched cluster" 2 \
  "$(run build-changed-collections DIFF_BASE="${baseline}")"

# Dropping a cluster's collections is a change to it, but there is nothing left
# to render.
rm -rf "${fixture}/management-clusters/beta/collections"
assert "build-changed-collections skips a cluster whose collections were removed" 0 \
  "$(run build-changed-collections DIFF_BASE="${baseline}")"

# The GitOps repos do not vendor this file, they pipe it into `make -f -` from a
# catch-all rule. `build-changed-collections` re-enters make, so check that the
# re-entry still resolves through that rule.
cat >"${fixture}/Makefile.custom.mk" <<EOF
FLEET_MAKEFILE=file://${shared_makefile}

.EXPORT_ALL_VARIABLES:

%::
	curl -sL \$(FLEET_MAKEFILE) | \$(MAKE) -f - \$@
EOF
rm -rf "${fixture}/output"
collection beta ocirepository.yaml
echo '# touched' >>"${fixture}/management-clusters/beta/collections/kustomization.yaml"
assert "build-changed-collections works through the fleet Makefile catch-all" 0 \
  "$(run build-changed-collections DIFF_BASE="${baseline}")"
assert "the catch-all run renders the touched cluster" 1 \
  "$([ -f "${fixture}/output/beta-collections.yaml" ] && echo 1 || echo 0)"

echo
if [ "${failures}" -ne 0 ]; then
  echo "${failures} check(s) failed"
  exit 1
fi
echo "all checks passed"
