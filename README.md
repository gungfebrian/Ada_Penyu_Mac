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
    ├── AppModel.swift          # Domain models and display formatting
    ├── DataLayer.swift         # API contract, client, adapters, and demo repository
    ├── AppStore.swift          # Screen state, loading, fallback, and commands
    ├── ContentView.swift       # App shell and route composition
    ├── CollectionViews.swift   # Individuals and Favorites screens
    ├── MapCanvasView.swift     # MapKit canvas and map controls
    ├── TurtleDetailView.swift  # Individual turtle detail screen
    ├── DesignSystem.swift      # Colors, layout tokens, pills, and shared styling
    ├── PreviewGallery.swift    # SwiftUI preview gallery
    ├── Ada_Penyu_DesktopApp.swift # macOS app entry point
    ├── Components/             # Reusable shell, favorite, and branding components
    ├── Views/                  # Page-level compositions such as DashboardView
    └── Assets.xcassets         # App icons and turtle artwork
```

Additional product and engineering documentation lives in [`design.md`](design.md) and [`docs/`](docs/).

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

## Data modes

The app opens in **Demo mode** so a presentation is deterministic and does not depend on a network connection. Use the mode menu in the top bar to switch to **Live API**. If the API is unavailable, the store automatically returns to demo data and shows a visible fallback notice instead of leaving a blank screen.

The live adapter expects the backend at `http://127.0.0.1:8010` and sends a stable `X-User-Id` header for favorites. Change the base URL in UserDefaults with the key `ada.apiBaseURL` when the backend is hosted elsewhere.

Favorites, search, filters, map period, detail navigation, and export are all wired through `AppStore`; replacing the repository does not require changing the views.

## Demo runbook

The backend worktree contains an idempotent seed script and a tested local stack. From the backend repository:

```bash
POSTGRES_PORT=55432 docker-compose -p ada-penyu-demo up -d postgres
DATABASE_URL=postgresql+psycopg://postgres:postgres@localhost:55432/turtle_identification_api \
  uv run alembic upgrade head
DATABASE_URL=postgresql+psycopg://postgres:postgres@localhost:55432/turtle_identification_api \
  uv run python scripts/seed_desktop_demo.py
DATABASE_URL=postgresql+psycopg://postgres:postgres@localhost:55432/turtle_identification_api \
  ML_MODELS_ENABLED=false uv run uvicorn app.main:app --host 127.0.0.1 --port 8010
```

Then build and open the desktop app in Xcode. Start in Demo mode for the safest walkthrough; switch to Live API only after `curl http://127.0.0.1:8010/health` returns `{"status":"ok"}`.

## Preview Screens

The preview gallery includes:

- Sea Turtle Group Dashboard
- Map overview
- Individuals collection
- Favorites collection
- Turtle detail
