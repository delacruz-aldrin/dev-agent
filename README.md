# dev-agent

A twelve-mode Claude Code skill that automates the full dev workflow — from Jira triage to PR merge.

## Modes

| Command | Arguments | What it does |
|---|---|---|
| `/dev-agent audit` | _(none)_ | Scans the full codebase for risks and architectural issues; tracks findings across runs (new/persisted/resolved), escalates persistent findings to high severity after 3+ runs, and offers to create Jira tickets |
| `/dev-agent fix` | `[ticket key or URL]` or `[description]` | Diagnoses a bug with side-effect checking, surfaces pre-existing audit findings for affected files, applies a scoped fix, runs tests with a pre-commit review gate, opens a PR, and transitions the Jira ticket |
| `/dev-agent refix` | `[ticket] [rejected PR]` | Re-diagnoses after a fix was rejected — classifies rejection reason (root cause / side effects / both), cross-references audit findings for side-effect rejections, applies a corrected fix on a new branch, and offers to auto-verify |
| `/dev-agent build` | `[ticket key or URL]` or `[description]` | Generates a full feature from a Jira ticket with duplicate endpoint guard, destructive migration safety, AC coverage check, and BE+FE wiring |
| `/dev-agent sweep` | _(none)_ or `--manual "desc1, desc2"` | Batch-processes all open assigned Jira tickets end-to-end with scope preview, routing confirmation, and intra-ticket checkpoint/resume. Use `--manual` to process descriptions without Jira. |
| `/dev-agent verify` | `[ticket] [PR]` or `[ticket] [PR] --comment` | Pre-merge root cause check — independently traces the code path, surfaces pre-existing audit findings in changed files, and returns a SAFE TO MERGE / DO NOT MERGE / NEEDS DISCUSSION verdict. Add `--comment` to post findings as a GitHub review. |
| `/dev-agent respond` | `[your PR]` | Addresses all open review comments (auto-applies GitHub Suggestions), surfaces pre-existing audit findings in changed files, pushes updates, polls required CI checks, then re-requests review |
| `/dev-agent review` | `[colleague's PR]` | Reviews a colleague's PR with urgency calibration, stale thread escalation, pre-existing audit findings awareness, new pattern detection, inline comments, verdict, and Slack notification |
| `/dev-agent follow-up` | `[PR]` or _(none for all)_ | Shows a PR health dashboard (CI status, review count, unresolved threads) before nudging; posts Slack nudges oldest-first; escalates to a GitHub comment for PRs open 7+ days |
| `/dev-agent setup <url> [url2 ...]` | Confluence, Jira, or any web URL | Reads setup docs, deduplicates steps, snapshots machine state, executes, and verifies |
| `/dev-agent setup --rollback [id]` | Snapshot ID or _(none to list)_ | Rolls back a previous setup session — restores config files, uninstalls brew/npm/pip packages, removes created files |
| `/dev-agent setup --diff <id1> <id2>` | Two snapshot IDs to compare | Compares two setup snapshots side by side — shows added/removed packages and config file changes between sessions |
| `/dev-agent pr` | `[ticket key or URL]` or _(none)_ or `--draft` | Opens a PR for the current branch using the project's PR template — labels, milestone, and reviewer applied automatically; offers optional Jira ticket transition. Pass `--draft` to open as a draft. |
| `/dev-agent refactor` | _(IDE selection)_ or `[file]` or `[file:start-end]` or `"[description]"` or `--from-audit <n>` | Restructures code without changing behavior — coverage gate before touching anything, plan shown for approval, full test suite after, PR with quality label. |
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
| Audit finding keeps recurring across runs | `audit` (auto-escalates after 3 runs) → `refactor --from-audit <n>` |
| Audit finding needs structural cleanup | `audit` → `refactor --from-audit <n>` |
| Inline refactor (file, lines, or IDE selection) | `refactor <target>` |
| Review a colleague's PR | `review` |
| Manual code work done, need a PR | `pr` |
| New machine / environment setup | `setup <url>` |

## Requirements

- [Claude Code](https://claude.ai/code) installed and authenticated
- `gh` CLI authenticated (`gh auth status`)
- Atlassian MCP configured (for Jira access) — verified at startup for Jira-dependent modes
- Slack MCP configured (for Slack posting) — verified at startup for sweep


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
| `version` | Schema version — managed automatically, never set this manually | `1` |
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
