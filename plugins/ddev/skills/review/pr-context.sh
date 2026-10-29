#!/usr/bin/env bash
# Print everything a review needs about a PR in one GraphQL request:
# metadata, commits, files, checks, comments, reviews, threads, and closing
# issues with their comments. Usage: pr-context.sh N [owner/repo]
# shellcheck disable=SC2016 # the $ in the GraphQL query and jq filter is not shell
set -euo pipefail

n=${1:?usage: pr-context.sh N [owner/repo]}
repo=${2:-'{owner}/{repo}'}
owner=${repo%%/*}
name=${repo#*/}

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
        comments(first: 50) { nodes { author { login } createdAt body } } } }
    }
  }
}' --jq '
def more(c; what): if c.totalCount > (c.nodes | length) then "!! only \(c.nodes | length) of \(c.totalCount) \(what) shown\n" else "" end;
def who: .author.login // "ghost";
.data.viewer.login as $me
| .data.repository.pullRequest as $p
| "# #\($p.number) \($p.title)\n\($p.url)\nstate=\($p.state) draft=\($p.isDraft) author=\($p.author.login) association=\($p.authorAssociation) viewer=\($me)\nbase=\($p.baseRefName) \($p.baseRefOid)\nhead=\($p.headRepository.nameWithOwner // "?"):\($p.headRefName) \($p.headRefOid)\n\n## Body\n\($p.body)\n"
, "## Commits\n" + more($p.commits; "commits") + ([$p.commits.nodes[].commit | "- \(.oid[0:9]) \(.messageHeadline)" + (if .messageBody != "" then "\n\(.messageBody | gsub("\n"; "\n  ") | "  " + .)" else "" end)] | join("\n")) + "\n"
, "## Files\n" + more($p.files; "files") + ([$p.files.nodes[] | "- \(.path) +\(.additions) -\(.deletions)"] | join("\n")) + "\n"
, "## Checks: \($p.head.nodes[0].commit.statusCheckRollup.state // "none")\n" + ([$p.head.nodes[0].commit.statusCheckRollup.contexts.nodes[]? | select((.conclusion // .state // .status) as $s | $s != "SUCCESS" and $s != "SKIPPED" and $s != "NEUTRAL") | "- \(.name // .context): \(.conclusion // .state // .status) \(.detailsUrl // .targetUrl)"] | join("\n")) + "\n"
, ($p.closingIssuesReferences.nodes[] | "## Issue #\(.number) \(.title)\n\(.url)\n\(.body)\n" + more(.comments; "comments") + ([.comments.nodes[] | "--- \(who) \(.createdAt)\n\(.body)"] | join("\n")) + "\n")
, "## PR comments\n" + more($p.comments; "comments") + ([$p.comments.nodes[] | select(.body | startswith("<!-- bot:") | not) | "--- \(who) \(.createdAt)\n\(.body)"] | join("\n")) + "\n"
, "## Reviews\n" + more($p.reviews; "reviews") + ([$p.reviews.nodes[] | "--- \(who) \(.state) id=\(.id) commit=\(.commit.oid[0:9]) \(.submittedAt // "")\n\(.body)"] | join("\n")) + "\n"
, "## Threads\n" + more($p.reviewThreads; "threads") + ([$p.reviewThreads.nodes[] | "--- \(.path):\(.line // "?") resolved=\(.isResolved) outdated=\(.isOutdated)\n" + ([.comments.nodes[] | "  [\(who)] \(.body | gsub("\n"; "\n  "))"] | join("\n"))] | join("\n"))
'
