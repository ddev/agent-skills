# GitHub through REST only

Read this when `gh` answers `GitHub GraphQL is not available`, or when
`gh pr`, `gh issue` or `gh repo` commands fail with HTTP 403 and that
message. Claude Code's cloud sessions and self-hosted runners provide a `gh`
that passes on only `gh api` REST requests, so GraphQL, and the `gh`
commands built on it, don't work there. The REST forms below work with a
signed-in `gh` too.

`pr-context.sh`, `mentions.sh` and `failed-job.sh` switch to REST on their
own. Through REST, `pr-context.sh` finds closing issues from keywords in the
PR body, and shows thread resolution only where Claude Code's
`ccr/review_threads` route exists.

`{owner}/{repo}` is the repository `gh` picked for the checkout, which can be
a fork. Name the upstream repository instead when the request is about it.

| Instead of | Use |
| --- | --- |
| `gh repo view --json parent --jq .parent.owner.login` | `gh api 'repos/{owner}/{repo}' --jq .parent.owner.login` |
| `gh pr view --json number,title,body` | `gh api 'repos/<owner>/<repo>/pulls?head=<fork owner>:<branch>' --jq '.[] \| {number, title, body}'` |
| `gh pr create --title T --body-file F` | `gh api 'repos/<owner>/<repo>/pulls' -f title=T -F body=@F -f head=<fork owner>:<branch> -f base=<base>`, with `-F draft=true` for a draft |
| `gh pr edit N --title T --body-file F` | `gh api -X PATCH 'repos/<owner>/<repo>/pulls/N' -f title=T -F body=@F` |
| `gh issue view M --comments` | `gh api 'repos/<owner>/<repo>/issues/M' --jq '.title, .body'`, then `gh api 'repos/<owner>/<repo>/issues/M/comments' --jq '.[] \| "--- \(.user.login)\n\(.body)"'` |
| `gh issue create --body-file F` | `gh api 'repos/<owner>/<repo>/issues' -f title=T -F body=@F` |

## Pending reviews

Creating a pending review is already REST: `POST .../pulls/N/reviews` with no
`event`. REST can't add a comment to a pending review that already exists,
which the GraphQL `addPullRequestReviewThread` step does. When
`pr-context.sh` shows a `PENDING` review, tell the user, and offer either:

- They finish or delete it in the GitHub UI, and you post the new one.
- With their OK, replace it. Read its comments, delete it, and post one
  review with its body and comments plus yours:

  ```bash
  gh api 'repos/<owner>/<repo>/pulls/N/reviews/<id>/comments' --jq '.[] | {path, line, side, body}'
  gh api -X DELETE 'repos/<owner>/<repo>/pulls/N/reviews/<id>'
  ```

To change only its body, which the GraphQL `updatePullRequestReview` step
does:

```bash
gh api -X PUT 'repos/<owner>/<repo>/pulls/N/reviews/<id>' -F body=@body.md
```

In the REST output, a review's `id` is the number these routes take.

## Other tools

An agent with GitHub MCP tools can use them for the same steps; their pending
review tools can add comments to an existing pending review.
