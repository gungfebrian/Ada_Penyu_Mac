# Contour beta implementation plan

Goal: an immediately discoverable, truthful and adjustable scale-edge comparison on current main.

Spec: `docs/superpowers/specs/2026-11-13-contour-beta-review.md`.

Architecture: isolated local ContourEngine and reusable SwiftUI photo comparison, integrated into the existing I3S and scientist demonstration surfaces. Preserve PR7 transport, authentication and v2 record implementation.

- [x] Preserve dirty tracked/untracked work in a Git stash; pull main with fast-forward only; record base and baseline checks.
- [x] Add failing contour and match-contract regressions, then implement Canny-style detection and safe mapping.
- [x] Build reusable comparison with explicit visibility, two colors, shared threshold, opacity, line weight, synchronized zoom/pan and actual image registration.
- [x] Integrate visible contour entry points, label demo/prototype state and remove fabricated fallback evidence.
- [x] Guard stale matching/query/filter state and make gallery replacement a separate, snapshot-based confirmed operation.
- [x] Run local Debug/Release verification and UI task paths; publish current architecture, Mermaid workflows, audit findings, verification and release gates to Notion.

Review focus: missing references, low contrast and excess background edges, opposite-side photographs, candidate changes during rendering, repeat identities in paired retrieval, query/session changes during requests and mismatched upload side.

Ruling: work in this checkout after preserving the previous dirty state, as the user explicitly requested pulling the newest main. Do not restore older AppStore/DataLayer/ContentView versions over PR7. Use Notion and Mermaid rather than install an unavailable Archify renderer. Leave owner review and merge intact.

## Execution record

- Main was fast-forwarded to `3aa7133`; pre-existing dirty work is preserved in stash `ef6e2c218736f2ca49d3af6d81391c98e8828538`. Baseline full tests passed.
- Contour detector: seven deterministic tests passed. Matching DTO regressions first failed with `invalidResponse`, then passed after current backend key mapping and duplicate-safe side evidence selection.
- Delayed map response/error tests first failed (old values and errors overwrote current filters), then passed with captured filter/session and request generations. Full-suite verification caught a redundant mode-transition reload; its scheduled task now coalesces with an explicit awaited reload.
- A fresh read-only whole-change reviewer identified two Important findings and no minors: dual input side ownership and changing to examples while backend matching is pending. Three negative regressions reproduced those failures, with a fourth valid-pair check. The fixes validate paired side ownership at data access, search and gallery-write boundaries; an explicit example source change advances the request generation.
- Final: Ruling: reject enabling dual mode while the primary photograph is marked Right, preserving that photograph; route known-side bundled samples to their matching slots. This avoids silently relabeling a photograph. Cost if wrong: an extra import/side-selection step; anatomical side for imported images still requires operator correctness.
- Final: Ruling: signed distribution, live backend deployment and field identification accuracy remain release gates. No changes to backend/iOS or production state are authorized by this Mac-only implementation scope. Cost if ignored: local comparison tests could be mistaken for a production-ready scientific review system.
- No deferred minor findings from the fresh reviewer.
- Concurrent user edits in `Views/AccountLoginView.swift` and `Ada_Penyu_Desktop.xcodeproj/project.pbxproj` were observed after implementation began; preserve them and exclude them from these commits.

Final: fixed both Important review findings — MatchInputOwnershipTests negative cases RED (3 failures) → GREEN; whole suite 55/55. Release BUILD SUCCEEDED. Manual color, visibility, threshold and both comparison paths verified. Minimum-window resize could not be verified because computer-use dragging failed; retained as a release checklist item.
