#!/usr/bin/env bash
#
# Reports how the Agent Platform is laid out across the management clusters of
# one fleet repository: which clusters run the aggregator (`./agent-platform/`
# in their extras) and whether every cluster lists both MCP backends. The
# convention is one aggregator per customer; this script only reports.
#
# Usage: check-agent-platform-topology.sh [<repo root>]
# Environment:
#   YQ   yq binary (default: yq on PATH).

set -euo pipefail

root="${1:-.}"
YQ="${YQ:-yq}"

lists_resource() {
  local kustomization="$1" pattern="$2"
  # grep reads all input on purpose: with -q it would exit early and the
  # pipeline would fail on yq's SIGPIPE under pipefail.
  "${YQ}" '.resources[]?' "${kustomization}" | grep -xE "${pattern}" >/dev/null
}

aggregators=()
shopt -s nullglob
for kustomization in "${root}"/management-clusters/*/extras/kustomization.yaml; do
  mc="$(basename "$(dirname "$(dirname "${kustomization}")")")"
  if lists_resource "${kustomization}" '\./agent-platform/?'; then
    aggregators+=("${mc}")
  fi
  has_k8s=false
  has_prom=false
  lists_resource "${kustomization}" '\./mcp-kubernetes/?' && has_k8s=true
  lists_resource "${kustomization}" '\./mcp-prometheus/?' && has_prom=true
  if [[ "${has_k8s}" != "${has_prom}" ]]; then
    echo "  [warn] ${mc}: extras list mcp-kubernetes=${has_k8s} mcp-prometheus=${has_prom}; muster needs both backends" >&2
  fi
done
shopt -u nullglob

mc_count="$(find "${root}/management-clusters" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
echo "management clusters: ${mc_count}, Agent Platform aggregators: ${#aggregators[@]} (${aggregators[*]:-none})"
if [[ ${mc_count} -gt 0 && ${#aggregators[@]} -eq 0 ]]; then
  echo "  [info] no management cluster runs the Agent Platform" >&2
elif [[ ${#aggregators[@]} -gt 1 ]]; then
  echo "  [info] more than one aggregator; the convention is one per customer" >&2
fi
