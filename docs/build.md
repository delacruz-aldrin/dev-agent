# build

Generates a complete feature implementation from a Jira ticket or description — backend endpoint, frontend integration, tests, and PR.

## When to use

- You're assigned a Story or Task ticket for a new feature or endpoint
- You need a full-stack implementation: backend + frontend wired together
- You want every acceptance criterion covered before the PR is opened

## Usage

```
/dev-agent build [Jira ticket key or URL]
/dev-agent build [plain description of the feature]
```

**With a Jira ticket:**
```
/dev-agent build HQA-35223
/dev-agent build https://your-org.atlassian.net/browse/HQA-35223
```

**Without a ticket (manual):**
```
/dev-agent build Add a GET /api/p/nodes/:id endpoint that returns a single node with its translations
/dev-agent build Add a CSV export button to the page list screen
```

## What gets generated

build follows the full stack of your project — it reads existing code first to match your exact patterns:

**Backend:**
- Route entry
- Controller (following your existing conventions)
- Business logic layer (usecase / service / handler, depending on your stack)
- Serializer / response object
- OpenAPI schema fragment (if your project uses it)
- Tests/specs for all new and modified files

**Frontend** (if your project has a frontend):
- TypeScript interfaces for the new/changed response shape
- API client integration (matches your existing client pattern)
- State management update (only if actually needed — explicitly noted if skipped)
- React component or page
- Frontend tests (if your project uses them)

## Acceptance criteria coverage

For Jira tickets, build maps every acceptance criterion to the implementation and shows you a coverage checklist before committing:

```
AC Coverage:
✅ "Users can fetch a single node" → GET /api/p/nodes/:id in nodes_controller.rb
✅ "Response includes all translations" → translations field in node_serializer.rb
❌ "Returns 404 for non-existent nodes" → NOT FOUND — no error handling added
```

For any uncovered AC item, you're asked: **generate it now or skip?**
- `generate` → implements it before continuing
- `skip` → records it under **Skipped AC Items** in the report (never silently dropped)

## Safety checks

### Duplicate endpoint guard
If the ticket or description specifies an HTTP method + path (e.g. `GET /api/p/nodes/:id`), build searches your routes file first. If a matching route already exists, it pauses:

```
A similar route already exists: GET /api/p/nodes/:id at config/routes.rb:42
Is this a new variant or a duplicate? (variant / duplicate / cancel)
```

### Destructive migration check
If the feature requires a database migration and that migration contains a destructive operation (`drop_column`, `drop_table`, `change_column` type change, etc.), build pauses before running it:

```
⚠️ Destructive migration detected: drop_column on users.legacy_token
This cannot be automatically rolled back in production. Confirm? (yes / abort)
```

### Pre-commit review gate
Before committing, build shows you every generated and modified file with a brief description. Options: `yes`, `review` (show full diff), `revert all`.

## What you'll see

```
## New Feature — GET /api/p/nodes/:id

### BE Files Written
  app/controllers/api/p/nodes_controller.rb
  app/usecases/nodes/fetch_node.rb
  app/serializers/node_serializer.rb
  spec/controllers/api/p/nodes_controller_spec.rb
  spec/usecases/nodes/fetch_node_spec.rb

### FE Files Written
  front/src/types/node.ts
  front/src/components/NodeDetail.tsx
  front/src/components/NodeDetail.test.tsx

### AC Coverage
✅ "Users can fetch a single node" → nodes_controller.rb#show
✅ "Returns 404 for non-existent nodes" → nodes_controller.rb#show rescue block
✅ "Response includes all translations" → node_serializer.rb#translations

### Test Suite  ✅ 156 examples, 0 failures
### PR  https://github.com/org/repo/pull/503
### Jira Status  HQA-35223 → For Review
```

## Before / After

| | Run |
|---|---|
| Before | Have the ticket key or a feature description |
| After: PR opened | Wait for review |
| After: reviewer leaves comments | `respond <PR number>` |
| After: want to verify correctness before review | `verify <ticket> <PR number>` |
| After: PR rejected | `refix <ticket> <PR number>` |
