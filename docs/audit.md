# audit

Scans your entire codebase for risks, bugs waiting to happen, and architectural problems — then optionally files them as Jira tickets.

## When to use

- Periodic health check (weekly, before a sprint, before a release)
- You suspect tech debt is accumulating but don't know where
- Before a major refactor — understand what's already broken
- A recurring problem keeps appearing and you want to find the root cause

## Usage

```
/dev-agent audit
```

No arguments. Reads the repo automatically.

## What it scans

audit looks across your entire backend and frontend for:

| Category | What it finds |
|---|---|
| **Production risks** | Code paths most likely to cause bugs right now |
| **Architectural issues** | Inconsistencies slowing down development |
| **Security concerns** | XSS, exposed secrets, token handling, injection risks |
| **Performance** | N+1 queries, missing indexes, unnecessary re-renders |
| **Test coverage gaps** | Critical paths with no specs or tests |
| **BE/FE contract gaps** | API response shapes that don't match TypeScript interfaces |
| **Frontend risks** | Stale state, missing error/loading states, type safety gaps |
| **Refactor candidates** | Files that should be cleaned up first |

## Tracking findings across runs

Every finding gets a fingerprint (hash). On each run, audit compares against the previous run:

- **NEW** — didn't exist last time
- **PERSISTED** — still present, with the date it was first seen
- **RESOLVED** — existed before, no longer present

The delta is shown at the top of every report: `N new | M persisted | P resolved`.

### Auto-escalation

A medium-severity (🟡) finding that persists for **3 or more consecutive runs** is automatically escalated to high severity (🔴↑). This surfaces tech debt that keeps getting pushed aside — it can't hide indefinitely.

## Ticket creation

At the end of the audit, you're asked which findings to file as Jira tickets:

1. Choose findings by number (or "all")
2. Assign to yourself or leave unassigned
3. Choose which Jira project (if you have multiple configured)

Before creating each ticket, audit searches for an existing open ticket with the same summary — **no duplicates** are created.

**Volume cap:** if you select more than 5 findings, audit pauses and asks you to confirm or reduce to the top 5 by severity. Creating too many tickets at once overwhelms the backlog.

## What you'll see

```
## Audit Report — [Project Name]
Delta since last audit: 3 new | 5 persisted | 1 resolved

### Top Production Risks
🔴↑ (escalated from 🟡 — persisted 4 runs) app/serializers/user_serializer.rb
    Nil check missing for suspended users — will 500 on any suspended user fetch

### Architectural Issues
🟡 [NEW] app/controllers/exports_controller.rb
    Business logic in controller — 3 separate concerns, should move to usecase

### Security Concerns
🔴 [PERSISTED since 2026-04-01] config/initializers/cors.rb
    Wildcard CORS origin — accepts requests from any domain
...

## Tickets Created
| # | Type | Priority | Summary | Ticket |
...
```

## How it connects to other modes

Audit findings are shared with other modes automatically via a shared findings file (`.claude/dev-agent/context/_audit.json`). When you run fix, verify, refix, review, or respond on files that have matching findings, those findings appear as context — no extra steps needed.

| After audit | Run this |
|---|---|
| Found a structural problem | `refactor --from-audit <n>` — directly targets the numbered finding |
| Found a bug | `fix` — will automatically surface the related audit finding |
| Finding keeps recurring | It auto-escalates after 3 runs; then `refactor --from-audit <n>` to resolve it |

## Requirements

- No Jira ticket needed to start
- Atlassian MCP must be reachable **only** for the ticket creation step at the end — if it's unavailable, the audit report is still produced in full
