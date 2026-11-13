# Mac API/auth and v2 records design

The approved work brings the Mac client closer to the sibling iOS app: Debug-only server settings before/after login, hosted defaults in both configurations, real sign-in and secure remembered sessions, then v2 records. Backend deployment and account recovery remain separate. Matching migration is recorded but deferred until Gung confirms its sighting workflow.

## Approach

Keep the existing SwiftUI screens, AppStore state owner, and repository interface. Adapt the sibling iOS transport/session lifecycle, add Mac-specific data-protection Keychain storage, and introduce v2 DTOs rather than changing v1 DTOs used by supported auxiliary services. This preserves the backend's intentional v1/v2 coexistence. A wholesale shared-package extraction or screen rewrite adds work beyond the agreed scope.

The shared app store is created once by the app, including across windows. Session generations invalidate late network/UI results. Live mode requires authentication; Demo remains an explicit choice. API errors stay visible instead of selecting fixture data automatically.

Configuration, session, HTTP, and v2 mapping have focused modules under Networking. Backend UUIDs identify records while display names remain human-readable. Unknown values remain unknown. Identity enrollment collects v2's required fields instead of attaching encounter condition data to a profile.

## Additional user requests during execution

- Copy shared assets from the iOS repository, preserving existing Mac assets and resolving catalog collisions.
- Install the complete Matt Pocock skills set alongside Superpowers with source revision and licenses.

## Acceptance

Project-local skills are readable; AGENTS.md retains Context7 guidance and requires Superpowers planning. Configuration and authentication tests cover session boundaries, trusted origins, credential persistence policy, and bounded retries. Record tests cover v2 wire shapes, pagination, null values, and enrollment/photos. The full Mac test suite and Debug/Release builds pass. A separate reviewer checks the completed change. Real backend v2 deployment and provisioned Keychain behavior are distinguished from local deterministic verification.
