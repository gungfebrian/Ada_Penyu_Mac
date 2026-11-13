# Mac API Settings, Authentication, and V2 Migration Implementation Plan

> **For agentic workers:** Use Superpowers `executing-plans` to implement this plan task by task. Steps use checkboxes for tracking.

**Goal:** Install project-local Superpowers, require it for planning, add Debug backend settings, secure sessions, and migrate records to v2.

**Architecture:** Keep SwiftUI and the repository boundary. Extract backend configuration and session management into focused modules, using the sibling iOS app and backend schemas as the contract. Matching stays on v1 pending Gung's flow confirmation.

**Tech Stack:** Swift 5 language mode, SwiftUI, AppKit, URLSession, Security Keychain, XCTest; macOS 26.5+.

**Spec:** `docs/superpowers/specs/2026-11-12-mac-api-auth-v2-design.md`.

## Global constraints

- Default Debug and Release backend: `https://api.donagondev.my.id`.
- Runtime backend overrides exist only in Debug, before and after login.
- Remember me persists refresh credentials in device-only Keychain. Passwords and access tokens remain in memory.
- Live failures stay visible. Demo is an explicit user choice.
- Records, sightings, and photos use v2. Auth, favorites, dashboard, exports, overlays, and current matching use v1.
- Backend deployment and account recovery screens are outside this change.

## Review focus

- Late responses after logout, backend changes, or account changes cannot restore private state.
- Concurrent 401 responses share one refresh; refresh rotation cannot replay a consumed token.
- External photo URLs and redirects cannot receive bearer credentials.
- Null condition/timestamp fields stay unknown; per-encounter data stays attached to its source.
- Release ignores persisted Debug backend overrides.

## Task 1: Project planning setup

- [x] Install all 15 upstream skills at commit `22f0b463e7a5e579904dd6211a520321035526f7`, with supporting resources and license; record provenance.
- [x] Create AGENTS.md with Superpowers planning guidance and preserve Context7 instructions.
- [x] Install the 39 Matt Pocock skills requested during execution, with license and pinned provenance.
- [x] Import shared iOS assets/resources, preserving existing Mac asset sets and avoiding name collisions.
- [x] Verify skill metadata and supporting resources.

## Task 2: Configuration and secure sessions

- [x] Add tests for config validation, Release isolation, login/context, remembering/restoration, refresh, logout, and trusted origins.
- [x] Implement configuration, Keychain refresh storage, coordinated authentication, and legacy-secret removal.
- [x] Verify public health requests carry no credentials and private requests have one bounded retry.

## Task 3: App lifecycle and Debug settings

- [x] Add tests for sign-in gating, explicit Demo mode, failed requests, backend changes, and late-response isolation.
- [x] Add login, Remember me, real identity, sign-out, and Debug-only URL/test/save/reset UI.
- [x] Clear records, details, photos, and workspace state on session/backend changes.

## Task 4: V2 records

- [x] Test nested v2 profiles, per-encounter logs, pagination, null values, photos, and enrollment payloads.
- [x] Migrate profile reads/creation, sighting history, and identity photo uploads to v2; keep supported v1 features.
- [x] Add required enrollment fields, distinguish observation data from identity fields, and retain unknown values.
- [x] Fix the pre-existing overlay test compilation error against the actual repository contract.

## Task 5: Verification and documentation

- [x] Run the full Mac test suite; build Debug and Release.
- [x] Perform a fresh whole-change review and address material findings.
- [x] Update API/auth/configuration documentation and record the hosted v2 release prerequisite.

## Matching migration — deferred after records

- [ ] **Pending Gung:** Confirm how searches select or create a sighting. Keep current v1 matching until this is settled.
- [ ] Add v2 single/pair matching with `log_id` and `attempt_id`.
- [ ] Preserve attempt UUIDs and encoded bytes on retries; changed inputs create new attempts.
- [ ] Map v2 candidates/confidence without inventing unavailable scores; show real errors and no-match results.
- [ ] Confirm identity on the original sighting and attach evidence photos without replacing identity photos implicitly.
- [ ] Display saved results and paginated history; preserve local I3S comparison and v1 overlays.
- [ ] Test conflicts, stale results, session expiry, changed inputs, and logout isolation.

## Execution record

- Implemented in the requested checkout on branch `codex/mac-api-auth-v2`; no additional worktree was created. The tradeoff is sharing the checkout with the user's current workspace.
- Installed 15 Superpowers and 39 Matt Pocock skills with pinned provenance and licenses; validated all 54 manifests.
- Imported 57 iOS asset sets and shared fonts/artwork; retained Mac asset definitions and namespaced colliding SVG names.
- Records use backend UUIDs independently of display names, avoiding collisions when turtles share a name. Enrollment now requires the v2 profile-code, sex, and first-seen fields, adding explicit inputs rather than fabricating values.
- Full Debug suite: **38 passed, 0 failed, 0 skipped**. Debug and production Release builds passed. Release override/legacy-credential test: **1 passed**. The Release test uses `ENABLE_TESTABILITY=YES` solely for its `@testable` import.
- The fresh review identified three Important issues. Four regression tests reproduced them, then passed after fixes for marking visibility/assessment semantics, sighting counts, and favorite-name search. The final full suite passed after those fixes.
- Mechanically checked asset references, skill manifests/licenses, and whitespace. Release contains no Developer API Settings UI or BackendSettingsSheet symbol.
- Live OpenAPI recheck: the hosted service still advertises 34 v1 paths and zero v2 paths. Backend v2 deployment remains a release prerequisite.
- Provisioned Keychain behavior and live authenticated v2 requests require runtime verification against a signed app and deployed backend. Pre-existing detail placeholders remain outside this change; no minor review findings were deferred.
