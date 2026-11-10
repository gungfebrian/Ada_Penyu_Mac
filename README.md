<div align="center">

<img src="Ada_Penyu_Desktop/Assets.xcassets/AppIcon.appiconset/icon-128@2x.png" alt="Ada Penyu Mac Logo" width="108" height="108" />

# Ada Penyu Mac

**Native macOS Conservation & Photo-Identification Workspace for Sea Turtle Monitoring**

[![Platform](https://img.shields.io/badge/Platform-macOS_26.5+-0C2A3E?style=for-the-badge&logo=apple&logoColor=white)](#technology-stack)
[![Swift](https://img.shields.io/badge/Swift-5.0-F05138?style=for-the-badge&logo=swift&logoColor=white)](#technology-stack)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI_%26_MapKit-4A90CD?style=for-the-badge&logo=swift&logoColor=white)](#architecture)
[![I3S Pattern](https://img.shields.io/badge/I3S_Pattern-v4.02_Oracle_Verified-177A4F?style=for-the-badge)](docs/i3s-reference.md)
[![AI Retrieval](https://img.shields.io/badge/Backend_AI-MiewID_%2B_XFeat-183A52?style=for-the-badge)](#photo-identification--i3s-workspace)
[![Tests](https://img.shields.io/badge/Tests-10_Passed_(97_Pairs)-2EA043?style=for-the-badge)](#validation--testing)
[![License](https://img.shields.io/badge/I3S_Matcher-GPL--2.0--or--later-blue?style=for-the-badge)](docs/licenses/I3S-GPL-2.0.txt)

[Features](#key-features) • [Architecture](#architecture) • [Photo Identification](#photo-identification--i3s-workspace) • [Getting Started](#getting-started) • [Data Modes](#data-modes--api-integration) • [Validation](#validation--testing) • [Documentation](#documentation)

</div>

---

## Overview

**Ada Penyu Mac** is a native macOS desktop application designed for sea turtle conservation teams and researchers to monitor individual sea turtles, track spatial-temporal sightings, evaluate body conditions, and perform facial-scale photo identification. Built as the desktop companion to the **Ada Penyu** mobile field application, it pairs a calm, field-ready SwiftUI interface with both backend AI retrieval (**MiewID + XFeat**) and a locally verified **I3S Pattern v4.02** fingerprint comparison workspace.

---

## Key Features

| Module | Capabilities |
| :--- | :--- |
| **Conservation Dashboard** | Sightings-over-time analytics, species breakdowns, body-condition distribution (`Healthy`, `Scarred`, `Injured`), and recent encounter summaries. |
| **Interactive MapKit Canvas** | Spatial visualization of turtle sightings with custom branded pins, time-window filtering (`7 days`, `30 days`, `90 days`, `1 year`), species/condition scoping, and direct detail handoff. |
| **Individuals & Favorites** | Searchable, sortable individual catalog with unified species/condition sidebar filtering, optimistic favorite toggling, live sidebar counters, and CSV/JSON data export. |
| **Turtle Detail Dossier** | Comprehensive per-individual profile featuring carapace measurements, historical sighting logs, anatomical markers, and location history. |
| **I3S & AI Identification** | Single-side and dual-side (`Left` / `Right`) database search via backend **MiewID/XFeat**, paired with interactive 3-point anatomical landmarking, polygonal ROI annotation, `.fgp` binary fingerprint import/export, and visual keypoint correspondence inspection. |
| **Resilient Data Layer** | Seamless switching between authenticated **Live API** mode and deterministic **Demo mode**, with automatic non-blocking fallback if the backend becomes unreachable. |

---

## Architecture

The application follows a unidirectional state architecture with a strict protocol boundary (`TurtleRepository`) decoupling SwiftUI views from networking and persistence details.

```mermaid
flowchart LR
    UI["SwiftUI Views\nDashboard · Map · Individuals · Favorites · Detail · I3S"]
    STORE["AppStore (@MainActor)\nRoute · Filters · Auth · Fallback · Commands"]
    REPO["TurtleRepository\nAsync Feature Contract"]
    DEMO["DemoTurtleRepository\nDeterministic Offline Dataset"]
    API["RemoteTurtleRepository\nDTO Mapping + APIClient"]
    I3S["I3SEngine\n.fgp Parser · Reference Matcher · Blob Extractor"]
    BE["FastAPI Backend\n/api/v1 (MiewID / XFeat)"]
    DB[("PostgreSQL\nProfiles · Sightings · Favorites")]

    UI <--> STORE
    UI <--> I3S
    STORE --> REPO
    REPO --> DEMO
    REPO --> API
    API --> BE --> DB
    API -. "Network / HTTP Error" .-> STORE
    STORE -. "Automatic Demo Fallback" .-> DEMO
```

### Project Structure

```text
Ada_Penyu_Desktop/
├── Ada_Penyu_Desktop.xcodeproj          # Xcode project configuration
├── Ada_Penyu_DesktopTests/              # Unit, app-flow, and C++ oracle parity tests
│   ├── AppFlowTests.swift               # Store, binary .fgp, and 97-pair I3S regression suite
│   └── Fixtures/                        # Official I3S v4.02 oracle fixtures & provenance hashes
├── scripts/
│   └── i3s_reference_oracle.py          # Offline C++ reference fixture generator
├── docs/                                # Architecture, I3S verification, runbooks, and licenses
└── Ada_Penyu_Desktop/
    ├── Ada_Penyu_DesktopApp.swift       # macOS app entry point and window sizing
    ├── AppModel.swift                   # Domain models, species/condition semantics, formatters
    ├── AppStore.swift                   # Centralized @MainActor state and command coordinator
    ├── DataLayer.swift                  # TurtleRepository contract, APIClient, DTOs, Demo repo
    ├── I3SEngine.swift                  # I3S Pattern v4.02 .fgp codec, blob detector, and matcher
    ├── ContentView.swift                # Root navigation shell and top bar
    ├── CollectionViews.swift            # Individuals and Favorites table views
    ├── MapCanvasView.swift              # MapKit canvas, callouts, and scoped filter panel
    ├── TurtleDetailView.swift           # Individual profile, biometric stats, and sighting logs
    ├── DesignSystem.swift               # Color tokens (AdaColors), layout metrics, and pills
    ├── PreviewGallery.swift             # SwiftUI preview gallery for rapid UI verification
    ├── Components/                      # Reusable shell, favorite button, and branding marks
    ├── Views/
    │   ├── DashboardView.swift          # Sightings analytics and summary cards
    │   └── I3SWorkspaceView.swift       # Interactive photo-identification & I3S annotation studio
    ├── SampleTurtles/                   # Bundled reference photos (.jpg) and fingerprints (.fgp)
    └── Assets.xcassets/                 # App icons, anatomical SVGs, and map pin artwork
```

---

## Photo Identification & I3S Workspace

The **Identification** workspace supports two complementary mechanisms:

1. **Backend AI Retrieval (`Search in Database`)**
   - Supports **Single Photo** (`Left` or `Right` head profile) and **Dual Photo** (`Left + Right` pair) queries.
   - Calls the FastAPI matching endpoints powered by **MiewID** global retrieval and **XFeat / LighterGlue** local feature matching.
   - Backend candidates retain their server-computed similarity ranking; local I3S distances do not reorder backend search results.

2. **Local I3S Pattern v4.02 Fingerprint Comparison**
   - Guides the user through placing the 3 canonical anatomical reference landmarks (**Beak edge**, **Inner edge of eye area**, **Edge of outer scale**) and closing a non-self-intersecting polygonal **Region of Interest (ROI)**.
   - Supports importing and exporting native binary `.fgp` (`I3S40`) files.
   - To inspect a side-by-side I3S comparison against a candidate, open the candidate's visual comparison panel and choose **Load Gallery .fgp…** for that gallery photo. Both fingerprints must share the same anatomical side and contain valid landmarks, a closed ROI, and keypoints.

> [!IMPORTANT]
> **Verification & Scope Boundaries**
> - **Matcher Parity:** The Swift I3S comparison algorithm (`I3SEngine.swift`) is verified against the original C++ sources (`compare.cpp`, `fingerprint.cpp`, `element.cpp`, `affine.cpp`) from the official `I3SPv4.02` distribution across all **97 same-side fingerprint combinations** (scores match within `1e-6`; matched pair counts match `100%`).
> - **Feature Extraction:** **Use Head Template** places fixed proportional coordinates that require manual adjustment to match the photo's anatomy. Newly extracted local blob features are labeled as an approximation and do not replicate OpenCV 2.4.2 upright SURF pyramid/warping behavior. Load saved `.fgp` files when checking strict compatibility with desktop I3S.
> - Detailed evidence, SHA-256 provenance, and reproduction steps are documented in [`docs/i3s-reference.md`](docs/i3s-reference.md).

---

## Getting Started

### Prerequisites

- **macOS:** 26.5+ deployment target
- **Xcode:** Xcode 17+ with macOS SDK
- **Swift:** 5.0+

### Open in Xcode

```bash
open Ada_Penyu_Desktop.xcodeproj
```

### Build from Terminal

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

---

## Data Modes & API Integration

The application starts in **Live API** mode and can be switched to **Demo mode** at any time from the top-bar account menu.

| Mode | Behavior |
| :--- | :--- |
| **Live API** | Connects to `http://127.0.0.1:8010` by default (configurable via the account sheet or `ada.apiBaseURL` in `UserDefaults`). Authenticates with Bearer tokens and sends a stable `X-User-Id` header for user-scoped favorites. Automatically falls back to Demo mode with a visible banner if the server is unreachable. |
| **Demo Mode** | Uses `DemoTurtleRepository` with 8 deterministic sea turtle profiles, sighting histories, and bundled sample assets. Ideal for offline walkthroughs and UI evaluations without requiring PostgreSQL or ML weights. |

### Running the Local Backend Stack

From the companion backend repository (`turtle-identification-be`):

```bash
# 1. Start PostgreSQL container
POSTGRES_PORT=55432 docker-compose -p ada-penyu-demo up -d postgres

# 2. Run database migrations
DATABASE_URL=postgresql+psycopg://postgres:postgres@localhost:55432/turtle_identification_api \
  uv run alembic upgrade head

# 3. Seed deterministic desktop demo records
DATABASE_URL=postgresql+psycopg://postgres:postgres@localhost:55432/turtle_identification_api \
  uv run python scripts/seed_desktop_demo.py

# 4. Launch FastAPI server on port 8010
DATABASE_URL=postgresql+psycopg://postgres:postgres@localhost:55432/turtle_identification_api \
  ML_MODELS_ENABLED=false uv run uvicorn app.main:app --host 127.0.0.1 --port 8010
```

Verify service availability with `curl http://127.0.0.1:8010/health` (`{"status":"ok"}`) before switching the desktop client to **Live API**.

---

## Validation & Testing

Run the full automated unit and regression test suite via `xcodebuild`:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
  -project Ada_Penyu_Desktop.xcodeproj \
  -scheme Ada_Penyu_Desktop \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

### What the Test Suite Covers

- **Original C++ Oracle Parity (`97/97` pairs):** Compares Swift I3S distance scores and matched feature-pair counts against the official C++ implementation across all 97 same-side combinations (including self-comparisons) from the 13 bundled sample fingerprints.
- **Encounter Ranking Regression (`13/13` queries):** Leave-one-encounter-out ranking verification across the bundled individuals.
- **Binary `.fgp` Codec & App Store Flows:** Verifies lossless `I3S40` binary read/write round-tripping, point-in-polygon geometry, sidebar filtering exclusivity, optimistic favorite updates, and automatic offline fallback.

*(Note: Passing local regression tests establish compatibility on saved sample fixtures; they do not claim field-level open-set accuracy, new-photo SURF extraction parity, or backend load/stress capacity.)*

---

## Technology Stack

- **UI Framework:** SwiftUI (macOS native shell, responsive `ViewThatFits` layouts, custom canvas overlays)
- **Mapping:** Apple MapKit (`MapCanvasView` with custom `TurtleMapPin` annotations)
- **Concurrency:** Swift Structured Concurrency (`async`/`await`, `@MainActor` state isolation)
- **Pattern Matching:** Native Swift port of I3S Pattern v4.02 affine alignment & metric scoring (`I3SEngine`)
- **Backend Integration:** RESTful `URLSession` client with Bearer authentication, multipart photo upload, and ISO-8601 decoding

---

## Documentation

| Document | Description |
| :--- | :--- |
| [`design.md`](design.md) | Product intent, color palette tokens (`AdaColors`), typography, and shell anatomy. |
| [`docs/architecture.md`](docs/architecture.md) | Runtime data flow, layer responsibilities, and REST API endpoint contract. |
| [`docs/i3s-reference.md`](docs/i3s-reference.md) | I3S Pattern v4.02 C++ oracle verification, SHA-256 fixture provenance, and extraction boundaries. |
| [`docs/components.md`](docs/components.md) | Usage guide for `FavoriteButton`, `TurtleAppIconMark`, `TurtleMapPin`, and filter pills. |
| [`docs/responsive-layout.md`](docs/responsive-layout.md) | Window resizing strategy, horizontal scroll rules, and layout verification targets. |
| [`docs/demo-runbook.md`](docs/demo-runbook.md) | Step-by-step offline and live-API presentation checklist. |

---

## License & Attribution

- The adapted I3S Pattern v4.02 matching logic in [`Ada_Penyu_Desktop/I3SEngine.swift`](Ada_Penyu_Desktop/I3SEngine.swift) carries the original authors' **GPL-2.0-or-later** notice (Jurgen den Hartog & Renate Reijns). See [`docs/licenses/I3S-GPL-2.0.txt`](docs/licenses/I3S-GPL-2.0.txt) for the full license text.
