---
name: soma-release
description: Prepares and verifies a Soma GitHub or TestFlight release. Use when changing versions, updating the changelog, creating release tags, archiving for TestFlight, or validating release metadata and signing boundaries.
---

# Soma Release SOP

## 1. Establish the release

1. Choose `vMAJOR.MINOR.PATCH` and confirm the release scope is already implemented.
2. Update `MARKETING_VERSION` and increment `CURRENT_PROJECT_VERSION` in `project.yml`.
3. Move user-visible entries from `CHANGELOG.md` Unreleased into the matching version section.
4. Call out privacy changes, data rebuild/migration, minimum iOS changes, and known issues.

## 2. Review and update documents before the release commit

1. Identify the previous release tag and review the full candidate diff against it, including staged,
   unstaged, and new files. Match each shipped behavior and engineering change to the applicable
   [documentation index](../../../docs/engineering/README.md) and its existing sources.
2. Update the affected PRD, ADR, Bug, Research, and engineering documents and their directory indexes.
   For a published decision that has changed, add both lifecycle links. At each release advance the
   three-version PRD/ADR window, move expired originals to the versioned archive, and merge still-valid
   requirements and decisions into the origin documents.
3. Reconcile the Changelog and applicable user and engineering guidance. Check acceptance criteria
   against actual test results and record pending verification. Check README/runbooks for commands
   and deployment, the schema reference for persistence changes, the prompt catalog for model
   input changes, and the privacy notes for changed data flows.
4. Review the staged release diff and document updates with `git diff --cached` and
   `git diff --cached --check`. Run `make verify` on the candidate before committing. State any
   remaining verification status in the relevant documents.

## 3. Verify the committed release and publish

1. Commit the release metadata and document updates with a Chinese Conventional Commit.
2. On the clean worktree run `scripts/verify-release.sh vMAJOR.MINOR.PATCH`.
3. For TestFlight, build with the maintainer's Apple Team using `DEVELOPMENT_TEAM=... make archive`
   and verify the archive in Xcode Organizer.
4. Create an annotated tag whose message summarizes user value and points to `CHANGELOG.md`.
5. Push the commit and tag. Wait for CI and GitHub Release workflows to complete.
6. Upload the locally signed archive through Organizer or the approved App Store Connect path.

Keep signing certificates, private keys, provisioning profiles, App Store Connect API keys,
user health data, and production LLM keys out of GitHub Actions. TestFlight distribution uses
the locally signed archive.
