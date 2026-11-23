# Not Sure scale patch comparison implementation plan

**Goal** Compare the photographed shape of two face-scale patches.

**Spec** [Compare face-scale patches in Not Sure](../specs/2026-11-24-not-sure-scale-patches-design.md)

- [x] Add tests for patch bounds, proportional preview geometry, session state, and same-side candidate photo fallback.
- [x] Add same-side patch picking and preview to Contours with shared photo geometry, an outline toggle, and independent viewports.
- [x] Run the macOS suite and check the diff. Rerun the Not Sure tests after the final UI changes.
- [ ] Verify trackpad input with physical hardware.
