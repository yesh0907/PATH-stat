#!/usr/bin/env bash
# Decide how this CI run proceeds and write the result to $GITHUB_OUTPUT:
#   disposition  full | docs | reuse
#   tree         exact Git tree SHA of the checked-out HEAD
#   reuse_run_id / reuse_url   only for a verified "reuse"
#
# full   run everything (default; any doubt, API error or mismatch ends up here)
# docs   documentation-only diff: skip the macOS jobs
# reuse  push to main that landed exactly one merged same-repo PR whose last CI run passed on
#        this exact tree (proved by that run's pathstat-tested-tree-<attempt> artifact)
#
# Runs on Linux in the `plan` job only; it is the only place that gets API read permissions.
# API data is parsed with jq and validated against strict patterns, never evaluated by a shell.
# GitHub context comes from the standard runner environment and GITHUB_EVENT_PATH.
set -euo pipefail

main=main
sha_re='^[0-9a-f]{40}$'
num_re='^[1-9][0-9]{0,17}$'

tree=$(git rev-parse 'HEAD^{tree}')
[[ $tree =~ $sha_re ]] || { echo "::error::Unexpected tree id"; exit 1; }

finish() { # disposition [run id]
  local url=
  [[ -n ${2:-} ]] && url="${GITHUB_SERVER_URL:-https://github.com}/$GITHUB_REPOSITORY/actions/runs/$2"
  {
    echo "disposition=$1"
    echo "tree=$tree"
    echo "reuse_run_id=${2:-}"
    echo "reuse_url=$url"
  } >> "$GITHUB_OUTPUT"
  echo "CI disposition: $1${2:+ (reusing run $2)}"
  exit 0
}

note() { echo "Full run: $1"; }

api() { timeout 15s gh api "repos/$GITHUB_REPOSITORY/$1" 2>/dev/null; }

# Prints the PR number, final head SHA and head branch for an unambiguous PR merge.
landed_pr() {
  local prs
  prs=$(api "commits/$GITHUB_SHA/pulls?per_page=100") \
    || { note "pull request lookup failed"; return 1; }
  jq -er --arg repo "$GITHUB_REPOSITORY" --arg sha "$GITHUB_SHA" --arg base "$main" '
    select(length < 100)
    | [.[] | select(.state == "closed" and .merged_at != null and .merge_commit_sha == $sha
        and .base.ref == $base and .base.repo.full_name == $repo and .head.repo.full_name == $repo)]
    | select(length == 1) | .[0] | [.number, .head.sha, .head.ref] | @tsv' <<< "$prs"
}

# Sets run_id on success. Check explicitly because errexit is off inside `if`.
try_reuse() {
  local pr=$1 head=$2 head_branch=$3 runs run_json attempt jobs name arts proof_id proof
  runs=$(api "actions/workflows/ci.yml/runs?event=pull_request&head_sha=$head&per_page=100") \
    || { note "workflow run lookup failed"; return 1; }
  # GitHub can omit PR associations after merge. Keep those candidates in the
  # ordered lookup so a newer failed run still blocks reuse. The proof must name
  # the merged PR before a run with no association can be reused.
  run_json=$(jq -c --arg repo "$GITHUB_REPOSITORY" --arg head "$head" \
    --arg branch "$head_branch" --argjson pr "$pr" '
    select(.total_count <= 100)
    | [.workflow_runs[] | select(((.path // "") | split("@")[0]) == ".github/workflows/ci.yml"
        and .event == "pull_request" and .head_sha == $head and .head_branch == $branch
        and .repository.full_name == $repo and .head_repository.full_name == $repo
        and (.pull_requests | type == "array" and (length == 0 or any(.[]; .number == $pr))))]
    | max_by(.run_number) // empty | select(.status == "completed" and .conclusion == "success")
    | {id, run_attempt}' <<< "$runs" 2>/dev/null) \
    || { note "workflow run response unusable"; return 1; }
  run_id=$(jq -r '.id // empty' <<< "$run_json" 2>/dev/null) || run_id=
  attempt=$(jq -r '.run_attempt // empty' <<< "$run_json" 2>/dev/null) || attempt=
  [[ $run_id =~ $num_re && $attempt =~ $num_re ]] \
    || { run_id=; note "no successful CI run for the final PR head"; return 1; }

  # A failed-job rerun can keep successful jobs from older attempts. Use the last
  # execution of each required job and reject a partial API page.
  jobs=$(api "actions/runs/$run_id/jobs?filter=all&per_page=100") \
    || { note "job lookup failed"; return 1; }
  jq -e --arg shards "$CI_SHARDS" --argjson run "$run_id" '
    select(.total_count == (.jobs | length) and .total_count <= 100)
    | (.jobs | map(select(.run_id == $run)) | group_by(.name) | map(max_by(.id))
        | map(select(.status == "completed" and .conclusion == "success").name)) as $passed
    | (["PATHKit package tests", "App build and simulator tests"]
        + ($shards | split(" ") | map("Simulator tests (\(.))"))) - $passed == []' <<< "$jobs" >/dev/null \
    || { note "successful package and simulator jobs could not be verified"; return 1; }

  name="pathstat-tested-tree-$attempt"
  arts=$(api "actions/runs/$run_id/artifacts?per_page=100") \
    || { note "artifact lookup failed"; return 1; }
  local aggregate_id
  read -r proof_id aggregate_id < <(jq -er --arg name "$name" '
    select(.total_count == (.artifacts | length) and .total_count <= 100)
    | .artifacts as $artifacts
    | def current($name):
        [$artifacts[] | select(.name == $name)] | select(length == 1)
        | .[0] | select(.expired == false);
      [ (current($name) | select(.size_in_bytes > 0 and .size_in_bytes <= 4096).id),
        (current("pathstat-test-results") | select(.size_in_bytes > 0).id) ]
    | select(length == 2) | @tsv' <<< "$arts") \
    || { note "proof or aggregate metadata is incomplete"; return 1; }
  [[ $proof_id =~ $num_re && $aggregate_id =~ $num_re ]] \
    || { note "proof or aggregate artifact is missing or expired"; return 1; }

  # Read the specific proof artifact, without extracting any paths from it.
  local workdir
  workdir=$(mktemp -d) || return 1
  api "actions/artifacts/$proof_id/zip" | head -c 4097 > "$workdir/proof.zip" \
    || { rm -rf -- "$workdir"; note "proof download failed"; return 1; }
  proof=$(unzip -p "$workdir/proof.zip" proof.json 2>/dev/null | head -c 4097) || proof=
  rm -rf -- "$workdir"
  [[ ${#proof} -le 4096 ]] && jq -es --arg tree "$tree" --arg head "$head" \
    --arg repo "$GITHUB_REPOSITORY" --arg base "$main" --argjson pr "$pr" --argjson run "$run_id" \
    --argjson attempt "$attempt" --argjson aggregate "$aggregate_id" '
    length == 1 and (.[0] | .schema == 1 and .tree == $tree and .head_sha == $head
      and .repository == $repo and .base_ref == $base and .pull_request == $pr
      and .run_id == $run and .run_attempt == $attempt and .aggregate_id == $aggregate)' \
    <<< "$proof" >/dev/null 2>&1 \
    || { note "proof does not match this tree, attempt and aggregate"; return 1; }
}

# Rename detection is off so moving source into docs still runs the suite.
docs_only() {
  git diff --quiet --no-renames "$1" HEAD -- . \
    ':(top,glob,exclude)*.md' ':(top,exclude)docs/' ':(top,exclude)screenshots/'
}

case "$GITHUB_EVENT_NAME" in
  pull_request)
    if jq -e --arg repo "$GITHUB_REPOSITORY" \
      '.pull_request.head.repo.full_name == $repo' "$GITHUB_EVENT_PATH" >/dev/null \
      && docs_only HEAD^1; then
      finish docs
    fi
    ;;
  push)
    before=$(jq -er 'select(.forced == false and .created == false and .deleted == false) | .before' \
      "$GITHUB_EVENT_PATH") || finish full
    if [[ $GITHUB_REF == "refs/heads/$main" && $before =~ $sha_re \
      && $(git rev-parse HEAD) == "$GITHUB_SHA" && $(git rev-parse HEAD^1 2>/dev/null) == "$before" ]]; then
      pair=$(landed_pr) || finish full
      IFS=$'\t' read -r pr head head_branch <<< "$pair"
      if [[ $pr =~ $num_re && $head =~ $sha_re ]]; then
        if docs_only "$before"; then finish docs; else [[ $? == 1 ]] || finish full; fi
        if git check-ref-format "refs/heads/$head_branch" && try_reuse "$pr" "$head" "$head_branch"; then
          finish reuse "$run_id"
        fi
      fi
    fi
    ;;
esac
finish full
