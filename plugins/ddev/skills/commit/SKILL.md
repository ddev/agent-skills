---
name: commit
description: Write, amend, or reword a commit message, a PR title and description, or an issue in a DDEV repository (a git remote under github.com/ddev, a fork of one, or a DDEV add-on), run the repository's checks, and commit locally. Use only in such a repository, when the user says "commit", "make a branch and commit", "amend", "squash into one commit", "rename the commit", "good commit name?", "update the PR body", "the commit body is too long", or asks to draft an issue. Not for other repositories.
---

# DDEV commit

The commit title and body become the PR title and description, so the user
can push and open the PR without rewriting anything. Write them for a
reviewer who reads the diff anyway: the message says what the diff can't,
which is why the change exists and how to check it by hand.

This skill is only for DDEV repositories: one with a remote under
`github.com/ddev/`, a fork of one, or a DDEV add-on with an `install.yaml` at
the top level. Check `git remote -v` first. A fork with no `ddev` remote
prints `ddev` for `gh repo view --json parent --jq .parent.owner.login`. In
any other repository, tell the user that `/ddev:commit` doesn't apply there,
and follow that repository's own conventions instead.

## 1. Read the repository's rules

Read these before writing. Where they differ from this skill, the repository
wins:

- `AGENTS.md`, and any commit, PR, or check notes it links. Without one, read
  the [organization AGENTS.md](https://raw.githubusercontent.com/ddev/.github/main/AGENTS.md)
  for branch names, the title format, attribution, and the words to avoid.
- `.github/PULL_REQUEST_TEMPLATE.md`, or the
  [organization template](https://raw.githubusercontent.com/ddev/.github/main/PULL_REQUEST_TEMPLATE.md)
  when the repository has none.
- For an issue, the form under `.github/ISSUE_TEMPLATE/`. Its field labels
  become the headings.

If the branch already has an open PR, start from its current title and body:
`gh pr view --json number,title,body`.

When the user asks for a branch, create it as `AGENTS.md` says. Otherwise
commit on the current branch.

## 2. Write the title

- Name the change as users see it, because titles on `main` become the
  changelog.
- Aim for about 60 characters, not counting `, fixes #N`. Past 72 it is too
  long, so move the detail to the body.
- A breaking change, such as a removed flag or key binding, gets `!` after
  the type and a line in Release/Deployment Notes.

## 3. Write the body

Use the template's sections in order, without its HTML comments. Write Short
Summary (TL;DR) last. Drop any other section, heading included, that has
nothing to say.

- **Describe the result against the base branch,** not the session that
  produced it. Leave out approaches you tried and dropped. Never write
  "instead of X" about an X that never reached the base branch.
- **The Issue:** the problem as a user meets it, and where it was reported,
  such as an issue, a Discord thread, or an email the user mentions. Keep
  `- Fixes #N` when there is an issue, and drop the placeholder line when
  there is none.
- **How This PR Solves The Issue:** the decision and why. For many similar
  changes, such as commands, keys, or versions, use a table with one row per
  change. When the change shows on screen or is about speed, show before and
  after output or timings from real runs.
- **Automated Testing Overview:** the tests added, and what ran where, naming
  who ran it: "Claude Code ran `go test ./pkg/ddevapp -run TestX` on Linux".
  Name the platforms nobody tested. Never claim a run that didn't happen.
- Known gaps, follow-ups, and what a reviewer should confirm by hand get one
  line each, in the section they fit.

### Manual Testing Instructions

Write a transcript a reviewer can paste: real commands with real values, an
actual project type, and after each step the output or behavior that
confirms the change. Cover each path the change affects, such as another
database, an older PHP version, or an add-on updated from an older release.
Start with how the reviewer gets the change:

| Repository | How the reviewer gets the change |
| --- | --- |
| ddev/ddev | `ddev utility download-ddev --pr N`, then `export PATH="$HOME/tmp/ddev-download-ddev/pr-N:$PATH"`. For docs, link the changed page in `https://ddev--N.org.readthedocs.build/en/N/` with its path and anchor, and point to the steps there instead of repeating them. |
| An add-on | `ddev add-on get <owner>/<repo> --pr N`. When it needs unreleased DDEV, first `ddev utility download-ddev --head` and `export PATH="$HOME/tmp/ddev-download-ddev/main:$PATH"`. |
| Other repositories | The preview or install steps in the repository's notes. |

Use the PR's number. Before the PR exists, predict it, so the instructions
work as soon as it opens:

```bash
gh api 'repos/<owner>/<repo>/issues?state=all&per_page=1' --jq '.[0].number + 1'
```

### Leave out

- Names of the user's own projects, clients, hosts, and paths. Use a generic
  example instead.
- People, PRs, and reviews that only led to the change, unless the user asks
  to credit them.
- State that changes from hour to hour, such as "this URL returns 404 right
  now". Say it happens intermittently, or give the date.

### Length and wording

A finished message should read in under a minute. State each fact once, in
the section it belongs to. A section longer than a handful of lines is
narrating the diff.

Many readers are not native English speakers. The first three rules come
from [ASD-STE100](https://en.wikipedia.org/wiki/Simplified_Technical_English):

- At most 20 words in an instruction, and 25 in a description
- Active voice that names who acts
- One name for one thing throughout
- One action per step in Manual Testing Instructions
- A "why" in its own clause, not in a parenthetical

End with the attribution from the organization `AGENTS.md`. The PR
description is the same text without the `Co-Authored-By` trailer.

## 4. Check the message

Write the message to a file under `~/tmp`, then run:

```bash
<skill dir>/check-message.sh <file>          # a commit message
<skill dir>/check-message.sh --body <file>   # a PR or issue body
```

It reports a title that is off-format or too long, line breaks inside a
paragraph, which GitHub shows as `<br>`, template comments, `REPLACE_ME`
placeholders, empty sections, and words from the organization's list. Fix
what it reports. Then reread each claim against the diff and your runs.

## 5. Run the checks and commit

1. Run the lint and test commands that the repository's `AGENTS.md` names
   for the changed files. Read the full output, without `tail`, `head`, or
   `grep`.
2. Fix every failure, including failures in changes you didn't write, and
   stage the fixes. Run the checks again. Commit only after a passing run,
   with no file changed since. This applies to an amend, squash, or reword
   too.
3. Read `git diff --cached` for comments that restate the code, and cut them.
4. Commit with `git commit -F <file>` or `git commit --amend -F <file>`.

When the user asks to commit what is staged, commit it without asking why.
Add only the fixes the checks need, and name them.

For an amend, squash, or fold, rewrite the body for the combined result.
Check each earlier claim against the current diff, and remove what no
longer holds. When the user wants one commit, fold fixes into it instead of
adding commits.

Report the commit title, the branch, the unpushed commits, and any fixes you
staged.

## 6. Push, PR, and issue

Pushing is the user's step. Push only when the user asks in this session and
the repository allows it. After the user pushes:

- To open the PR when the user asks:
  `gh pr create --title "<title>" --body-file <file>`.
- With an open PR, re-read its title and body against the whole branch diff,
  `git diff <base>...HEAD`. Update them with
  `gh pr edit N --title "<title>" --body-file <file>` when a commit changed
  behavior or made a claim untrue. Replace a predicted PR number or preview
  link that turned out wrong.

Draft an issue the same way and show the file. Create it with
`gh issue create --body-file <file>` only when the user asks.
