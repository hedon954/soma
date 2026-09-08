---
name: soma-ui-development
description: Design, implement, or review Soma SwiftUI screens and components using the product's semantic dual-theme system, frequency-first information architecture, reviewable record patterns, and visual QA contract. Use for Soma UI changes; use soma-development alongside it for project-wide engineering gates.
---

# Soma UI Development

Use the current PRD and Accepted ADRs as the product contract. This skill supplies the visual and interaction rules that are easy to lose during later iterations; it does not authorize new product scope, persistence fields, data flows, or Agent tools.

## Start from the task

1. Identify the screen, its highest-frequency user outcome, and the source visual or nearby implemented pattern.
2. Read [design-system.md](references/design-system.md) before changing tokens, surfaces, typography, spacing, theme behavior, or shared components.
3. Read [screen-contracts.md](references/screen-contracts.md) when changing a root page, navigation, settings order, empty/error state, or secondary list/detail.
4. Read [workout-records.md](references/workout-records.md) whenever training plans, records, logical groups, sides, targets, rest, or guided-workout progress are shown or edited.
5. Read [visual-qa.md](references/visual-qa.md) before handing off any visible change.

## Make the design decision

- Put the highest-frequency task on the shortest path. Move configuration and debugging down, but keep direct feedback at the bottom of Settings.
- Prefer one clear hierarchy over many equal cards. Use page background, main card, inset block, divider, then typography—not extra borders or colors—to express nesting.
- Root titles are compact and centered. Do not introduce large navigation titles on Tab roots.
- Use black and white for navigation, focus, primary actions and selection. Cyan, orange, green, blue, violet, coral, amber and system red are sparse semantic colors, never a global brand tint.
- Give business-category icons their semantic color; do not default training, meal, body or trend icons to black merely because the primary interaction system is monochrome.
- Separate category, metric and status color. `AppSemanticRole` answers what record this is; `AppMetricRole` answers what is measured; `AppStatusRole` only answers whether an evidence-backed threshold is positive, cautionary or critical. Metric role wins over page or record category.
- Give chart marks the same role as the metric: frequency/continuity uses cyan, load/capacity orange, recovery green, performance violet, body measurements blue and vital signs coral. Lines, points, bars and area fills must not fall back to the black/white interaction tint; axes, grid lines and separators stay neutral.
- Use multiple colors in one series only when thresholds, zones or outliers have deterministic domain meaning. Never add rainbow segments merely to make a chart look richer.
- Use `AppSemanticRole` and `SemanticIconBadge` for business-entry icons, and `AppMetricRole` with `MetricHeading` for metric titles. Each metric needs a specific SF Symbol; one generic training icon for every metric is a design failure.
- Render every muscle map with the training semantic color: stronger orange for primary/high intensity and a lighter orange for secondary/low intensity. Never use the black/white interaction tint for active muscles.
- Treat color as state information, not card decoration. Ordinary cards, message surfaces and navigation stay neutral; category colors belong on a small icon, progress mark or necessary warning.
- Preserve native navigation, sheets, context menus, swipe actions, text selection, pickers, Charts, media and accessibility behavior.
- Design both light and dark at the same time. Light is a pure-white page with light-gray grouped cards; dark is a pure-black page with two dark-gray surface levels.
- Chat body and user messages use Dynamic Type Subheadline Light. Raise headings and explicit emphasis only to Medium, keep metadata Caption, and do not solve hierarchy with Bold/Semibold blocks.
- User messages use the theme inset surface. Never place repeated white message bubbles on the dark page.
- Unselected root-tab icons are outline symbols; the selected item may use its fill counterpart and a neutral system selection background.
- The coach composer contains only plus, text, microphone and send. Keep the three Skill shortcuts visually compact while retaining a 44-point hit target.
- Every chat message shows date and time. AI prose uses the controlled Markdown layout in `CoachResponseView`; never render model-authored arbitrary UI.
- AI prose starts at the message area's leading edge. Do not reserve a repeated avatar or decorative-icon column.

## Implement without losing truth

- Views render values and collect intent; existing Stores and Services remain the mutation boundary.
- Business records expose one editable current state. Training plans and exercise definitions must not introduce version numbers, revision history, version pickers, restore actions, or version-suffixed labels. A plan detail opens directly into its current parameters and saves back to that plan.
- A started or completed training Session preserves an immutable prescription snapshot as execution evidence. Editing the current plan only affects future Sessions and must never rewrite historical facts.
- Missing facts stay `nil` and display as an em dash or disappear when the whole metric has no evidence. Zero weight means self-weight only where the data model already defines that meaning.
- Reuse the same record draft/projection in chat and detail editors. A more compact card must not rebuild ordered evidence from aggregate sets/reps/weight fields.
- Ignore rest when deciding whether consecutive workout groups share one display run. Hide after-group rest for the final logical group, while preserving between-side rest and all stored evidence.
- In plan authoring, edit between-set rest and between-side rest once at the exercise level beside laterality. Show between-side rest only for `.both`; do not repeat planned rest fields inside each set. Compile between-set rest to non-final logical sets when a Session starts, while actual workout rest remains per-set evidence.
- Preserve primary/secondary muscle identity when aggregating a plan. Target-set count may scale intensity, but must not promote an accumulated secondary muscle into primary focus.
- In exercise detail, keep primary muscles, secondary muscles, coaching notes, the two-sided muscle map, and its legend in one Standard Action list row. Do not let `Form` create spacer-like rows from standalone dividers, maps, or legends.
- When an exercise detail is opened from a plan, show that plan prescription first. Separate latest training, capacity trend and record rows; use exact recorded dates on chart axes and compact heterogeneous sets without visible group numbers.
- Keep failure recoverable. Preserve successful work, drafts, selected media, completed training progress, and recorded evidence across retry.
- Keep new files focused and below the repository's 500-line soft limit.

## Verify the result

- Add deterministic tests for any formatter, projection, grouping, ordering, theme mapping, or state transition.
- When changing colors, test contrast on the actual semantic surface and verify that the page/card/inset luminance order remains visible in both themes.
- Audit data marks, metric icons and category icons separately from navigation. Neutral Tab icons and primary controls are correct; black or page-wide-orange metric marks are not.
- Use the shared `appToggleStyle()` for Switches so enabled state remains visible in both themes; preserve labels and non-color state cues.
- Render the affected flow with fictional data in light and dark mode. Also inspect long Chinese text, missing values, keyboard, scrolling, safe area and a large Dynamic Type size.
- Compare implementation and source design at the same viewport and state. Fix P0/P1/P2 differences before handoff and record the evidence in `design-qa.md` for product-wide redesigns.
- Run `make format`, `make check`, and `make verify` as required by `soma-development`.
