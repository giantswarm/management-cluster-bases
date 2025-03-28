#!/usr/bin/env bash

set -euo pipefail

YQ="bin/yq"
KUSTOMIZATION_FILENAME="kustomization.yaml"

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

# valid_until_date fail if valid-until annotation is missing or invalid
valid_until_date() {
  valid_until_annotation="$($YQ e '.metadata.annotations.valid-until' "$1")" || return 1
  if [[ -n "$valid_until_annotation" ]] && [[ "$valid_until_annotation" != "null" ]]; then
    if ! valid_until="$(date --rfc-3339=date -d "${valid_until_annotation}" 2>&1)"; then
      error "  [err] valid until : $valid_until"
      return 1
    fi
    echo "  [ok] valid until correct $valid_until"
  else
    error "  [err] valid until required"
    return 1
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
  mapfile -t changed_files < <(git --no-pager diff --diff-filter=d --name-only HEAD "$merge_base" -- "${silences_path}" ":(exclude)$kustomization_path")
  echo "> found ${#changed_files[@]} changed files between $(git rev-parse --abbrev-ref HEAD) and $default_branch"

  # Run file checks
  local has_error=false
  for file in "${changed_files[@]}"; do
    file_path="${git_root}/${file}"
    echo "> checking $file_path"

    yaml_extension "$file_path"              || has_error=true
    valid_until_date "$file_path"            || has_error=true
    validate_kustomization_resources "$file" || has_error=true

  done

  if $has_error; then
    error "> failed"
    exit 1
  fi

  echo "> success"
}

 main "$@"
