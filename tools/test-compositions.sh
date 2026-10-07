#!/usr/bin/env bash
# Smoke-tests Crossplane compositions by rendering their examples.
#
# Every extras/crossplane/compositions/<provider>/<name>/composition.yaml with
# an examples/ directory next to it gets each examples/<case>/ rendered with
# `crossplane beta render`. A case is:
#
#   xr.yaml        the composite resource, including status for later passes
#   observed.yaml  optional, observed composed resources (--observed-resources)
#   extra.yaml     optional, extra resources (--extra-resources)
#
# Functions come from extras/crossplane/functions/<provider>/, the same
# manifests management clusters deploy, so their versions cannot drift.
# Compositions without examples are skipped.
#
# Usage: test-compositions.sh <path to crossplane CLI>

set -euo pipefail

crossplane=${1:?usage: $0 <path to crossplane CLI>}
root=extras/crossplane

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# render takes a file or directory of Function manifests only, so the
# kustomization.yaml has to go and the rest is merged into one stream.
functions_for() {
	local provider=$1 out="$tmp/functions-$1.yaml" f
	if [[ ! -f $out ]]; then
		for f in "$root/functions/$provider"/*.yaml; do
			[[ $(basename "$f") == kustomization.yaml ]] && continue
			echo ---
			sed '/^---$/d' "$f"
		done >"$out"
	fi
	echo "$out"
}

rc=0
while IFS= read -r composition; do
	dir=$(dirname "$composition")
	[[ -d $dir/examples ]] || continue

	provider=${dir#"$root/compositions/"}
	provider=${provider%%/*}
	functions=$(functions_for "$provider")

	for case in "$dir"/examples/*/; do
		case=${case%/}
		args=("$case/xr.yaml" "$composition" "$functions")
		[[ -f $case/observed.yaml ]] && args+=(--observed-resources "$case/observed.yaml")
		[[ -f $case/extra.yaml ]] && args+=(--extra-resources "$case/extra.yaml")

		if out=$("$crossplane" beta render "${args[@]}" 2>&1); then
			echo "ok    $case"
		else
			echo "FAIL  $case"
			echo "$out" | sed 's/^/      /'
			rc=1
		fi
	done
done < <(find "$root/compositions" -name composition.yaml | sort)

exit $rc
