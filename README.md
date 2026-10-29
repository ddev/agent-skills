# DDEV agent skills

Skills for DDEV maintainers working with coding agents.

## Skills

| Skill | What it does |
|---|---|
| [`/ddev:review`](plugins/ddev/skills/review/SKILL.md) | Reviews a PR, branch or commit in a DDEV repository: runs it against a baseline build, reports evidence and gaps, and drafts a pending GitHub review. Ask "let's review 1234", or run `/ddev:review 1234`. Needs bash, git, a signed-in [gh](https://cli.github.com/), and Docker with DDEV, on Linux or macOS. On Windows, use WSL2. |

## Install in Claude Code

```bash
claude plugin install ddev --marketplace ddev/agent-skills
```

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
For Codex or another agent that reads it, symlink the skill folder from a
clone of this repository into that agent's skills directory, so `git pull`
updates it. Copying the folder works too, but then you update it by hand.

## Add a skill

Create `plugins/ddev/skills/<name>/SKILL.md`. It becomes `/ddev:<name>`.
[AGENTS.md](AGENTS.md) has the conventions and the checks to run before you push.
