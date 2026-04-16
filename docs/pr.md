# pr

Opens a PR for the current branch — applies labels, milestone, and reviewer team automatically, and optionally transitions the Jira ticket.

## When to use

- You've written code manually and just need the PR opened correctly
- You want the PR template, labels, milestone, and reviewers set without doing it by hand
- You optionally want to transition the Jira ticket to "For Review" at the same time

**vs. fix / build:**
- Use `fix` or `build` when you want dev-agent to write the code too
- Use `pr` when the code is already written and you just need the PR

## Usage

```
/dev-agent pr
/dev-agent pr [Jira ticket key or URL]
/dev-agent pr [Jira ticket key or URL] --draft
```

```
/dev-agent pr
→ Reads the current branch, infers title + body from commits and diff, creates PR

/dev-agent pr HQA-37771
→ Same, but includes the Jira ticket link in the PR body

/dev-agent pr HQA-37771 --draft
→ Opens as a draft PR (no Slack notification, no Jira transition)
```

## What it does

### 1. Pre-checks

Before creating anything, pr runs several checks:

- **Not on the base branch** — stops if you're on `main` (or whatever your base branch is)
- **Has commits** — stops if there are no commits ahead of the base branch
- **No existing open PR** — stops if an open PR already exists for this branch, and redirects you to `respond` or `follow-up`
- **Warns about uncommitted changes** — doesn't block, but flags them so you're aware

### 2. Jira ticket detection

If you pass a ticket key or URL, it's used as the Jira link in the PR body. If you don't, pr looks at the branch name for a ticket key pattern (e.g., `bug/HQA-37771` → `HQA-37771`).

### 3. PR creation

Creates the PR using your project's PR template with:
- Title inferred from commits and diff
- Labels from config
- Milestone from config
- Reviewer team from config

### 4. Optional Jira transition

If a ticket was detected and the PR is not a draft:

```
Transition the Jira ticket to 'For Review'? (yes / no)
```

This is optional — pr mode is typically used for manual branches where you may want full control over board state.

### 5. Slack notification

Posts a PR notification to your team's Slack channel (unless `--draft` is passed — draft PRs are not ready for review).

## What you'll see

```
## PR — Add node export endpoint

PR: https://github.com/org/repo/pull/519
Branch: feat/HQA-35223
Commits: 4
Draft: no
Labels: feature, needs-review
Reviewer: @team-reviewers
Milestone: Q2 Sprint 3
Jira: HQA-35223 → For Review ✅
```

## Arguments

| Argument | Description |
|---|---|
| _(none)_ | Reads branch name for ticket key; title + body inferred from commits |
| `HQA-123` or full Jira URL | Explicitly links this ticket in the PR body |
| `--draft` | Opens as a draft — no Slack notification, no Jira transition offered |

## Tips

- Works best right after you've pushed your branch — all commits already there
- If you have uncommitted changes, commit them first (or stash them) for a clean PR
- If the branch name follows the `bug/HQA-123` or `feat/HQA-123` pattern, the ticket is detected automatically — no need to pass it as an argument
- For draft PRs, run `pr` again without `--draft` when you're ready to request review

## Before / After

| | Run |
|---|---|
| Before | Have a branch with commits ready to PR |
| After: PR opened | Wait for review |
| After: reviewer left comments | `respond <PR number>` |
| After: need to nudge reviewers | `follow-up <PR number>` |
