# MILA — AI Voice Assistant (Flutter)

Production-ready Flutter app implementing the MILA design: real-time voice
conversations over the **Gemini Live API**, and text intelligence
(chat, summaries, actions) via **Gemini**. ChatGPT/OpenAI account mode is
currently disabled.

## Features

| Screen (design #) | Status |
|---|---|
| Splash, Onboarding, Sign In, Permissions (01–04) | ✅ unified Agentic OS account |
| Living orb: animated listening/thinking/speaking/error states | ✅ lightweight CustomPainter, audio-reactive |
| Home Dashboard + suggestions (05) | ✅ |
| Voice assistant: idle / listening / thinking / speaking (06–09) | ✅ Gemini Live, acoustic echo protection, live camera vision |
| Chat transcript + AI action cards (09–10) | ✅ streaming, photos, camera and document attachments |
| Command Center shortcuts (11) | ✅ |
| Tasks & Automations (12) | ✅ Hermes Kanban sync; local fallback before pairing |
| Memory Vault (13) | ✅ Obsidian sync; injected into text and voice prompts |
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

MILA and the web panel use the same Agentic OS account, role and personal
workspace. The phone holds a revocable account token plus a separate MILA voice
session, while Gemini and LiveKit secrets remain server-side. Personal tasks
and notes synchronize through `/api/member/*`. See
`docs/UNIFIED_ACCOUNTS_RU.md` and `docs/AGENTIC_OS_SYNC_RU.md`.

Creator and Admin accounts with two-factor authentication enabled use the same
TOTP or recovery code on mobile as on the web. The five-minute MFA challenge is
kept in memory only; the app stores the revocable mobile session after the
second factor succeeds. Regular Member accounts continue to sign in with email
and password without an extra step unless MFA is enabled for that role later.

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
  `https://agent.milanapremium.uz/mila`, used for secure voice sessions,
  updates and downloads. New users register or sign in with the same email and
  password used by the Agentic OS web panel. The one-time connection code is
  retained only for older installed builds and administrative compatibility.

Keys are stored in the Android Keystore / iOS Keychain.
You can bake Gemini defaults in at build time (secure storage still overrides
them):

```bash
flutter build apk --release \
  --dart-define=MILA_BACKEND_URL=https://agent.milanapremium.uz/mila \
  --dart-define=APP_VERSION=1.1.0 \
  --dart-define=APP_VERSION_CODE=5
```

### Google Sign-In

Google Sign-In is hidden until the server-side OAuth flow is connected to the
same Agentic OS user store. This prevents a local-only account from appearing
signed in without a real server identity.

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
| Server voice (LiveKit + Gemini Native Audio) | `gemini-3.1-flash-live-preview` |
| Direct mobile fallback | `gemini-3.1-flash-live-preview` |
| Gemini text | `gemini-3.5-flash` |

If Google releases new models, type the new name in Settings.

The server voice agent enables affective dialogue by default. MILA gently
adapts pace, warmth, and intonation to the user's emotional tone while
preserving Russian, Uzbek, English, and mixed speech. Production overrides are
read from `backend/.env`:

```dotenv
GEMINI_LIVE_MODEL=gemini-3.1-flash-live-preview
MILA_VOICE=Laomedeia
MILA_AFFECTIVE_DIALOG=true
MILA_VOICE_TEMPERATURE=0.7
MILA_THINKING_LEVEL=LOW
MILA_MEDIA_RESOLUTION=LOW
MILA_CONTEXT_TRIGGER_TOKENS=104857
MILA_CONTEXT_TARGET_TOKENS=52428
GEMINI_API_VERSION=v1alpha
```

The server maps `GEMINI_LIVE_MODEL` to the LiveKit voice worker so the mobile
app, dashboard status, and actual runtime use the same model. MILA
automatically disables affective dialogue for 3.1 because that model does not
support the capability.

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
- **Auth:** registration, password sign-in, mobile session issuance and
  Creator/Admin MFA are backed by the Agentic OS API. Device tokens live in
  Android Keystore / iOS Keychain and can be revoked from the web account.
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
