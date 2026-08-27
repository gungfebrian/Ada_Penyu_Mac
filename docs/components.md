# Component Guide

## Reusable Components

### `FavoriteButton`

Use for any row or card that toggles a turtle favorite.

```swift
FavoriteButton(isFavorite: favoriteIDs.contains(turtle.id)) {
    onToggleFavorite(turtle)
}
```

The component owns the icon state, color, circular hit area, animation, help text, and accessibility label. The parent owns persistence and business logic.

### `TurtleAppIconMark`

Use when the interface needs the exact current macOS app icon. It reads the dedicated `TurtleAppIcon` image asset and applies the small continuous corner radius required by the sidebar.

### `TurtleBrandMark`

Use for the compact navy turtle template mark when the app icon is not appropriate, such as a neutral brand illustration or a future empty state.

### `TurtleMapPin`

Use only for map annotations. It combines the turtle pin artwork, selected outline, pointer triangle, and shadow so map callouts remain consistent.

### `FilterChip`, `ConditionPill`, and `SectionTitle`

These components standardize filter interaction, condition semantics, and small section hierarchy. They should be preferred over one-off pills or text styling in new views.

## Layout Components

`SidebarView` and `TopBar` live in `Components/AppShellComponents.swift` because they are shell-level components used independently from page content. Dashboard-specific cards live in `Views/DashboardView.swift` rather than the shell.

## Adding a Component

1. Give it one visual responsibility.
2. Pass state and actions in from the parent; do not reach into `DemoFixtures` unless the component is explicitly data-display-only.
3. Keep colors, spacing, and window dimensions in `DesignSystem.swift`.
4. Add an accessibility label when the component's visual meaning is not represented by visible text.
5. Add or update a SwiftUI preview when the component has a distinct visual state.
