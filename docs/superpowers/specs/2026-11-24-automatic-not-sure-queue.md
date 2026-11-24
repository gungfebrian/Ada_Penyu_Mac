# Automatic Not Sure Review

Approved behavior: entering Not Sure Review automatically requests one page of 50 unidentified, submitted organization sightings. Queue loading fetches JSON only: no photos and no matching. Refresh and pagination remain explicit; there is no polling.

Opening a case fetches detail and uses its saved match result and immutable query evidence. Without a saved result, automatically rematch only that selected case using stored photo IDs. If source photo selection or side is ambiguous, ask for explicit input before matching. Fetch query images and the selected candidate image only when needed. A deliberate rematch creates a fresh attempt UUID; retries reuse its UUID and payload. Confirm with the attempt-based identification endpoint before recording a local verdict. Refresh conflicting server state. Preserve local cases, annotations, notes and demo behavior, and reject stale account/navigation responses.

Backend APIs already implement this contract; add queue regression tests, isolated load measurements and integration documentation. No new workflow status, migration or production deployment.
