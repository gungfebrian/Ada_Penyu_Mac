# Turtle illustration sync implementation plan

Goal: Match the iOS illustration geometry and outlines while preserving Mac behavior.
Spec: ../specs/2026-11-26-turtle-illustration-sync-design.md

- [x] Extract TurtleBodyDiagram(highlights:) into Components/TurtleBodyDiagram.swift.
- [x] Copy canonical 200 × 200 frames, shell-last order, direct image sizing, and bounded shape outline support.
- [x] Preserve namespaced assets, Mac tints and neutral tint, accessibility labels, and 230-point maximum width.
- [x] Build and run existing ReviewRegressionTests: 7 tests passed, zero failures.
- [x] Compare neutral/mixed renders at 190 and 230 points: all seven compiled assets resolved. Twenty paired PNG renders matched the iOS reference exactly after normalizing its asset namespace and colors to Mac values. Cases cover neutral, mixed, each condition filter, and all seven parts in each condition. Card arrangement and filter/history integration were inspected as unchanged; live card interactions were not exercised.
- [x] Complete an independent code review: no actionable bugs. Fixed artwork syntax is verified; generic SVG syntax is outside the private renderer’s intended inputs.

Ruling: This reversible visual adaptation uses existing regression tests and rendered comparisons, as approved; no new tests that mirror artwork constants. Existing unrelated concepts_brief.md is preserved. Work occurs in the existing isolated abui-am/butterfish worktree. No merge or publish is requested.

Validation: xcodebuild test -project Ada_Penyu_Desktop.xcodeproj -scheme Ada_Penyu_Desktop -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:Ada_Penyu_DesktopTests/ReviewRegressionTests succeeded. git diff --check passed. The built application was launched and its running process confirmed. Temporary rendering harness initially had duplicate reference helper names and missing bundle metadata; both were corrected only in temporary files, with no production changes.
