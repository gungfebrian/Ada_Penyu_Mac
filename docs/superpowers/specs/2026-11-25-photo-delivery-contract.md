# Photo delivery contract: backend, iOS and Mac

Author: adjiemuliadi  
Date: 2026-11-25  
Revision: 1  
Status: approved by user on 2026-11-25. Retention, unavailable history, and thumbnail-failure behavior were confirmed the same day. Staging acceptance has not been run.

## Ownership and authority

This is the shared target contract for turtle identity photos, sighting photos,
and Waiting to Match / Not Sure Review. The canonical copy lives in backend
`docs/superpowers/specs/2026-11-25-photo-delivery-contract.md`. Identical copies
live at the same path in the iOS and Mac repositories. Update all three copies
together. Existing API documentation describes runtime behavior until this
contract is implemented and verified against staging.

## Confirmed requirements

- Preserve the original source image. A thumbnail never replaces its bytes.
- Queue rows and candidate cards use thumbnails.
- Comparison, zoom and image analysis use originals, never thumbnails.
- Use signed storage downloads to avoid backend database lookups for each image.
- Measure thumbnail creation during upload before introducing a separate worker.
- Changes cover backend, iOS and Mac, including reopening saved reviews.

## Current evidence

The backend already supplies original `url`, `download_url` and `expires_at`
through its v2 photo projection. R2 signing does not read the image object.
Local storage returns null signed fields. Saved match candidates do not include
photo metadata. Mac candidate photo decoding currently discards signed fields;
iOS already has signed original loading and expiry renewal.

Backend remote was fetched on 2026-11-25. Local HEAD `4e1aabc` and remote main
`b5a138c` had identical committed trees; preexisting local edits remain separate.
This is source evidence, not a production deployment claim.

## Proposed wire contract

Extend existing v2 Photo objects additively. Existing top-level fields keep their
meaning: `url`, `download_url` and `expires_at` refer to the original. Do not move
them into a new `original` envelope and break existing clients.

```json
{
  "id": "b931fb6d-e91c-4a56-a446-dbb8b1f064ed",
  "revision": "immutable-source-version",
  "url": "/api/v2/individuals/example/photos/left",
  "download_url": "https://storage.example/original.jpg?signature=example",
  "expires_at": "2026-11-25T12:00:00Z",
  "captured_at": null,
  "uploaded_at": "2026-11-25T04:00:00Z",
  "thumbnail": {
    "revision": "thumbnail-recipe-version",
    "url": "/api/v2/photos/example/thumbnail",
    "download_url": "https://storage.example/thumbnail.jpg?signature=example",
    "expires_at": "2026-11-25T12:00:00Z",
    "width": 384,
    "height": 288,
    "content_type": "image/jpeg"
  }
}
```

`revision` is the immutable photo-asset version ID. `thumbnail` is optional while
clients support older servers. `thumbnail: null` or an absent field means
unavailable, not a request to decode the original as a thumbnail. A populated
thumbnail describes an object that has been successfully stored. Width and height
describe actual oriented output pixels. Installed derivative routes are
`GET /api/v2/photo-assets/{revision}/original` and
`GET /api/v2/photo-assets/{revision}/thumbnail`. One attempt's review metadata is
`GET /api/v2/logs/{log_id}/match-results/{attempt_id}/photos`. A current profile
or sighting projection may still put the legacy photo route in the top-level
original `url`. The example thumbnail size is the default recipe
`jpeg-v1-384-q80`: longest edge 384, JPEG quality 80, no upscale.

Signed URLs are opaque: preserve their query and encoding exactly. A stable URL
is a fallback transport locator, not sufficient identity for a replaced photo.
New-server responses that have a stored version provide revision metadata.

## Backend obligations

1. Authorize review/organization access before issuing photo references. Never
   accept arbitrary object keys from clients as proof of access.
2. Read photo metadata for all requested candidates in batches. Returning ten
   references must not perform a separate database lookup per candidate.
3. Provide the same photo metadata for fresh matching and saved-review hydration.
   Keep ranking, confidence, candidate labels and query provenance unchanged.
4. Refresh signed links at the metadata boundary. Do not store signatures in
   durable match snapshots, journals, analytics or logs.
5. Keep queue metadata responses free of image downloads and matching work.
   Creating signed metadata is distinct from storage GET/HEAD and DB work.
6. Store derivatives separately from original objects. Replacement creates a
   distinct source revision; derivative identity includes that revision and the
   thumbnail recipe version. Reads never generate a thumbnail on demand.
7. Define recoverable partial states: a valid original may exist while its
   thumbnail is unavailable. Failed derivative creation must not publish a URL
   to a missing object. Replacement, deletion, retention and orphan cleanup
   cover original and derivative ownership together.
8. Backfill old photos through an idempotent, resumable operation with bounded
   concurrency; protect against replacement/deletion during backfill.

## iOS and Mac obligations

Both clients follow the same selection rules:

| Context | Required representation | If unavailable |
| --- | --- | --- |
| Queue row, list or candidate card on a capable server | Thumbnail | Placeholder and retry; do not eagerly fetch originals for every card |
| Comparison and zoom | Original | Loading/error state and explicit retry; never substitute a thumbnail |
| Contours, landmarks, matching or other image analysis | Original or the exact retained query input | Do not run on thumbnail pixels |
| Server predating thumbnail support | Existing original behavior | Compatibility mode; no claimed thumbnail savings |

Prefer `download_url` for the selected representation. Use that representation's
stable authenticated route when signed delivery is unavailable, including local
storage and older backends. Never route a storage request through API credential
injection, bearer refresh or API-session error handling.

Cache by backend, authorized account/organization scope, photo ID, source
revision and representation. Include the derivative recipe revision for a
thumbnail. Do not use the rotating signed URL as cache identity. Old servers
without revision metadata retain legacy behavior rather than claiming immutable
historical identity. Clear private in-memory state on logout/scope changes;
discard late results from obsolete sessions, cases or matching attempts.

Coalesce concurrent loads of the same representation. Give the selected original
priority. Bound speculative original downloads, decoded memory and retained
bytes; cancel irrelevant work when leaving the review. Never prefetch originals
for the whole queue. Exact budgets remain engineering choices pending profiling.

If a link is expired, or storage reports 403/404, coalesce metadata renewal for
the active review and retry once with the refreshed reference. If renewal says
the photo is inaccessible/deleted, show that state. If storage still fails, show
a retryable image error. Do not loop, renew once per failed image, silently
create a new matching attempt, or treat storage 403 as an API logout.

## History and exact evidence

The user expressed a preference for the old candidate photo when reopening an
old review. The proposed target is to pin each candidate's photo identity and
source revision to the matching attempt, independent of renewable signed URLs.
Confirm historical retention before implementation: current snapshots cannot
reconstruct a replaced image that was never retained. Legacy attempts with no
provenance must show that historical photo availability is unknown; never label
a current photo as the historical input.

The query side must show the exact retained matching input, including an explicit
crop or alternate upload used for that attempt. Its source original can be a
separate view, but must not replace the evidence that produced the result.
Deletion/access removal remains authoritative; retained history does not grant
new access. Confirmed on 2026-11-25: retain a source version while an active matching-history
reference points at it. Unavailable or deleted history stays unavailable and is
never replaced with the current photo. Attempts saved before version pinning
report `unknown_legacy`. Unreferenced retired versions may be removed after the
existing cleanup grace period. Referenced history has no separate calendar expiry.

## Thumbnail execution and worker decision

First profile thumbnail creation during upload with representative camera files,
concurrent uploads, storage writes and production-like resource limits. A worker
is an execution choice, not a requirement for separate image representations.
Do not make original-based comparison wait for a thumbnail that is not ready.

A local exploratory run on 13 bundled 640x640 JPEGs produced 384-pixel JPEG
thumbnails at quality 80 with per-file median decode/resize/encode times around
3–4 ms. It excluded storage, DB, API concurrency and camera-size originals;
it does not establish upload latency or justify a production architecture.

Confirmed on 2026-11-25 after the synthetic benchmark in
`docs/benchmarks/photo-delivery-2026-11-25.md`: generate thumbnails inline with
one encoder slot per API process, default longest edge 384 and JPEG quality 80,
behind `PHOTO_THUMBNAIL_ENABLED`. A successful original upload stays successful
if thumbnail creation fails; backfill repairs the derivative. Do not add a
durable worker unless a later production-like upload profile exceeds the
deployment budget. An in-process fire-and-forget task is not the durability
contract. That benchmark is not a production capacity claim.

## Alternatives and tradeoffs

- Existing signed fields plus review metadata hydration reuse backend support;
  a separate general-purpose batch endpoint is not yet necessary by evidence.
- A single review metadata response can coalesce saved-photo lookup and renewal;
  its exact route and bounds remain to be designed without changing snapshot DTOs.
- Binary bundles reduce client requests but can resend cached originals and delay
  the first usable image. They do not directly solve database access per image.
- Base64 couples image transfer to metadata and enlarges payloads.
- Proxy image routes remain compatibility paths; they cannot be the normal
  signed-link expiry path if the aim is reducing database work.

## Rollout and acceptance

Deploy additive backend metadata before enabling client thumbnail selection.
Retain existing original fields/routes and support local storage. Both clients
must distinguish absent capabilities from a missing derivative on a new server.
Test old client/new server and new client/old server, then exercise one staging
release with iOS and Mac. Backfill rollout is independent of original availability.

Acceptance checks for implementation:

- Compare candidate metadata query counts for 1, 10 and the supported maximum;
  prove bounded query growth, and no DB/API request for normal signed image bytes.
- Check fresh matching, saved reopening and coalesced expiry renewal separately.
- Verify cards request thumbnail bytes and comparison/analysis request original
  bytes; originals and retained query evidence keep their source content.
- Cover no thumbnail, legacy server, local storage, storage 403/404, deletion,
  replacement, retry exhaustion, cancellation and corrupt image handling.
- Verify cross-organization denial, no credentials sent to storage, no signature
  persistence/logging, and scope changes while a download is in flight.
- Exercise interrupted derivative creation, duplicate backfill and replacement
  during generation. Record API/DB time, storage requests, transfer bytes,
  comparison-ready latency and peak memory separately.

No implementation tests or staging acceptance have run for this document.

## Approval and next step

The user approved this target contract on 2026-11-25 and later confirmed
retention, unavailable-history behavior, and upload success when thumbnail
creation fails. Those decisions are recorded above. Staging end-to-end
acceptance is still outstanding.
