# Remove App Demo Mode Implementation Plan

Goal: authenticated backend records with no automatic demo substitution.
Spec: ../specs/2026-11-13-delete-demo-data-design.md

- [x] Remove DataMode, DemoTurtleRepository, DemoFixtures and store mode switching.
- [x] Remove demo sign-in/account controls and neutralize account defaults.
- [x] Route record photos through the repository; remove synthetic overlay fallback.
- [x] Separate explicit I3S reference candidates from backend candidates and guard backend candidate actions.
- [x] Replace populated previews with empty states; migrate test dependencies to test-only fixtures.
- [x] Update current API documentation and runbook.
- [x] Verify XCTest suite, Release build, and independent review.

Constraints: preserve I3S reference assets/oracle tests and Scientist Review prototype; no database mutations, API changes or dependencies.
Validation: signed-out startup, API failures, filename collisions with samples, account menu, details, session clearing, I3S oracle parity. UI walkthrough remains manual.

Verification: full suite passed (40 tests, zero failures); final focused AppFlow/APIContract/SidebarAccount run passed after cleanup; final Release build passed with code signing disabled. Independent review found a source-transition race, fixed by synchronous selection invalidation and generation checks; follow-up review found no important remaining issues. The updated account menu was inspected in the running app and contains Developer API Settings and Sign Out only. Live photo rendering against backend records remains unverified.
