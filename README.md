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
- Guided facial-scale annotation, `.fgp` import/export, and visual candidate inspection in the I3S workspace.
- Local I3S fingerprint comparison checked against the original C++ implementation, alongside backend MiewID/XFeat search.

## Technology

- SwiftUI
- MapKit
- Xcode with a macOS 26.5-compatible SDK
- Swift 5
- macOS 26.5 deployment target

## Project Structure

```text
Ada_Penyu_Desktop/
├── Ada_Penyu_Desktop.xcodeproj
├── Ada_Penyu_DesktopTests/      # App-flow and original-C++ matcher regression tests
├── scripts/                    # Offline reference-fixture generation
└── Ada_Penyu_Desktop/
    ├── AppModel.swift          # Domain models and display formatting
    ├── DataLayer.swift         # API contract, client, adapters, and demo repository
    ├── AppStore.swift          # Screen state, loading, fallback, and commands
    ├── I3SEngine.swift         # Fingerprint format, approximate blob extraction, and reference matcher
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

The app starts in **Live API** mode. Use the account menu to select **Demo mode** for a deterministic offline walkthrough. If live data loading fails, the store automatically switches to demo data and shows a visible fallback notice.

The live adapter defaults to `http://127.0.0.1:8010`, authenticates requests with bearer tokens, and sends a stable `X-User-Id` header for favorites. Configure the server and account through the account menu when using another backend.

Favorites, search, filters, map period, detail navigation, and export are all wired through `AppStore`; replacing the repository does not require changing the views.

## Photo identification

`Search in Database` calls the backend's single-photo or left/right-pair matching endpoint. Backend results use MiewID/XFeat; local I3S distances do not reorder those results.

To compare saved I3S fingerprints, load or annotate the query photo, open a candidate's visual comparison, and choose **Load Gallery .fgp…** for that gallery photo. The workspace does not substitute sample photos or annotations when a candidate is unavailable. The head template places fixed coordinates that need manual adjustment, and the local blob extractor remains an approximation of OpenCV SURF.

See [I3S reference verification](docs/i3s-reference.md) for the original-source oracle, fixture generation, retained evidence, and licensing.

## Validation

Run the complete test suite:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
  -project Ada_Penyu_Desktop.xcodeproj \
  -scheme Ada_Penyu_Desktop \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

The suite checks all 97 same-side fingerprint combinations against the original C++ scores and pair counts, plus a separate encounter-ranking regression using the 13 bundled photos. These checks establish compatibility on saved examples. They do not establish production accuracy, new-photo extraction parity, end-to-end backend matching, or load/stress-test capacity. A successful `/health` response establishes service availability only.

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
