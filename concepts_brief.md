# Compare face-scale patches in Not Sure

**Author** adjiemuliadi

**Date** 2026-11-24

## Overview

Let a reviewer select the same patch of neighboring face scales in a sighting and candidate photo, then compare the photographed shapes side by side.

## Analysis

Seven Goldfish reviewers examined the concept. Enlarging each whole patch proportionally preserves scale shape and spacing within it. A pin-based warp can change the shape under review. Detected outlines are closed polygons, so glare or partial visibility can make an outline misleading. The close-ups show the original photo pixels and let the reviewer hide the outlines.

## Goals and alternatives

The first version uses two reviewer-selected patches and temporary selections. Automatic selection could save a drag when detection is clear, while merged or missed scales could select a different neighborhood. Explicit links between individual scales add work. Whole-patch comparison meets the stated need.

## Decisions and follow-up

Require photos from the same head side and keep the Needs photo verdict available. Reuse cached local contours and retain the sighting patch when switching candidates. Defer automatic selection, individual links, angle correction, and restoring the exact patches after reopening.
