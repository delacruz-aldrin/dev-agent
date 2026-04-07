# dev-agent

A multi-mode Claude Code skill that automates the full dev workflow — from Jira triage to PR merge.

## Modes

| Command | Arguments | What it does |
|---|---|---|
| `/dev-agent audit` | _(none)_ | Scans the full codebase for risks and architectural issues, then offers to create Jira tickets for findings |
| `/dev-agent fix` | `[ticket key or URL]` or `[description]` | Diagnoses a bug, applies a scoped fix, runs tests, opens a PR, and transitions the Jira ticket |
| `/dev-agent refix` | `[ticket] [rejected PR]` | Re-diagnoses after a fix was rejected — classifies the rejection, applies a corrected fix on a new branch |
| `/dev-agent build` | `[ticket key or URL]` or `[description]` | Generates a full feature (route → controller → serializer → specs + FE integration) from a Jira ticket |
| `/dev-agent sweep` | _(none)_ | Pulls all open assigned tickets from Jira and processes each end-to-end; supports resume from checkpoint |
| `/dev-agent verify` | `[ticket] [PR]` | Pre-merge root cause check — independently traces the code path and compares it against the PR diff |
| `/dev-agent respond` | `[your PR]` | Addresses all open review comments, pushes updates, waits for CI, then re-requests review |
| `/dev-agent review` | `[colleague's PR]` | Reviews a colleague's PR — leaves inline comments, submits verdict, notifies author on Slack |
| `/dev-agent follow-up` | `[PR]` or _(none for all)_ | Posts a Slack nudge to the existing thread for one PR or all your open unapproved PRs |
| `/dev-agent setup <url> [url2 ...]` | One or more doc URLs | Reads setup docs (Confluence or web), deduplicates steps, snapshots machine state, executes, and verifies |
| `/dev-agent setup --rollback [id]` | Snapshot ID or _(none to list)_ | Rolls back a previous setup session — restores config files, uninstalls packages, removes created files |
| `/dev-agent config` | _(see below)_ | View, edit, reset, or validate project config |

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
| `jira_project` | One or more Jira project keys, comma-separated (spaces around commas are fine) | `HQA` or `MULTI, HQA` |
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
