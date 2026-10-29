#!/usr/bin/env bash
# List the issues and PRs that mention an issue or PR, with their state, so
# the related work can be read before starting. Usage: mentions.sh N [owner/repo]
# shellcheck disable=SC2016 # the $ in the GraphQL query and jq filter is not shell
set -euo pipefail

n=${1:?usage: mentions.sh N [owner/repo]}
repo=${2:-'{owner}/{repo}'}
owner=${repo%%/*}
name=${repo#*/}

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
