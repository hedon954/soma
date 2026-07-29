# Soma coding instructions

Read and follow `/CLAUDE.md` as the canonical repository contract.

For product-code changes, apply `/.claude/skills/soma-development/SKILL.md`. Read the current
PRD, affected Accepted ADRs, and `/docs/acceptance.md` before editing.

Never add real health data, body photos, API keys, signing assets, private traces, generated
Xcode projects, or DerivedData to the repository. Preserve chat-first creation, reviewable CRUD,
missing-is-nil, fixed native Tool Calling, Trace Event streaming, deterministic metrics, and
cursor-based external import invariants. Use `make check` while iterating and run `make verify`
before completion.
