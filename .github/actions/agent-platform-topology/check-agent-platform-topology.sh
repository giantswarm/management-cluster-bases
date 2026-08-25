#!/usr/bin/env bash
#
# Checks how the Agent Platform is laid out across the management clusters of
# one fleet repository. The rule: exactly one management cluster runs the
# aggregator (`./agent-platform/` in its extras), unless the repository root
# file `.agent-platform.yaml` records something else:
#
#   aggregators: [gazelle, glean, graveler]   # several aggregators, listed exactly
#
#   decision: none                            # no aggregator at all
#   reason: proof-of-concept cluster
#   issue: https://github.com/giantswarm/giantswarm/issues/37446
#
# Every management cluster that lists ./mcp-kubernetes/ must also list
# ./mcp-prometheus/ and vice versa; that check only warns.
#
# Usage: check-agent-platform-topology.sh [<repo root>]
# Environment:
#   AGENT_PLATFORM_TOPOLOGY_STRICT  "true" makes rule violations exit 1
#                                   (default "false": report and exit 0).
#   YQ                              yq binary (default: yq on PATH).

set -euo pipefail

root="${1:-.}"
strict="${AGENT_PLATFORM_TOPOLOGY_STRICT:-false}"
YQ="${YQ:-yq}"
topology_file="${root}/.agent-platform.yaml"

violations=0

fail() {
  echo "  [err] $*" >&2
  violations=$((violations + 1))
}

warn() {
  echo "  [warn] $*" >&2
}

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
    warn "${mc}: extras list mcp-kubernetes=${has_k8s} mcp-prometheus=${has_prom}; muster needs both backends"
  fi
done
shopt -u nullglob

mc_count="$(find "${root}/management-clusters" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
echo "management clusters: ${mc_count}, aggregators: ${#aggregators[@]} (${aggregators[*]:-none})"

if [[ -f "${topology_file}" ]]; then
  decision="$("${YQ}" '.decision // ""' "${topology_file}")"
  mapfile -t declared < <("${YQ}" '.aggregators[]?' "${topology_file}")
  if [[ "${decision}" == "none" ]]; then
    reason="$("${YQ}" '.reason // ""' "${topology_file}")"
    issue="$("${YQ}" '.issue // ""' "${topology_file}")"
    [[ -n "${reason}" && -n "${issue}" ]] || fail ".agent-platform.yaml: decision: none needs reason and issue"
    if [[ ${#aggregators[@]} -gt 0 ]]; then
      fail ".agent-platform.yaml records decision: none but ${aggregators[*]} run(s) the Agent Platform"
    fi
  elif [[ ${#declared[@]} -gt 0 ]]; then
    have="$(printf '%s\n' "${aggregators[@]:-}" | sort -u | tr '\n' ' ')"
    want="$(printf '%s\n' "${declared[@]}" | sort -u | tr '\n' ' ')"
    if [[ "${have}" != "${want}" ]]; then
      fail ".agent-platform.yaml lists aggregators [${want% }] but the extras show [${have% }]"
    fi
  else
    fail ".agent-platform.yaml must set either aggregators: [...] or decision: none"
  fi
elif [[ ${mc_count} -gt 0 ]]; then
  case ${#aggregators[@]} in
    1) ;;
    0) fail "no management cluster runs the Agent Platform; add ./agent-platform/ to one extras/kustomization.yaml or record decision: none in .agent-platform.yaml" ;;
    *) fail "more than one management cluster runs the Agent Platform (${aggregators[*]}); one aggregator per customer, or list them in .agent-platform.yaml" ;;
  esac
fi

if [[ ${violations} -eq 0 ]]; then
  echo "  [ok] agent platform topology"
  exit 0
fi
if [[ "${strict}" == "true" ]]; then
  exit 1
fi
echo "  [warn] ${violations} violation(s); not enforced yet (AGENT_PLATFORM_TOPOLOGY_STRICT=false)" >&2
