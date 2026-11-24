# Automatic Not Sure verification

Mac implementation: `feat/automatic-not-sure-queue` (base `fa59f65`). Backend tests and documentation: `feat/not-sure-queue-loading` (base `086ea3d`).

## Automated checks

- Full Mac suite passed 201 tests in 129.5 seconds (`/tmp/ada-auto-final-full.log`).
- After the final UI task-identity/preview cleanup, the final rerun passed 198 tests, including all 10 new queue/matching tests. Three existing image-analysis tests were interrupted by SIGTERM; XCTest relaunched the test host. This run is not reported as a green full suite (`/tmp/ada-auto-verified-full.log`). The interrupted tests were:
  - `AppFlowTests.testI3SMatchesOriginalCppReferenceScoresAndPairs`
  - `AppFlowTests.testI3SRecognizesOtherEncountersInBundledGallery`
  - `PatternContourEngineTests.testExtractsWatertightPolygonalScaleSutureMeshAcrossBundledTurtles`
- Test-result bundle confirms `Test crashed with signal term.` for all three. No Ada Penyu application crash report was present; a separate Swift compiler report was produced while diagnosing a local binding-shadowing compiler failure, corrected before the successful builds.
- Backend full suite: 838 passed, 1 skipped, no failures; optional official-reference parity test skipped. Local 50-row metadata benchmark p95 14.941 ms, 57,745 bytes, 10 SQL queries. See backend `docs/benchmarks/api-v2/not-sure-queue-2026-11-24.md` for isolation, commands and limits.
- Both worktrees pass `git diff --check`.

## Standalone app and deployment evidence

Tests have stopped. Opened the standalone app at `/tmp/AdaPenyuAutoQueueBuild/Build/Products/Debug/Ada_Penyu_Desktop.app`; its running process has no XCTest launch arguments. Observed the Not Sure screen with automatic Loading, then Refresh/Retry and a queue API error. Existing saved local cases remained visible. No live case was matched or confirmed during this inspection.

The Debug endpoint override is `https://api-dev.donagondev.my.id`. Its public OpenAPI describes v2 logs and saved history, but no `unidentified_only` filter, `is_draft` sighting field, source-photo side, rematch/query-evidence or attempt-based confirmation routes. The current queue DTO correctly targets the approved newer backend contract; the old server response fails decoding. The default production host `https://api.donagondev.my.id` advertises v1 only, and direct unauthenticated GET `/api/v2/logs` returned404.

The approved newer backend exists in the inspected repository but is not deployed to these endpoints. Deployment is outside this plan. End-to-end live validation requires that deployment; do not silently fall back to a mixed first page or legacy confirmation route.

Review: all seven original findings corrected, plus the Reviewed→Pending task restart issue. No remaining Important finding was reported after the fix pass aside from that subsequently corrected task identity. Journal byte stripping was considered and deferred; legacy/local/reviewed evidence remains compatible.
