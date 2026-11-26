# Expanded Not Sure Review on Mac

* **Author:** adjiemuliadi
* **Date:** 2026-11-26
* **Status:** Brainstorm reviewed through seven Goldfish lenses. Product choices below remain open; this is not an implementation plan.

## Overview

The largest gap is that completing a wider search does not establish that the reviewer checked every result, or that every catalog individual had a usable reference photo. The feature must make both limits visible before the reviewer decides that a sighting represents a new turtle.

The user confirmed this flow: the Mac Not Sure workspace initially runs detailed XFeat photo comparisons against a 70% shortlist of eligible same-side indexed gallery photos. If the reviewer finds no match, clicking **“Didn’t find a match? Search all”** explicitly expands detailed comparisons to 100% of that eligible gallery. Every individual returned by the completed full search, including low-ranked and low-score individuals, must be available through pagination. The current eight-result request and fifty-result maximum are insufficient.

The reviewer uses the existing comparison tools, explicitly confirms an existing identity when found, or explicitly chooses **New turtle** after checking the catalog without a match and judging the sighting photo adequate. Search completion never creates a turtle automatically. The original and expanded attempts, reviewer, time, reason, selected or new identity, and compared photo evidence must be retained.

## Analysis

### Complete results and stable evidence are prerequisites

The current Mac command defaults to eight results, the rematch API caps its request at fifty, and matching truncates candidates before returning them. Low-reliability policy can also hide candidates. Saved match-result summaries contain only returned candidates. Existing pagination lists attempts; it does not page a complete candidate set. Raising the request limit alone cannot satisfy the confirmed behavior. [S1–S4]

The proposed safeguard is to retain a complete, ordered full-search result set and serve pages from that saved attempt. Later pages must not rerun matching against a changing gallery. Low scores remain visible for human review without changing automatic acceptance thresholds. Confirmation currently requires the selected identity to belong to the saved attempt; every result page must preserve that rule. [S3–S5]

The existing server-backed Mac flow replaces candidates when its attempt changes. Preserve that behavior when adding expansion and history. The fallback flow merges candidates, but it is not evidence of an existing server-backed confirmation bug. [S2, S9]

### “All” means the eligible gallery, not the whole catalog

Eligibility currently depends on an indexed identity photo, compatible index/model information where required, and the same side as the query. The gallery is not a collection of every historical sighting photo. The current schema permits one identity-photo row per turtle and side, so eligible photo and individual counts coincide for a single-side search today. Keep the percentage defined in photos; do not invent a historical-photo indexing expansion. [S4, S8]

Show the denominator and the actual completed comparisons. Missing, unindexed, incompatible, unavailable, failed, and opposite-side-only evidence must not be counted as a successful comparison or a nonmatch. A successful 100% search can still leave catalog individuals outside its eligible gallery. “100% of eligible same-side photos compared” is more precise than an unqualified “all turtles checked.”

Whether expansion keeps the original gallery snapshot or uses a clearly linked fresh snapshot is open. Either choice must preserve what each attempt actually used. The inspected attempt summaries retain query evidence and candidate labels/ranks/confidence, but do not retain the complete compared reference-photo set. The proposal is to extend evidence with photo identity/revision, search policy, relevant model/index/calibration information, exclusions, and actual comparison outcomes. The exact evidence format and retention remain design work. [S3, S5]

### Machine coverage and human checking are different facts

Keep three facts distinct: photos successfully compared by the pipeline, individuals available to browse, and individuals the reviewer actually inspected. Fetching a page, reaching the last page, or finishing computation cannot prove visual inspection. A failed or cancelled search cannot imply completed coverage.

The user clarified that the existing × Reject button is the marker for a reviewed candidate that does not match. Reuse that action rather than adding a separate checked button or replacing it with an attestation. The current action inserts the candidate ID into rejectedCandidateIDs, advances to the next candidate, supports Restore, and saves to the local review journal. This is an explicit reviewer decision, not machine proof of inspection.

Carry that decision into the expanded-review evidence. Proposed safeguard: retain a previous rejection only when the query evidence, head side, and compared reference-photo evidence remain unchanged. A changed ranking alone does not invalidate it; changed evidence needs renewed inspection. Restore removes the active rejection while preserving the audit history. Candidates newly introduced by the 100% search remain unreviewed.

The intended completed-review pathway is: reject nonmatches in the 70% results, expand to 100%, inspect/reject remaining candidates, then explicitly confirm New turtle if no match exists and the sighting photo is adequate. Display inspection progress from explicit review decisions rather than page views. The treatment of excluded catalog individuals and exact New turtle gating still need a stated rule; do not silently treat unavailable evidence as ruled out. A separate manual catalog picker remains deferred, not an assumed v1 feature.

### Coverage must be scoped to the review request

The current desktop command carries a result limit, not a coverage policy. Local matching reads a configured fraction, research bundles have their own policy, and remote inference both sends and validates the configured fraction. Changing a global setting would not isolate this Mac workflow. [S1, S4, S6]

The proposal is a request-specific 70% or 100% review intent carried consistently through local scoring, remote scoring, validation, attempt fingerprinting and replay. Preserve mobile defaults and frozen/research calibration behavior. An unsupported combination must fail visibly rather than silently use another percentage. Rounding for small galleries and compatibility with older backend/inference versions need explicit design decisions.

### New turtle currently saves a local outcome

The inspected Mac synchronization function sends existing-identity recommendations to the server. New turtle instead becomes a locally saved review outcome. This does not establish that a server identity was created or linked to the sighting. [S2, S10]

The confirmed explicit New turtle decision must be preserved. Its server meaning remains to be settled: if v1 creates a real identity, creation and sighting linkage need a deliberate transaction, retries that cannot create duplicates, conflict handling, and durable reviewer/time/reason/photo/attempt evidence. A local verdict must not be presented as completed server creation. Photo adequacy and the treatment of incomplete catalog coverage also need a stated review rule.

### Wider search changes cost and score context

The rematch endpoint is synchronous and matching runs while the sighting attempt lock is held. Detailed comparisons can materialize reference features. Measure current catalog size, time, payload and memory use before choosing a different execution model. Define honest busy, failure, retry and cancellation behavior; stopping the client wait does not demonstrate that server computation stopped. Do not promise numeric progress without measured stages or counts. No new queue or cloud service is assumed. [S3–S6]

Confidence is a score against the strongest rival, explicitly not the probability that an identity is correct. Expansion can change the rival and score context. Preserve both attempts and avoid presenting a confidence increase or decrease as a direct change in identity certainty. [S7]

The inventive resolution is small: separate complete reviewer visibility from automatic decision thresholds, and separate each saved attempt from the human verdict. Reusing query features or earlier comparison scores is an optional optimization only when query bytes, reference evidence, model/calibration and gallery compatibility can be established. It is not necessary to settle that optimization now.

## Goals vs. Non-Goals

**In-scope goals**

- The confirmed Mac 70% → explicit expansion click → 100% flow.
- Complete paginated browsing of full-search results, including weak results.
- Existing visual comparison tools and explicit human identity decisions.
- Honest eligibility, exclusion, computation and human-review information, using the existing × Reject and Restore actions for explicit nonmatch decisions.
- Preserved original and expanded attempts, result ownership, compared-photo evidence and decision audit.
- A deliberate New turtle outcome after catalog checking and adequate-photo assessment.

**Out-of-scope non-goals**

- Automatic new-turtle creation because a search ended or scores were low.
- Global changes to mobile matching, frozen calibration or research policies.
- Indexing every historical sighting photo, replacing the comparison tools, or redesigning the matching system broadly.
- Adding a separate inspected-state control instead of the existing × Reject action, a separate catalog picker, a new queue, or a new cloud service. Exact New turtle gating for incomplete/excluded evidence remains open.
- Code changes, backend mutation, deployment verification, tests or builds in this brainstorm.

## Alternatives Weighed

| Alternative | Assessment |
| --- | --- |
| Increase eight results to fifty | Insufficient: still truncates a larger gallery and does not create complete saved pagination. |
| Change the global shortlist fraction | Not selected by this review: would couple Mac review to other clients and remote/frozen behavior. |
| Always run 100% immediately | Not the confirmed product flow; loses the user's explicit staged expansion. |
| Hide weak results after the full search | Conflicts with the confirmed ability to inspect every completed full-search result. |
| Create a turtle when processing ends | Conflicts with the confirmed explicit human decision. |
| Add a separate checked marker or reviewer attestation | Not selected after user clarification: reuse the existing × Reject and Restore actions. Exact gating for incomplete review/coverage remains open. |
| Add a separate manual catalog picker | Deferred/open; exclusions still need an honest review policy. |
| Add background job infrastructure immediately | Deferred pending measurements of the current synchronous path. |

These assessments are review conclusions or confirmed-flow constraints, not attributed maintainer decisions.

## Key Decisions & Staging for Next Steps

**Confirmed and carried forward:** the percentages apply to eligible same-side indexed photos; expansion needs the explicit click; all completed full-search results remain browsable; existing identity and New turtle both require explicit human decisions; machine completion is separate from human checking; unavailable evidence cannot silently become a nonmatch; preserve both attempts and decision evidence.

**Inspection decision resolved after review:** The user identified the existing × Reject button as the marker for a reviewed nonmatch. Use it and its Restore action for inspection progress and evidence. Preserve compatible rejections across the 70% → 100% expansion and inspect newly introduced candidates; this is a proposed evidence-matching safeguard, not a new user-confirmed gate.

**Remaining product decisions:** Define how unavailable catalog references or incomplete review affect the explicit New turtle action, and define its durable server-side creation/linking outcome.

Other choices to settle before an implementation plan:

1. Define the actual server outcome of New turtle, including identity details, creation/linking, and retries; distinguish it from the current local verdict.
2. Define how missing or unusable catalog references affect New turtle and when the case should remain unresolved or request another photo. Keep a separate catalog picker deferred unless selected.
3. Choose original versus refreshed gallery membership for expansion; retain the relation between attempts and stable pages either way.
4. Set the request-specific coverage, rounding, compatibility and frozen-policy behavior; decide handling for old truncated attempts.
5. Measure synchronous feasibility, then define truthful progress, cancellation, retry and failure behavior. Select extra infrastructure only if those measurements justify it.

The seven-reviewer findings above preceded the user’s clarification about × Reject. The inspection-decision update was incorporated by the primary agent after checking the existing reject, auto-advance, Restore and local persistence code; the updated brief has not been rerun through Goldfish.

After those choices, draft the design and then a checkable implementation plan in the project's approved locations. This brief does not authorize implementation or claim those choices are resolved.

## Reviewer Status and Read Evidence

All seven reviewers ran as separate native agents with `fork_turns: none`, without the parent transcript or retrieved memory. They read the installed persona and Codex integration before reporting. Instruction-file exclusion by the host was not independently proven. No document standards were supplied or applied. No reviewer failed or required a retry.

Persona root: `/Users/abui/.codex/plugins/cache/egm/egm/0.1.1/agents/`. Integration: `/Users/abui/.codex/plugins/cache/egm/egm/0.1.1/docs/codex.md`.

| Reviewer | Status | Reported read evidence |
| --- | --- | --- |
| egm-design | Completed | `design_critic.md:7–32,49–66`; integration `1–164`; S1–S7 and focused desktop UI. |
| egm-codebase-details | Completed | `codebase_details.md` and integration; all supplied desktop/backend sources; findings cite S1–S7. |
| egm-zoom-out | Completed | `zoom_out.md:7–39,69–74`; integration `47–70`; S1–S8 and desktop UI. |
| egm-comprehension | Completed | `comprehension.md` and integration; all supplied sources plus S8; findings cite S1–S8 and desktop UI. |
| egm-implementation-readiness | Completed | `implementation_readiness.md:1–67`; integration `1–145`; S1–S8 and desktop UI. |
| egm-structural | Completed | `structural.md:9–32`; integration `47–70`; all supplied sources, with truncated output reread; S1–S8 and desktop UI. |
| egm-inventive-catalyst | Completed | `inventive_catalyst.md:1–101`; integration `1–149`; S1–S8 and desktop UI. |

Read evidence above is each reviewer's reported evidence. The synthesizer also directly read the listed core source sections and checked S8–S10 to resolve coverage and attempt-ownership claims. Local backend checkout evidence does not prove live deployment behavior.

Source roots: **Mac** = `/Users/abui/orca/workspaces/Ada_Penyu_Mac/butterfish/Ada_Penyu_Desktop/`; **Backend** = `/Users/abui/@code/turtle-identification-be/`.

- **S1:** Mac `Networking/NotSureRecords.swift:53–99` — command limit and result DTOs.
- **S2:** Mac `AppStore.swift:470–520,944–1098` — verdict synchronization, retries, searches and fallback candidate handling.
- **S3:** Backend `app/api/v2/rematch.py:43–46,137–186,213–247` — maximum limit, fingerprint/replay/query evidence, matching lifecycle and confirmation restrictions.
- **S4:** Backend `app/services/matching/match_service.py:128–150,190–438` — gallery filtering, shortlist, detailed comparisons, ranking, truncation and visibility.
- **S5:** Backend `app/services/match_result_service.py:15–81`; `app/models/match_result.py:12–27` — saved summaries, idempotency and attempt-history pagination.
- **S6:** Backend `app/services/ml/remote_inference.py:158–197` — coverage on the wire and output validation.
- **S7:** Backend `app/services/matching/fusion.py:15–47,95–103,228–246` — shortlist fusion, relative confidence and visibility policy.
- **S8:** Backend `app/models/turtle_photo.py:15–17`; `app/repositories/gallery_repository.py:36–64` — one identity photo per side and indexed gallery selection.
- **S9:** Mac `AppStore.swift:717–732,778–813` — server-backed hydration replaces candidates on attempt change and retains attempt context.
- **S10:** Mac `NotSureReview.swift:191–237`; `Views/NotSureWorkspaceView.swift:2426–2595,2990–3040` — explicit verdicts, local new-individual outcome, confirmation and client search behavior.
