# MILA Backend

Node backend for MILA health checks, APK downloads, app update metadata, and
optional server-side Gemini Live token creation.

ChatGPT/OpenAI account mode is currently disabled by default
(`ENABLE_OPENAI_ACCOUNT=false`). The legacy endpoints remain behind that flag
for future work, but the mobile app currently uses Gemini directly.

## Run Locally

```powershell
cd backend
Copy-Item .env.example .env
# edit .env and set PUBLIC_BASE_URL, ADMIN_TOKEN and optionally GEMINI_API_KEY
npm start
```

Build the app with:

```powershell
flutter build apk --release `
  --dart-define=MILA_BACKEND_URL=https://agent.milanapremium.uz
```

Use `http://10.0.2.2:8787` for the Android emulator. On a physical phone, use
your computer or server IP, or a real HTTPS domain.

## Endpoints

- `GET /health` - health check.
- `GET /downloads/<file>` - static downloads, used for APK releases.
- `POST /v1/voice/token` - authenticated, single-use Gemini Live token. This
  is only useful when the app has a valid MILA session.
- `GET /v1/app/update?platform=android&versionCode=1` - app update metadata.
- `POST /admin/app/update` - save update metadata. Requires `X-Admin-Token`.
- `GET /admin/devices` - list paired mobile devices without exposing session tokens.
- `DELETE /admin/devices/<id>` - revoke one paired device. Requires `X-Admin-Token`.

Legacy endpoints, disabled unless `ENABLE_OPENAI_ACCOUNT=true`:

- `GET /auth/openai/start`
- `POST /auth/openai/device`
- `POST /v1/chat/stream`
- `POST /admin/subscription`

Example update publish request:

```powershell
Invoke-RestMethod http://localhost:8787/admin/app/update `
  -Method Post `
  -Headers @{ "X-Admin-Token" = "change-me-admin-token" } `
  -ContentType "application/json" `
  -Body '{"platform":"android","latestVersion":"1.0.1","latestCode":2,"minSupportedVersion":"1.0.0","minSupportedCode":1,"apkUrl":"https://example.com/downloads/app-release.apk","notes":"Bug fixes"}'
```

## Production Notes

Keep provider secrets, billing checks, SQLite data, and release APKs on the
server. Do not commit `backend/.env`, `backend/data`, or `downloads`.

SQLite data is stored in `DB_PATH`; back this file up on the server.
