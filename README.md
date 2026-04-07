# dev-agent

A multi-mode Claude Code skill that automates the full dev workflow — from Jira triage to PR merge.

## Modes

| Command | What it does |
|---|---|
| `/dev-agent audit` | Codebase assessment — maps architecture, surfaces risks, generates Jira tickets |
| `/dev-agent fix` | Diagnoses a bug from a Jira ticket and opens a PR |
| `/dev-agent refix` | Re-diagnoses and fixes a rejected or reverted deployment |
| `/dev-agent build` | Generates a full endpoint (backend + frontend) from a Jira ticket |
| `/dev-agent sweep` | Autonomous pipeline — pulls a batch of Jira tickets and opens PRs for all of them |
| `/dev-agent verify` | Root-cause checks a PR before merging |
| `/dev-agent respond` | Addresses PR review comments and pushes updates |
| `/dev-agent review` | Reviews a colleague's PR and posts structured feedback |
| `/dev-agent follow-up` | Posts a Slack nudge to a PR review thread |
| `/dev-agent config` | View, edit, reset, or validate project config |

## Requirements

- [Claude Code](https://claude.ai/code) installed and authenticated
- `gh` CLI authenticated (`gh auth status`)
- Atlassian MCP configured (for Jira access)
- Slack MCP configured (for Slack posting)

## Install

```sh
git clone https://github.com/delacruz-aldrin/dev-agent.git ~/.claude/skills/dev-agent
```

That's it. The skill is picked up automatically by Claude Code on next launch.

## Update

```sh
git -C ~/.claude/skills/dev-agent pull
```

## Project Config

Each project gets its own config file at `.claude/dev-agent.json`. It's auto-generated the first time you run any dev-agent mode in a new project — Claude will prompt for the values.

Commit it so teammates share the setup:

```sh
git add .claude/dev-agent.json && git commit -m "chore: add dev-agent config"
```

### Config values

| Key | Description | Example |
|---|---|---|
| `repo` | GitHub repo in `owner/repo` format | `C-FO/baberu` |
| `jira_domain` | Jira hostname, no protocol | `your-org.atlassian.net` |
| `jira_project` | Jira project key | `HQA` |
| `slack_channel` | Slack channel for PR notifications (no `#`) | `team-dev` |
| `slack_group` | Slack group handle for review nudges (no `@`) | `team-eng` |
| `pr_reviewer_team` | GitHub team slug for PR reviewers | `dev-agent` |
| `pr_milestone` | Default PR milestone name | `Untracked` |

### Config commands

```sh
/dev-agent config            # show current values
/dev-agent config edit       # update specific keys interactively
/dev-agent config validate   # test GitHub, Jira, and Slack connectivity
/dev-agent config reset      # wipe and redo setup
```

## Uninstall

```sh
rm -rf ~/.claude/skills/dev-agent
```
