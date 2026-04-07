# Mode: pr

## Usage

```
/dev-agent pr
/dev-agent pr [Jira link or ticket key]
```

Opens a PR for the current branch using the project's PR template. Applies labels, milestone, and reviewer team from config automatically.

Use this after doing manual work on a branch — when you've already written the code and just need the PR opened correctly.

**Examples:**
```
/dev-agent pr
→ Reads current branch, infers title + body from commits and diff, creates PR

/dev-agent pr HQA-37771
→ Same, but includes the Jira ticket link in the Tickets section of the PR body

/dev-agent pr https://jira-freee.atlassian.net/browse/HQA-37771
→ Same via full URL
```

**When to use vs fix/build:**
- Use `fix` or `build` when you want dev-agent to write the code too
- Use `pr` when the code is already written and you just need the PR

---

## Phase 0 — Setup
Read config.

Check current branch:
```bash
git branch --show-current
```
If on `main` or `master`: stop.
```
⛔ You're on main. Checkout a feature branch first before opening a PR.
```

Check for uncommitted changes:
```bash
git status --porcelain
```
If dirty: warn but do not stop — user may have intentionally staged partial changes.

Check commits vs main:
```bash
git log main..HEAD --oneline
```
If no commits ahead of main: stop.
```
⛔ No commits ahead of main. Nothing to PR.
```

Detect Jira ticket:
- If an argument was provided (link or key): use it as `TICKET_LINK`.
- If no argument: try to infer from the current branch name. Pattern `^(bug|feat|fix)/([A-Z]+-[0-9]+)` — extract the ticket key and set as `TICKET_LINK` (key only, not a URL). If the branch doesn't match, set `TICKET_LINK=none`.

## Phase 1 — Create PR
Run **Shared: Create PR** with `TICKET_LINK`.

## Phase 2 — Report
```
## PR — [title]
PR: {PR_URL}
Branch: {branch}
Commits: {n}
Labels: {labels}
Reviewer: {pr_reviewer_team}
Milestone: {pr_milestone}
Jira: {TICKET_LINK or '—'}
```
