# Turtle illustration sync

Approved in chat on 2026-11-26 after seven Goldfish reviews.

Match the colored iOS TurtleBodyDiagram at commit f54176fd37ad94cbc1280e3e691b12fc9792192e: square 200 × 200 canvas, exact seven-part frames, appendages before shell, and white outlines at opacity 0.72 with width max(0.7, scale * 1.1). Keep the Mac 230-point maximum width, namespaced assets, condition/neutral tints, accessibility, filters, aggregation, history, and legend.

## Approaches

Adapt the existing iOS metadata and bounded shape renderer locally. Retuning Mac positions or scaling image halos would approximate the reference. A shared package or general SVG renderer adds unnecessary dependencies. Existing SVGs are byte-identical, so asset replacement is unnecessary.

No spot editing, side selection, API changes, stored-data changes, or global palette changes. Validate rendered geometry and existing record regressions rather than adding tests that repeat layout constants.
