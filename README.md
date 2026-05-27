# Sol MVP

Sol is a relationship-first AI product focused on emotional continuity, persistent memory, and believable long-term companion dynamics. This repository contains the Flutter client and the FastAPI backend that power the current MVP.

## Repo Structure

- `frontend/companion_app` — Flutter app for auth, onboarding, chat, profile/privacy controls, and companion UX
- `backend` — FastAPI backend for chat orchestration, memory systems, relationship state, proactive behavior, and ops tooling

## Current Product State

Most of the planned MVP architecture is implemented in code:

- pair-scoped identity and memory boundaries
- Firebase-backed auth flow with server-side verification
- multi-companion roster support
- first-run encounter and onboarding
- burst-style chat playback with pacing metadata
- relationship state updates and long-term memory synthesis
- profile, transparency, privacy, and reset/delete controls
- guarded proactive messaging and basic admin/ops visibility

What is still not fully proven from this environment is runtime validation. The repo needs live backend startup, frontend smoke testing, and production deployment verification on your machine before we can honestly call the whole system fully validated.

## Local Setup

### Backend

1. Install Python 3.11+.
2. Create a virtual environment outside git or reuse a local untracked one.
3. Install dependencies:

```powershell
cd backend
pip install -r requirements.txt
```

4. Create either `backend/.env` or a repo-root `.env` from `backend/.env.example`.
   The backend now reads both, with `backend/.env` taking precedence.
5. Provide a Firebase service account JSON file and point `FIREBASE_SERVICE_ACCOUNT_PATH` to it.
6. Start the API:

```powershell
cd backend
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### Frontend

```powershell
cd frontend/companion_app
flutter pub get
flutter run
```

## Testing

Backend:

```powershell
cd backend
pytest
```

Frontend:

```powershell
cd frontend/companion_app
dart analyze
flutter test
```

## Deployment

Railway is the intended backend target. Use `backend/railway.json`, `backend/Procfile`, and the instructions in [backend/RAILWAY_SETUP.md](/C:/Users/aakash09/Desktop/sol_mvp/backend/RAILWAY_SETUP.md).

## Repo Hygiene Notes

- Do not commit local `.env` files.
- Do not commit `backend/venv`, `backend/chroma_db`, or SQLite database files.
- Keep Firebase service account files out of version control.
- Treat generated Flutter build output as disposable.
