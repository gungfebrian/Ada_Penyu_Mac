# Expanded desktop review: execution design and shared contract

Approved direction: Mac review runs 70% detailed same-side comparisons; reviewer explicitly expands to 100%; all full-search results (including weak ones) are browsable; × Reject and Restore track review; explicit Same turtle or New turtle decisions are audited. Source concept: concepts_brief.md. User authorized implementation in Mac + BE and separate PRs on 2026-11-26.

## Execution rulings

- Additive request-scoped desktop review. Legacy/mobile requests without review_coverage retain current behavior, thresholds and schemas. Review requests never automatically assign identity, including under frozen research policies. Support local and remote inference consistently without mutating global settings.
- Percent denominator is eligible same-side indexed identity photos. Use ceil(N * percent / 100), capped at N, so small galleries are not undercounted. Existing schema has one identity photo per turtle/side. For paired queries, eligible_count and compared_count sum reference-photo comparisons across both query sides. candidate_total and excluded_count count distinct turtles. 100% means completed comparisons, not human inspection.
- Preserve original/expanded attempts. Expansion uses the parent's immutable query bytes and a fresh clearly linked gallery snapshot; reject stale source changes. Carry rejections only for identical query bytes, side and pinned reference-photo evidence. Do not reuse a rejection merely by turtle ID or a score/rank.
- Store every ranked candidate and reference-photo evidence before slicing the HTTP response. Pages read only the immutable saved result, with existing pinned-photo delivery. Keep low scores visible for review. Review result scores are relative, not correctness probabilities.
- Keep synchronous inference for this increment, with honest busy/cancel-wait UI; cancelling client wait does not promise server cancellation. Retry uses the same attempt UUID and payload. Expose no invented numeric progress. Existing timeouts must accommodate the configured inference timeout. No new queue/cloud service.
- Explicit reject/restore is saved server-first with authenticated actor and timestamp, then reflected locally. Existing same-identity selection is also audited. Expose failures; never silently treat failed saves as successful.
- New turtle: require completed 100%, every candidate actively rejected, no catalog exclusions, adequate-photo acknowledgement, nonblank reason, and both left/right source photos as required by the existing domain. Atomically create profile + link original sighting + audit, with a client decision UUID reused on retry; reject changed payload on replay. Never auto-create from low scores. Missing prerequisites leave case pending with actionable messages.
- Preserve source photos; promote/copy suitable submitted sighting head-photo evidence into the new identity's reference photos using existing storage/assets/indexing patterns. Do not invent a missing side. Name, six-digit profile code and species are explicit form inputs; sex defaults unknown; first_seen_at uses original sighting time. No out-of-org access, destructive migrations, live DB writes or deployments.

## Shared HTTP contract (both implementers must follow)

Existing POST /api/v2/logs/{log_id}/rematch multipart manifest gains optional review_coverage: 70|100 and parent_attempt_id: UUID|null. Its limit remains first-page size (default 8 from Mac, existing cap 50); complete result persistence is independent of this size. 100% requires a completed parent 70% review attempt from the same sighting; expansion takes immutable query bytes from that parent, no upload, and inputs identify the same source IDs/sides. A changed source must require a fresh 70% search. Existing manifest without these fields behaves unchanged.

Response and saved attempt objects gain optional review: ReviewState|null. ReviewState wire fields:
- coverage_percent: Int (70 or 100)
- candidate_total: Int (full durable ranked result count)
- eligible_count: Int (same-side eligible reference photos, summed across paired query sides)
- compared_count: Int (actually completed detailed comparisons)
- excluded_count: Int (catalog identities unavailable to this search)
- parent_attempt_id: UUID|null
- rejected_candidate_ids: [UUID] (active compatible rejections)
- can_create_new: Bool (server's coverage/rejection eligibility, photo adequacy still explicitly acknowledged on POST)

GET /api/v2/logs/{log_id}/match-results?review_only=true&limit=1 returns the latest desktop attempt. Default review_only=false preserves the full history. Filtering applies before counting and paging.

GET /api/v2/logs/{log_id}/match-results/{attempt_id}/candidates?limit=50&offset=0 -> {items:[existing expanded v2.MatchCandidate],total:Int,limit:Int,offset:Int,review:ReviewState}. All pages belong to one saved attempt; fields/order stable, no matching rerun. Candidate photo delivery must work after the first 50 as well.

GET /api/v2/logs/{log_id}/match-results/{attempt_id}/review -> ReviewState.
PUT same /review body {decision_id:UUID,candidate_id:UUID,rejected:Bool} -> ReviewState. Authenticated actor/time captured server-side; decision_id is idempotency identity, reused payload must match; reject then Restore is a new event with new UUID. Reject unavailable/stale photo evidence visibly. Cross-org/attempt membership enforced. Persist evidence-bound rejection history, not a mutable client-only set.

Existing PUT /api/v2/logs/{log_id}/identification gains optional decision_id:UUID and note:String; review attempts require both, and record a manual explicit decision, while legacy requests remain compatible. A rejected candidate requires Restore before confirming. Preserve existing source evidence conflict checks.

POST /api/v2/logs/{log_id}/match-results/{attempt_id}/new-turtle body {decision_id:UUID,note:String,photos_adequate:Bool,turtle:existing v2.CreateTurtle} -> existing v2.Sighting. Existing CreateTurtle fields: id,profile_code,name,species,sex,first_seen_at. Replay is idempotent; invalid or stale prerequisites create neither orphan profile nor duplicate decision. Profile code conflict is actionable 409. Use original submitted sighting head photos, including the companion side, to satisfy the existing both-sides domain rule.

Store reviewer/time/reason/attempt/query/reference evidence for rejects, restore, same and new. Add an additive migration for durable decision events if needed; never change completed matching facts when decisions change. Audit retrieval is not a new analytics project.

## Mac integration

Select an unresolved case: use the latest desktop-review snapshot if present; if only a legacy/mobile attempt exists, preserve it in BE history and start a 70% desktop attempt. Empty unsaved case also starts at 70%. An old backend rejecting the new contract must show a useful error and must not silently claim 70%.
Render first page; Load more reads saved candidate pages and deduplicates by ID for that attempt. Thumbnails lazy, originals selected/on-demand, no eager download of entire catalog. Show coverage/rejected counts and exclusions. Reuse the existing rail ×/Restore, Compare/Contours/Align. Add 'Didn’t find a match? Search all' for 70% only and Load more when more results exist. After expansion, apply server rejection state; changed evidence loses its rejection. All async operations guard account/navigation/attempt changes and surface retry.
New turtle confirmation adds name/code/species, adequacy confirmation, existing reason field and stable decision/turtle IDs for safe retry. Enable only when server review eligibility allows; domain failure remains pending. Server-backed rejected/confirmed/new states only update after success. Keep demo/local behavior unchanged.

## Acceptance

Backend tests: default matching unchanged; 70% vs100% changes real detailed call count with ceil and no cross-request leakage; remote wire + validation use request policy; weak results beyond50 remain persisted/paged with pinned photos; retries and altered payload; foreign org access; source/ref replacement; compatible parent rejects inherited but stale rejects reset; restore removes active rejection and remains audited; New requires100/all rejects/no exclusions/both photos, creates+links once and rolls back entirely on failure; existing identity confirm audited and legacy compatible.
Mac tests: DTO/requests match shared contract; automatic70, explicit100 parent, limit independent; page load/retry/account/attempt guarding; rejection save failure leaves state intact; restore; preservation from server after expansion; complete result browsing; new creation required inputs/eligibility, repeat retry IDs, success removes pending queue row, failure stays pending; unsupported older BE surfaced; existing workflow regressions.

## Verification and companion rollout

Backend PR: https://github.com/abui-am/turtle-identification-be/pull/16 (commits7f960b8,8507b09). Backend full suite894passed,1optional upstream-reference skip; additive migration022 roundtrip and schema checkpassed on isolated PostgreSQL. Independent review and cache-provenance rereview clean.

Mac validates actual backend-generated HTTP responses in fixture decode tests and uses MobileBuildMCP2.7.1 for build/test/launch. Credentials are never repository artifacts. Deploy workflow updates development only after main passes CI; a feature-branch push alone does not deploy new APIs. The API and configured remote inference need compatible coverage support before live expanded review can succeed.
