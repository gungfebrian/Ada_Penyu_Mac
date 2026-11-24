# Automatic Not Sure Review implementation

- [x] Add metadata queue and v2 rematch/results/confirmation repository contracts, tested against HTTP fixtures.
- [x] Replace eager sync with paginated metadata loading and stale-session guards.
- [x] Prepare only selected cases, prefer saved attempts, prompt ambiguous sources, fetch selected images lazily and preserve retry attempts.
- [x] Connect automatic loading, Refresh/Retry/Load more, preparation and source picker to existing review UI.
- [x] Add backend queue/storage/ML/query-count regression checks and isolated latency/payload measurements; update integration docs.
- [ ] Run complete Mac/backend suites, build and inspect the app, review complete changes in fresh context.

## Execution ledger

Base Mac fa59f65; backend 086ea3d. Worktrees isolate existing feature branches and preserve unrelated artifacts. Backend characterization and benchmark work delegated independently; Mac implementation stays inline.

Ruling: keep lightweight remote queue rows separate from journal cases so opening a queue cannot require persisted image bytes. Hydrate a journal case only on selection; preserve local review edits when refreshing metadata.


Backend verification: 838 passed, 1 optional reference-checkout skip. Local 50-row metadata page p50 11.566 ms, p95 14.941 ms, 57,745 bytes, 10 SQL queries. This characterizes the existing backend endpoint and is not a backend speedup or production timing claim. Full details live in the backend benchmark report.

Review fixes: accept flat saved snapshots, retain recorded legacy query sides, attach paired crops to the matching side/photo ID, distinguish Retry from a fresh match, refresh detail state per attempt, retain Reviewed history access, adjust pagination after known removals and navigate legacy cases using their selected queue identity. Source selection previews only the chosen photo.

Journal compatibility: existing embedded local/history evidence remains intact. Removing journal image bytes is deferred because it requires an explicit history restoration design. Ordinary revisits preserve annotation maps; a changed query clears coordinates tied to old pixels. Reopening a reviewed case changes preparation eligibility and restarts its task.

Final verification evidence and deployment limitation: [verification report](2026-11-24-automatic-not-sure-verification.md). Final UI cleanup rerun passed198 tests including all10 new regressions; three existing image tests received SIGTERM and were not rerun to avoid further visible test-host relaunches. Standalone app opened and stayed running. Live validation remains deferred until the newer backend contract is deployed to the configured dev endpoint.
