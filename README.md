# MILA — AI Voice Assistant (Flutter)

Production-ready Flutter app implementing the MILA design: real-time voice
conversations over the **Gemini Live API**, and text intelligence
(chat, summaries, actions) via **Gemini**. ChatGPT/OpenAI account mode is
currently disabled.

## Features

| Screen (design #) | Status |
|---|---|
| Splash, Onboarding, Sign In, Permissions (01–04) | ✅ local profile + Google OAuth-ready |
| Living orb: animated listening/thinking/speaking/error states | ✅ lightweight CustomPainter, audio-reactive |
| Home Dashboard + suggestions (05) | ✅ |
| Voice assistant: idle / listening / thinking / speaking (06–09) | ✅ Gemini Live, acoustic echo protection, live camera vision |
| Chat transcript + AI action cards (09–10) | ✅ streaming, photos, camera and document attachments |
| Command Center shortcuts (11) | ✅ |
| Tasks & Automations (12) | ✅ local storage |
| Memory Vault (13) | ✅ injected into the system prompt for text *and* voice |
| Integrations (14) | ⚠️ UI + local state; real OAuth needs your backend (below) |
| Profile & Settings (15) | ✅ |
| Approval confirmation (16) | ✅ drafts require explicit approval |
| Offline & empty states (17–18) | ✅ |

## Architecture

```
lib/
  core/            theme (style-guide palette, Inter), orb/waveform/glass widgets
  data/            plain models with JSON persistence (no codegen)
  services/
    llm/           LlmProvider abstraction → GeminiTextProvider (SSE streaming)
    voice/         GeminiLiveClient (WebSocket) + VoiceController (mic/playback state machine)
    storage/       Hive local store + flutter_secure_storage for API keys
  features/        one folder per screen, Riverpod state, go_router navigation
```

Adding another LLM vendor = one new `LlmProvider` subclass and a settings entry.

## Quick start

```bash
flutter pub get
flutter run
```

Run the backend locally when testing updates/downloads:

```powershell
cd backend
Copy-Item .env.example .env
npm start
```

For a server/VPS deployment:

```bash
cd mila
cp backend/.env.example backend/.env
# edit backend/.env: PUBLIC_BASE_URL, ADMIN_TOKEN, GEMINI_API_KEY if needed
docker compose up -d --build
```

In the app: **Settings → AI Providers**:

- **Gemini API key** (required for real-time voice; also usable for text) — from
  [Google AI Studio](https://aistudio.google.com/apikey)
- **MILA server URL** — your backend domain, for example
  `https://agent.milanapremium.uz`, used for updates and downloads.

Keys are stored in the Android Keystore / iOS Keychain.
You can bake Gemini defaults in at build time (secure storage still overrides
them):

```bash
flutter build apk --release \
  --dart-define=MILA_BACKEND_URL=https://agent.milanapremium.uz \
  --dart-define=APP_VERSION=1.1.0 \
  --dart-define=APP_VERSION_CODE=5
```

### Google Sign-In

Create an Android OAuth client for package `app.milaai.mila` (with the SHA-1
of the signing key) and a Web OAuth client in the same Google Cloud project.
Then provide the Web client ID at build or run time:

```powershell
flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=123456.apps.googleusercontent.com
flutter build apk --release --dart-define=GOOGLE_WEB_CLIENT_ID=123456.apps.googleusercontent.com
```

The client ID is public configuration, not a client secret. A Google account
updates the local MILA profile; provider API keys remain separate.

> ⚠️ Anything compiled into an APK can be extracted. `--dart-define` is fine
> for non-secret endpoints and internal/team defaults. Keep provider secrets
> and OAuth credentials on your server. With `GEMINI_API_KEY` configured on
> the MILA backend, voice uses a short-lived, one-session Gemini token instead
> of a key embedded in the app. A user-entered Gemini key remains available
> only as a direct-development fallback.

### Models (editable in-app, no code changes)

| Purpose | Default |
|---|---|
| Voice (Gemini Live) | `gemini-3.1-flash-live-preview` |
| Gemini text | `gemini-3.5-flash` |

If Google releases new models, type the new name in Settings.

## Building for release

### Android (APK / AAB)

1. Create a keystore (once):
   ```bash
   keytool -genkey -v -keystore mila-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mila
   ```
2. Create `android/key.properties` (never commit it):
   ```properties
   storePassword=***
   keyPassword=***
   keyAlias=mila
   storeFile=C:/keys/mila-release.jks
   ```
   Without this file the build automatically falls back to debug signing, so
   development keeps working.
3. Build:
   ```bash
   flutter build apk --release          # direct-download APK
   flutter build appbundle --release    # Play Store AAB
   ```
   Output: `build/app/outputs/flutter-apk/app-release.apk`
   and `build/app/outputs/bundle/release/app-release.aab`.

### Hosting the APK on your server

Upload `app-release.apk` and serve it with the right MIME type
(`application/vnd.android.package-archive`). nginx example:

```nginx
location /downloads/ {
    types { application/vnd.android.package-archive apk; }
}
```

Users need "Install unknown apps" enabled. For updates, bump `version:` in
`pubspec.yaml` (e.g. `1.0.1+2`) and rebuild — Android only upgrades if
`versionCode` (the `+N`) increases and the signature matches, so **keep the
keystore safe**.

### iOS

Requires macOS + Xcode. `Info.plist` already contains the microphone /
calendar / contacts usage strings and background-audio mode. After the first
`pod install`, enable the permission macros `permission_handler` needs in
`ios/Podfile`:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)',
        'PERMISSION_MICROPHONE=1',
        'PERMISSION_EVENTS_FULL_ACCESS=1',
        'PERMISSION_CONTACTS=1',
        'PERMISSION_NOTIFICATIONS=1',
      ]
    end
  end
end
```

Then `flutter build ipa --release` and distribute via TestFlight/App Store
(ad-hoc server distribution on iOS requires an enterprise account).

## Production hardening checklist

- **Backend:** keep `backend/.env`, `backend/data`, and `downloads` on the
  server. Do not commit secrets or the SQLite database.
- **Updates:** publish APK metadata through `/admin/app/update`; the mobile app
  checks `/v1/app/update` from Settings → Check for Updates. Store the APK at
  the URL you publish in `apkUrl`.
- **Auth:** sign-in is a local profile today. To use your own backend, wire
  `sign_in_screen.dart` to your API and keep saving the same `UserProfile`.
- **Integrations (Gmail, Telegram, Calendar, ERP/CRM):** the screen stores
  connection flags; each real integration needs an OAuth flow + API calls,
  best done through your server so tokens never live only on-device.
- **Crash reporting / analytics:** add Sentry or Firebase Crashlytics before
  a public launch.

## Windows development note

If your Flutter SDK lives in a path with a space (e.g. `C:\Flutter SDK`),
`flutter test`/native-assets builds fail with a garbled "not recognized as a
command" error. Fix (already applied on this machine):

```powershell
New-Item -ItemType Junction -Path C:\FlutterSDK -Target "C:\Flutter SDK"
# then use C:\FlutterSDK\bin\flutter for builds, or put it first in PATH
```

## Troubleshooting

- **Voice error "session closed / 1008"** — wrong or missing Gemini key, or
  the Live model name is outdated; update it in Settings → AI Providers.
- **Silence from MILA** — check the mic permission and that the device
  volume/route is correct; barge-in stops playback by design when you speak.
