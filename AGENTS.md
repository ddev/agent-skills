# AGENTS.md

Guidance for AI agents working on DDEV's agent skills. Branches, commits, pull
requests and writing style follow DDEV's
[organization-wide patterns](https://raw.githubusercontent.com/ddev/.github/main/AGENTS.md).

## Layout

- `.claude-plugin/marketplace.json` makes the repository a Claude Code
  marketplace, `ddev-agent-skills`, that lists the plugins in `plugins/`.
- Each skill is `plugins/ddev/skills/<name>/SKILL.md`, invoked as
  `/ddev:<name>`, with its scripts in the same directory.
- `plugin.json` has no `version` on purpose: installs update to the latest
  commit. Don't add one.

## Writing a skill

- Follow Anthropic's
  [skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices).
  Write only what an agent can't work out from the repository or the task.
- Word instructions plainly. Current models follow them without `IMPORTANT`,
  `MUST` or capitals, and emphasis makes them over-apply a rule.
- Codex and other agents use these skills too. Refer to bundled scripts as
  `<skill dir>/script.sh`, and keep the steps free of Claude Code-only
  features. Claude Code-only frontmatter, such as `effort`, is fine.
- Keep `SKILL.md` under 500 lines. Move long reference material into a file
  next to it and say when to read it.

## Scripts

Scripts run on Linux, macOS and Git Bash, under macOS's bash 3.2:

- No bash 4 features, such as associative arrays, `mapfile` or `${var,,}`.
- No GNU-only tools or flags: `flock`, `timeout`, `setsid`, `/proc`,
  `date -d`, `stat -c`, `sed -i` without a suffix.

## Checks

Run these before committing, and try a changed skill in a session. CI runs
the first two on every pull request.

```bash
claude plugin validate .
shellcheck plugins/*/skills/*/*.sh
claude --plugin-dir ./plugins/ddev
```
