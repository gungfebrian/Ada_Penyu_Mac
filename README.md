# Ada Penyu Mac

Ada Penyu Mac is a native macOS dashboard for monitoring sea turtle individuals, sightings, locations, and conservation conditions. It is designed as the desktop companion to the Ada Penyu mobile app.

## Features

- Dashboard with sightings-over-time and recent-sighting summaries.
- Native MapKit map with turtle locations, condition filters, and custom turtle pins.
- Individuals table with search, species filters, condition filters, and detail navigation.
- Interactive favorite buttons beside each turtle thumbnail.
- Favorites page and sidebar counters that update immediately when a favorite changes.
- Shared turtle branding from the mobile app, including the app icon, brand mark, and map pin artwork.
- SwiftUI previews for dashboard, map, individuals, favorites, and turtle detail screens.
- Responsive desktop layout with horizontal filter scrolling to prevent clipped labels.

## Technology

- SwiftUI
- MapKit
- Xcode 17+
- Swift 5
- macOS 26.5 deployment target

## Project Structure

```text
Ada_Penyu_Desktop/
├── Ada_Penyu_Desktop.xcodeproj
└── Ada_Penyu_Desktop/
    ├── AppModel.swift          # Demo models and sample turtle data
    ├── ContentView.swift       # App shell, dashboard, sidebar, navigation, and shared favorite state
    ├── CollectionViews.swift   # Individuals and Favorites screens
    ├── MapCanvasView.swift     # MapKit canvas and map controls
    ├── TurtleDetailView.swift  # Individual turtle detail screen
    ├── DesignSystem.swift      # Colors, pills, buttons, and turtle brand components
    ├── PreviewGallery.swift    # SwiftUI preview gallery
    ├── Ada_Penyu_DesktopApp.swift # macOS app entry point
    └── Assets.xcassets         # App icons and turtle artwork
```

## Run Locally

Open the project in Xcode:

```bash
open Ada_Penyu_Desktop.xcodeproj
```

Or build from Terminal:

```bash
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" \
xcodebuild \
  -project Ada_Penyu_Desktop.xcodeproj \
  -scheme Ada_Penyu_Desktop \
  -configuration Debug \
  -sdk macosx \
  build \
  CODE_SIGNING_ALLOWED=NO
```

## Current Data State

The desktop app currently uses local demo data from `AppModel.swift`. Favorite changes are stored in an in-memory `Set<String>` shared by the app shell, Individuals page, Favorites page, and sidebar. This keeps the UI fully interactive while the mobile/API data integration is being prepared.

Favorites will reset to the demo defaults when the app is relaunched. Persistent favorites and live turtle data can be connected in a later integration step.

## Preview Screens

The preview gallery includes:

- Sea Turtle Group Dashboard
- Map overview
- Individuals collection
- Favorites collection
- Turtle detail
