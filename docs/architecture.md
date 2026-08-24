# Architecture

## Overview

Ada Penyu Mac is a small SwiftUI application organized around a single app shell and focused feature views. The shell owns navigation and shared UI state; feature views render pages and communicate through closures and bindings.

## Responsibilities

| Area | Responsibility |
| --- | --- |
| `ContentView` | Owns active section, selected turtle, search text, chart mode, export alert, and temporary favorite IDs. |
| `Components/AppShellComponents.swift` | Sidebar navigation and top bar. |
| `Components/FavoriteButton.swift` | Reusable favorite interaction and accessibility labels. |
| `Components/TurtleBranding.swift` | App icon mark, template brand mark, map pin, and map pin pointer. |
| `Views/DashboardView.swift` | Dashboard chart and summary cards. |
| `CollectionViews.swift` | Individuals and Favorites collection flows. |
| `MapCanvasView.swift` | MapKit canvas, map annotations, filters, and results. |
| `TurtleDetailView.swift` | Detail summary and detail panels. |
| `AppModel.swift` | Domain models and demo data. |
| `DesignSystem.swift` | Colors, layout constants, cards, condition pills, filters, and placeholders. |

## Data Flow

```text
DemoData
   │
   ├── ContentView initializes favoriteIDs
   │       │
   │       ├── SidebarView(favoriteCount:)
   │       ├── IndividualsView(favoriteIDs:, onToggleFavorite:)
   │       └── FavoritesView(favoriteIDs:, onToggleFavorite:)
   │
   ├── MapPageView filters DemoData.sightings
   └── DashboardView reads summary collections
```

The favorite set is keyed by `Turtle.id`, so row state does not depend on the immutable demo model. This is the intended seam for a future persistence or mobile/API adapter.

## Folder Convention

- `Components/` contains reusable UI pieces that can be used by multiple pages.
- `Views/` contains page-level compositions and feature-specific child views.
- Root Swift files contain models, page flows that have not yet grown beyond one focused responsibility, or app entry points.
- `Assets.xcassets/` contains all runtime images and app branding assets.
- `docs/` contains implementation-facing documentation; `design.md` is the product-facing visual contract.

## Navigation

`AppSection` is the navigation enum. The sidebar changes `activeSection`; selecting a turtle stores `selectedTurtle` and moves to `.detail`. Returning from detail clears the selection and routes back to Individuals.

## Future Integration Boundary

Keep view APIs stable while replacing `DemoData`:

```swift
IndividualsView(
    searchText: $searchText,
    favoriteIDs: $favoriteIDs,
    onToggleFavorite: toggleFavorite,
    onSelect: showDetail
)
```

An API-backed repository can feed the same view models, while a persistence layer can replace the in-memory `favoriteIDs` set without changing the favorite button or table row.
