---
name: soma-development
description: Applies Soma's project-wide development SOP and product invariants. Use when implementing, fixing, refactoring, testing, or reviewing Soma SwiftUI, SwiftData, ReAct Agent, health import, records, insights, or settings behavior.
---

# Soma Development SOP

Use this workflow for every product-code change. `CLAUDE.md` is the engineering contract,
the current PRD defines scope, and Accepted ADRs define durable boundaries.

## 1. Establish the change contract

1. Read `docs/prd/README.md`, the compacted origin PRD, living PRDs in the current 3-version window, and the relevant acceptance rows.
2. Read `docs/adr/README.md` and every ADR touched by the change.
3. Search `docs/bugs/README.md` for known failure mechanisms in the touched area.
4. Lifecycle links apply only to documents already in Git. If an uncommitted implementation or
   draft was superseded in the same working tree, delete it; do not leave transition notes.
   When a committed document is revised or replaced, add reciprocal lifecycle links in both
   documents and update their directory README; never leave a one-way supersession reference.
5. Write down the user-visible success path, empty state, failure state, privacy impact, and
   data that must survive navigation or restart.
6. Identify whether the change belongs to App, Models, Services, Views, or Components.
7. If it contradicts an Accepted ADR or adds a durable dependency/data flow, create a new ADR
   before implementation.

Do not add a top-level GUI, account system, background server, unapproved external API, custom
Agent Tool, or model thinking display as a speculative convenience.

## 2. Protect Soma's invariants

- Chat is the default create path for unstructured facts. A specialized structured GUI is allowed
  only when an Accepted PRD/ADR authorizes it; current exceptions are training-plan authoring
  (ADR 0036) and guided set confirmation (ADR 0030).
- Missing facts remain `nil`; never make a record look complete by guessing.
- Agent writes happen through fixed Tool Calls, not by parsing final prose.
- Tool Schema is system-owned; Skills are progressively disclosed and user-editable.
- One user message maps to one Trace; stream Event updates without token-level database rows.
- Demo and personal spaces remain isolated.
- External data is normalized, cursor-based, idempotent, and deletion-aware.
- Real user media and health data never become fixtures, screenshots, logs, or Issue content.

### LLM prompts

- Give each LLM request scenario one complete `xxx_system_prompt.md` and one complete `xxx_user_prompt.md`.
  Send the System file as-is and put all user, session, personalization, and Skill context in named
  `{{snake_case}}` User placeholders. Keep one file per built-in Skill. Image endpoints use their native prompt field.
- Keep tool descriptions, parameter guidance, schemas, and tool feedback with the tool code. Send tool
  definitions as native API metadata. Keep button presets, composer drafts, interface copy, and data formatters
  with the feature code.
- Update the [prompt source catalog](../../../docs/engineering/prompt-source-catalog.md) in the same change
  when adding, moving, removing, or changing the inputs of a model request. Record its call site and context
  sources. Changes to remote data flows must follow the accepted PRD/ADR privacy boundary.
- Preserve System text across users and turns within a build, keep Tool ordering deterministic, and preserve
  frozen Job snapshots. Run `make check` for prompt pairs and resource references, and `make verify` for
  runtime assembly. Verify Server builds when changing their resource packaging.

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
6. For media, speech, signing, or TestFlight changes, document the applicable manual
   device scenario.
7. Update PRD for product scope, ADR for durable decisions, and Changelog for shipped behavior;
   do not turn those files into implementation diaries.

## 5. Commit one small feature at a time

- Give each independently reviewable feature or fix its own commit with its related tests and docs.
- Stage only the files or hunks needed for that change. Keep shared groundwork and release metadata
  in their own commits when they can stand alone.
- Keep tightly coupled changes together when splitting them would leave a broken intermediate state.

## Definition of done

- Product and privacy behavior match the current PRD.
- Missing fields, derived values, data-space isolation, and external import idempotency remain
  correct.
- Failure and cancellation are visible and recoverable.
- Tests cover deterministic behavior.
- Critical regressions have a `docs/bugs/` record and an executable prevention rule where
  automation is possible.
- Revised PRD/ADR/Bug/Research/engineering documents have reciprocal lifecycle links, and the
  lifecycle checker passes.
- No secret, real health data, generated Xcode project, archive, or local config enters Git.
- `make verify` passes.
