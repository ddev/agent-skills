# DDEV agent skills

Skills for DDEV maintainers working with coding agents.

## Skills

| Skill | What it does |
|---|---|
| [`/ddev:ci-failure`](plugins/ddev/skills/ci-failure/SKILL.md) | Diagnoses a failing CI job from a GitHub Actions or Buildkite URL, or a downloaded log: finds the first real error, checks the job's recent history to tell a regression from an intermittent or upstream failure, and fixes the cause. Ask "is it intermittent?" with the run URL, or run `/ddev:ci-failure <url>`. Needs bash, git and a signed-in [gh](https://cli.github.com/), jq for Buildkite, an authorized [bk](https://github.com/buildkite/cli) to find every Buildkite failure of a test, and Docker with DDEV to reproduce. |
| [`/ddev:commit`](plugins/ddev/skills/commit/SKILL.md) | Writes a commit message that doubles as the PR description, runs the repository's checks, and commits locally; later it keeps the PR title and body in sync with the branch. Ask "make a branch and commit", or run `/ddev:commit`. Needs bash and git, plus a signed-in [gh](https://cli.github.com/) for PRs and issues. |
| [`/ddev:review`](plugins/ddev/skills/review/SKILL.md) | Reviews a PR, branch or commit in a DDEV repository: runs it against a baseline build, reports evidence and gaps, and drafts a pending GitHub review. Ask "let's review 1234", or run `/ddev:review 1234`. Needs bash, git, a signed-in [gh](https://cli.github.com/), and Docker with DDEV, on Linux or macOS. On Windows, use WSL2. |

## Install in Claude Code

```bash
claude plugin install ddev --marketplace ddev/agent-skills
```

In Claude Code cloud and self-hosted sessions, `gh` passes on only `gh api` REST
requests. The scripts fall back to REST there, which needs jq, and
[`github-rest.md`](plugins/ddev/skills/review/github-rest.md) gives the
skills REST forms of the other `gh` commands.

A plugin installed on your own machine isn't in those sessions. They get the
plugins and skills of your claude.ai account and organization instead, so add
this plugin there to use it in a cloud or self-hosted session.

## Update

Auto-update is off for this marketplace by default. To turn it on, run
`/plugin` in a session, open the **Marketplaces** tab, select
`ddev-agent-skills`, and select **Enable auto-update**. To update once
instead:

```bash
claude plugin update ddev@ddev-agent-skills
```

## Use with other agents

Each skill is a folder with a `SKILL.md`, the [Agent Skills](https://agentskills.io) format.
For Codex or another agent that reads it, symlink each folder in
`plugins/ddev/skills` from a clone of this repository into that agent's
skills directory, so `git pull` updates them. Link all of them, because the
skills run each other's scripts. Copying the folders works too, but then you
update them by hand.

## Add a skill

Create `plugins/ddev/skills/<name>/SKILL.md`. It becomes `/ddev:<name>`.
Add a row for it to the table under [Skills](#skills), the one list of skills.
[AGENTS.md](AGENTS.md) has the conventions and the checks to run before you push.
