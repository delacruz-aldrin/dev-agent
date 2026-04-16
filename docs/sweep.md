# sweep

Processes all your open assigned Jira tickets end-to-end — branch, fix or build, tests, PR, Jira transition, Slack — one by one, autonomously.

## When to use

- End-of-sprint batch processing: clear multiple tickets at once
- You have several bugs/stories to tackle and want to run them sequentially without babysitting
- You want to use `fix` or `build` logic across multiple tickets but only have to set it up once

## Usage

```
/dev-agent sweep
/dev-agent sweep --manual "description 1, description 2, ..."
```

**No argument** — queries Jira for all open tickets assigned to you in the configured project(s):
```
/dev-agent sweep
```

**`--manual`** — skip Jira and process a list of descriptions instead:
```
/dev-agent sweep --manual "fix login redirect bug, add CSV export endpoint, fix null pointer in user serializer"
```

Use `--manual` when tickets don't exist yet, or when you're working outside Jira.

## What happens

### Phase 0 — Board scan

sweep fetches all open tickets assigned to you in your Jira project. It tries multiple JQL query variations until it finds results.

### Phase 1 — Prioritization

Tickets are grouped and presented for your review — **bugs first**, then stories/tasks:

```
| # | Ticket | Type | Title |
|---|--------|------|-------|
| 1 | HQA-123 | 🐛 Bug → fix | Login redirects to 404 after reset |
| 2 | HQA-456 | 📋 Story → build | Add CSV export endpoint |
| 3 | HQA-789 | 📋 Task → build | Update node serializer fields |
```

You set the priority order. Then sweep shows a **scope preview** — the planned branches and modes for all tickets — and waits for final confirmation before touching any code.

### Phase 2 — Sequential processing

For each ticket, sweep runs the full `fix` or `build` mode:
- Bug tickets → `fix` mode
- Story/Task/Improvement tickets → `build` mode

**Interactive gates are suppressed** — sweep is autonomous. It does not pause at the pre-commit review gate or after tests. If tests fail after an automatic fix attempt, the ticket is reverted and skipped (noted in the final report).

After each ticket:
- PR is opened
- Jira ticket is transitioned to "For Review"
- Slack thread is posted (each ticket gets a different message angle)

### Checkpoint and resume

sweep writes progress to `.claude/sweep-checkpoint.json` after every major milestone (branch created → code applied → tests passed → PR created → Jira transitioned → Slack posted). If sweep is interrupted at any point — network failure, error, manual stop — run it again:

```
/dev-agent sweep
```

It detects the checkpoint and asks: **Resume from where it left off? (yes / no)**

If `yes`, completed tickets are skipped and processing continues from the last milestone of the in-progress ticket.

## Manual mode

`--manual` bypasses Jira entirely. Each comma-separated description is treated as a manual input — equivalent to running `/dev-agent fix "..."` or `/dev-agent build "..."` per description. No Jira transitions, no ticket deduplication.

sweep auto-routes each item:
- Descriptions containing "fix", "bug", "broken", "error", "crash", "regression" → `fix` mode
- Everything else → `build` mode

The routing plan is shown before anything runs — you can adjust which mode each item uses.

```
Manual sweep — routing plan:
| # | Description | Mode |
|---|-------------|------|
| 1 | "fix login redirect bug" | fix |
| 2 | "add export endpoint" | build |

Correct? (yes / change 1 to build / remove 2)
```

## What you'll see

```
## Sweep Report

### Summary
✅ Completed: 3 tickets
❌ Skipped:   1 ticket (HQA-789 — FE tests failed after auto-fix; see below)

### Results
| Ticket | Type | Branch | PR | Status |
|--------|------|--------|----|--------|
| HQA-123 | fix | bug/HQA-123 | #502 | ✅ Done |
| HQA-456 | build | feat/HQA-456 | #503 | ✅ Done |
| HQA-789 | build | feat/HQA-789 | — | ❌ Skipped — FE tests failed |

### Skipped Tickets
HQA-789: Frontend tests failed after auto-fix attempt. Run `/dev-agent build HQA-789` manually.
```

## Guardrails

- **Scope preview before any code runs** — you see every ticket and planned branch before committing to the sweep
- **One ticket at a time** — never processes two tickets in parallel; never leaves a ticket half-done
- **Test failures abort that ticket** — changes reverted cleanly, sweep continues to the next ticket
- **Checkpoint resume** — safe to interrupt; progress is never lost
- **Autonomous gates only** — interactive gates (pre-commit review, etc.) are suppressed; use `fix` or `build` individually if you want to stay hands-on
- **Both Atlassian and Slack MCP checked upfront** — if either is unreachable, sweep stops before doing any work

## Before / After

| | Run |
|---|---|
| Before | Have your Jira board open; optionally reprioritize tickets first |
| After: all PRs opened | Wait for reviews; use `follow-up` to nudge if needed |
| After: a PR gets review comments | `respond <PR number>` on that specific PR |
| After: a PR is rejected | `refix <ticket> <PR number>` on that specific ticket |
