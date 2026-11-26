# Expanded desktop review implementation plan

> For agentic workers: use subagent-driven-development or executing-plans task by task.

**Goal:** Deliver request-scoped 70% → explicit100% review, complete saved candidates, audited Reject/Restore and durable identity decisions across BE and Mac.
**Architecture:** Add request-scoped search policy and immutable full attempt evidence on BE; a focused review-decision service stores audit events. Mac consumes the additive contract, pages candidates and saves decisions server-first.
**Tech stack:** Existing SwiftUI/Swift and FastAPI/SQLAlchemy/Postgres/inference service; no new infrastructure.
**Spec:** ../specs/2026-11-26-expanded-not-sure-review/design.md

## Global constraints

Use exact shared contract in the design. Preserve mobile/legacy defaults and existing both-side requirement for new identities. Work in isolated branches from main. No live database migration/deployment. Protect other local work. Keep screenshot illustration PR separate.

## Review focus

Cross-org access; retries with altered payload; stale photo/index/account evidence; incomplete pages versus complete review; same/new transaction rollback and duplicate creation.

## Task 1: Backend contract and implementation

- [x] Add failing integration and focused engine tests for the acceptance cases in the design; run and confirm failures.
- [x] Implement per-request70/100 through local and remote inference, persist full snapshots/coverage and pinned photos, expose stable pages.
- [x] Implement additive audit migration/model/service, reject/restore, audited existing identity and atomic idempotent new identity. Update API docs.
- [x] Run focused and full backend suite, migration/static checks; record exact results and independently review.

## Task 2: Mac client and workflow

- [x] Add failing contract/store tests for design acceptance cases, watching failures.
- [x] Add DTO/repository endpoints and attempt-scoped paging/review state; integrate automatic70, explicit100 and compatible server rejections.
- [x] Reuse rail ×/Restore; add counts, exclusions, Load more, Search all, honest busy/cancel-wait and safe retries.
- [x] Add required New turtle form and server-backed completion; preserve local/demo behavior.
- [x] Build, run focused and full Mac tests; inspect rendered UI and independently review. MobileBuildMCP245tests passed0failures; native controls rendered and independent review plus fixes clean.

## Task 3: Integrate and publish

- [x] Verify request/response fixtures across both repositories and all acceptance requirements, fix material review findings. Actual BE HTTP fixtures decode in Swift; stale-feature/hydration regression REDGREEN verified.
- [x] Commit only this feature in coherent groups, push branches and create linked PRs targeting main. Do not merge or deploy. Mac PR: https://github.com/gungfebrian/Ada_Penyu_Mac/pull/24

Final verification: BE 894 passed, 1 optional skip, with migration roundtrip and alembic check. Mac 245 passed, 0 failed, via MobileBuildMCP 2.7.1. Four backend-response fixture tests are in the Mac suite. Both independent reviews and scoped fix reviews passed. No production data, credentials, or local .env included. Backend PR https://github.com/abui-am/turtle-identification-be/pull/16 is merged; dev OpenAPI still lacks review_coverage and decision routes until the main image deploy finishes. Live feature E2E remains gated by that rollout.
