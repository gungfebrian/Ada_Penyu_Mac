# Mac API configuration, sessions, and v2 records

Debug and Release default to `https://api.donagondev.my.id`. Only Debug reads `ada.debug.apiBaseURL` from UserDefaults. The former `ada.apiBaseURL` setting is no longer read. Developer API Settings is available on the login screen and the sidebar account menu in Debug; it is compiled out of Release. URL validation accepts HTTP/HTTPS with a host and optional port/path and rejects credentials, query strings, fragments, and malformed ports.

Test connection uses an ephemeral, credential-free request to `/health` with a five-second timeout. It does not sign in, save the URL, or establish v2 availability. Save and Reset end the outgoing session and clear records, photos, detail state, and matching workspace state. They return the app to sign-in without reusing credentials on the new server.

## Authentication

`SessionCoordinator` follows the sibling iOS client's session contract: v1 login, refresh, `/me`, `/organization`, and logout. Real account and organization context must be consistent before sign-in succeeds. Unknown roles and inactive accounts cannot create a usable session.

Without Remember me, credentials live only in memory. Remember me stores the refresh token, refresh expiry, account/organization IDs, and an interrupted-rotation marker in the macOS data-protection Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Its service is separate from the iOS app. Passwords and access tokens are never persisted. Legacy plaintext credentials and the fixed user-ID override are removed from UserDefaults at client creation.

Refresh is serialized across concurrent requests. A request retries once after authentication failure, preserving its encoded body. Another failure ends the session. Ambiguous refresh failures require sign-in rather than replaying a potentially consumed refresh credential. A failed context reload preserves replacement refresh credentials for recovery; a rejected session clears them. Responses from an earlier session cannot populate current private state.

Keychain Remember me must be exercised with an appropriately signed macOS app. If secure storage is unavailable, the user sees an error and can sign in without Remember me. Deterministic tests inject memory storage; they do not establish provisioning or live identity-provider readiness.

## Records

Profiles, creation, per-individual sighting history, and identity photo uploads use v2. UUIDs identify records; display names are independent and may repeat. Enrollment requires a six-digit profile code, name, species, sex (including unknown), and first-seen date. Condition and observation notes are sighting data and are not sent in identity-only creation payloads.

The v2 summary supplies exact sighting counts, latest encounter context, and the last recorded condition. Missing conditions/species remain Unknown. Missing latest encounters remain Not recorded. History is loaded through all pages; each encounter's measurements, location, condition, and markings retain that encounter's date. Authenticated photo URLs are loaded through the shared transport. External URLs never receive bearer credentials; private sessions have no shared disk cache or cookies and reject cross-origin redirects.

Favorites, dashboard/map summaries, exports, authentication, overlays, and current matching retain their v1 routes. This is intentional version coexistence, not an automatic fallback when v2 fails. Backend errors remain visible with a Retry action; no demo records are substituted.

## Organization integration API keys

Settings in the sidebar contains Developer Options → Organization API Key in both Debug and Release. Live organization owners can inspect key status, generate or rotate a key, and revoke it. Other members see an owner-only explanation; demo accounts do not send management requests. The Mac app continues to authenticate with bearer sessions; organization keys are for external read-only integrations.

Management uses `GET /api/v1/organization/api-key`, `POST /api/v1/organization/api-key/rotate` (no body), and `DELETE /api/v1/organization/api-key` (empty 204). Only a newly issued key can be revealed or copied; an existing key's full secret cannot be retrieved. Rotation immediately invalidates the previous key. A lost issuance response is not automatically replayed; reload metadata and explicitly rotate again if needed.

Secrets start masked and are never persisted by the app. Leaving Settings clears the secret; an unacknowledged secret requires a discard confirmation. Key-changing requests block ordinary navigation and use a 30-second timeout. Sign-out, backend changes, and account/permission changes clear state and invalidate late responses. Copy schedules clipboard clearing after 60 seconds only if its ownership has not changed; the timer survives page navigation. External clipboard history cannot be erased.

Earlier November 17 checks found no advertised key routes, a public management GET returned 404, and trusted-host SSH inspection failed authentication. A later standalone Mac build was opened successfully, Settings navigation was verified, and the user-provided [screenshot](screenshots/settings-organization-api-key.png) shows active organization key metadata. This confirms the live metadata UI, not the complete isolated-QA issuance/read/rotate/revoke lifecycle. The [backend readiness package](superpowers/plans/2026-11-17-organization-key-backend-readiness.md) records the earlier candidate and migration findings and the approved QA organization. This client change performs no backend deployment or database migration.

## Deferred matching migration

The implementation plan records the complete follow-up checklist. Gung must confirm how a Mac photo search selects or creates its parent sighting. Until then, current single/pair matching remains on v1. Its v2 replacement must use stable sighting/attempt IDs, frozen retry bytes, saved snapshots/history, and explicit sighting identity confirmation rather than silently replacing identity photos.

## Release prerequisite

Deploy the backend's v2 contract and apply its required migrations, including `009_photo_captured_at` and `010_match_results`, through the backend's deployment process before releasing this client. A successful health check is insufficient. A November 12, 2026 recheck of the hosted OpenAPI advertised 34 v1 paths and zero v2 paths. Backend deployment is outside this repository change.

## Project skills and shared assets

Superpowers and Matt Pocock's skills are installed as pinned project-local copies under `.agents/skills`, with source manifests and licenses in `.agents`. They are available to subsequent Codex turns; refresh/restart the session if the skill catalog has not updated. Upstream experimental skills from Matt's `in-progress` directory are included because the complete repository set was requested; their presence does not activate them automatically for unrelated work.

The iOS asset import is recorded in `asset-import.json`. Existing Mac sets and icons are retained. Imported SVG body-part assets have a namespace to avoid generated-symbol collisions; otherwise unassigned side-photo variants live in Resources/Artwork. Shared fonts and their license files are copied without changing the Mac app's typography.
