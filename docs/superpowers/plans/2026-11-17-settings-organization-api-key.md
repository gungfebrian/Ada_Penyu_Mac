# Settings and Organization API Key Implementation Plan

> **For agentic workers:** Use executing-plans task by task with a final independent review. Track progress in the plan ledger.

**Goal:** Add owner organization-key management to Settings and verify the complete live integration flow.

**Architecture:** SwiftUI Settings page, an AppStore-owned feature state model and a focused APIClient-backed service. Navigation routes through the Settings guard. An app-lifetime clipboard owner expires only its own entry.

**Tech Stack:** SwiftUI, AppKit, Foundation URLSession, XCTest; existing Python backend deployment tooling.

**Spec:** docs/superpowers/specs/2026-11-17-settings-organization-api-key-design.md

## Global Constraints

Settings ships in Debug and Release; only live owners access keys. Full secrets stay in memory, start masked, and clear on exit/context changes. Copy expires after 60 seconds without overwriting newer clipboard contents. Key changes time out after 30 seconds and block ordinary navigation; ambiguous rotation is not replayed. Production promotion requires review of a concrete release.

## Review Focus

- Session/account/permission changes and late responses cannot restore secrets.
- Leaving Settings cannot accidentally lose an unacknowledged key.
- Clipboard expiry survives navigation and preserves subsequent user copies.
- Ambiguous mutation failures never imply rollback or automatically rotate again.
- Production verification affects only the retained synthetic QA organization.

### Task 1: Key service and lifecycle state

**Files:** Create Networking/OrganizationAPIKeyService.swift, OrganizationAPIKeySettings.swift, and focused XCTest files in the existing source/test roots. Modify AppStore for lifecycle ownership.

**Interfaces:** OrganizationAPIKeyService.fetchMetadata() async throws -> OrganizationAPIKeyMetadata; rotate() async throws -> IssuedOrganizationAPIKey; revoke() async throws. OrganizationAPIKeySettings owns metadata, masked one-time secret, acknowledgement, progress, errors and pending navigation. AppStore supplies the current owner/demo context and invalidates settings when it changes.

- [ ] Add contract tests for routes/methods, bearer auth, nullable fields, empty 204 and 30-second timeout; observe RED, implement service, verify GREEN.
- [ ] Add behavior tests for owner/demo gating, generation/rotation/revocation, no automatic ambiguous replay, duplicate prevention and stale-response isolation; observe RED, implement state, verify GREEN.
- [ ] Add leave/acknowledgement and isolated-pasteboard expiry tests; observe RED, implement guard and app-lifetime clipboard handling, verify GREEN.
- [ ] Run focused tests with xcodebuild test -project Ada_Penyu_Desktop.xcodeproj -scheme Ada_Penyu_Desktop -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:Ada_Penyu_DesktopTests/OrganizationAPIKeyTests -only-testing:Ada_Penyu_DesktopTests/OrganizationAPIKeySettingsTests. Expected: zero failures.

### Task 2: Settings navigation and UI

**Files:** Modify AppModel, ContentView, AppShellComponents and WorkspaceControls; create Views/SettingsView.swift. Update navigation/UI regression tests.

**Interfaces:** AppSection.settings and guarded AppStore.requestNavigation(to:); SettingsView consumes the Task 1 model. Existing Debug backend sheet is retained.

- [ ] Add navigation guard tests covering selected turtle dismissal, in-flight changes and unacknowledged secret; verify RED, then wire Settings and sidebar routing.
- [ ] Render metadata, owner/demo/loading/error states, generation/rotation/revocation confirmations, masked Reveal/Hide/Copy and acknowledgement. Hide record header controls on Settings.
- [ ] Verify focused tests, full suite and Debug/Release builds. Inspect expanded/collapsed sidebar, minimum window, long keys and confirmation flows. Expected: no failures or clipping.
- [ ] Commit small coherent service/state and UI/test changes; request independent whole-change review and fix important findings.

### Task 3: Backend readiness and live verification

**References:** Backend docs/api/integration.md, docs/accounts-setup.md and deploy/vps/README.md.

- [ ] Inspect deployed version/revision/routes and identify newest eligible tested release containing key implementation. Preserve unrelated local backend changes.
- [ ] If rollout is required, present exact release, full diff and migration/recovery implications; promote only after review. Follow documented backup and staged migration process through 012_organization_api_keys.
- [ ] Provision retained AdaPenyu Integration QA / adapenyu-integration-qa with owner qa@adapenyu.com and adopt_legacy_data false through private stdin; securely generate/store credentials without chat/log disclosure.
- [ ] Seed a synthetic turtle, issue a key through the Mac app, verify X-API-Key integration read, rotate and prove old/new behavior, revoke and prove rejection. Leave no active QA key.
- [ ] Update docs with actual verification evidence and blockers. Do not claim live acceptance from stub tests or public schema alone.
