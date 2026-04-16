# follow-up

Shows a PR health dashboard, then posts a Slack nudge to your PR's review thread — with a different angle every time.

## When to use

- Your PR has been open for a day or two without a review
- You just pushed updates after responding to comments and want to re-ping
- End of sprint — clear the review queue
- You want a quick look at the health of all your open PRs before nudging

## Usage

```
/dev-agent follow-up [PR number or URL]   ← nudge for one PR
/dev-agent follow-up                       ← nudge for ALL your open PRs
```

```
/dev-agent follow-up 519
/dev-agent follow-up https://github.com/org/repo/pull/519
/dev-agent follow-up
```

**Only works on your own PRs.** Trying it on someone else's PR will be blocked.

## What happens

### Dashboard (always shown first)

Before sending any nudges, follow-up shows you a health snapshot of all your open PRs:

```
## Your Open PRs
| # | PR | Days Open | Last Activity | CI | Reviews | Unresolved |
|---|-----|-----------|---------------|-----|---------|------------|
| 1 | #519 — Add export endpoint | 12d | 3d ago | ✅ passing | 1 | 2 threads |
| 2 | #507 — Fix login redirect  |  6d | 1d ago | ❌ failing | 0 | 0 threads |
| 3 | #501 — Refactor auth       |  2d | 4h ago | ⏳ pending | 0 | 0 threads |

Nudging all 3 in order above. Reply with PR numbers to skip any (e.g. "skip 2"), or 'yes' to proceed.
```

Already-approved PRs are filtered out — only PRs still waiting for review are shown. The oldest ones appear first.

You can skip specific PRs before nudging proceeds.

### Slack nudges

For each qualifying PR:

1. **Finds the existing thread** — searches Slack by PR URL. Never creates a duplicate top-level message if a thread already exists.
2. **Reads the thread history** — so the next nudge uses a completely different angle from previous ones
3. **Posts a warm, varied reply** — mentions the reviewer group, weaves in how long it's been open, keeps it brief and human

Example nudge reply:
> "This one's been sitting in the queue for 12 days now — like a pizza no one ordered but also no one wants to throw away. <!subteam^ABC123> — if you get a moment, it'd be great to get eyes on #519!"

If CI is failing, that's woven into the nudge naturally too.

### Escalation for old PRs

If a PR has been open for more than **7 days**, follow-up offers to also post a GitHub comment tagging the assigned reviewers:

```
This PR has been open 12 days without a review. Post a GitHub comment tagging reviewers? (yes / no)
```

If `yes`: posts directly on the PR — `@reviewer1 @reviewer2 — this PR has been waiting 12 days. Could you take a look?`

## What you'll see

```
## Follow-up — 3 PRs nudged

| PR | Days Open | CI | Slack |
|----|-----------|----|-------|
| #519 Add export endpoint | 12d | ✅ | ✅ Posted reply in thread |
| #507 Fix login redirect  |  6d | ❌ | ✅ Posted (mentioned CI failure) |
| #501 Refactor auth       |  2d | ⏳ | ✅ Posted reply in thread |

GitHub comment posted for #519 (open 12 days — offered escalation, you approved).
```

## Guardrails

- **Slack-only** — never touches GitHub code or comments (except the 7-day escalation, which is explicit and requires your confirmation)
- **Author check** — blocks immediately if you try to run on someone else's PR
- **No duplicate messages** — finds the existing thread first; only creates a new top-level message if no thread exists at all
- **No repeating angles** — reads the thread history before writing each nudge; each one uses a different framing
- **Approved PRs excluded** — won't nudge PRs that are already approved

## Tips

- Run with no argument at the start of each day for a quick PR health overview
- The dashboard is shown even when you pass a specific PR number — useful as a sanity check
- CI failure is woven into the nudge automatically — reviewers see the issue without you having to explain it separately
