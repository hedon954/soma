---
name: soma-development
description: Applies Soma's project-wide development SOP and product invariants. Use when implementing, fixing, refactoring, testing, or reviewing Soma SwiftUI, SwiftData, ReAct Agent, health import, records, insights, or settings behavior.
---

# Soma Development SOP

Use this workflow for every product-code change. `CLAUDE.md` is the engineering contract,
the current PRD defines scope, and Accepted ADRs define durable boundaries.

## 1. Establish the change contract

1. Read `docs/prd/004-soma-current-product.md` and the relevant acceptance rows.
2. Read `docs/adr/README.md` and every ADR touched by the change.
3. Write down the user-visible success path, empty state, failure state, privacy impact, and
   data that must survive navigation or restart.
4. Identify whether the change belongs to App, Models, Services, Views, or Components.
5. If it contradicts an Accepted ADR or adds a durable dependency/data flow, create a new ADR
   before implementation.

Do not add a top-level GUI, account system, background server, unapproved external API, custom
Agent Tool, or model thinking display as a speculative convenience.

## 2. Protect Soma's invariants

- Chat is the create path; lists and details are the review/correction path.
- Missing facts remain `nil`; never make a record look complete by guessing.
- Agent writes happen through fixed Tool Calls, not by parsing final prose.
- Tool Schema is system-owned; Skills are progressively disclosed and user-editable.
- One user message maps to one Trace; stream Event updates without token-level database rows.
- Demo and personal spaces remain isolated.
- External data is normalized, cursor-based, idempotent, and deletion-aware.
- Real user media and health data never become fixtures, screenshots, logs, or Issue content.

## 3. Implement the smallest vertical slice

1. Add or update the narrowest deterministic test.
2. Keep SwiftData mutation on `@MainActor`.
3. Reuse current record and deletion rules instead of duplicating them in a View.
4. Preserve source evidence separately from AI observations and derived metrics.
5. Make errors actionable and keep successful prior Tool writes truthful.
6. Add accessibility labels and verify long Chinese text and empty optional fields.

When touching a file already over the 500-line soft limit, avoid making it broader. Extract a
cohesive type when that can be done without mixing unrelated behavior.

## 4. Verify in increasing scope

1. Run the narrowest test or build while iterating.
2. Run `make format` for intentional source changes.
3. Run `make check` as the fast static gate while iterating.
4. Run `make verify` before declaring completion.
5. For UI changes, launch an iPhone simulator and inspect the affected flow.
6. For media, speech, HealthKit, signing, or TestFlight changes, document the applicable manual
   device scenario.
7. Update PRD for product scope, ADR for durable decisions, and Changelog for shipped behavior;
   do not turn those files into implementation diaries.

## Definition of done

- Product and privacy behavior match the current PRD.
- Missing fields, derived values, data-space isolation, and external import idempotency remain
  correct.
- Failure and cancellation are visible and recoverable.
- Tests cover deterministic behavior.
- No secret, real health data, generated Xcode project, archive, or local config enters Git.
- `make verify` passes.
