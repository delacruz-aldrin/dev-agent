# Mode: follow-up

## Usage

```
/dev-agent follow-up [PR link or number]   ← nudge for one PR
/dev-agent follow-up                       ← nudge for ALL your open unapproved PRs
```

Posts a review nudge to the existing Slack thread for your PR(s). Finds the thread by searching for the PR URL — never creates a new top-level message if a thread already exists. Each nudge uses a completely different angle from previous ones in the same thread.

**Slack only — never touches GitHub or code.**

**Examples:**
```
/dev-agent follow-up 519
→ Finds the Slack thread for PR #519, posts a warm nudge mentioning @team-reviewers

/dev-agent follow-up
→ Finds all your open PRs without approval, posts a nudge to each thread

/dev-agent follow-up https://github.com/C-FO/baberu/pull/519
→ Same as the first example via full URL
```

**When to use:**
- PR has been open for a day or two without a review
- After pushing updates and wanting to re-ping without being annoying
- End of sprint to clear the review queue

---

## THIS MODE IS SLACK ONLY
Does NOT read/post GitHub comments, run tests, modify files, run git commands, or touch code. If doing any of these — STOP, wrong mode.

## Invocation
```
/dev-agent follow-up [PR link]   ← one PR
/dev-agent follow-up             ← ALL open unapproved PRs
```

## Phase 0 — Config + Ownership + PR Detection
Read config.

**Link provided:** fetch PR via `gh api repos/{REPO}/pulls/{pr_number}`, verify ownership:
```
⛔ This PR wasn't authored by you. /dev-agent follow-up only works on your own PRs.
```

**No link:** resolve current user login, then fetch open PRs:
```bash
CURRENT_USER=$(gh api user --jq '.login')
gh api "repos/{REPO}/pulls?state=open" --jq "[.[] | select(.user.login == \"$CURRENT_USER\") | {number, title, html_url, created_at}]"
```
Filter out already-approved PRs. Sort remaining PRs by `days_open` descending (oldest first). Present a grouped table before nudging:
```
Open PRs queued for nudge (oldest first):
| # | PR | Days Open | Last Activity |
|---|-----|-----------|---------------|
| 1 | #519 — Add export endpoint | 12 days | 3 days ago |
| 2 | #507 — Fix login redirect | 6 days | 1 day ago |
```
Process each sequentially in this order.

## Phase 1 — Status Check
Skip if merged, closed, or already approved.

For each qualifying PR, fetch staleness data from the PR API response:
- `days_open` — days since `created_at`
- `days_since_activity` — days since `updated_at`

Store both for use in the composed message.

## Phase 2 — Find or Create Slack Thread
Using Slack MCP only. Search `#{slack_channel}` in order — stop at first match:
1. Search query: `https://github.com/{REPO}/pull/{pr_number}` — try both raw and `<https://...>` wrapped forms
2. Search query: `{repo_name}/pull/{pr_number}`
3. Search query: `pull/{pr_number}`
4. Search query: PR title verbatim

Do NOT browse recent messages — use targeted text search only. If all four searches return no results, treat as not found.

**Found:** store `thread_ts`.
**Not found:** create parent immediately — do not stop:
```
🔔 PR ready for review — [PR title]
PR: https://github.com/{REPO}/pull/{pr_number}
```
Store returned `thread_ts`.

## Phase 3 — Compose + Send
Read existing thread messages. Write a reply:
- Completely different angle from any previous nudge in this thread
- Mentions `<!subteam^GROUP_ID>` — look up `{slack_group}` via Slack MCP
- Warm, humorous, 2–4 sentences
- Weave in staleness naturally — e.g. "it's been {days_open} days" or "last activity was {days_since_activity} days ago" — but only if it adds to the message, not as a standalone data dump
- Never: "just following up", "circling back", "as per my last", "As an AI"

Send via Slack MCP. Reply in thread using `thread_ts`. Send immediately — no confirmation. Never create a new top-level message if a thread already exists. Never touch GitHub.

**Escalation tier:** after posting the Slack nudge, check `days_open` for this PR:
- `days_open > 7`: offer to also post a GitHub PR comment tagging the assigned reviewers: "This PR has been open {days_open} days without a review. Post a GitHub comment tagging reviewers? (yes / no)". If `yes`: post via `gh api repos/{REPO}/issues/{pr_number}/comments` with `@reviewer1 @reviewer2 — this PR has been waiting {days_open} days. Could you take a look?`
- Otherwise: no GitHub comment.
