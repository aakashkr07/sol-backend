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
- `SQLITE_DB_PATH=/data/db/companion.db`
- `CHROMA_DB_PATH=/data/chroma_db`
- Optional tuning vars from `.env.example`

Do not rely on local `.env` for cloud deployment.

## 3) Health check

`backend/railway.json` already defines:

- `startCommand`: `uvicorn main:app --host 0.0.0.0 --port $PORT`
- `healthcheckPath`: `/health`
- restart policy

Railway will only route traffic after `/health` returns `200`.

## 4) Persistence (important)

Without a Railway volume, SQLite and Chroma are ephemeral.
For persistent memory across redeploys/restarts, attach a volume and mount it to `/data`.

## 5) Frontend base URL

Point frontend API URL at the Railway public domain, for example:

`https://your-service.up.railway.app`

The frontend code now normalizes host-only values to HTTPS automatically.
