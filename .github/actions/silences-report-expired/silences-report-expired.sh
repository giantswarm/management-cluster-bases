#!/usr/bin/env bash

set -eu

YQ="bin/yq"
KUSTOMIZATION_FILENAME="kustomization.yaml"

DEFAULT_EXPIRATION="14 days"
COMMIT_MESSAGE_PREFIX="remove expired silence - "
PULL_REQUEST_BODY=$(printf "This pull request was automatically created using the \`$(basename $0)\` script.\n\nIf you are assigned for review this means you created a silence which is now expired, based on the \`valid-until\` annotation, and has **been removed from AlertManager**.\n\nIf this correct please approve this PR and make sure it is being merged, otherwise feel free to update to extend or set the \`valid-until\` annotation, see https://github.com/giantswarm/silences#readme.\n\nThanks")
PULL_REQUEST_REMINDER="please merge this PR to delete this silence or update the \`valid-until\` annotation"

SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
DATE="$(command -v gdate || command -v date)"

RED='\033[0;31m'
NC='\033[0m' # No Color

print_usage() {
        echo "Usage: $(basename "$0") <action> <name>

Check for expired Silences

A silence is considered expired $DEFAULT_EXPIRATION after their creation date (git commit date where the file was added).
This can be overrided using the valid-until annotation, when present the given date is used as expiration date.
The owner of a silence is considered to be the author of the git commit where the file was added.

-r, --report  generate 1 pull request for each expired silence and ask its owner for review
    --dry-run do not actually change anything but show what would be done
-h, --help    print this help"
}

find_expired() {
  local directory="$1"
  local today_date
  local commit
  local latest_commit
  local expiration_date
  local valid_until_annotation
  local expired=()

  today_date="$($DATE "+%s")"

  # Find expired silences
  # We only check .yaml files, this validation is done in silences-validate.sh script
  for f in "$directory/"*.yaml; do
    if [[ "${f##*/}" == "$KUSTOMIZATION_FILENAME" ]]; then
      echo "> skipping $f" >&2
      continue
    fi

    echo -n "> checking $f" >&2
    # Produce json of commit where the file was last modified
    latest_commit="$(git log --format='{"timestamp": "%at", "hash": "%H", "author": "%an", "email": "%ae", "file": "'"$f"'"}' "$f" | head -1)"

    # Use valid-until annotation.
    # In case the annotation does not exist we want to get rid of this silence.
    expiration_date="0"
    valid_until_annotation="$($YQ e '.metadata.annotations.valid-until' "$f")"
    if [[ -n "$valid_until_annotation" ]] && [[ "$valid_until_annotation" != "null" ]]; then
      expiration_date="$($DATE "+%s" -d "${valid_until_annotation}")"
    fi

    # Check if Silence is expired
    if [ "${expiration_date}" -le "${today_date}" ]; then
      printf "$RED - EXPIRED$NC" >&2
      expired+=("$latest_commit")
    fi
    echo "" >&2
  done
  echo "> found ${#expired[@]} expired silence(s)" >&2

  for silence in "${expired[@]}"; do
      echo "$silence"
  done
}

main() {
  local dry_run=false
  local reporting=false

  args=()
  while test $# -gt 0; do
    case "$1" in
      --dry-run)
        shift
        dry_run=true
        echo "> dry_run=$dry_run"
        ;;
      -r|--report)
        shift
        reporting=true
        ;;
      -h|--help)
        print_usage
        exit 0
        ;;
      *)
        args+=("$1")
        ;;
    esac
    shift
  done

  set -- "${args[@]}"

  directory="$1"

  echo "> start with directory: $directory"

  local expired=()
  mapfile expired < <(find_expired "$directory")

  # Report expired silences via github pull requests
  # 1 pull request is created for each expired silence, and the owner is assigned for review.
  if $reporting; then
    echo
    echo "> reporting expired silences"

    start_branch="$(git branch --show-current)"


    function _run () {
        if $dry_run; then
            echo "$*"
        else
            "$@"
        fi
    }

    for commit in "${expired[@]}"; do
      file="$(echo "$commit" | jq -r '.file')"
      commit_sha="$(echo "$commit" | jq -r '.hash')"
      branch_name="clean-$file"

      # Map the git commit author to its github handle using github api
      userGithubHandle="$(gh api "/repos/giantswarm/silences/commits/${commit_sha}" -q '.author.login')"

      message="${COMMIT_MESSAGE_PREFIX}${file}"

      # Create the git branch
      $dry_run && echo "> dry run active, otherwise would run..."
      _run git checkout --quiet -b "$branch_name"
      _run git rm --quiet -- "${file}"
      _run git commit --quiet --all --message="${message}"
      _run git push --force --quiet --set-upstream origin "$branch_name"

      pr_data="$(gh pr view "$branch_name" --json state,url || echo '{}')"
      pr_status="$(echo "$pr_data" | jq -r '.state')"
      pr_link="$(echo "$pr_data" | jq -r '.url')"

      case "$pr_status" in
        "OPEN")
          _run gh pr comment "$branch_name" --body "@${userGithubHandle} $PULL_REQUEST_REMINDER"
          ;;
        *)
          pr_link=$(_run gh pr create \
                   --head "$branch_name" \
                   --reviewer "${userGithubHandle}" \
                   --assignee "${userGithubHandle}" \
                   --title "${message}" \
                   --body "$PULL_REQUEST_BODY")
          _run gh pr merge --squash --auto "$branch_name"
          ;;
      esac

      _run echo "> reported ${file} at ${pr_link}"
      _run git checkout --quiet "$start_branch"
    done
  fi
}

main "$@"
