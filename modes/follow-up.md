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
Skip the dashboard and go straight to Phase 1 for that single PR.

**No link:** resolve current user login, then fetch all open PRs authored by you:
```bash
CURRENT_USER=$(gh api user --jq '.login')
gh api "repos/{REPO}/pulls?state=open&per_page=50" --jq "[.[] | select(.user.login == \"$CURRENT_USER\")]"
```

For each PR, collect the following health data:
- `days_open` — days since `created_at`
- `days_since_activity` — days since `updated_at`
- `ci_status` — fetch latest check-run conclusions: `gh api repos/{REPO}/commits/{head_sha}/check-runs --jq '[.check_runs[] | .conclusion] | if any(. == "failure") then "failing" elif any(. == null) then "pending" else "passing" end'`
- `review_count` — number of submitted reviews: `gh api repos/{REPO}/pulls/{pr_number}/reviews --jq '[.[] | select(.state != "DISMISSED")] | length'`
- `unresolved_threads` — `gh api repos/{REPO}/pulls/{pr_number}/comments --jq '[.[] | select(.position != null)] | length'` (approximate)
- `approved` — `gh api repos/{REPO}/pulls/{pr_number}/reviews --jq '[.[] | select(.state == "APPROVED")] | length > 0'`

Filter out already-approved PRs (`approved = true`). Sort remaining PRs by `days_open` descending (oldest first).

**Show PR dashboard:**
- **Multiple PRs (2+):** always show the dashboard table and wait for confirmation before nudging:
  ```
  ## Your Open PRs
  | # | PR | Days Open | Last Activity | CI | Reviews | Unresolved |
  |---|-----|-----------|---------------|-----|---------|------------|
  | 1 | #519 — Add export endpoint | 12d | 3d ago | ✅ passing | 1 | 2 threads |
  | 2 | #507 — Fix login redirect | 6d | 1d ago | ❌ failing | 0 | 0 threads |
  | 3 | #501 — Refactor auth | 2d | 4h ago | ⏳ pending | 0 | 0 threads |

  Nudging all 3 in order above. Reply with PR numbers to skip any (e.g. "skip 2"), or 'yes' to proceed.
  ```
  Wait for response before nudging. If user skips any PRs, remove them from the list.

- **Single PR (1 remaining after filter):** skip the confirmation prompt — print the single-PR health line and proceed directly to nudging:
  ```
  ## PR #519 — Add export endpoint
  12d open | last activity 3d ago | ✅ CI passing | 1 review | 2 unresolved threads
  ```
  No "yes/skip" gate — the user already named the PR (or there's only one), so go straight to Phase 1.

- **Zero PRs after filter:** stop — "No open unapproved PRs found."

## Phase 1 — Status Check
Skip if merged, closed, or already approved.

For each qualifying PR, use the health data already collected in Phase 0 (do not re-fetch):
- `days_open` — days since `created_at`
- `days_since_activity` — days since `updated_at`
- `ci_status` — as fetched above
- `unresolved_threads` — as fetched above

If `ci_status = failing`: weave CI failure into the nudge naturally ("heads up, CI is also failing — might be worth a look while reviewing").

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
- Look up `{slack_group}` group ID via Slack MCP (reuse cached `SLACK_GROUP_ID` if already fetched this session). If `SLACK_GROUP_ID≠none`: mention `<!subteam^{SLACK_GROUP_ID}>`. If `SLACK_GROUP_ID=none`: omit the mention — never write the literal placeholder
- Warm, humorous, 2–4 sentences
- Weave in staleness naturally — e.g. "it's been {days_open} days" or "last activity was {days_since_activity} days ago" — but only if it adds to the message, not as a standalone data dump
- Never: "just following up", "circling back", "as per my last", "As an AI"

**Positive example of an acceptable nudge reply:**
> "This one's been sitting in the queue for 6 days now — like a pizza no one ordered but also no one wants to throw away. <!subteam^ABC123> — if you get a moment, it'd be great to get eyes on #519!"

Match this energy: specific, light, brief, clear ask. Vary the metaphor/framing each time — never reuse the same angle across nudges in the same thread.

Send via Slack MCP. Reply in thread using `thread_ts`. Send immediately — no confirmation. Never create a new top-level message if a thread already exists. Never touch GitHub.

**Escalation tier:** after posting the Slack nudge, check `days_open` for this PR:
- `days_open > 7`: offer to also post a GitHub PR comment tagging the assigned reviewers: "This PR has been open {days_open} days without a review. Post a GitHub comment tagging reviewers? (yes / no)". If `yes`: post via `gh api repos/{REPO}/issues/{pr_number}/comments` with `@reviewer1 @reviewer2 — this PR has been waiting {days_open} days. Could you take a look?`
- Otherwise: no GitHub comment.
