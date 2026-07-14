# MILA Deploy

## Local development on Windows

Run commands from the project folder:

```powershell
cd "C:\AI Agent\mila"
& "C:\FlutterSDK\bin\flutter.bat" test
npm test --prefix backend
```

Use the no-space Flutter path (`C:\FlutterSDK`) because native asset hooks can
break when Flutter is installed under `C:\Flutter SDK`.

## Backend deploy on VM 105

The production backend runs from:

```bash
/opt/mila
```

Deploy the latest GitHub version:

```bash
cd /opt/mila
./deploy.sh
```

The deploy script keeps `backend/.env`, `backend/data`, and `downloads` local
to the server. Do not commit secrets or the SQLite database.

## Release APK

Build a release APK locally:

```powershell
cd "C:\AI Agent\mila"
& "C:\FlutterSDK\bin\flutter.bat" build apk --release --dart-define=MILA_BACKEND_URL=https://agent.milanapremium.uz/mila
```

Upload the APK to:

```bash
/opt/mila/downloads/app-release.apk
```

Then update `/admin/app/update` on the backend with the new version metadata.
