# Tuganire: Kinyarwanda conversation tutor (Flutter)

Two parts:

- `backend/` is a small Express server. It holds the Claude API key and the tutor's teaching instructions, checks who is signed in, and serves the web app. The app talks only to it.
- The Flutter app is the rest of this repository (`lib/`, `web/`, `android/`, `ios/`, ...).

Why a backend: if the API key were inside the app, anyone could pull it out and run up your bill. The server also lets you improve the tutor's prompt without publishing a new app version.

In production it all runs as **one Railway service**: the Docker image builds the Flutter web app and the Express server serves it, with the API under `/api` on the same origin. Phones and desktops call that same server.

```
https://<your-service>.up.railway.app/            Flutter web app (index.html for app routes)
https://<your-service>.up.railway.app/api/chat    tutor endpoint (needs a signed-in, allowed user)
https://<your-service>.up.railway.app/api/health  health check (also at /health)
```

## Sign-in

Learners sign in with an email and password from Supabase. There is no sign-up in the app: you create the accounts, and only emails in `ALLOWED_EMAILS` can use the tutor.

1. Create a Supabase project.
2. Authentication > Sign In / Providers: keep **Email** on and turn **Allow new users to sign up** off.
3. Authentication > Users > **Add user** > Create new user, with **Auto Confirm User** ticked. Repeat for each learner.
4. Project Settings > API Keys: copy the project URL and the **publishable** key (`sb_publishable_...`).

The app sends `Authorization: Bearer <access token>` on every request. The server asks Supabase who the token belongs to and checks their email against `ALLOWED_EMAILS` before calling Claude. A rejected token (401) signs the app out; an email not on the list gets 403.

Only the publishable key is used, by both the app and the server. It's designed to be public. **Never** put the Supabase secret key or `service_role` key, or the Anthropic API key, in the app, in a build argument, or in git.

## Environment variables

| Variable | Used by | When | Required | Notes |
| --- | --- | --- | --- | --- |
| `ANTHROPIC_API_KEY` | server | runtime | yes | From console.anthropic.com. Secret: runtime only. |
| `SUPABASE_URL` | server and web app | runtime **and** build | yes | `https://<ref>.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | server and web app | runtime **and** build | yes | `sb_publishable_...`. Public by design. |
| `ALLOWED_EMAILS` | server | runtime | yes | Comma-separated, case-insensitive: `a@x.com,b@y.com` |
| `CLAUDE_MODEL` | server | runtime | no | Default `claude-sonnet-5-5` |
| `PORT` | server | runtime | no | Railway sets it. Local default 8787. |
| `NODE_ENV` | server | runtime | no | The Docker image sets `production`. Anything else turns on CORS for `localhost` origins, for `flutter run -d chrome`. |
| `WEB_DIR` | server | runtime | no | Folder with the web build. Default `backend/public` (where the image puts it). |

App build settings, passed with `--dart-define` (or `--dart-define-from-file`):

| Define | Notes |
| --- | --- |
| `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` | Required on every platform. The Docker build passes them for web. |
| `BACKEND_URL` | Phones and desktop: your Railway URL. Web: leave it out to use the same origin, or set it to a local server while developing. If it's missing on a phone, the app falls back to the placeholder in `lib/config.dart` and says the server address isn't set. You can put your Railway URL in `railwayUrlPlaceholder` there instead of passing it each time. |

## Deploy to Railway

1. Push this repository to GitHub.
2. In Railway: **New Project > Deploy from GitHub repo** and pick the repo. Railway finds `railway.json`, builds the root `Dockerfile` and uses `/health` as the health check.
3. In the service's **Variables** tab, add `ANTHROPIC_API_KEY`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` and `ALLOWED_EMAILS` (and `CLAUDE_MODEL` if you want a different model). Don't set `PORT`.
   Railway passes service variables to the Docker build only for names the Dockerfile declares with `ARG`, which are `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`. That's how the web build gets them. `ANTHROPIC_API_KEY` is deliberately not an `ARG`, so it never ends up in an image layer.
4. **Settings > Networking > Generate Domain** to get `https://<your-service>.up.railway.app`.
5. Deploy. Open `https://<your-service>.up.railway.app/health`, then the site itself, and sign in.

If you change `SUPABASE_URL` or `SUPABASE_PUBLISHABLE_KEY`, redeploy so the web app is rebuilt with the new values.

To check the image locally:

```
docker build -t tuganire --build-arg SUPABASE_URL=https://<ref>.supabase.co --build-arg SUPABASE_PUBLISHABLE_KEY=sb_publishable_... .
docker run --rm -p 8787:8787 --env-file backend/.env tuganire
```

## Local development

You need Node 20 or newer and Flutter 3.47.

Backend:

```
cd backend
npm install
cp .env.example .env      # then fill it in
npm run dev               # restarts when you edit the server
```

Check it works: http://localhost:8787/health should show `{"ok":true,...}`.

App settings: copy `dart_defines.example.json` to `dart_defines.json` (gitignored) and fill in your Supabase URL and publishable key.

Web, against the local server (CORS for localhost is on outside production):

```
flutter run -d chrome --dart-define-from-file=dart_defines.json --dart-define=BACKEND_URL=http://localhost:8787
```

To try the production setup locally instead (one origin, no CORS), build the web app and let Express serve it:

```
flutter build web --dart-define-from-file=dart_defines.json
cd backend && WEB_DIR=../build/web npm start      # then open http://localhost:8787
```

Android phone against Railway:

```
flutter run --dart-define-from-file=dart_defines.json --dart-define=BACKEND_URL=https://<your-service>.up.railway.app
```

Android phone against your computer (same Wi-Fi; find your IP with `ipconfig` on Windows, `ip a` or `ifconfig` on Mac/Linux, and allow port 8787 through the firewall):

```
flutter run --dart-define-from-file=dart_defines.json --dart-define=BACKEND_URL=http://192.168.1.20:8787
```

The Android emulator reaches your computer at `http://10.0.2.2:8787`.

Tests:

```
flutter analyze
flutter test
cd backend && npm test
```

## Platform setup

Already applied in this repository:

- Android: `INTERNET` and `RECORD_AUDIO` permissions and the `queries` block for the speech recogniser and text to speech, in `android/app/src/main/AndroidManifest.xml`.
- Android: `usesCleartextTraffic` is set only in `android/app/src/debug/AndroidManifest.xml`, so debug builds can reach a local `http://` backend and release builds can't. Railway serves https.
- Android: `minSdk` uses Flutter's default (24), which meets flutter_tts (24) and speech_to_text (21).
- iOS: microphone and speech recognition usage descriptions in `ios/Runner/Info.plist`.

## How the code is organised

```
Dockerfile                        builds the web app, then the server image
railway.json                      Railway build and health check settings
backend/
  server.js                       reads env vars, starts the server
  app.js                          routes: /api, auth check, web app and index.html fallback
  auth.js                         Supabase token check and ALLOWED_EMAILS
  tutor.js                        calls Claude and parses the tutor's reply
  prompt.js                       how the tutor teaches (levels, situations, instructions)
  test/                           backend tests (npm test)
lib/
  main.dart                       app entry, Supabase setup, sign-in gate
  config.dart                     backend URL and Supabase settings from --dart-define
  theme.dart                      colours and Material 3 theme
  models/scenario.dart            levels and role-play situations
  models/chat.dart                messages, feedback, suggestions, JSON parsing
  services/auth_service.dart      Supabase email and password sign-in
  services/tutor_service.dart     calls your backend with the user's token
  services/speech_service.dart    speech to text (device recogniser)
  services/voice_service.dart     text to speech behind an interface you can swap
  controllers/conversation_controller.dart   the conversation state
  screens/sign_in_screen.dart     email and password sign-in
  screens/setup_screen.dart       pick level and situation, sign out
  screens/chat_screen.dart        the conversation and composer
  widgets/message_bubble.dart     tutor and learner bubbles, correction cards
```

Adding a new situation: add it to `SCENARIOS` in `backend/prompt.js` and to `scenarios` in `lib/models/scenario.dart` with the same id.

## Known limitation: voice

Devices rarely include Kinyarwanda speech recognition or a Kinyarwanda voice.

- If the device can't recognise Kinyarwanda, the mic listens in English and the tutor shows how to say it in Kinyarwanda.
- If there's no Kinyarwanda voice, the app uses Swahili, which is an approximation.

The planned fix is to run a real Kinyarwanda speech model on the backend (Meta's open MMS models include Kinyarwanda speech recognition and text to speech) and add a `RemoteVoiceService` that implements `VoiceService`. No screen code needs to change for that.

## Before publishing to the Play Store

- Rate-limit requests per user on the server.
- Set a monthly spend limit in the Anthropic console.
