# Responsive Layout Notes

## Previous Crop Cause

The original shell forced a `minWidth` of `1080` on `ContentView`, while several children also declared fixed widths: a `252` point sidebar, fixed top-bar search width, fixed table columns, and a dashboard card with a minimum width. The vertical `ScrollView` content did not have a full-width frame, so SwiftUI measured the content at its intrinsic width. When the actual window was narrower, the content extended beyond the window instead of adapting.

## Current Strategy

- `ContentView` uses flexible max-width and max-height frames.
- `AdaLayout` centralizes the default window size, minimum window size, sidebar width, table minimum width, and page padding.
- The app entry point supplies the window default/minimum size instead of forcing a large page frame.
- Dashboard summary cards use `ViewThatFits`: horizontal layout first, vertical stack fallback second.
- The chart card header uses the same pattern so controls can wrap into a clean second row.
- The collection table scrolls horizontally when its readable columns cannot fit, preventing silent clipping.
- Search and filters retain one-line labels and use horizontal scrolling where necessary.

## Verification Targets

Test the app at these states:

1. Default desktop window: dashboard cards are balanced side-by-side.
2. Narrow window near the minimum size: dashboard cards stack and table columns remain reachable by horizontal scrolling.
3. Wide window: chart and cards expand without introducing a second unexpected horizontal scroll.
4. Individuals page: heart is to the left of both thumbnails and does not trigger row navigation.
5. Sidebar: the same app icon appears beside both Sea Turtle Group labels.
