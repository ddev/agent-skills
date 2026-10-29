#!/usr/bin/env bash
# Fetch the failed jobs of a GitHub Actions run or a public Buildkite build:
# each log, its first error lines, and how the same job did in recent runs,
# to tell a regression from an intermittent failure.
# Usage: failed-job.sh https://github.com/OWNER/REPO/actions/runs/RUN[/job/JOB]
#        failed-job.sh https://buildkite.com/ORG/PIPELINE/builds/N[#JOB-UUID]
set -euo pipefail

usage() {
  echo "Usage: $0 https://github.com/OWNER/REPO/actions/runs/RUN[/job/JOB]" >&2
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
  IFS=/ read -r owner name actions runs run _ job _ <<EOF
$path
EOF
  [ "$actions/$runs" = "actions/runs" ] || usage
  case $run in '' | *[!0-9]*) usage ;; esac
  case ${job:-0} in *[!0-9]*) usage ;; esac
  repo=$owner/$name
  out=$HOME/tmp/ci-$name-$run
  mkdir -p "$out"

  gh api "repos/$repo/actions/runs/$run" --jq '
    "# Run \(.id) \"\(.name)\", attempt \(.run_attempt): \(.conclusion // .status)",
    "\(.event) on \(.head_branch) at \(.head_sha[0:9])"
      + ([.pull_requests[].number | "#\(.)"] | if length > 0 then ", PR " + join(", ") else "" end),
    .html_url'
  read -r workflow attempt <<EOF
$(gh api "repos/$repo/actions/runs/$run" --jq '"\(.workflow_id) \(.run_attempt)"')
EOF

  if [ -n "${job:-}" ]; then
    jobs=$job
  else
    jobs=$(gh api "repos/$repo/actions/runs/$run/jobs?per_page=100" \
      --jq '.jobs[] | select(.conclusion == "failure" or .conclusion == "timed_out") | .id')
    if [ -z "$jobs" ]; then
      echo
      echo "No failed jobs in attempt $attempt."
      [ "$attempt" -gt 1 ] && echo "It passed after a rerun. Pass a /job/ URL from an earlier attempt to see that failure."
      exit 0
    fi
  fi

  # The same workflow's last 15 runs on any branch, one line per job. A job
  # shows its latest attempt, so note when the run needed a rerun.
  gh api "repos/$repo/actions/workflows/$workflow/runs?per_page=15" \
    --jq '.workflow_runs[] | "\(.id)\t\(.created_at[0:10])\t\(.head_branch)\t\(.head_sha[0:9])\t\(.html_url)\t\(.run_attempt)"' |
    while IFS=$tab read -r id date branch sha rurl tries; do
      gh api "repos/$repo/actions/runs/$id/jobs?per_page=100" \
        --jq '.jobs[] | "\(.name)\t\(.conclusion // .status)"' |
        while IFS=$tab read -r jname result; do
          [ "$tries" -gt 1 ] && result="$result, attempt $tries"
          printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$jname" "$date" "$result" "$branch" "$sha" "$rurl"
        done
    done > "$out/history.tsv"

  for j in $jobs; do
    echo
    gh api "repos/$repo/actions/jobs/$j" --jq '
      "## Job \(.id) \"\(.name)\", attempt \(.run_attempt): \(.conclusion // .status)",
      "failed steps: \([.steps[]? | select(.conclusion == "failure") | .name] | join(", "))",
      .html_url'
    jname=$(gh api "repos/$repo/actions/jobs/$j" --jq .name)
    gh api --allow-escape-sequences "repos/$repo/actions/jobs/$j/logs" > "$out/$j.raw.log"
    clean < "$out/$j.raw.log" > "$out/$j.log"
    first_errors "$out/$j.log"
    echo "this job in the last 15 runs, newest first:"
    awk -F'\t' -v n="$jname" '$1 == n { printf "  %s %-20s %s %s %s\n", $2, $3, $4, $5, $6 }' "$out/history.tsv"
  done
}

# Public Buildkite pipelines, such as DDEV's, need no token. Its JSON has no
# GitHub API to parse it, so this part needs jq.
buildkite() {
  command -v jq > /dev/null || { echo "Reading a Buildkite build needs jq." >&2; exit 1; }
  path=${url#*buildkite.com/}
  job=
  case $path in *'#'*) job=${path#*#} ;; esac
  path=${path%%[?#]*}
  IFS=/ read -r org pipeline builds n _ <<EOF
$path
EOF
  [ "$builds" = "builds" ] || usage
  case $n in '' | *[!0-9]*) usage ;; esac
  job=${job%%/*}
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
  gh_repo=$(jq -r '.pipeline.provider.url // "" | sub("^https://github.com/"; "")' "$out/build.json")

  if [ -z "$job" ]; then
    job=$(jq -r '.records[] | select(.type == "script" and .passed == false and .retried_in_job_uuid == null) | .id' "$out/jobs.json")
    [ -n "$job" ] || { echo; echo "No failed jobs."; exit 0; }
  fi

  # Buildkite has no public build list, but it posts a commit status named
  # buildkite/<pipeline> to GitHub, so read the history from there.
  if [ -n "$gh_repo" ]; then
    branch=$(gh api "repos/$gh_repo" --jq .default_branch)
    gh api "repos/$gh_repo/commits?sha=$branch&per_page=15" \
      --jq '.[] | "\(.sha)\t\(.commit.committer.date[0:10])"' |
      while IFS=$tab read -r sha date; do
        gh api "repos/$gh_repo/commits/$sha/status?per_page=100" \
          --jq '.statuses[] | "\(.context)\t\(.state)\t\(.target_url)"' |
          awk -F'\t' -v c="buildkite/$pipeline" -v d="$date" -v s="${sha:0:9}" \
            '$1 == c { printf "  %s %-8s %s %s\n", d, $2, s, $3 }'
      done > "$out/history.txt"
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

  if [ -s "$out/history.txt" ]; then
    echo
    echo "buildkite/$pipeline on the last 15 commits of $gh_repo $branch, newest first, where it ran:"
    cat "$out/history.txt"
  fi
}

case $url in
  https://github.com/*) github ;;
  https://buildkite.com/*) buildkite ;;
  *) usage ;;
esac
