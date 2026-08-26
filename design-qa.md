# Ada Penyu Desktop — Design QA

final result: passed

## QA target

- Platform: native macOS SwiftUI
- Reference viewport: 1512 × 982 px at 1×
- Implementation window: 1512 px wide; 893 px visible height after macOS working-area constraint
- Comparison normalization: each source was top-cropped to 1512 × 893 and scaled to the Computer Use capture size of 1301 × 768. No implementation screenshot was stretched or selectively cropped.
- Density: source PNGs are 1×; Computer Use captures are 1301 × 768 JPEGs representing the 1512 × 893 logical window.
- State parity: Individuals / All / All conditions, Map / 30 days / All species / All conditions, Turtle #001 detail, and Individuals export modal.

## Sources and implementation evidence

| Surface | Source | Implementation | Combined comparison |
|---|---|---|---|
| Individuals | `/Users/gung/Downloads/3 (individual list).png` | `/Users/gung/Documents/Codex/2026-08-26/users-gung-documents-swift-ada-penyu/work/audit/final/individuals-implementation.jpeg` | `/Users/gung/Documents/Codex/2026-08-26/users-gung-documents-swift-ada-penyu/work/audit/final/individuals-comparison.png` |
| Map | `/Users/gung/Downloads/2 (map).png` | `/Users/gung/Documents/Codex/2026-08-26/users-gung-documents-swift-ada-penyu/work/audit/final/map-implementation.jpeg` | `/Users/gung/Documents/Codex/2026-08-26/users-gung-documents-swift-ada-penyu/work/audit/final/map-comparison.png` |
| Turtle detail | `/Users/gung/Downloads/5 (sighting log).png` | `/Users/gung/Documents/Codex/2026-08-26/users-gung-documents-swift-ada-penyu/work/audit/final/detail-implementation.jpeg` | `/Users/gung/Documents/Codex/2026-08-26/users-gung-documents-swift-ada-penyu/work/audit/final/detail-comparison.png` |
| Export modal | `/Users/gung/Downloads/3 (individual list)-2.png` | `/Users/gung/Documents/Codex/2026-08-26/users-gung-documents-swift-ada-penyu/work/audit/final/export-implementation.jpeg` | `/Users/gung/Documents/Codex/2026-08-26/users-gung-documents-swift-ada-penyu/work/audit/final/export-comparison.png` |

## Full-surface comparison

- Shell geometry matches the reference: 253 px sidebar, 52 px topbar, 22 px list leading inset, 32 px trailing inset, and custom traffic-light placement in the sidebar.
- Sampled surface colors match the source tokens: sidebar RGB 239/240/241 and content canvas RGB 245/245/247.
- Individuals filter rows, table top edge, column rhythm, 40 px header, 51 px rows, 11 px radius, search field, and export control align with the source composition.
- Map preserves the 973/287 content-to-filter split at 1512 px, natural-width wrapping chips, white filter rail, compact results, and clickable result cards.
- Detail summary is 125 px high; the content columns use the source 545 px / 15 px gap / flexible remainder proportions. Measurement/location panels are 329 px and the sighting panel is 330 px.
- Export modal is 414 × 493 px with the source section order, two-column fields, pill controls, and bottom-right actions.

## Focused comparison and interaction checks

- Window chrome: native duplicate traffic lights are hidden; custom controls remain accessible and functional.
- Navigation: Dashboard → Individuals → Map → Turtle detail was exercised through accessibility-backed Computer Use.
- Filters: species, period, and condition controls expose correct selectable states; map condition chips remain on one row at the reference width.
- Table: all real records remain reachable; narrow windows fall back to horizontal table scrolling rather than wrapping IDs.
- Export: modal open, cancel, scope, range, fields, format, and export actions are accessible; at least one export field is always selected.
- Detail actions: favorite toggles persisted immediately, and the download action opened an export scoped to the selected turtle (`Filtered from 1 catalogued individuals`).
- Build verification: `xcodebuild ... build` passed.
- Test verification: `xcodebuild ... test` passed (2 tests, exit 0).

## Iteration history

1. Baseline audit found duplicated native/custom window chrome, mismatched gray tokens, duplicate in-page collection titles, narrow intrinsic table layout, oversized system export sheet, equal detail columns, and grid-based map chips.
2. Pass one introduced reference tokens, custom full-size window chrome, exact sidebar/topbar geometry, source collection hierarchy, custom export overlay, map flow layout, and detail proportions.
3. Pass two fixed responsive table width, condition alignment, compact map chip padding/backgrounds, and full-height detail-card backgrounds.
4. Final pass captured all four working states, normalized source and implementation viewports, and reviewed each combined comparison input.

## Accepted content differences

- The reference list repeats four placeholder records; the implementation intentionally shows eight distinct backend/demo records so the demo remains credible and usable.
- Map tiles, labels, and camera region are live MapKit output and therefore cannot be pixel-identical to the static reference map image; the surrounding geometry, filters, pins, and result composition match.
- Functional panel labels and real measurement values replace blank placeholder content from the design reference without changing its layout.

No P1 or P2 visual issues remain in the required fidelity surfaces.
