# Contour comparison and beta readiness

Base: `origin/main` at `3aa7133` (PR #7). Earlier local work is preserved in stash `ef6e2c218736f2ca49d3af6d81391c98e8828538`; do not apply it wholesale over the new authentication/v2 architecture.

## User outcome

A ranger or scientist can find contour comparison immediately in I3S, compare the actual same-side photographs, turn edges on/off, change each photograph's contour color, adjust threshold/opacity/line weight, and inspect originals without landmarks or a backend dependency. Use the existing AdaColors, cards, spacing, typography and native macOS controls.

## Design and research decision

Keep Photo comparison as the main comparison mode, with an always-visible Contours checkbox. Put the older landmark/XFeat loupe view under a clearly named Features mode. Use a compact layout menu rather than adding segments to an already crowded header. Share the photo/contour component with Scientist Review, which must remain prominently labeled as a scenario demo until encounter-backed review exists.

Use a local Swift Canny-style pipeline: luminance, optional Gaussian noise reduction, Sobel gradient, non-maximum suppression, connected weak-edge hysteresis, and optional line dilation. One absolute cutoff is shared by both photographs. Cache the field by photograph and smoothing; color, visibility and opacity must not trigger detection. Keep raw photograph pixels unchanged. Limit processing resolution to 1280 pixels on the longest side and cancel obsolete work.

OpenCV documents why smoothing, thinning and hysteresis improve edge continuity over thresholded Sobel alone: https://docs.opencv.org/4.x/da/d22/tutorial_py_canny.html . Apple's native contour request is an alternative with contrast/polarity controls, but its default 512-pixel processing size can hide small details; see https://developer.apple.com/documentation/vision/vndetectcontoursrequest/maximumimagedimension . These sources justify the method, not field accuracy or an optimal turtle-specific threshold.

Archify was researched at https://github.com/tt-a1i/archify . It is not installed here. The authorized Notion/Mermaid alternative will provide source-backed architecture and workflow diagrams without installing or executing downloaded renderer code.

## Evidence integrity fixes

- Missing candidate photographs remain missing, without arbitrary bundled substitutions.
- Missing backend correspondences remain unavailable; never generate demo correspondences for live photographs.
- Demo and bundled gallery evidence are labeled. Bundled fingerprints can supply real I3S distances, but no invented AI confidence or XFeat counts.
- Decode current legacy v1 match responses and support duplicate identities across paired sides. This compatibility repair does not perform the deferred v2 sighting/attempt migration.
- Pixel, side, source and session changes invalidate stale matching state. Keep companion fingerprints attached to their own photographs.
- Gallery replacement is a separate named action, with explicit confirmation of an immutable photograph/identity/side snapshot. It must not be described as encounter confirmation.
- Same-session filter requests must not publish old results under newer controls.

## Verification and release boundary

Test constant/low-contrast/asymmetric images, thin-edge and connectivity behavior, shared cutoff subsets, line dilation, malformed rasters, actual bundled photographs, stale render cancellation, match JSON, paired duplicate IDs and delayed query results. Inspect on/off, colors, threshold, originals and missing-photo behavior in the actual app at standard and minimum window sizes.

No backend or iOS code changes. Backend v2 deployment/migrations, signed Keychain behavior, complete encounter-backed scientist review, calibrated open-set thresholds and field evaluation remain explicit release gates. Do not describe this change as complete production certification.
