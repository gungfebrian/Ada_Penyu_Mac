# Ada Penyu Mac — Product Design

## Product Intent

Ada Penyu Mac is the desktop workspace for a sea turtle research group. The interface should make field data easy to scan, compare, and act on without losing the calm, conservation-focused character of the mobile app.

The desktop experience prioritizes:

1. Fast orientation through the Dashboard and Map.
2. Clear individual-level records and condition states.
3. A lightweight favorite workflow for turtles that need follow-up.
4. Visual continuity with the Ada Penyu mobile app.

## Visual Direction

- **Tone:** calm, focused, field-ready, and trustworthy.
- **Canvas:** soft neutral gray rather than pure white so cards remain distinct.
- **Surface:** white cards with continuous corners and restrained borders.
- **Primary ink:** deep navy for navigation, chart lines, map pins, and primary actions.
- **Accent:** ocean blue for selected favorites and interactive focus states.
- **Typography:** compact system typography with clear weight changes instead of excessive decoration.

## Design Tokens

| Token | Value | Usage |
| --- | --- | --- |
| Canvas | `#E8E8E8` | Page background |
| Sidebar | `#F2F2F2` | Navigation rail |
| Navy | `#0C2A3E` | Primary action, navigation, chart |
| Navy soft | `#183A52` | Secondary navy text |
| Accent blue | `#4A90CD` | Active favorite and selected map pin |
| Healthy | `#177A4F` | Healthy condition |
| Scarred | `#E6AC3E` | Scarred condition |
| Injured | `#D62828` | Injured condition |

The source of truth for these values is `AdaColors` and `AdaLayout` in `DesignSystem.swift`.

## Shell Anatomy

```text
Window
├── Sidebar
│   ├── App icon + Sea Turtle Group
│   ├── Dashboard
│   ├── Map
│   ├── App icon + Sea Turtle Group section label
│   ├── Individuals + count
│   └── Favorites + live count
└── Main content
    ├── Top bar: title, optional subtitle, search, export
    └── Page content
```

The app icon is reused as the group mark through `TurtleAppIconMark`. The template turtle artwork remains available for map-specific branding through `TurtleBrandMark` and `TurtleMapPin`.

## Favorite Interaction

The favorite control sits immediately to the left of the turtle thumbnails in the Individuals and Favorites tables.

- **Inactive:** outline heart, neutral gray, subtle circular background.
- **Active:** filled heart, accent blue, light blue circular background.
- **Interaction:** toggles in place without opening the turtle detail view.
- **Data flow:** `ContentView` owns the temporary `Set<String>` and passes the set plus a toggle action into collection views.

## Responsive Rules

- The root shell fills the available window instead of forcing a large intrinsic width.
- The window has a sensible default and minimum size, but its content remains flexible after resizing.
- Dashboard cards are side-by-side when they fit and stack vertically when they do not.
- The chart expands to the available content width.
- The collection table keeps readable column widths inside a horizontal scroll region instead of clipping columns.
- Filter chips scroll horizontally when their labels cannot fit on one line.
- Fixed values are centralized in `AdaLayout` rather than scattered across views.

## Current Product Boundary

The current design is backed by `DemoData`. Favorites are interactive but session-only. The next data integration should preserve the same view interfaces and replace the demo source with the mobile/API adapter.
