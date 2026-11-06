#!/usr/bin/env bash
set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work_directory=$(mktemp -d)
trap 'rm -rf "$work_directory"' EXIT

kustomize build "$repository_root/extras/mcp-kubernetes" > "$work_directory/resources.yaml"
version_range=$(yq -r 'select(.kind == "OCIRepository" and .metadata.name == "mcp-kubernetes") | .spec.ref.semver' "$work_directory/resources.yaml")

mkdir -p "$work_directory/chart/templates"
cat > "$work_directory/chart/Chart.yaml" <<'YAML'
apiVersion: v2
name: version-policy
version: 0.0.0
YAML
cat > "$work_directory/chart/templates/policy.yaml" <<'YAML'
compatible: {{ semverCompare .Values.constraint .Values.version }}
YAML

while read -r version expected; do
  actual=$(helm template version-policy "$work_directory/chart" --kube-context offline-render \
    --set-string "constraint=$version_range" --set-string "version=$version" | yq -r '.compatible')
  if [ "$actual" != "$expected" ]; then
    printf 'FAIL %s: %s selected %s, want %s\n' "$version" "$version_range" "$actual" "$expected" >&2
    exit 1
  fi
  printf 'ok %s: %s\n' "$version" "$actual"
done <<'VERSIONS'
1.13.33 false
1.13.34 true
1.13.51 true
1.14.0 true
1.99.0 true
1.14.0-rc.1 false
2.0.0-rc.1 false
2.0.0 false
VERSIONS
