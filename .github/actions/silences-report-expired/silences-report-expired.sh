#!/usr/bin/env bash

set -euo pipefail

YQ="bin/yq"
KUSTOMIZATION_FILENAME="kustomization.yaml"

COMMIT_MESSAGE_PREFIX="remove expired silence - "
PULL_REQUEST_BODY_EXPIRED="This pull request was automatically created using the $(basename "$0") script.

If you are assigned for review, this means you created a silence which is **now expired** based on the \`valid-until\` annotation, and has **been removed from AlertManager**.

If this is correct, please approve this PR and make sure it is being merged. Otherwise, feel free to update or extend the \`valid-until\` annotation. See: https://intranet.giantswarm.io/docs/observability/silences/#when-to-delete-a-silence"
PULL_REQUEST_BODY_SOON="This pull request was automatically created using the $(basename "$0") script.

If you are assigned for review, this means you created a silence which is **expiring soon**, based on the \`valid-until\` annotation. The silence has **not yet been removed from AlertManager**, but we suggest you check and update the annotation if needed.

If this is correct, please approve this PR or update the \`valid-until\` annotation. See: https://intranet.giantswarm.io/docs/observability/silences/#when-to-delete-a-silence"
PULL_REQUEST_REMINDER="Please merge this PR to delete this silence or update the \`valid-until\` annotation."

DATE="$(command -v gdate || command -v date)"

RED='\033[0;31m'
NC='\033[0m' # No Color

DRY_RUN=false

print_usage() {
        echo "Usage: $(basename "$0") <action> <name>

Check for expired Silences

A silence is considered expired when its valid-until annotation is in the past.
The owner of a silence is considered to be the author of the git commit where the file was added.

-r, --report  generate 1 pull request for each expired silence and ask its owner for review
    --dry-run do not actually change anything but show what would be done
-h, --help    print this help"
}

find_expired() {
  local directory="$1"
  local today_date
  local latest_commit
  local expiration_date
  local valid_until_annotation
  local expired=()
  local expiring_soon=()

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
    latest_commit="$(git log -1 --format='{"timestamp": "%at", "hash": "%H", "author": "%an", "email": "%ae"}' "$f" | jq -c --arg file "$f" '. + {file: $file}')"

    # Use valid-until annotation.
    # In case the annotation does not exist we want to get rid of this silence.
    expiration_date="0"
    valid_until_annotation="$($YQ e '.metadata.annotations.valid-until' "$f")"
    if [[ -n "$valid_until_annotation" ]] && [[ "$valid_until_annotation" != "null" ]]; then
      if ! expiration_date="$($DATE "+%s" -d "${valid_until_annotation}")" ; then
          echo "${RED} - invalid valid-until annotation, skipping${NC}" >&2
          continue
      fi
    fi

    # Check if Silence is about to expire or already expired
    warning_threshold="$((60 * 60 * 24 * 2))" # 2 days in seconds
    if [ "$expiration_date" -le "$today_date" ]; then
      printf "${RED} - EXPIRED${NC}" >&2
      expired+=("$latest_commit")
    elif [ "$((expiration_date - today_date))" -le "$warning_threshold" ]; then
      printf "${RED} - EXPIRING SOON${NC}" >&2
      expiring_soon+=("$latest_commit")
    fi
    echo "" >&2
  done

  echo "> found ${#expired[@]} expired and ${#expiring_soon[@]} expiring soon silence(s)" >&2

  for silence in "${expired[@]}"; do
    echo "EXPIRED::$silence"
  done
  for silence in "${expiring_soon[@]}"; do
    echo "EXPIRING_SOON::$silence"
  done
}

function _run () {
    if $DRY_RUN; then
        echo "$*"
    else
        "$@"
    fi
}

report() {
  local file="$1"
  local directory="$2"
  local commit_sha="$3"
  local start_branch="$4"
  local repository_name="$5"
  local mode="${6:-expired}"  # default is expired

  branch_name="clean-$file"

  # Map the git commit author to its github handle using github api
  userGithubHandle="$(gh api "/repos/${repository_name}/commits/${commit_sha}" -q '.author.login')"

  message="${COMMIT_MESSAGE_PREFIX}${file}"

  # Create the git branch
  $DRY_RUN && echo "> dry run active, otherwise would run..."
  _run git checkout --quiet -B "$branch_name" "$start_branch"
  _run git rm --quiet -- "$file"
  if [ -f "$directory/$KUSTOMIZATION_FILENAME" ]; then
    filename="${file##*/}"
    _run "$YQ" -i  'del(.resources[] | select(. == "'"$filename"'"))' "$directory/$KUSTOMIZATION_FILENAME"
    _run git add "$directory/$KUSTOMIZATION_FILENAME"
  fi
  _run git commit --quiet --all --message="${message}"
  _run git push --force-with-lease --quiet --set-upstream origin "$branch_name"

  pr_data="$(gh pr view "$branch_name" --json state,url || echo '{}')"
  pr_status="$(echo "$pr_data" | $YQ e '.state')"
  pr_body="$([[ "$mode" == "expired" ]] && echo "$PULL_REQUEST_BODY_EXPIRED" || echo "$PULL_REQUEST_BODY_SOON")"

  if [[ "$pr_status" == "OPEN" ]]; then
    _run gh pr comment "$branch_name" --body "@${userGithubHandle} $PULL_REQUEST_REMINDER"

    _run gh pr edit "$branch_name" --body "$pr_body"
  else
    _run gh pr create \
      --head "$branch_name" \
      --reviewer "${userGithubHandle}" \
      --assignee "${userGithubHandle}" \
      --title "${message}" \
      --body "$pr_body"

    [[ "$mode" == "expired" ]] && _run gh pr merge --squash --auto "$branch_name" || true
  fi

  _run git checkout --quiet "$start_branch"
}

main() {
  local reporting=false

  args=()
  while test $# -gt 0; do
    case "$1" in
      --dry-run)
        DRY_RUN=true
        echo "> dry_run=$DRY_RUN"
        ;;
      -r|--report)
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
  local expired_raw=()
  mapfile -t expired_raw < <(find_expired "$directory")

  expired=()
  expiring_soon=()
  for line in "${expired_raw[@]}"; do
    type="${line%%::*}"
    data="${line#*::}"
    if [[ "$type" == "EXPIRED" ]]; then
      expired+=("$data")
    elif [[ "$type" == "EXPIRING_SOON" ]]; then
      expiring_soon+=("$data")
    fi
  done

  # Report expired silences via github pull requests
  # 1 pull request is created for each expired silence, and the owner is assigned for review.
  if $reporting; then
    echo
    echo "> reporting expired silences"

    start_branch="$(git branch --show-current)"
    repository_name="${GITHUB_REPOSITORY-}"
    if [[ -z "$repository_name" ]]; then
      repository_name="$(git remote get-url origin --push | sed -n 's#.*:\(.*\)\.git#\1#p')"
    fi

    # Handle expired: auto-merge
    for commit in "${expired[@]}"; do
      file="$(echo "$commit" | $YQ e '.file')"
      commit_sha="$(echo "$commit" | $YQ e '.hash')"
      report "$file" "$directory" "$commit_sha" "$start_branch" "$repository_name" "expired"
    done

    # Handle expiring soon: no auto-merge
    for commit in "${expiring_soon[@]}"; do
      file="$(echo "$commit" | $YQ e '.file')"
      commit_sha="$(echo "$commit" | $YQ e '.hash')"
      report "$file" "$directory" "$commit_sha" "$start_branch" "$repository_name" "soon"
    done
  fi
}

main "$@"
