#!/usr/bin/env bash
# Print everything a review needs about a PR: metadata, commits, files,
# checks, comments, reviews, threads, and closing issues with their comments.
# Uses one GraphQL request, or REST requests where gh has no GraphQL, as in
# Claude Code cloud and self-hosted sessions. Usage: pr-context.sh N [owner/repo]
# shellcheck disable=SC2016 # the $ in the GraphQL query and jq filter is not shell
set -euo pipefail

n=${1:?usage: pr-context.sh N [owner/repo]}
repo=${2:-'{owner}/{repo}'}
owner=${repo%%/*}
name=${repo#*/}

graphql() {
gh api graphql -F owner="$owner" -F name="$name" -F n="$n" -f query='
query($owner: String!, $name: String!, $n: Int!) {
  viewer { login }
  repository(owner: $owner, name: $name) {
    pullRequest(number: $n) {
      number title url state isDraft author { login } authorAssociation
      baseRefName baseRefOid headRefName headRefOid
      headRepository { nameWithOwner }
      body
      files(first: 100) { totalCount nodes { path additions deletions } }
      commits(first: 100) { totalCount nodes { commit { oid messageHeadline messageBody } } }
      head: commits(last: 1) { nodes { commit { statusCheckRollup { state
        contexts(first: 100) { nodes {
          ... on CheckRun { name status conclusion detailsUrl }
          ... on StatusContext { context state targetUrl }
        } } } } } }
      closingIssuesReferences(first: 10) { nodes { number title url body
        comments(first: 100) { totalCount nodes { author { login } createdAt body } } } }
      comments(first: 100) { totalCount nodes { author { login } createdAt body } }
      reviews(first: 100) { totalCount nodes { id author { login } state submittedAt commit { oid } body } }
      reviewThreads(first: 100) { totalCount nodes { isResolved isOutdated path line
        comments(first: 50) { totalCount nodes { author { login } createdAt body } } } }
    }
  }
}' --jq '
def more(c; what): if c.totalCount > (c.nodes | length) then "!! only \(c.nodes | length) of \(c.totalCount) \(what) shown\n" else "" end;
def who: .author.login // "ghost";
.data.viewer.login as $me
| .data.repository.pullRequest as $p
| "# #\($p.number) \($p.title)\n\($p.url)\nstate=\($p.state) draft=\($p.isDraft) author=\($p | who) association=\($p.authorAssociation) viewer=\($me)\nbase=\($p.baseRefName) \($p.baseRefOid)\nhead=\($p.headRepository.nameWithOwner // "?"):\($p.headRefName) \($p.headRefOid)\n\n## Body\n\($p.body)\n"
, "## Commits\n" + more($p.commits; "commits") + ([$p.commits.nodes[].commit | "- \(.oid[0:9]) \(.messageHeadline)" + (if .messageBody != "" then "\n\(.messageBody | gsub("\n"; "\n  ") | "  " + .)" else "" end)] | join("\n")) + "\n"
, "## Files\n" + more($p.files; "files") + ([$p.files.nodes[] | "- \(.path) +\(.additions) -\(.deletions)"] | join("\n")) + "\n"
, "## Checks: \($p.head.nodes[0].commit.statusCheckRollup.state // "none")\n" + ([$p.head.nodes[0].commit.statusCheckRollup.contexts.nodes[]? | select((.conclusion // .state // .status) as $s | $s != "SUCCESS" and $s != "SKIPPED" and $s != "NEUTRAL") | "- \(.name // .context): \(.conclusion // .state // .status) \(.detailsUrl // .targetUrl)"] | join("\n")) + "\n"
, ($p.closingIssuesReferences.nodes[] | "## Issue #\(.number) \(.title)\n\(.url)\n\(.body)\n" + more(.comments; "comments") + ([.comments.nodes[] | "--- \(who) \(.createdAt)\n\(.body)"] | join("\n")) + "\n")
, "## PR comments\n" + more($p.comments; "comments") + ([$p.comments.nodes[] | select(.body | startswith("<!-- bot:") | not) | "--- \(who) \(.createdAt)\n\(.body)"] | join("\n")) + "\n"
, "## Reviews\n" + more($p.reviews; "reviews") + ([$p.reviews.nodes[] | "--- \(who) \(.state) id=\(.id) commit=\(.commit.oid[0:9]) \(.submittedAt // "")\n\(.body)"] | join("\n")) + "\n"
, "## Threads\n" + more($p.reviewThreads; "threads") + ([$p.reviewThreads.nodes[] | "--- \(.path):\(.line // "?") resolved=\(.isResolved) outdated=\(.isOutdated)\n" + more(.comments; "comments") + ([.comments.nodes[] | "  [\(who)] \(.body | gsub("\n"; "\n  "))"] | join("\n"))] | join("\n"))
'
}

# The same sections from REST. Thread resolution comes from Claude Code's
# ccr/review_threads route where it exists, and closing issues from closing
# keywords in the body, since REST has neither.
rest() {
  local p="repos/$repo" head i
  d=$(mktemp -d "${TMPDIR:-/tmp}/pr-context.XXXXXX")
  trap 'rm -rf "$d"' EXIT
  gh api "$p/pulls/$n" > "$d/pr.json"
  head=$(jq -r .head.sha "$d/pr.json")
  gh api user > "$d/me.json" 2>/dev/null || echo '{"login": "?"}' > "$d/me.json"
  gh api "$p/pulls/$n/commits?per_page=100" > "$d/commits.json"
  gh api "$p/pulls/$n/files?per_page=100" > "$d/files.json"
  gh api "$p/commits/$head/check-runs?per_page=100" > "$d/runs.json"
  gh api "$p/commits/$head/status?per_page=100" > "$d/status.json"
  gh api "$p/issues/$n/comments?per_page=100" > "$d/comments.json"
  gh api "$p/pulls/$n/reviews?per_page=100" > "$d/reviews.json"
  gh api "$p/pulls/$n/comments?per_page=100" > "$d/review-comments.json"
  gh api "$p/pulls/$n/ccr/review_threads" > "$d/threads.json" 2>/dev/null || echo null > "$d/threads.json"
  for i in $(jq -r '[.body // "" | scan("(?i)\\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):?\\s+#(\\d+)") | .[0]] | unique | .[]' "$d/pr.json"); do
    gh api "$p/issues/$i" > "$d/issue.json" || { echo "(skipping #$i from the body)" >&2; continue; }
    gh api "$p/issues/$i/comments?per_page=100" > "$d/issue-comments.json"
    jq --slurpfile c "$d/issue-comments.json" '. + {thread: $c[0]}' "$d/issue.json"
  done | jq -s . > "$d/issues.json"

  jq -rn --slurpfile pr "$d/pr.json" --slurpfile me "$d/me.json" \
    --slurpfile commits "$d/commits.json" --slurpfile files "$d/files.json" \
    --slurpfile runs "$d/runs.json" --slurpfile status "$d/status.json" \
    --slurpfile comments "$d/comments.json" --slurpfile reviews "$d/reviews.json" \
    --slurpfile rc "$d/review-comments.json" --slurpfile threads "$d/threads.json" \
    --slurpfile issues "$d/issues.json" '
def more(total; shown; what): if total > shown then "!! only \(shown) of \(total) \(what) shown\n" else "" end;
def who: .user.login // "ghost";
def indent: gsub("\n"; "\n  ") | "  " + .;
$pr[0] as $p | $rc[0] as $c
| "# #\($p.number) \($p.title)\n\($p.html_url)\nstate=\(if $p.merged_at then "MERGED" else $p.state | ascii_upcase end) draft=\($p.draft) author=\($p | who) association=\($p.author_association) viewer=\($me[0].login)\nbase=\($p.base.ref) \($p.base.sha)\nhead=\($p.head.repo.full_name // "?"):\($p.head.ref) \($p.head.sha)\n(read through REST: closing issues are found from keywords in the body)\n\n## Body\n\($p.body // "")\n"
, "## Commits\n" + more($p.commits; $commits[0] | length; "commits") + ([$commits[0][] | (.commit.message | split("\n")) as $l | "- \(.sha[0:9]) \($l[0])" + (($l[1:] | join("\n") | sub("^\\s+"; "")) as $b | if $b != "" then "\n" + ($b | indent) else "" end)] | join("\n")) + "\n"
, "## Files\n" + more($p.changed_files; $files[0] | length; "files") + ([$files[0][] | "- \(.filename) +\(.additions) -\(.deletions)"] | join("\n")) + "\n"
, ([($runs[0].check_runs[] | select(.status != "completed" or (.conclusion | IN("success", "skipped", "neutral") | not)) | "- \(.name): \(.conclusion // .status | ascii_upcase) \(.details_url)")
    , ($status[0].statuses[] | select(.state != "success") | "- \(.context): \(.state | ascii_upcase) \(.target_url)")] as $bad
   | "## Checks: \(if ($bad | length) == 0 then "SUCCESS" else "NOT ALL PASSING" end)\n" + more($runs[0].total_count; $runs[0].check_runs | length; "check runs") + ($bad | join("\n")) + "\n")
, ($issues[0][] | "## Issue #\(.number) \(.title)\n\(.html_url)\n\(.body // "")\n" + more(.comments; .thread | length; "comments") + ([.thread[] | "--- \(who) \(.created_at)\n\(.body)"] | join("\n")) + "\n")
, "## PR comments\n" + more($p.comments; $comments[0] | length; "comments") + ([$comments[0][] | select(.body | startswith("<!-- bot:") | not) | "--- \(who) \(.created_at)\n\(.body)"] | join("\n")) + "\n"
, "## Reviews\n" + (if ($reviews[0] | length) == 100 then "!! only the first 100 reviews shown\n" else "" end) + ([$reviews[0][] | "--- \(who) \(.state) id=\(.id) commit=\((.commit_id // "")[0:9]) \(.submitted_at // "")\n\(.body)"] | join("\n")) + "\n"
, "## Threads\n" + more($p.review_comments; $c | length; "review comments")
  + (if $threads[0] == null and ($c | length) > 0 then "(resolution unknown through REST)\n" else "" end)
  + ((if $threads[0] != null
      then [$threads[0][] | . as $t | {path, line, resolved: .resolved, outdated: .outdated, ids: .comment_ids}]
      else [$c[] | select(.in_reply_to_id == null) | . as $r | {path, line, resolved: "?", outdated: (.line == null), ids: [$c[] | select(.id == $r.id or .in_reply_to_id == $r.id) | .id]}]
      end)
     | [.[] | . as $t | "--- \(.path):\(.line // "?") resolved=\(.resolved) outdated=\(.outdated)\n" + ([$c[] | select(.id as $id | $t.ids | index($id)) | "  [\(who)] \(.body | gsub("\n"; "\n  "))"] | join("\n"))]
     | join("\n"))
'
}

if ! out=$(graphql); then
  echo "(gh api graphql failed; reading through REST)" >&2
  rest
  exit
fi
printf '%s\n' "$out"
