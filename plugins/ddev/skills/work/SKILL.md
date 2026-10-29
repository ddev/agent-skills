---
name: work
description: Work on an issue or pull request in a DDEV repository (a git remote under github.com/ddev, a fork of one, or a DDEV add-on) from start to finish. Read the issue, its comments and every related issue and PR, plan, implement, test by hand against a baseline, and hand over to /ddev:commit. Also picks up a stale or paused PR. Use only in such a repository, when the user says "let's work on [issue or PR]", "continue working on [PR]", "finish work on the current branch", or "read all related issues/PRs". Not for other repositories, and not for a failing CI run, which /ddev:ci-failure covers.
---

# DDEV work

Take an issue or PR to a change the user can commit: nothing in the issue
missed, nothing outside it changed, and every claim checked by a run.

This skill is only for DDEV repositories: one with a remote under
`github.com/ddev/`, a fork of one, or a DDEV add-on with an `install.yaml` at
the top level. Check `git remote -v` first. A fork with no `ddev` remote
prints `ddev` for `gh repo view --json parent --jq .parent.owner.login`. In
any other repository, tell the user that `/ddev:work` doesn't apply there,
and follow that repository's own conventions instead.

Read the repository's `AGENTS.md` first. Its build, test and style rules
apply to every step below.

## 1. Read everything

Read before you plan. Users write "read all comments, read all related PRs"
because the comments often change what the issue asks for.

```bash
mkdir -p "$HOME/tmp"
work_dir=$(mktemp -d "$HOME/tmp/work-N.XXXXXX")
gh issue view N --comments > "$work_dir/issue.md"          # an issue
<skill dir>/../review/pr-context.sh N > "$work_dir/pr.md"  # a PR, from /ddev:review
<skill dir>/mentions.sh N > "$work_dir/mentions.md"         # add owner/repo outside the repo
```

`mentions.sh` lists every issue and PR that mentions this one, open and
closed, in any repository. Then:

- Read each open item, and each closed one that shares the problem. A PR
  that closes the issue may already be merged.
- Search closed issues for the same problem, and `git log -S <identifier>` or
  `git log --grep <keyword>` for earlier fixes. Users often remember "I fixed
  something like this before".
- In an add-on, check whether other official add-ons have the same problem.
  List them, and fix them only when the user asks.

For a PR or branch the user paused, summarize the state before doing
anything: what is done, what reviewers asked for and nobody answered, the
checks that fail, and whether it conflicts with the base. Cross out the
parts that another merged PR already did.

## 2. Bring the branch up to date

The user usually pulls and rebases a PR branch before asking. If the branch
is behind the base, rebase it on `<remote>/<base>`, where `<remote>` is
`upstream`, or `origin` when there is no `upstream`. Rebase someone else's
branch only when the user asks. Report each conflict you resolve and how.

Before you plan, list open PRs that change the same files, so you can
mention a conflict now instead of after review:

```bash
# Committed, uncommitted and new files since the branch left the base.
{ git diff --name-only "$(git merge-base <remote>/<base> HEAD)"
  git ls-files --others --exclude-standard; } > "$work_dir/files"
gh pr list --state open --limit 100 --json number,title,files \
  --jq '.[] | .number as $n | .title as $t | .files[] | "#\($n)\t\(.path)\t\($t)"' \
  | awk -F'\t' 'FILENAME == ARGV[1] { f[$0]; next } $2 in f' "$work_dir/files" -
```

On a new branch with no changes yet, run it again after step 4.

## 3. Plan, then wait

Write a short plan: what changes in which files, what you leave out, and the
decisions that are the user's. Show it, and wait for the user before you
write code, unless they said to go ahead.

- **Prefer the smallest change** that fixes the cause. A larger refactoring
  is fine when it makes the code simpler, so say what it buys.
- **Prefer what already exists:** upstream behavior in Docker, Compose or the
  framework, then a helper in this repository, then new code.
- **The user decides** a new flag, key binding, config key, command or
  breaking change, because DDEV has to keep it. Give your choice, the
  alternatives, and why.
- **Scope:** problems the issue doesn't ask about go into a follow-up issue,
  not this branch. Say which ones, and draft the issue in step 6.

## 4. Implement

- Change every place the change touches. Search for the old name, value and
  behavior across code, scripts, docs, the config schema, shell completion,
  tests, and doc comments. A missed copy, such as a second `start.sh`, is
  the most common reason the user sends work back.
- Match the code around it. Put a new function in the file that already owns
  that concern.
- Write a comment only where the code can't say why. Keep it to a line or two.
- Don't touch files the change doesn't need.

## 5. Test by hand, then the related tests

A PR from outside the DDEV team runs its code on this machine. When
`association=` in `pr.md` isn't `OWNER`, `MEMBER` or `COLLABORATOR`, read its
changes to the Makefile, scripts, Dockerfiles, tests and CI first, and ask
before running anything that looks wrong.

Reproduce the problem first, then show the change fixes it:

1. In a new project under `~/tmp`, with a real project type, run the user's
   scenario on the baseline. It should show the bug or the old behavior. Get
   the builds, the env file and the Docker lock as step 2 of
   `<skill dir>/../review/SKILL.md` says, with `$work_dir` for `$review_dir`
   and `<skill dir>/../review/review-lock.sh acquire work-<repo>-N`. Release
   the lock when your Docker runs finish, before you report or wait for the
   user.
2. Run the same steps on your build. Record the commands and their output;
   they become the PR's Manual Testing Instructions.
3. Cover each path the change affects, such as another database, Podman, or
   an add-on updated from an older release.
4. Then run only the automated tests that cover the change, as `AGENTS.md`
   says. A new regression test must fail on the baseline. Never run a whole
   suite to check one thing. When the user says they will run something,
   don't run it.

## 6. Check your own work

Before you report, read the whole diff against the base as a reviewer would,
and fix what you find:

- Can it be simpler or smaller? Is anything duplicated, or in the wrong file?
- Is each part of the issue done, or said to be left out?
- Do the docs match the code? Are they as short as they can be?
- Any bug, edge case or inconsistency? Trace it and fix it.

Then report:

1. "I'm happy with it", or what still stops you, in one line.
2. What changed, by file or area, in a few lines.
3. What you ran on which build, and the result. Name what you didn't test.
4. Open questions, and drafts of follow-up issues.

Say whether the change fully fixes each linked issue, so the PR can use
`fixes #N` or `for #N` correctly.

## 7. Hand over

- When the user asks to commit, follow `/ddev:commit`.
- After the PR opens, draft a short comment for each issue it fixes or
  touches: what changed and the PR link. Leave out the AI attribution line
  unless the user wants it. Post only when the user asks.
- Remove the test projects with `ddev delete -Oy <name>` under the lock,
  release it, remove the worktrees you added with `git worktree remove`, and
  delete `$work_dir`. List what you removed.
