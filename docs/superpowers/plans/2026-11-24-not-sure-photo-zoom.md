# Not Sure photo zoom implementation plan

**Goal** Add trackpad pinch zoom and independent photo zoom in the Not Sure workspace.

**Spec** [Not Sure photo zoom](../specs/2026-11-24-not-sure-photo-zoom-design.md)

- [x] Add viewport regression tests for independent zoom and pan, gesture scaling relative to the start of the pinch, scale limits, and resetting the viewport at 100%.
- [x] Give the workspace separate sighting, candidate, and overlay viewports. Wire pinch gestures, toolbar buttons, and pan to those viewports. Use the matching viewport for AI correspondence endpoints.
- [x] Run the macOS test suite and check the diff. Verify the photo pane routing and shared Curtain and Blend transforms.
