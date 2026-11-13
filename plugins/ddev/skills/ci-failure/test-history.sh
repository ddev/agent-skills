#!/usr/bin/env bash
# Find every CI failure of one test since a date, across all Buildkite
# pipelines of an org and all GitHub Actions workflows of a repository,
# including failed attempts that a retry or rerun hid behind a pass.
# Usage: test-history.sh TestName YYYY-MM-DD [OWNER/REPO]
# Buildkite needs an authorized `bk` (read_builds, read_build_logs); without
# one, only GitHub is searched. Set BK_ORG for an org other than ddev.
set -euo pipefail

[ $# -ge 2 ] || { echo "Usage: $0 TestName YYYY-MM-DD [OWNER/REPO]" >&2; exit 2; }
test=$1
since=$2
repo=${3:-ddev/ddev}
org=${BK_ORG:-ddev}
case $since in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) echo "Date must be YYYY-MM-DD" >&2; exit 2 ;; esac
command -v jq > /dev/null || { echo "This needs jq." >&2; exit 1; }
out=$HOME/tmp/ci-history-$test
mkdir -p "$out/logs"
tab=$(printf '\t')
esc=$(printf '\033')
bel=$(printf '\007')
cr=$(printf '\r')

clean() {
  LC_ALL=C sed -E "s/${esc}_bk;t=[0-9]+${bel}//g; s/_bk;t=[0-9]+//g; s/${esc}\\[[0-9;]*[A-Za-z]//g; s/^[0-9-]{10}T[0-9:.]+Z //; s/${cr}\$//"
}

# Prints the test's first failing file:line and the error lines after it.
# Buildkite's ddev tests print "--- RUN" for "=== RUN".
first_failure() {
  awk -v t="$test" '
    $0 ~ "(===|---) RUN +" t "([/ ]|$)" { in_test = 1 }
    in_test && !loc && match($0, /[A-Za-z0-9_]+_test\.go:[0-9]+:/) { loc = substr($0, RSTART, RLENGTH - 1); n = 0; next }
    loc && n < 4 && $0 !~ /Error Trace|Received unexpected error:[[:space:]]*$|^[[:space:]]*$/ {
      sub(/^[[:space:]]*(Error:)?[[:space:]]*/, ""); msg = msg (msg ? " | " : "") substr($0, 1, 160); n++ }
    loc && n >= 4 { exit }
    END { print (loc ? loc : "?") "\t" msg }'
}

check_log() { # file, then the fields that describe the job
  local f=$1
  shift
  grep -Eq "(---|\+\+\+) FAIL: $test( |/|$)" "$f" || return 0
  printf '%s\t%s\n' "$(IFS=$tab; echo "$*")" "$(clean < "$f" | first_failure)"
}

buildkite() {
  if ! command -v bk > /dev/null || ! bk api "/pipelines?per_page=1" > /dev/null 2>&1; then
    echo "Skipping Buildkite: \`bk\` is missing or not authorized. Run \`bk auth login\`." >&2
    return 0
  fi
  # bk api adds /organizations/<org> itself. Page until empty, because the
  # list has no total.
  : > "$out/bk-jobs.tsv"
  page=1
  while :; do
    bk api "/builds?created_from=${since}T00:00:00Z&per_page=100&page=$page" > "$out/bk-page.json"
    [ "$(jq length "$out/bk-page.json")" -gt 0 ] || break
    # A retried job is left out of its build's jobs. Only its replacement's
    # retry_source names it, so a build that passed on retry still counts.
    jq -r '.[] as $b | $b.jobs[]? |
      (select(.type == "script" and .state == "failed") | .id),
      (.retry_source.job_id // empty)
      | [$b.pipeline.slug, $b.number, $b.branch, $b.created_at[0:10], $b.state, .] | @tsv' \
      "$out/bk-page.json" >> "$out/bk-jobs.tsv"
    page=$((page + 1))
  done
  sort -u "$out/bk-jobs.tsv" | while IFS=$tab read -r pipeline n branch date state job; do
    f=$out/logs/$job.log
    [ -s "$f" ] || bk api "/pipelines/$pipeline/builds/$n/jobs/$job/log" 2> /dev/null | jq -r '.content // empty' > "$f"
    check_log "$f" "$date" "buildkite/$pipeline" "build $n ($state)" "$branch" \
      "https://buildkite.com/$org/$pipeline/builds/$n#$job"
  done
}

# A run that passed on a rerun has run_attempt > 1 and shows only its last
# attempt, so read the jobs of every attempt.
github() {
  gh api --paginate "repos/$repo/actions/runs?created=%3E%3D$since&per_page=100" \
    --jq '.workflow_runs[] | select(.conclusion == "failure" or .run_attempt > 1)
      | [.id, .run_attempt, .name, .head_branch, .created_at[0:10], .conclusion // .status] | @tsv' |
    while IFS=$tab read -r run attempts name branch date result; do
      a=1
      while [ "$a" -le "$attempts" ]; do
        gh api "repos/$repo/actions/runs/$run/attempts/$a/jobs?per_page=100" \
          --jq '.jobs[] | select(.conclusion == "failure") | .id' | while read -r job; do
          f=$out/logs/$job.log
          [ -s "$f" ] || gh api "repos/$repo/actions/jobs/$job/logs" > "$f" 2> /dev/null || continue
          check_log "$f" "$date" "$name" "attempt $a of $attempts ($result)" "$branch" \
            "https://github.com/$repo/actions/runs/$run/job/$job"
        done
        a=$((a + 1))
      done
    done
}

echo "# $test failures since $since: date, workflow, run, branch, url, location, error"
{ buildkite; github; } | sort
echo "Logs: $out/logs"
