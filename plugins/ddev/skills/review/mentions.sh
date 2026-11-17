#!/usr/bin/env bash
# List the issues and PRs that mention an issue or PR, with their state, so
# related issues and earlier attempts can be read. Falls back to REST where gh
# has no GraphQL, as in Claude Code cloud sessions.
# Usage: mentions.sh N [owner/repo]
# shellcheck disable=SC2016 # the $ in the GraphQL query and jq filter is not shell
set -euo pipefail

n=${1:?usage: mentions.sh N [owner/repo]}
repo=${2:-'{owner}/{repo}'}
owner=${repo%%/*}
name=${repo#*/}

# gh exits with status 4 when it has no sign-in, as on a Claude Code
# self-hosted runner whose workspace nobody signed in.
no_gh() {
  echo "$1. In a Claude Code self-hosted runner session, don't sign gh in;" >&2
  echo "use the GitHub MCP tools (mcp__github__*) that $(cd "$(dirname "$0")" && pwd)/github-rest.md lists." >&2
  exit 1
}
command -v gh > /dev/null || no_gh "gh isn't installed"

graphql() {
gh api graphql -F owner="$owner" -F name="$name" -F n="$n" -f query='
fragment mention on CrossReferencedEvent { willCloseTarget source {
  __typename
  ... on Issue { number title url state stateReason repository { nameWithOwner } }
  ... on PullRequest { number title url state isDraft repository { nameWithOwner } }
} }
query($owner: String!, $name: String!, $n: Int!) {
  repository(owner: $owner, name: $name) {
    issueOrPullRequest(number: $n) {
      ... on Issue { number title url
        timelineItems(first: 100, itemTypes: [CROSS_REFERENCED_EVENT]) { filteredCount nodes { ...mention } } }
      ... on PullRequest { number title url
        timelineItems(first: 100, itemTypes: [CROSS_REFERENCED_EVENT]) { filteredCount nodes { ...mention } } }
    }
  }
}' --jq '
.data.repository.issueOrPullRequest as $t
| "# Mentions of #\($t.number) \($t.title)\n\($t.url)"
, if $t.timelineItems.filteredCount > ($t.timelineItems.nodes | length)
  then "!! only \($t.timelineItems.nodes | length) of \($t.timelineItems.filteredCount) mentions shown" else empty end
, ([$t.timelineItems.nodes[]
    | .source as $s
    | select($s.number != null and $s.url != $t.url)
    | "- \($s.repository.nameWithOwner)#\($s.number) "
      + (if $s.__typename == "PullRequest" then "PR" else "issue" end)
      + " \($s.state)"
      + (if $s.isDraft then " draft" else "" end)
      + (if $s.stateReason == "DUPLICATE" then " duplicate" else "" end)
      + (if .willCloseTarget then " closes-it" else "" end)
      + ": \($s.title)\n  \($s.url)"]
   | unique | if length == 0 then "No mentions." else join("\n") end)
'
}

# The same list from the REST timeline, which has no willCloseTarget.
rest() {
  gh api "repos/$repo/issues/$n" --jq '"# Mentions of #\(.number) \(.title)\n\(.html_url)"'
  gh api "repos/$repo/issues/$n/timeline?per_page=100" --jq '
(if length == 100 then "!! only the first 100 timeline events read\n" else "" end)
+ ([.[] | select(.event == "cross-referenced") | .source.issue | select(. != null)
    | "- \(.repository.full_name)#\(.number) "
      + (if .pull_request then "PR" else "issue" end)
      + (if .pull_request.merged_at then " MERGED" else " \(.state | ascii_upcase)" end)
      + (if .draft then " draft" else "" end)
      + (if .state_reason == "duplicate" then " duplicate" else "" end)
      + ": \(.title)\n  \(.html_url)"]
   | unique | if length == 0 then "No mentions." else join("\n") end)'
}

if out=$(graphql); then
  printf '%s\n' "$out"
  exit
else
  status=$?
fi
[ "$status" -ne 4 ] || no_gh "gh isn't signed in to GitHub"
echo "(gh api graphql failed; reading through REST)" >&2
rest
