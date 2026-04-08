# dev-agent

An eleven-mode Claude Code skill that automates the full dev workflow — from Jira triage to PR merge.

## Modes

| Command | Arguments | What it does |
|---|---|---|
| `/dev-agent audit` | _(none)_ | Scans the full codebase for risks and architectural issues, then offers to create Jira tickets for findings |
| `/dev-agent fix` | `[ticket key or URL]` or `[description]` | Diagnoses a bug, applies a scoped fix, runs tests, opens a PR, and transitions the Jira ticket |
| `/dev-agent refix` | `[ticket] [rejected PR]` | Re-diagnoses after a fix was rejected — classifies the rejection, applies a corrected fix on a new branch |
| `/dev-agent build` | `[ticket key or URL]` or `[description]` | Generates a full feature (route → controller → serializer → specs + FE integration) from a Jira ticket |
| `/dev-agent sweep` | _(none)_ or `--manual "desc1, desc2"` | Pulls all open assigned tickets from Jira and processes each end-to-end; supports resume from checkpoint. Use `--manual` to process a comma-separated list of descriptions without Jira. |
| `/dev-agent verify` | `[ticket] [PR]` or `[ticket] [PR] --comment` | Pre-merge root cause check — independently traces the code path and compares it against the PR diff. Add `--comment` to post findings as a GitHub review. |
| `/dev-agent respond` | `[your PR]` | Addresses all open review comments, pushes updates, waits for CI, then re-requests review |
| `/dev-agent review` | `[colleague's PR]` | Reviews a colleague's PR — leaves inline comments, submits verdict, notifies author on Slack |
| `/dev-agent follow-up` | `[PR]` or _(none for all)_ | Posts a Slack nudge to the existing thread for one PR or all your open unapproved PRs |
| `/dev-agent setup <url> [url2 ...]` | One or more doc URLs | Reads setup docs (Confluence or web), deduplicates steps, snapshots machine state, executes, and verifies |
| `/dev-agent setup --rollback [id]` | Snapshot ID or _(none to list)_ | Rolls back a previous setup session — restores config files, uninstalls brew/npm/pip packages, removes created files |
| `/dev-agent setup --diff <id1> <id2>` | Two snapshot IDs | Compares two setup snapshots side by side — shows added/removed packages and config file changes between sessions |
| `/dev-agent pr` | `[ticket key or URL]` or _(none)_ or `--draft` | Opens a PR for the current branch using the project's PR template — labels, milestone, and reviewer applied automatically. Pass `--draft` to open as a draft. |
| `/dev-agent config` | _(see below)_ | View, edit, reset, or validate project config |

## Mode Chains

Natural workflows — what to run next:

| Situation | What to run |
|---|---|
| New ticket assigned | `fix` or `build` |
| PR gets review comments | `respond` |
| PR gets rejected / reverted | `refix` |
| Unsure a fix is correct before merging | `verify` (add `--comment` to post findings to the PR) |
| Reviewer needs a nudge | `follow-up` |
| Batch of tickets (end-of-sprint) | `sweep` |
| Code smells / tech debt surface | `audit` |
| Review a colleague's PR | `review` |
| Manual code work done, need a PR | `pr` |
| New machine / environment setup | `setup <url>` |

## Requirements

- [Claude Code](https://claude.ai/code) installed and authenticated
- `gh` CLI authenticated (`gh auth status`)
- Atlassian MCP configured (for Jira access)
- Slack MCP configured (for Slack posting)


## Install

### Option 1 — Script (recommended)

The install script prompts you to choose between a global install (available in all projects) or a project-local install (this project only):

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/delacruz-aldrin/dev-agent/main/install.sh)
```

Or if you've already cloned the repo:

```sh
bash ~/.claude/skills/dev-agent/install.sh
```

### Option 2 — Manual

**Global** (available in all Claude Code projects):

```sh
git clone https://github.com/delacruz-aldrin/dev-agent.git ~/.claude/skills/dev-agent
```

**Project-local** (this project only — run from the project root):

```sh
git clone https://github.com/delacruz-aldrin/dev-agent.git .claude/skills/dev-agent
# Optionally exclude from git:
echo '.claude/skills/' >> .gitignore
```

Restart Claude Code after installing. The skill is picked up automatically on next launch.

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
| `base_branch` | Branch to open PRs against | `main` |

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
