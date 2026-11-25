# Photo Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver thumbnails for lists and signed originals for comparison across backend, iOS and Mac, with bounded database work and three linked pull requests.

**Architecture:** Keep current original fields and add optional derivative metadata. Authorize and load review photo references together, download bytes directly from storage, and isolate original and thumbnail state in both clients. Introduce durable jobs only if measured upload cost warrants them.

**Tech Stack:** Existing FastAPI, SQLAlchemy, Alembic, Pillow and R2/local storage; Swift/SwiftUI, UIKit and AppKit. No new queue dependency by default.

**Spec:** `docs/superpowers/specs/2026-11-25-photo-delivery-contract.md`, approved by user on 2026-11-25. Canonical spec lives in the backend; identical copies live in all three repositories.

## Global Constraints

- Preserve the original source image. A thumbnail never replaces its bytes.
- Queue rows and candidate cards use thumbnails.
- Comparison, zoom and image analysis use originals, never thumbnails.
- Use signed storage downloads to avoid backend database lookups for each image.
- Measure thumbnail creation during upload before introducing a separate worker.
- Changes cover backend, iOS and Mac, including reopening saved reviews.
- Existing `url`, `download_url`, `expires_at` remain original fields. No breaking envelope change.
- Never store or log signatures. Never send API credentials to storage.
- Do not claim historical provenance for legacy attempts without retained evidence.
- Preserve existing uncommitted work in each repository; do not include unrelated changes in commits or PRs.
- User authorized opening PRs in all three repositories after verification; no merge or production deployment is authorized.

## Review Focus

- Signed-link rotation must reuse cached content without hiding a replaced source; Tasks 3, 6, 7 test revision identity.
- Storage 403 must not log the user out or cause one renewal per candidate; Tasks 5–7 test coalesced recovery.
- Missing thumbnails must not start downloads of every original; Tasks 6–7 test new/old server selection separately.
- Photo replacement during a saved review must not present current bytes as historical evidence; Tasks 4–5 test unavailable history.
- Scope changes during downloads must discard late results; Tasks 6–7 test cancellation and private-state clearing.

## Execution boundaries

Repository labels: BE = `/Users/abui/@code/turtle-identification-be`; iOS = `/Users/abui/@code/ADA_Penyu`; Mac = `/Users/abui/@code/Ada_Penyu_Mac`.

Backend was fetched during design: local `4e1aabc`, remote main `b5a138c`, identical committed trees. Fetch again at execution. Use `using-git-worktrees` before product changes; inspect and preserve dirty worktrees. Do not blindly pull, reset or copy whole dirty files into new branches. Identify any existing queue changes this feature depends on and isolate only necessary hunks with reviewable provenance.

This feature crosses three repositories but shares one wire contract. Execute backend contract work first, then client adapters, then integration. Each repository gets its own branch, commits, and PR.

### Task 1: Establish baseline and resolve execution gates

**Files:** BE create `scripts/benchmark_photo_derivatives.py`, `docs/benchmarks/photo-delivery-2026-11-25.md`; all repos update the approved contract only with explicit decisions. Mac exploratory result: `docs/superpowers/specs/2026-11-25-thumbnail-spike.json`.

**Interfaces:** Produces a reproducible benchmark report and explicit decisions for thumbnail size/quality, inline execution versus durable worker, upload failure policy and historical retention. No production behavior changes.

- [ ] Read the approved spec and relevant skills; fetch remotes and record exact base SHAs and dirty-file ownership for each branch.
- [ ] Implement benchmark CLI `python -m scripts.benchmark_photo_derivatives --input-dir PATH --runs 20 --concurrency 1`. Add configurable concurrency and max-edge/quality flags, reporting decode/encode time, output bytes and peak process memory without writing over inputs or logging image content.
- [ ] Measure representative full camera-size JPEG/PNG/WebP, rotated input and high-pixel-count files, then concurrent uploads with storage writes on an isolated environment. Keep original hashes before/after; report cold and warm runs separately. Use existing bundled samples only as a limited baseline if representative data is unavailable, explicitly leaving the production performance conclusion open.
- [ ] Record measured API baseline and added thumbnail cost. Propose concrete thumbnail settings and an acceptable upload latency/resource budget from the measurements; do not invent an SLA from the sample spike.
- [ ] Obtain the outstanding product decisions: whether successful original upload survives thumbnail failure; historical-photo retention period and unavailable-history behavior. Approval of the spec did not decide these. Stop only the dependent tasks if unresolved; continue independent DTO/transport tests.
- [ ] Record the worker decision. If durable async generation is required, return to design for queue ownership/retry/deployment; do not slip in fire-and-forget work. This plan's upload-generation task assumes inline generation has passed the measurement gate.
- [ ] Commit benchmark code and report with limitations. Verification: repeat the CLI on a fixed fixture; outputs must parse and original checksums must remain equal.

### Task 2: Add image representations and stable source identity

**Files:** BE create `app/models/photo_asset_version.py`, `app/services/photo_derivatives.py`, `tests/test_photo_derivatives.py`; modify `app/models/__init__.py`, `app/models/turtle_photo.py`, `app/models/log_photo.py`, `app/schemas/v2.py`; create the next Alembic migration after checking the current head.

**Interfaces:** `make_thumbnail(data: bytes, *, max_edge: int, quality: int) -> ThumbnailResult` returns encoded JPEG bytes, oriented width/height and recipe revision. `ThumbnailResult` is an immutable value object in `photo_derivatives.py`. A stored source version has an opaque immutable revision, organization ownership, original key and optional thumbnail metadata. Keep public photo ID distinct from its version.

- [ ] Write `test_original_bytes_unchanged`, `test_thumbnail_preserves_aspect_and_orientation`, `test_no_upscale`, `test_corrupt_or_oversize_input_rejected`, and `test_original_and_thumbnail_fields_decode_independently`. Use settings selected by Task 1, with dimension/byte assertions rather than timing assertions.
- [ ] Run `.venv/bin/python -m pytest tests/test_photo_derivatives.py -q`; verify failures identify the missing feature.
- [ ] Implement the pure derivative function with the existing Pillow dependency, EXIF orientation handling, RGB output and existing validation limits. Never use its output for matching.
- [ ] Add immutable asset-version metadata and optional current-version references on identity/sighting photo rows. Migration records existing objects without changing their bytes; null derivative state remains valid. Source keys for future versions must be immutable, not overwritten at the legacy side-based key.
- [ ] Extend v2 Photo with additive `revision` and nullable `thumbnail`; define thumbnail revision, stable URL, signed URL, expiry, width, height and MIME type as in the spec. Old decoders must still receive the original top-level fields.
- [ ] Verify migration upgrade on a disposable database with preexisting photo rows. Assert byte identity and nullable derivative state. Run focused tests and commit the independently testable model/derivative change.

### Task 3: Integrate upload, projection and backfill

**Files:** BE modify `app/services/individual_service.py`, `app/services/log_service.py`, `app/services/photo_storage.py`, `app/services/v2_projection.py`, `app/repositories/individual_repository.py`, `app/repositories/log_repository.py`; create `app/services/photo_assets.py`, `scripts/backfill_photo_thumbnails.py`, `tests/test_photo_asset_lifecycle.py`; extend `tests/test_api_v2.py` and `tests/test_photo_storage.py`.

**Interfaces:** `PhotoAssetService.store_source(data: bytes, content_type: str) -> PhotoAssetVersion` stages a new immutable source version under the authorized organization. `PhotoAssetService.ensure_thumbnail(version_id: UUID) -> PhotoAssetVersion` is idempotent and revision-bound. `PhotoAssetService.references(versions: list[PhotoAssetVersion]) -> dict[UUID, v2.Photo]` signs already-authorized metadata without object reads.

- [ ] Depends on Tasks 1–2 and the upload failure policy. Write tests for failure before/after original promotion, derivative failure, duplicate generation, replacement, deletion, local storage, null signed links and orphan cleanup. Ensure failures follow the explicit Task 1 policy.
- [ ] Run `.venv/bin/python -m pytest tests/test_photo_asset_lifecycle.py tests/test_photo_storage.py tests/test_api_v2.py -q` against the disposable DB; confirm new assertions fail before integration.
- [ ] Route both identity and sighting upload paths through versioned assets, preserving embeddings/index invalidation behavior and source bytes. Publish derivative references only after successful storage. Stable original routes resolve the current version for legacy callers.
- [ ] Extend projection to return both variants from batch-loaded metadata. Add the selected stable derivative route to existing individual/log routers, with organization authorization, declared image MIME and existing error conventions; register its exact spelling in the contract before clients consume it.
- [ ] Implement `python -m scripts.backfill_photo_thumbnails --limit N --dry-run` and explicit `--apply`. Backfill uses recorded versions, skips completed recipe versions, checks ownership/current deletion state before publishing, and never re-runs ML. Limit and dry-run validation must precede object writes.
- [ ] Re-run lifecycle tests plus `tests/test_not_sure_queue.py`. Add an R2-stub check proving queue metadata does not GET/HEAD objects or run inference; count signing separately. Verify restartable backfill on disposable fixtures, then commit.

### Task 4: Pin historical evidence without changing saved ranking DTOs

**Files:** BE modify `app/models/match_result.py`, `app/services/match_result_service.py`, `app/api/v2/match.py`, `app/api/v2/rematch.py`; extend `tests/test_match_results_v2.py`, `tests/test_sighting_rematch.py`; add a migration only if asset references require a separate association table.

**Interfaces:** `MatchResultRecord.candidate_photo_refs` stores durable candidate ID, side, photo ID and source-version ID per attempt. It contains no URLs or credentials. The existing `result` snapshot remains unchanged.

- [ ] Depends on immutable versions and explicit retention policy. Write `test_replacement_keeps_attempt_photo_reference`, `test_attempt_retry_does_not_repin_current_photo`, `test_legacy_attempt_has_unknown_photo_provenance`, and `test_exact_query_crop_is_preserved`.
- [ ] Run the two focused backend test files; verify the new history assertions fail first.
- [ ] Capture the versions actually used by the matching gallery in the same attempt workflow; do not resolve current photos after matching and call them historical. Keep existing attempt replay/idempotency and frozen labels/confidence unchanged.
- [ ] Implement retention/access handling according to Task 1. Deleted or forbidden history is unavailable, never silently substituted. Do not fabricate photo provenance for old attempts.
- [ ] Verify tests with profile replacement and concurrent attempt replay, plus existing confirmation tests; commit.

### Task 5: Add one review photo metadata/renewal boundary

**Files:** BE create `app/services/review_photo_delivery.py`, `tests/test_review_photo_delivery.py`; modify `app/api/v2/logs.py`, `app/schemas/v2.py`; update `docs/api/v2.md` and `docs/api/fe-not-sure-rematch.md` using isolated hunks around preexisting edits.

**Interfaces:** Proposed route `GET /api/v2/logs/{log_id}/match-results/{attempt_id}/photos`, implemented as `ReviewPhotoDeliveryService.metadata(log_id: UUID, attempt_id: UUID) -> ReviewPhotoDelivery`. Response has `attempt_id`, `queries[]` and `candidates[]`; each candidate includes `turtle_id`, `side`, `availability` (`available`, `unavailable`, `unknown_legacy`) and nullable `photo: v2.Photo`. Queries identify the exact retained matching input. This route is new; existing saved snapshot endpoints stay stable. Metadata issuance and renewal use the same route.

- [ ] Write `test_sql_count_bounded_for_1_10_50_candidates`, `test_foreign_attempt_denied`, `test_metadata_never_reads_objects`, `test_legacy_provenance_is_explicit`, and `test_new_signatures_keep_revision`. Use cold ORM sessions and authenticated requests; assert fixed query count across fixture sizes rather than guessing a count before measurement.
- [ ] Run `.venv/bin/python -m pytest tests/test_review_photo_delivery.py -q`; establish the missing-route failures.
- [ ] Authorize the log and attempt together, batch-load retained version references, filter inaccessible resources and sign both variants. Bound response size by the existing maximum 50 candidates; do not expose arbitrary-key signing or change ranking order. Handle local storage with authenticated stable variant locators.
- [ ] Include exact query evidence metadata, retaining crop bytes and existing no-store/access behavior. The metadata route must not materialize query images.
- [ ] Verify bounded SQL, organization isolation, missing/deleted objects, legacy attempts and no signature persistence. Document wire examples and regenerate/check OpenAPI using existing project conventions; commit.

### Task 6: Mac representation-aware loader and review integration

**Files:** Mac create `Ada_Penyu_Desktop/Networking/PhotoDelivery.swift`, `Ada_Penyu_DesktopTests/PhotoDeliveryTests.swift`; modify `Networking/V2Records.swift`, `Networking/NotSureRecords.swift`, `DataLayer.swift`, `AppStore.swift`, `Views/NotSureWorkspaceView.swift`, `Components/TurtlePhoto.swift`; extend `AutomaticNotSureQueueTests.swift`, `TurtlePhotoTests.swift` and the shared spec.

**Interfaces:** `PhotoRepresentation` has `.original` and `.thumbnail`. `PhotoCacheKey` contains backend/account/organization, photo ID, source revision, variant and derivative revision. `PhotoDelivery.load(_ photo: PhotoReference, representation: PhotoRepresentation) async throws -> NSImage` owns cache/in-flight deduplication; `clear()` cancels pending work and clears private memory. `PhotoReference` retains stable identity and renewable transport separately. Repository `reviewPhotoMetadata(logID: UUID, attemptID: UUID) async throws -> ReviewPhotoDelivery` consumes Task 5.

- [ ] Write URLProtocol-backed tests for variant selection, absent/new-server-null thumbnail distinction, rotating links with stable cache key, revision replacement, concurrent original load deduplication, storage 403 without logout, one review renewal/one retry, scope reset and cancellation.
- [ ] Run the Mac focused suites with the test command below and `-only-testing:Ada_Penyu_DesktopTests/PhotoDeliveryTests`; verify feature assertions fail first.
- [ ] Decode the additive DTOs and implement separate ephemeral external storage transport. Preserve signed query strings exactly. Metadata renewal is keyed by active log/attempt, coalesces failures and retries each image at most once.
- [ ] Keep candidate thumbnail state separate from original `photo` used by comparison/contours. Cards choose thumbnail; selected comparison loads original immediately. Initial engineering budget: one selected download plus one speculative original, at most two original requests in flight; prioritize selection changes and avoid whole-queue prefetch. Record measured memory before increasing it.
- [ ] Fetch Task 5 metadata when preparing/reopening an attempt. Never persist signed URLs through `NotSureReviewJournal`; preserve session/scope/attempt checks. Unknown legacy evidence is labeled and does not masquerade as the old photo. Clear caches on authorization/backend changes.
- [ ] Run focused suites and existing automatic-review/photo/contour regressions, then full Mac suite. Commit only owned changes.

### Task 7: iOS adopts the same representation rules

**Files:** iOS modify `ADA_Penyu/ADA_Penyu/Models/API/IndividualDTOs.swift`, `Models/API/LogDTOs.swift`, `Models/API/MatchDTOs.swift`, `Models/API/DomainMapping.swift`, `Models/RemotePhoto.swift`, `Services/API/RemoteImageLoader.swift`, `Services/API/RemoteTurtleRepository.swift`, `Views/Shared/PhotoTile.swift`, `Views/List/WaitingToMatchView.swift`, `Views/Matching/MatchingView.swift`, `Views/Shared/PhotoComparisonZoomView.swift`; create `ADA_Penyu/ADA_PenyuTests/PhotoDeliveryTests.swift`; extend `RemotePhotoTests.swift` and `V2APITests.swift`.

**Interfaces:** iOS uses the same `PhotoRepresentation`, `PhotoCacheKey`, `PhotoReference`, `ReviewPhotoDelivery` semantics as Task 6, expressed with UIImage and the existing environment loader. Extend `RemoteImageLoader.load` and `cached` with an explicit representation argument; update all call sites deliberately.

- [ ] Add the same transport/DTO fixtures as Mac for old/new servers, absent thumbnails, rotation/replacement, retry exhaustion, coalesced metadata renewal, direct storage credential isolation and logout during downloads. Add a comparison test proving an original is requested even when a thumbnail is already cached.
- [ ] Run `PhotoDeliveryTests` and `RemotePhotoTests` on an installed iOS 18+ simulator; verify feature failures first.
- [ ] Decode/map the additive metadata, batch review references and explicit history availability. Reuse existing session-aware loader behavior while replacing URL-only cache identity and per-image renewal with representation-aware keys and review-coalesced renewal.
- [ ] Wire thumbnail selection into cards/waiting rows; wire original selection into comparison, zoom and analysis. Keep a valid original ready independently of derivative availability. Preserve original coordinate/orientation semantics and legacy server behavior.
- [ ] Verify shared fixtures and relevant matching/photo suites, then full iOS suite. Commit owned changes and keep the spec identical across repos.

### Task 8: Cross-repository verification and PR handoff

**Files:** all three contract copies; BE benchmark report/API docs; iOS `docs/api-v2.md`; Mac `README.md`; repository PR descriptions.

**Interfaces:** Three PRs with explicit dependency links, validation evidence, deployment order and deferred product decisions. No merge/deploy step.

- [ ] On isolated test infrastructure, run backend focused suites and full suite with `ML_MODELS_ENABLED=false`; tests may recreate tables, so explicitly set a newly created owned `TEST_DATABASE_URL`, never the application database.
- [ ] Run full Mac and iOS test commands below. Validate contract-copy hashes, JSON examples and Markdown links; run `git diff --check` in each repo.
- [ ] Exercise one staging release: cold/warm queue, selected comparison, saved history after replacement, expired signed URLs, partial thumbnail backfill, and old/new version combinations. Record API/SQL operations separately from object GETs, transferred bytes and memory. If unavailable, report staging as not run; do not claim end-to-end acceptance.
- [ ] Request independent code review using the applicable Superpowers review skill; fix material findings and repeat only affected checks.
- [ ] Use the `pr` skill to prepare descriptions and open a PR in each repository without another permission request. Link all three PRs after URLs exist, state backend-first deployment and compatibility support, and identify any deliberately deferred capability. Do not claim complete history support if its gated tasks were not executed.
- [ ] Report the three PR URLs, passing checks and any staging or unresolved product limitations. Do not merge.

## Verification commands

Run from each repository root, using owned disposable backend infrastructure:

```bash
# BE: set TEST_DATABASE_URL to the owned disposable test database first.
ML_MODELS_ENABLED=false .venv/bin/python -m pytest -q

# Mac
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Ada_Penyu_Desktop.xcodeproj -scheme Ada_Penyu_Desktop -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# iOS: choose an installed iOS 18+ simulator using xcrun simctl list devices available.
# Set ADA_SIMULATOR_ID to that simulator's UDID.
xcodebuild test -project ADA_Penyu/ADA_Penyu.xcodeproj -scheme ADA_Penyu -configuration Debug -destination "platform=iOS Simulator,id=$ADA_SIMULATOR_ID" -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

## Self-review and deferred scope

All approved contract sections map to Tasks 1–8. Shared DTO names and representation/cache rules agree across clients. SQL growth, credentials, expiry, image quality, history and migration failures have owning test steps. The added review route, asset-version module and initial original-request budget are engineering proposals in this plan, not claims about existing behavior.

Historical retention, unavailable-history presentation and upload success on derivative failure remain explicit product gates. Do not silently choose those during execution. A durable-worker branch of the design requires a follow-up plan if Task 1 demonstrates the need. No production changes, migrations or implementation tests have been executed by writing this plan.
