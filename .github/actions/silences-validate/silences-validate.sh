#!/usr/bin/env bash

set -euo pipefail

YQ="bin/yq"
KUSTOMIZATION_FILENAME="kustomization.yaml"
PROMETHEUS_RULES_CHART="oci://gsoci.azurecr.io/charts/giantswarm/prometheus-rules"
# Latest release of the public prometheus-rules repo pins the chart version
# templated for the impacted-alerts lookup (see build_all_pipelines_alerts). The
# repo is public, so no authentication is required.
PROMETHEUS_RULES_LATEST_RELEASE_URL="https://api.github.com/repos/giantswarm/prometheus-rules/releases/latest"

# Cache for the prometheus-rules all_pipelines alert lookup (see build_all_pipelines_alerts).
ALL_PIPELINES_BUILT=""    # cache state: "" (not attempted), "ok", or "failed"
ALL_PIPELINES_ALERTS=()   # "<alert>|<runbook_url>" entries once built

RED='\033[0;31m'
NC='\033[0m' # No Color

error() {
  echo -e "${RED}$*${NC}" >&2
}

# yaml_extension fail if file does not have .yaml extension
yaml_extension() {
  if ! [[ "$1" =~ .*\.yaml ]]; then
    error "  [err] wrong extension, please use .yaml"
    return 1
  fi
  echo "  [ok] .yaml extension"
}

has_cluster_id_matcher() {
  content="$($YQ e '.spec.matchers[] | select(.name == "cluster_id")' "$1")"
  if [[ -z "$content" ]] || [[ "$content" == "null" ]]; then
    error "  [err] cluster_id matcher not found"
    return 1
  fi
  echo "  [ok] cluster_id matcher found"
}

# Get the API version of the silence
get_api_version() {
  api_version="$($YQ e '.apiVersion' "$1")"
  echo "$api_version"
}

# validate_v1alpha2_apiversion fail if v1alpha2 file doesn't have correct apiVersion
validate_v1alpha2_apiversion() {
  local file_path="$1"
  local api_version
  api_version="$(get_api_version "$file_path")"

  if [[ "$api_version" == "observability.giantswarm.io/v1alpha2" ]]; then
    echo "  [ok] v1alpha2 apiVersion correct"
    return 0
  elif [[ "$api_version" == "monitoring.giantswarm.io/v1alpha1" ]]; then
    error "  [err] v1alpha1 silences are no longer accepted. Please migrate to v1alpha2."
    return 1
  else
    error "  [err] invalid apiVersion: $api_version (expected observability.giantswarm.io/v1alpha2)"
    return 1
  fi
}

# validate_v1alpha2_namespace fail if v1alpha2 file doesn't have namespace
validate_v1alpha2_namespace() {
  local file_path="$1"
  local api_version
  api_version="$(get_api_version "$file_path")"

  # Only validate namespace for v1alpha2
  if [[ "$api_version" == "observability.giantswarm.io/v1alpha2" ]]; then
    local namespace
    namespace="$($YQ e '.metadata.namespace' "$file_path")"
    if [[ -z "$namespace" ]] || [[ "$namespace" == "null" ]]; then
      error "  [err] v1alpha2 silence requires metadata.namespace"
      return 1
    fi
    echo "  [ok] v1alpha2 namespace present: $namespace"
  else
    echo "  [ok] v1alpha1 silence (namespace not required)"
  fi
}

# build_all_pipelines_alerts templates the prometheus-rules chart once and caches
# the alerts carrying the all_pipelines="true" label as "<alert>|<runbook_url>"
# entries in the ALL_PIPELINES_ALERTS array. Returns non-zero (once) if the list
# could not be built, so callers can fall back to a plain warning. Memoized.
build_all_pipelines_alerts() {
  case "$ALL_PIPELINES_BUILT" in
    ok) return 0 ;;
    failed) return 1 ;;
  esac

  if ! command -v helm >/dev/null 2>&1; then
    error "  [warn] helm not found; skipping impacted-alerts lookup"
    ALL_PIPELINES_BUILT="failed"
    return 1
  fi

  # Resolve the chart version from the latest GitHub release. The release tag
  # (e.g. v4.107.1) maps to the chart version (4.107.1).
  local version
  version="$(curl -fsSL "$PROMETHEUS_RULES_LATEST_RELEASE_URL" 2>/dev/null | $YQ '.tag_name' 2>/dev/null)"
  version="${version#v}"
  if [[ -z "$version" || "$version" == "null" ]]; then
    error "  [warn] could not resolve latest prometheus-rules version; skipping impacted-alerts lookup"
    ALL_PIPELINES_BUILT="failed"
    return 1
  fi

  local manifests
  if ! manifests="$(helm template prometheus-rules "$PROMETHEUS_RULES_CHART" --version "$version" 2>/dev/null)"; then
    error "  [warn] could not template $PROMETHEUS_RULES_CHART $version; skipping impacted-alerts lookup"
    ALL_PIPELINES_BUILT="failed"
    return 1
  fi

  # Each entry: "<alert>|<runbook_url>" (runbook query string stripped). Alert
  # names and runbook URLs never contain "|", so it is a safe separator.
  mapfile -t ALL_PIPELINES_ALERTS < <(printf '%s' "$manifests" \
    | $YQ ea -N 'select(.kind == "PrometheusRule") | .spec.groups[].rules[] | select(.labels.all_pipelines == "true") | .alert + "|" + (.annotations.runbook_url // "" | sub("\?.*$"; ""))' 2>/dev/null \
    | grep -v '^[[:space:]]*$' | sort -u || true)

  ALL_PIPELINES_BUILT="ok"
  return 0
}

# alertname_matches returns 0 if alert name $1 satisfies the Alertmanager matcher
# described by match type $2 and match value $3. Regex matchers are fully anchored,
# as in Alertmanager.
alertname_matches() {
  local alert_name="$1" match_type="$2" match_value="$3"
  case "$match_type" in
    "="|"") [[ "$alert_name" == "$match_value" ]] ;;
    "!=")   [[ "$alert_name" != "$match_value" ]] ;;
    "=~")   [[ "$alert_name" =~ ^($match_value)$ ]] ;;
    "!~")   ! [[ "$alert_name" =~ ^($match_value)$ ]] ;;
    *)      return 1 ;;
  esac
}

# impacted_alerts_for prints a markdown bullet list of the cached all_pipelines
# alerts whose name satisfies every alertname matcher of the silence file $1.
# With no alertname matcher, all all_pipelines alerts are listed.
impacted_alerts_for() {
  local silence_file="$1"
  local -a alertname_matchers
  mapfile -t alertname_matchers < <($YQ e -N '.spec.matchers[] | select(.name == "alertname") | (.matchType // "=") + " " + .value' "$silence_file" 2>/dev/null | grep -v '^[[:space:]]*$' || true)

  local alert_entry alert_name runbook_url matcher match_type match_value alert_is_impacted
  for alert_entry in "${ALL_PIPELINES_ALERTS[@]}"; do
    alert_name="${alert_entry%%|*}"
    runbook_url="${alert_entry#*|}"
    alert_is_impacted=true
    for matcher in "${alertname_matchers[@]}"; do
      match_type="${matcher%% *}"
      match_value="${matcher#* }"
      if ! alertname_matches "$alert_name" "$match_type" "$match_value"; then
        alert_is_impacted=false
        break
      fi
    done
    $alert_is_impacted || continue
    if [[ -n "$runbook_url" ]]; then
      printf -- '- `%s` ([runbook](%s))\n' "$alert_name" "$runbook_url"
    else
      printf -- '- `%s`\n' "$alert_name"
    fi
  done
}

# warn_force_all posts a PR comment when the force-all annotation is set to "true",
# listing the all_pipelines alerts this silence would override (best effort).
warn_force_all() {
  local file_path="$1"
  local force_all
  force_all="$($YQ e '.metadata.annotations["silence.application.giantswarm.io/force-all"]' "$file_path")"
  if [[ "$force_all" != "true" ]]; then
    return
  fi
  echo "  [warn] silence.application.giantswarm.io/force-all is set to true"

  if ! gh pr view "$(git branch --show-current)" --json number >/dev/null 2>&1; then
    # We can't comment if there's no PR
    return
  fi

  local body
  body=":warning: The silence \`$(basename "$file_path")\` sets \`silence.application.giantswarm.io/force-all: \"true\"\`, which makes it apply to alerts regardless of their \`all_pipelines\` label."

  # Best effort: list the all_pipelines alerts this silence would reach.
  if build_all_pipelines_alerts; then
    local impacted
    impacted="$(impacted_alerts_for "$file_path" || true)"
    if [[ -n "$impacted" ]]; then
      body+=$'\n\n'"It would override the \`all_pipelines\` protection for at least the following alerts:"$'\n'"$impacted"
    else
      body+=$'\n\n'"_No \`all_pipelines\` alert from the \`prometheus-rules\` chart matches this silence's \`alertname\` matcher(s)._"
    fi
    body+=$'\n\n'"_This list is derived from the \`prometheus-rules\` chart, which is the main but not the only source of alerts, so it may be incomplete._"
  fi

  body+=$'\n\n'"Please make sure this is intended. See [documentation](https://docs.giantswarm.io/overview/observability/alert-management/silences/) for more information."

  gh pr comment "$(git branch --show-current)" --body "$body"
}

notify_expiry_on_weekend(){
  if ! gh pr view "$(git branch --show-current)" --json number >/dev/null 2>&1; then
    # We can't comment if there's no PR
    return
  fi
  repo_name="$(git remote get-url origin | sed -n 's#.*:\(.*\)\.git#\1#p')"
  commit_sha="$(git log -n 1 --format="%H" -- "$1")"
  userGithubHandle="$(gh api "/repos/${repo_name}/commits/${commit_sha}" -q '.author.login')"
  weekend_msg="Note: The \`valid-until\` date for \`$(basename "$1")\` falls on a **weekend** ($valid_until_annotation)."
  gh pr comment "$(git branch --show-current)" --body "@${userGithubHandle} $weekend_msg"
}

# valid_until_date fail if valid-until annotation is missing or invalid
valid_until_date() {
  valid_until_annotation="$($YQ e '.metadata.annotations.valid-until' "$1")" || return 1
  if [[ -z "$valid_until_annotation" ]] || [[ "$valid_until_annotation" == "null" ]]; then
    error "  [err] valid until required"
    return 1
  fi
  if ! valid_until="$(date --rfc-3339=date -d "${valid_until_annotation}" 2>&1)"; then
    error "  [err] can't parse valid until : $valid_until"
    return 1
  fi
  echo "  [ok] valid until correct $valid_until"

  # notify if silence expires on a weekend
  if [[ $(date -d "$valid_until" +%u) -gt 5 ]]; then
    notify_expiry_on_weekend "$1"
  fi
}

# validate_kustomization_resources fail if resource is not found in kustomization.yaml
validate_kustomization_resources() {
  file_basename="$(basename "$1")"
  if ! echo "${KUSTOMIZATION_RESOURCES}" | grep -qE "^${file_basename}$"; then
    error "  [err] resource ${file_basename} not found in kustomization.yaml"
    return 1
  fi
  echo "  [ok] resource ${file_basename} found in kustomization.yaml"
}

main() {
  echo "> start"

  # Get default branch and merge base to compare against
  default_branch="$(git remote show origin | grep 'HEAD' | cut -d':' -f2 | tr -d '[[:space:]]')"
  merge_base="$(git merge-base HEAD "origin/$default_branch")"
  # Get the root of the git repository
  git_root="$(git rev-parse --show-toplevel)"

  silences_path="${git_root}/${1}"
  # Assume kustomization.yaml is at root of silences path
  kustomization_path="$silences_path/$KUSTOMIZATION_FILENAME"

  # List resources referenced in kustomization.yaml
  KUSTOMIZATION_RESOURCES="$($YQ e '.resources[]' "$kustomization_path")"

  # Detect files which changed between the current HEAD and the remote default branch in the silences path
  mapfile -t changed_files < <(git --no-pager diff --diff-filter=d --name-only "$merge_base" HEAD -- "${silences_path}" ":(exclude)$kustomization_path")
  echo "> found ${#changed_files[@]} changed files between $(git rev-parse --abbrev-ref HEAD) and $default_branch"

  # Run file checks
  local has_error=false
  for file in "${changed_files[@]}"; do
    file_path="${git_root}/${file}"
    echo "> checking $file_path"

    yaml_extension "$file_path"               || has_error=true
    validate_v1alpha2_apiversion "$file_path" || has_error=true
    validate_v1alpha2_namespace "$file_path"  || has_error=true
    valid_until_date "$file_path"             || has_error=true
    validate_kustomization_resources "$file"  || has_error=true
    has_cluster_id_matcher "$file_path"       || has_error=true

    # Non-blocking: warn in the PR thread when force-all is enabled
    warn_force_all "$file_path"

  done

  if $has_error; then
    error "> failed"
    exit 1
  fi

  echo "> success"
}

 main "$@"
