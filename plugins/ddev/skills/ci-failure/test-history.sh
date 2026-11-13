#!/usr/bin/env bash
# Find every CI failure of one test since a date, across all Buildkite
# pipelines of an org and all GitHub Actions workflows of a repository,
# including failed attempts that a retry or rerun hid behind a pass.
# Usage: test-history.sh TestName YYYY-MM-DD [OWNER/REPO]
# Buildkite needs an authorized `bk` (read_builds, read_build_logs), and
# GitHub a signed-in `gh`. A side without one is skipped with a message that
# says how to fix it. Set BK_ORG for an org other than ddev.
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
# Logs that couldn't be downloaded, so a failure in them isn't missed.
: > "$out/unread.tsv"
tab=$(printf '\t')
esc=$(printf '\033')
bel=$(printf '\007')
cr=$(printf '\r')

clean() {
  LC_ALL=C sed -E "s/${esc}_bk;t=[0-9]+${bel}//g; s/_bk;t=[0-9]+//g; s/${esc}\\[[0-9;]*[A-Za-z]//g; s/^[0-9-]{10}T[0-9:.]+Z //; s/${cr}+\$//"
}

# Prints the test's first failing file:line and its message: the text after
# file:line, and the indented lines that follow it, such as testify's
# "Error:" block, leaving out its "Error Trace:" and "Test:" fields.
# Buildkite's ddev tests print "--- RUN" for "=== RUN".
first_failure() {
  awk -v t="$test" '
    function add(s) { if (s != "" && n < 4) { msg = msg (msg ? " | " : "") substr(s, 1, 160); n++ } }
    $0 ~ "(===|---) RUN +" t "([/ ]|$)" { in_test = 1 }
    in_test && !loc && match($0, /[A-Za-z0-9_]+_test\.go:[0-9]+:/) {
      loc = substr($0, RSTART, RLENGTH - 1)
      rest = substr($0, RSTART + RLENGTH); sub(/^[[:space:]]+/, "", rest); add(rest)
      next }
    loc && $0 !~ /^[[:space:]]/ { exit }
    loc && /^[[:space:]]*(Error Trace|Test):/ { next }
    loc { s = $0; sub(/^[[:space:]]*(Error:|Messages:)?[[:space:]]*/, "", s)
      if (s !~ /^Received unexpected error:$/) add(s) }
    END { print (loc ? loc : "?") "\t" msg }'
}

check_log() { # file, then the fields that describe the job
  local f=$1
  shift
  grep -Eq "(---|\+\+\+) FAIL: $test( |/|$)" "$f" || return 0
  printf '%s\t%s\n' "$(IFS=$tab; echo "$*")" "$(clean < "$f" | first_failure)"
}

buildkite() {
  if ! command -v bk > /dev/null; then
    echo "Skipping Buildkite: the Buildkite CLI \`bk\` is not installed. See https://github.com/buildkite/cli." >&2
    return 0
  fi
  if ! bk api --org "$org" "/pipelines?per_page=1" > /dev/null 2>&1; then
    echo "Skipping Buildkite: \`bk\` is not authorized for $org. Run \`bk auth login --org=$org --token=<token>\`" >&2
    echo "with a token that has read_builds and read_build_logs, or \`bk auth login --org=$org\` to sign in." >&2
    return 0
  fi
  # bk api adds /organizations/<org> itself. Page until empty, because the
  # list has no total.
  : > "$out/bk-jobs.tsv"
  page=1
  while :; do
    bk api --org "$org" "/builds?created_from=${since}T00:00:00Z&per_page=100&page=$page" > "$out/bk-page.json"
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
    url="https://buildkite.com/$org/$pipeline/builds/$n#$job"
    # Keep a log only when it downloaded, so a later run retries it.
    if [ ! -f "$f" ] && ! { bk api --org "$org" "/pipelines/$pipeline/builds/$n/jobs/$job/log" 2> /dev/null |
      jq -r '.content // empty' > "$f.part" && mv "$f.part" "$f"; }; then
      rm -f "$f.part"
      printf '%s\t%s\t%s\n' "$date" "buildkite/$pipeline" "$url" >> "$out/unread.tsv"
      continue
    fi
    check_log "$f" "$date" "buildkite/$pipeline" "build $n ($state)" "$branch" "$url"
  done
}

# A run that passed on a rerun has run_attempt > 1 and shows only its last
# attempt, so read the jobs of every attempt.
github() {
  if ! command -v gh > /dev/null; then
    echo "Skipping GitHub: the GitHub CLI \`gh\` is not installed. See https://cli.github.com." >&2
    return 0
  fi
  if ! gh auth status > /dev/null 2>&1; then
    echo "Skipping GitHub: \`gh\` is not signed in. Run \`gh auth login\`." >&2
    return 0
  fi
  # Newer gh refuses to print a log with colors without this flag, which
  # older gh doesn't know.
  raw=''
  gh api --help | grep -- --allow-escape-sequences > /dev/null && raw=--allow-escape-sequences
  # A filtered run list stops at 1000 runs, so ask for one day at a time.
  jq -rn --arg s "$since" '($s + "T00:00:00Z" | fromdate) as $a | range($a; now; 86400) | strftime("%Y-%m-%d")' |
    while read -r day; do
      gh api --paginate "repos/$repo/actions/runs?created=$day&per_page=100" \
        --jq '.workflow_runs[] | select(.conclusion == "failure" or .run_attempt > 1)
          | [.id, .run_attempt, .name, .head_branch, .created_at[0:10], .conclusion // .status] | @tsv'
    done |
    while IFS=$tab read -r run attempts name branch date result; do
      a=1
      while [ "$a" -le "$attempts" ]; do
        gh api "repos/$repo/actions/runs/$run/attempts/$a/jobs?per_page=100" \
          --jq '.jobs[] | select(.conclusion == "failure" or .conclusion == "timed_out") | .id' | while read -r job; do
          f=$out/logs/$job.log
          url="https://github.com/$repo/actions/runs/$run/job/$job"
          # gh writes an error page to stdout too. GitHub loses some logs,
          # mostly of earlier attempts, that its web page still shows.
          if [ ! -f "$f" ] && ! { gh api ${raw:+"$raw"} "repos/$repo/actions/jobs/$job/logs" > "$f.part" 2> /dev/null &&
            mv "$f.part" "$f"; }; then
            rm -f "$f.part"
            printf '%s\t%s\t%s\n' "$date" "$name" "$url" >> "$out/unread.tsv"
            continue
          fi
          check_log "$f" "$date" "$name" "attempt $a of $attempts ($result)" "$branch" "$url"
        done
        a=$((a + 1))
      done
    done
}

echo "# $test failures since $since: date, workflow, run, branch, url, location, error"
{ buildkite; github; } | sort
if [ -s "$out/unread.tsv" ]; then
  echo "# Logs that couldn't be downloaded, which may hide more failures. Open them in a browser: date, workflow, url"
  sort -u "$out/unread.tsv"
fi
echo "Logs: $out/logs"
