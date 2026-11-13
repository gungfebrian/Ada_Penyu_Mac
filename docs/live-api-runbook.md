# Authenticated API walkthrough

1. Build and launch the desktop app; sign in with a backend account, or restore a remembered session.
2. In Debug, Developer API Settings can select a local backend. Changing it signs out and clears private state.
3. Browse Dashboard, Map, Individuals, Favorites, and an individual detail. Empty accounts show empty states.
4. Search, filter, toggle a favorite, and export authorized records.
5. Stop the API or return an error: verify the visible error and Retry action. No bundled records, photos, or overlays replace failed responses.
6. Sign out and verify private records and photos disappear.

Explicit I3S sample tools remain available for reference comparisons. They use bundled photos/fingerprints only when selected explicitly; sample candidate IDs cannot be included in the backend database. Scientist Review remains a separate prototype with fabricated scenarios, deferred for later replacement.

Backend database cleanup is outside this desktop change. Local servers must expose the documented v2 records and v1 support routes; see [API setup](api-v2.md).
