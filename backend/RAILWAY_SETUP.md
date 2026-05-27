# Railway Setup (Always-On Backend)

This backend is ready to run on Railway without manual initialization on each deploy.

## 1) Service root

Create/select your Railway service and set the service root to:

`/backend`

This ensures Railway sees:

- `requirements.txt`
- `Procfile` / `railway.json`
- `main.py`

## 2) Environment variables

In Railway service variables, add:

- `GROQ_API_KEY` (required)
- `FIREBASE_PROJECT_ID=sol-mvp-4f7c1`
- `FIREBASE_SERVICE_ACCOUNT_PATH=/app/firebase-service-account.json` if you mount a service account file
- `PUBLIC_BASE_URL=https://your-service.up.railway.app`
- `CORS_ALLOWED_ORIGINS=https://your-frontend-domain.com`
- `ADMIN_DEBUG_TOKEN=<long-random-secret>` for admin/debug endpoints
- `SQLITE_DB_PATH=/data/db/companion.db`
- `CHROMA_DB_PATH=/data/chroma_db`
- `PROACTIVE_MESSAGES_ENABLED=true` when you want live outreach enabled
- Optional proactive tuning vars from `.env.example`
- Optional tuning vars from `.env.example`

Do not rely on local `.env` for cloud deployment.

## 3) Health check

`backend/railway.json` already defines:

- `startCommand`: `uvicorn main:app --host 0.0.0.0 --port $PORT`
- `healthcheckPath`: `/health`
- restart policy

Railway will only route traffic after `/health` returns `200`.
The default `/health` check is intentionally lightweight and does not call Groq.
For manual deep verification, call `/health?deep=true`.

## 4) Persistence (important)

Without a Railway volume, SQLite and Chroma are ephemeral.
For persistent memory across redeploys/restarts, attach a volume and mount it to `/data`.

## 5) Firebase admin credentials

The backend now verifies Firebase tokens server-side, so Railway needs access to a valid Firebase Admin service account JSON file.

Recommended approach:

- add the JSON as a Railway secret file or mounted asset
- set `FIREBASE_SERVICE_ACCOUNT_PATH=/app/firebase-service-account.json`
- confirm the file exists at runtime before first deploy

Never commit the service account JSON into this repository.

## 6) Frontend base URL

Point frontend API URL at the Railway public domain, for example:

`https://your-service.up.railway.app`

The frontend code now normalizes host-only values to HTTPS automatically.

## 7) Push and proactive behavior notes

- Proactive messaging can work as an in-app inbox without push, but real delivery needs Firebase Messaging platform setup in the Flutter app.
- Configure Android and iOS Firebase Messaging separately before expecting background notifications to arrive.
- Keep proactive behavior disabled until quiet hours, cadence, and companion tone feel right in staging.

## 8) Hygiene checklist before deploy

- local `.env` files are untracked
- `backend/venv` is not committed
- `backend/chroma_db` is not committed
- SQLite database files are not committed
- Firebase service account files are not committed
