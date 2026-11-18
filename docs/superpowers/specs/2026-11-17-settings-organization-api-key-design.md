# Settings and organization API keys

Approved design, including the grilling decisions of November 17, 2026.

Add Settings immediately below Not Sure Review, with a gear icon and the existing collapsed/expanded navigation behavior. Open a main-pane page titled Settings containing Developer Options → Organization API Key. Hide record filters and Export on this page. Debug and Release include it; the existing Debug-only backend URL sheet is unchanged.

The key serves external read-only integrations. The Mac app retains bearer authentication. Only live organization owners may request metadata or change a key. Rangers see an owner-only explanation; demo users see an unavailable state without requests.

Use GET /api/v1/organization/api-key (configured, nullable prefix and issued_at), POST /api/v1/organization/api-key/rotate (no body, metadata plus one-time api_key), and DELETE /api/v1/organization/api-key (empty 204). Use the existing authenticated transport and its explicit-401 recovery. Never retry an ambiguous rotation automatically.

Display metadata and Generate or Rotate/Revoke as appropriate. Confirm rotation/revocation and explain immediate integration interruption: there is one active key and no overlap. Newly issued secrets start masked, with Reveal/Hide, Copy, and I've saved it controls. Keys cannot be retrieved later. Before discarding an unacknowledged secret during navigation, offer Stay or Discard and Leave. Signing out always clears sensitive state immediately. Leaving after acknowledgement also clears the secret.

Copy shows feedback and schedules expiry after 60 seconds, only if the pasteboard has not changed. The expiry survives page navigation; clipboard history outside the app cannot be erased. Never log or persist integration secrets. Block ordinary navigation and duplicate key operations during changes; use a 30-second request timeout. Sign-out and quitting remain possible. Treat timeout or cancellation as potentially committed server changes; explicit new rotation is needed to recover an unavailable secret. Clear private state and ignore stale responses on navigation, account/role/organization changes, sign-out, and backend changes.

## Approaches

Metadata-only was rejected in favor of full owner key management. A full existing secret cannot be retrieved because the server stores only its digest. Local persistent secret storage and backend overlap periods are excluded. Keep the established SwiftUI/AppStore/APIClient architecture and add focused key-service and Settings-state modules rather than restructuring record services.

## Backend and acceptance

Delivery includes backend readiness and, when required, production promotion through the existing tested-release, backup, migration, and manual promotion process. Present the exact candidate, production diff, migration impact, and recovery implications for review before promotion. Do not include unrelated backend working-tree changes.

Provision and retain AdaPenyu Integration QA (slug adapenyu-integration-qa), owner qa@adapenyu.com, with synthetic data only and adopt_legacy_data false. Generate credentials securely, provision through private stdin, never expose them in chat/logs, and hand them off through secure local storage. Do not touch operational organization keys.

Acceptance includes deterministic transport, permissions, navigation, clipboard, race, and error tests; Mac Debug/Release builds; and live issuance in the Mac app followed by integration reads of a known synthetic QA turtle, rotation (old fails/new works), and revocation (replacement fails). Leave QA without an active key. Distinguish local verification from live verification. Public hosted OpenAPI currently omits key routes; this is a readiness finding, not proof that runtime routes are absent.
