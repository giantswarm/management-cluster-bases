#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"

YQ="${SCRIPT_DIR}/../bin/yq"

silences_path="$1"
kustomization_path="$silences_path/kustomization.yaml"

no_yml() {
  # Reject .yml
  if [[ "$1" =~ .*\.yml ]]; then
    echo "  [err] wrong extension, please use .yaml"
    return 1
  fi
  echo "  [ok] no .yml"
}

skip_non_yaml() {
  # Skip non yaml files
  if [[ ! "$1" =~ .*\.yaml ]]; then
    echo "  [ok] skipping non .yaml file"
    return 1
  fi
}

valid_until_date() {
  # Validate date from valid_until annotation
  valid_until_annotation="$($YQ e '.metadata.annotations.valid-until' "$1")"
  if [[ "$valid_until_annotation" != "null" ]]; then
    if ! valid_until="$(date --rfc-3339=date -d "${valid_until_annotation}" 2>&1)"; then
      echo "  [err] valid until : $valid_until"
      return 1
    fi
    echo "  [ok] valid until correct $valid_until"
  else
    echo "  [err] valid until required"
    return 1
  fi
}

main() {
  echo "> start"
  cd "${SCRIPT_DIR}/.."

  default_branch="$(git remote show origin | grep 'HEAD' | cut -d':' -f2 | tr -d '[[:space:]]')"
  merge_base="$(git merge-base HEAD "origin/$default_branch")"

  # Detect files which changed between the current HEAD and the remote default branch.
  # Only keep first level files.
  mapfile -t changed_files < <(git --no-pager diff --name-only "$merge_base" HEAD -- "$silences_path" ":(exclude)$kustomization_path")
  echo "> found ${#changed_files[@]} changed files between $(git rev-parse --abbrev-ref HEAD) and $default_branch"

  # Run file checks
  local has_error=false
  for file in "${changed_files[@]}"; do
    echo "> checking $file"

    no_yml "$file"           || has_error=true
    skip_non_yaml "$file"    || continue
    valid_until_date "$file" || has_error=true

  done

  if $has_error; then
    echo "> fail"
    exit 1
  fi

  echo "> success"
}

 main "$@"
