#!/usr/bin/env bash
# Fetch the failed jobs of a GitHub Actions run or a public Buildkite build:
# each log, its first error lines, and how the same job did in recent runs,
# to tell a regression from an intermittent failure.
# Usage: failed-job.sh https://github.com/OWNER/REPO/actions/runs/RUN[/job/JOB|/attempts/N]
#        failed-job.sh https://buildkite.com/ORG/PIPELINE/builds/N[#JOB-UUID]
# shellcheck disable=SC2016 # the $ in the GraphQL query is not shell
set -euo pipefail

usage() {
  echo "Usage: $0 https://github.com/OWNER/REPO/actions/runs/RUN[/job/JOB|/attempts/N]" >&2
  echo "       $0 https://buildkite.com/ORG/PIPELINE/builds/N[#JOB-UUID]" >&2
  exit 2
}
[ $# -eq 1 ] || usage
url=$1

esc=$(printf '\033')
bel=$(printf '\007')
cr=$(printf '\r')
tab=$(printf '\t')
# Strips ANSI colors, Buildkite's _bk;t= markers, Actions timestamps and CRs.
clean() {
  LC_ALL=C sed -E "s/${esc}_bk;t=[0-9]+${bel}//g; s/${esc}\\[[0-9;]*[A-Za-z]//g; s/^[0-9-]{10}T[0-9:.]+Z //; s/${cr}\$//"
}
first_errors() {
  echo "log: $1 ($(wc -l < "$1" | tr -d ' ') lines)"
  echo "first error lines:"
  grep -n -E -m 15 '##\[error\]|(---|\+\+\+) FAIL|^(not ok|FAIL)|panic:|[Ee]rror:|fatal:|timed out' "$1" |
    cut -c1-200 | sed 's/^/  /' || echo "  none matched; read the failed step"
}

github() {
  path=${url#*github.com/}
  path=${path%%[?#]*}
  IFS=/ read -r owner name actions runs run kind id _ <<EOF
$path
EOF
  [ "$actions/$runs" = "actions/runs" ] || usage
  case $run in '' | *[!0-9]*) usage ;; esac
  case $kind:$id in : | job:[0-9]* | attempts:[0-9]*) ;; *) usage ;; esac
  case $id in *[!0-9]*) usage ;; esac
  repo=$owner/$name
  out=$HOME/tmp/ci-$name-$run
  # Newer gh refuses to print a log with colors without this flag, which
  # older gh doesn't know.
  raw=''
  gh api --help | grep -- --allow-escape-sequences > /dev/null && raw=--allow-escape-sequences
  mkdir -p "$out"

  { read -r workflow attempt; cat; } < <(gh api "repos/$repo/actions/runs/$run" --jq '
    "\(.workflow_id) \(.run_attempt)",
    "# Run \(.id) \"\(.name)\", attempt \(.run_attempt): \(.conclusion // .status)",
    "\(.event) on \(.head_branch) at \(.head_sha[0:9])"
      + ([.pull_requests[].number | "#\(.)"] | if length > 0 then ", PR " + join(", ") else "" end),
    .html_url')

  # The job the URL names, from any attempt, or the failed jobs of one attempt.
  if [ "$kind" = job ]; then
    filter=".id == $id"
  else
    attempt=${id:-$attempt}
    filter=".run_attempt == $attempt and (.conclusion == \"failure\" or .conclusion == \"timed_out\")"
  fi
  gh api --paginate "repos/$repo/actions/runs/$run/jobs?filter=all&per_page=100" --jq ".jobs[] | select($filter)
    | [.id, .name, .run_attempt, .conclusion // .status, .html_url,
       ([.steps[]? | select(.conclusion == \"failure\") | .name] | join(\", \"))] | @tsv" > "$out/jobs.tsv"
  if [ ! -s "$out/jobs.tsv" ]; then
    echo
    echo "No failed jobs in attempt $attempt."
    [ "$attempt" -gt 1 ] && echo "The attempt before it: https://github.com/$repo/actions/runs/$run/attempts/$((attempt - 1))"
    exit 0
  fi

  # The same workflow's last 15 runs on any branch, one line per job. A job
  # shows its latest attempt, so note when the run needed a rerun.
  gh api "repos/$repo/actions/workflows/$workflow/runs?per_page=15" \
    --jq '.workflow_runs[] | [.id, .created_at[0:10], .head_branch, .head_sha[0:9], .html_url, .run_attempt] | @tsv' |
    while IFS=$tab read -r rid date branch sha rurl tries; do
      gh api "repos/$repo/actions/runs/$rid/jobs?per_page=100" \
        --jq '.jobs[] | [.name, .conclusion // .status] | @tsv' |
        while IFS=$tab read -r jname result; do
          [ "$tries" -gt 1 ] && result="$result, attempt $tries"
          printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$jname" "$date" "$result" "$branch" "$sha" "$rurl"
        done
    done > "$out/history.tsv"

  while IFS=$tab read -r j jname jattempt result jurl steps; do
    printf '\n## Job %s "%s", attempt %s: %s\nfailed steps: %s\n%s\n' "$j" "$jname" "$jattempt" "$result" "$steps" "$jurl"
    # A job's ID is also its check run's, whose annotations name failures
    # that leave no log, such as a lost runner.
    gh api "repos/$repo/check-runs/$j/annotations" \
      --jq '.[] | select(.annotation_level == "failure") | "annotation: \(.message)"'
    if gh api ${raw:+"$raw"} "repos/$repo/actions/jobs/$j/logs" > "$out/$j.raw.log"; then
      clean < "$out/$j.raw.log" > "$out/$j.log"
      first_errors "$out/$j.log"
    else
      echo "no log; gh printed why"
    fi
    echo "this job in the last 15 runs, newest first:"
    awk -F'\t' -v n="$jname" '$1 == n { printf "  %s %-20s %s %s %s\n", $2, $3, $4, $5, $6 }' "$out/history.tsv"
  done < "$out/jobs.tsv"
}

# Public Buildkite pipelines, such as DDEV's, need no token. Its JSON has no
# GitHub API to parse it, so this part needs jq.
buildkite() {
  command -v jq > /dev/null || { echo "Reading a Buildkite build needs jq." >&2; exit 1; }
  path=${url#*buildkite.com/}
  job=
  case $path in *'#'*) job=${path#*#} ;; esac
  job=${job%%/*}
  path=${path%%[?#]*}
  IFS=/ read -r org pipeline builds n _ <<EOF
$path
EOF
  [ "$builds" = "builds" ] || usage
  case $n in '' | *[!0-9]*) usage ;; esac
  out=$HOME/tmp/ci-$pipeline-$n
  mkdir -p "$out"

  base=https://buildkite.com/$org/$pipeline/builds/$n
  if ! curl -fsS "$base.json" -o "$out/build.json" 2> /dev/null; then
    echo "Can't read $base without signing in. If it is private, run \`bk auth login\`," >&2
    echo "then \`bk build view $n --pipeline $pipeline --org $org\` and \`bk job log <job-uuid> --org $org --no-timestamps\`." >&2
    exit 1
  fi
  curl -fsS "$base/data/jobs" -o "$out/jobs.json"

  jq -r --arg url "$base" '
    "# Build \(.number) \(.pipeline.name): \(.state)",
    "\(.branch_name) at \(.commit_id[0:9])" + (if .pull_request then ", PR #\(.pull_request.id)" else "" end),
    $url' "$out/build.json"

  if [ -z "$job" ]; then
    job=$(jq -r '.records[] | select(.type == "script" and .passed == false and .retried_in_job_uuid == null) | .id' "$out/jobs.json")
    [ -n "$job" ] || { echo; echo "No failed jobs."; exit 0; }
  fi

  for j in $job; do
    echo
    jq -r --arg j "$j" '.records[] | select(.id == $j)
      | "## Job \(.id) \"\(.name // .step_key // "")\" on \(.agent_hostname // "?"): \(.state), exit \(.exit_status)"
        + (if .retries_count > 0 then ", retried \(.retries_count)x" else "" end)' "$out/jobs.json"
    curl -fsS -L "https://buildkite.com/organizations/$org/pipelines/$pipeline/builds/$n/jobs/$j/download.txt" \
      -o "$out/$j.raw.log"
    clean < "$out/$j.raw.log" > "$out/$j.log"
    first_errors "$out/$j.log"
  done

  # Buildkite has no public build list, but it posts a commit status named
  # buildkite/<pipeline> to GitHub, so read the history from there.
  gh_repo=$(jq -r '.pipeline.provider.url // "" | sub("^https://github.com/"; "")' "$out/build.json")
  [ -n "$gh_repo" ] || return 0
  echo
  echo "buildkite/$pipeline on the last 15 commits of $gh_repo's default branch, newest first, where it ran:"
  gh api graphql -F owner="${gh_repo%%/*}" -F name="${gh_repo#*/}" -F context="buildkite/$pipeline" -f query='
query($owner: String!, $name: String!, $context: String!) {
  repository(owner: $owner, name: $name) { defaultBranchRef { target { ... on Commit {
    history(first: 15) { nodes { oid committedDate status { context(name: $context) { state targetUrl } } } } } } } }
}' --jq '.data.repository.defaultBranchRef.target.history.nodes[] | select(.status.context)
    | "  \(.committedDate[0:10]) \(.status.context.state | ascii_downcase) \(.oid[0:9]) \(.status.context.targetUrl)"'
}

case $url in
  https://github.com/*) github ;;
  https://buildkite.com/*) buildkite ;;
  *) usage ;;
esac
