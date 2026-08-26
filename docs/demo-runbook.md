# Demo runbook

## Fast path (offline-safe)

1. Build and run `Ada_Penyu_Desktop.xcodeproj` with the `Ada_Penyu_Desktop` scheme.
2. Leave the top-bar mode menu on **Demo mode**.
3. Walk through Dashboard → Map → select a result → **Open turtle detail** → back to Individuals.
4. On Individuals, search `Turtle #004`, toggle the heart, open Favorites, then use Export.

Demo mode is deterministic and does not need Postgres, the API, or ML model weights.

## Live API path

Run these commands in the backend worktree:

```bash
POSTGRES_PORT=55432 docker-compose -p ada-penyu-demo up -d postgres
DATABASE_URL=postgresql+psycopg://postgres:postgres@localhost:55432/turtle_identification_api uv run alembic upgrade head
DATABASE_URL=postgresql+psycopg://postgres:postgres@localhost:55432/turtle_identification_api uv run python scripts/seed_desktop_demo.py
DATABASE_URL=postgresql+psycopg://postgres:postgres@localhost:55432/turtle_identification_api ML_MODELS_ENABLED=false uv run uvicorn app.main:app --host 127.0.0.1 --port 8010
```

Verify `curl http://127.0.0.1:8010/health` before switching the app to **Live API**. The desktop client uses the seeded records (`Turtle #001` … `Turtle #008`). If the API stops responding, the app falls back to Demo mode and labels the state in the top bar.

## Presentation checklist

- Use a 1280×800 or larger window so the sidebar and map filter panel remain visible.
- Keep the first screen on Dashboard; it communicates scope fastest.
- Use the explicit result-card action on Map to demonstrate the map → detail handoff.
- Mention the Demo/Live menu if connectivity is part of the demo; do not wait on model loading because `ML_MODELS_ENABLED=false` is intentional for this flow.
