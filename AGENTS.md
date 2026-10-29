# AGENTS.md

Guidance for AI agents working on DDEV's agent skills. Branches, commits, pull
requests and writing style follow DDEV's
[organization-wide patterns](https://raw.githubusercontent.com/ddev/.github/main/AGENTS.md).

## Layout

- `.claude-plugin/marketplace.json` makes the repository a Claude Code
  marketplace, `ddev-agent-skills`, that lists the plugins in `plugins/`.
- Each skill is `plugins/ddev/skills/<name>/SKILL.md`, invoked as
  `/ddev:<name>`, with its scripts in the same directory. A skill can use
  another skill's script as `<skill dir>/../<other>/script.sh`, because the
  plugin installs them together, such as the review skill's Docker lock.
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

### When a skill should load

When you change a skill's `description` or its repository check, test which
requests load it. Make two throwaway repositories in `~/tmp`, one with a
`github.com/ddev/` remote and one with another remote. In each, run the
skill's trigger phrases headless against this checkout, with the installed
copy turned off. The command prints the skills that loaded:

```bash
plugin=<this checkout>/plugins/ddev
claude -p "let's review last commit" --plugin-dir "$plugin" \
  --settings '{"enabledPlugins":{"ddev@ddev-agent-skills":false}}' \
  --allowedTools "Bash(git *)" --max-turns 4 --output-format stream-json --verbose \
  | jq -r 'select(.type=="assistant") | .message.content[]
      | select(.type=="tool_use" and .name=="Skill") | .input.skill'
```

The skill should load in the DDEV repository. In the other one it should not
load, or should stop after its repository check. Loading is not
deterministic, so run each case more than once before you trust a result.
