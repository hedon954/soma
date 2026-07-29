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

## 2. Verify

1. Run `make verify`.
2. Run `scripts/verify-release.sh vMAJOR.MINOR.PATCH`.
3. For TestFlight, select the real Apple Team locally and run
   `DEVELOPMENT_TEAM=... make archive`.
4. Verify the archive in Xcode Organizer before uploading.

Do not put signing certificates, private keys, provisioning profiles, App Store Connect API
keys, user health data, or production LLM keys in GitHub Actions.

## 3. Publish

1. Commit the release metadata with a Chinese Conventional Commit.
2. Create an annotated tag whose message summarizes user value and points to `CHANGELOG.md`.
3. Push the commit and tag.
4. Wait for CI and GitHub Release workflows to complete.
5. Upload the locally signed archive through Organizer or the approved App Store Connect path.

GitHub Release is source metadata, not a substitute for TestFlight distribution.
