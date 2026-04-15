# Mode: pr

## Usage

```
/dev-agent pr
/dev-agent pr [Jira link or ticket key]
/dev-agent pr [Jira link or ticket key] --draft
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
Read config. Detect `--draft` flag — store as `DRAFT_PR=true` or `false`.

Check current branch:
```bash
git branch --show-current
```
Store as `CURRENT_BRANCH`. If it matches `{base_branch}` or `master`: stop.
```
⛔ You're on {base_branch}. Checkout a feature branch first before opening a PR.
```

Check for uncommitted changes:
```bash
git status --porcelain
```
If dirty: warn but do not stop — user may have intentionally staged partial changes.

Check commits vs base branch:
```bash
git log {base_branch}..HEAD --oneline
```
If no commits ahead: stop.
```
⛔ No commits ahead of {base_branch}. Nothing to PR.
```

**Duplicate PR guard:** check for an existing open PR on this branch:
```bash
gh pr list --head {CURRENT_BRANCH} --repo {REPO} --state open --json number,url --jq '.[0]'
```
If one exists: stop.
```
⛔ An open PR already exists for this branch: {PR_URL}
   Use /dev-agent respond to address comments or /dev-agent follow-up to nudge reviewers.
```

Detect Jira ticket:
- If an argument was provided (link or key): use it as `TICKET_LINK`.
- If no argument: try to infer from the current branch name. Pattern `^(bug|feat|fix)/([A-Z]+-[0-9]+)` — extract the ticket key and set as `TICKET_LINK` (key only, not a URL). If the branch doesn't match, set `TICKET_LINK=none`.

## Phase 1 — Create PR
Run **Shared: Create PR** with `TICKET_LINK`. `DRAFT_PR` is already set from Phase 0 — **Shared: Create PR** reads this flag and passes `"draft": true` automatically when `DRAFT_PR=true`.

**Optional Jira transition** — skip if `TICKET_LINK=none` or `DRAFT_PR=true`. Ask: "Transition the Jira ticket to 'For Review'? (yes / no)". If yes: transition via Atlassian MCP (cloudId = `{jira_domain}`). If transition fails: note in report and continue.

Run **Shared: Post Slack Thread** — if Slack MCP fails: note in report and continue. Skip if `DRAFT_PR=true` (draft PRs are not ready for review).

Write context per **Shared: Session Context** — if `TICKET_LINK≠none`, write the `build` key to the per-ticket context file: `pr_number`, `pr_url`, `branch` (`CURRENT_BRANCH`), `timestamp`. This allows `verify` to find the PR context when run after `pr` mode. Skip if `TICKET_LINK=none` (no ticket key to key the file on) or if the write fails (note in report, continue).

## Phase 2 — Report
```
## PR — [title]
PR: {PR_URL}
Branch: {branch}
Commits: {n}
Draft: {yes / no}
Labels: {labels}
Reviewer: {pr_reviewer_team}
Milestone: {pr_milestone}
Jira: {TICKET_LINK or '—'}
```
