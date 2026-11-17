# GitHub when `gh` is limited

Read this in a Claude Code self-hosted runner session, when `gh` says it
isn't signed in (it suggests `gh auth login` and exits with status 4), or
when `gh` answers `GitHub GraphQL is not available`.

## Self-hosted runners

In a Claude Code self-hosted runner session, `gh` in Bash is the machine's
own CLI, with the machine's sign-in. The session's system prompt says so.
Runner sessions can carry a REST-only `gh` shim, but it isn't on the Bash
`PATH`, so `gh` is either:

- not signed in: every command, `gh api` included, fails with `gh auth
  login` advice.
- signed in as whoever set up the workspace: it works, GraphQL included, but
  it acts as that account for every session on the machine, including
  sessions other people start.

Before using `gh` there, compare `gh api user --jq .login` with the
session's own account, which the GitHub MCP tool `get_me` returns. When
`gh` isn't signed in, or names another account, use the GitHub MCP tools
(`mcp__github__*`) for GitHub steps; the table below maps the skills' steps
to them. git itself keeps working, through the session's own proxy.

Don't run `gh auth login` or `gh auth switch`, and don't set `GH_TOKEN` or
`GITHUB_TOKEN`, in a runner workspace: other sessions share it and would act
as that account. A session has the MCP tools only for repositories attached
to it. When they are missing, ask the user to attach the repository, and
otherwise work from git and from what the user pastes.

| Step | GitHub MCP tool |
| --- | --- |
| `pr-context.sh N` | `pull_request_read` with `method` `get`, `get_commits`, `get_files`, `get_check_runs`, `get_status`, `get_comments`, `get_reviews` and `get_review_comments` (threads with resolution); closing issues from `issue_read` `get` and `get_comments` |
| `mentions.sh N` | no equivalent; `issue_read` `get` lists up to 5 PRs that close it, in `closed_by_pull_requests` |
| `failed-job.sh` on a GitHub Actions URL | `actions_get` `get_workflow_run`, `actions_list` `list_workflow_jobs` with the run ID, `get_job_logs` with `job_id`, `return_content` and `tail_lines`, and `actions_list` `list_workflow_runs` with the workflow ID for history |
| `gh pr view`, `gh pr diff` | `pull_request_read` `get`, `get_diff` |
| `gh pr create`, `gh pr edit` | `create_pull_request`, `update_pull_request` |
| `gh issue view --comments`, `gh issue create` | `issue_read` `get` and `get_comments`, `issue_write` `create` |
| a pending review | `pull_request_review_write` `create` with no `event`, then `add_comment_to_pending_review`; it adds to the session account's existing pending review too |

`failed-job.sh` on a public Buildkite URL works without `gh`; it skips only
the GitHub history.

## Cloud sessions: REST only

Claude Code's cloud sessions provide a `gh` that passes on only `gh api`
REST requests, so GraphQL, and the `gh` commands built on it, don't work
there. The REST forms below work with a signed-in `gh` too.

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
| `gh issue create --title T --body-file F` | `gh api 'repos/<owner>/<repo>/issues' -f title=T -F body=@F` |

### Pending reviews

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

An agent with GitHub MCP tools can use them instead, as the table under
"Self-hosted runners" shows.
