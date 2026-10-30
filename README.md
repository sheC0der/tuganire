# Tuganire: Kinyarwanda conversation tutor (Flutter)

Three parts:

- `backend/` is a small Express server. It holds the Claude API key and the tutor's teaching instructions, checks who is signed in, and serves the web app. The app talks only to it.
- `tts/` is a private Python service that turns Kinyarwanda text into speech with Meta's MMS model. Only the backend calls it.
- The Flutter app is the rest of this repository (`lib/`, `web/`, `android/`, `ios/`, ...).

Why a backend: if the API key were inside the app, anyone could pull it out and run up your bill. The server also lets you improve the tutor's prompt without publishing a new app version.

In production it runs as **two Railway services** in one project:

- **web**: the root `Dockerfile` builds the Flutter web app and the Express server serves it, with the API under `/api` on the same origin. Phones and desktops call this same server.
- **tts**: `tts/Dockerfile`, reachable only over Railway's private network. It has no public URL.

```
https://<your-service>.up.railway.app/            Flutter web app (index.html for app routes)
https://<your-service>.up.railway.app/api/chat    tutor endpoint (needs a signed-in, allowed user)
https://<your-service>.up.railway.app/api/tts     Kinyarwanda audio (same sign-in check)
https://<your-service>.up.railway.app/api/health  health check (also at /health)
http://tts.railway.internal:8000/synthesize       private: the backend's call to the TTS service
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
| `TTS_URL` | server | runtime | no | The TTS service, e.g. `http://${{tts.RAILWAY_PRIVATE_DOMAIN}}:${{tts.PORT}}` on Railway. Without it, `/api/tts` answers 503 and the app uses the device's voice. |
| `TTS_SHARED_SECRET` | server and TTS service | runtime | with `TTS_URL` | The same random string on both services. Secret: runtime only. |
| `TTS_CACHE_MB` | server | runtime | no | Memory for cached audio. Default 50 (about 25 minutes of speech). |

The TTS service's own variables:

| Variable | When | Required | Notes |
| --- | --- | --- | --- |
| `TTS_SHARED_SECRET` | runtime | yes | At least 16 characters. The service refuses to start without it, and answers 401 to any request that doesn't send it. |
| `PORT` | runtime | yes on Railway | Set it to `8000`, so the backend's `TTS_URL` can name the port. Local default 8000. |
| `TTS_MODEL` | runtime **and** build | no | Hugging Face model id. Default `facebook/mms-tts-kin` (set in `tts/engine.py`). The build bakes this model into the image. |
| `TTS_THREADS` | runtime | no | CPU threads per synthesis. Default: torch's choice. Set it to the service's vCPU count if speech is slow. |

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

The root `railway.json` only redeploys this service when files it uses change, so editing `tts/` doesn't rebuild the web app.

To check the image locally:

```
docker build -t tuganire --build-arg SUPABASE_URL=https://<ref>.supabase.co --build-arg SUPABASE_PUBLISHABLE_KEY=sb_publishable_... .
docker run --rm -p 8787:8787 --env-file backend/.env tuganire
```

## Kinyarwanda voice (the TTS service)

Browser and phone voices can't speak Kinyarwanda. The app therefore asks the backend for audio (`POST /api/tts`). The backend checks the sign-in exactly as for `/api/chat`, then forwards the text to the TTS service. It keeps recent audio in memory, so repeated phrases come back instantly. The app keeps the last 40 clips too, so "Hear again" doesn't even reach the server.

If the TTS service is missing, down or too slow (30 s), the app reads aloud with the device's voice and shows a short notice once. It tries the server again a minute later. "Test voice" in the chat's ⋮ menu shows which voice was used.

Speed: on CPU, MMS takes about as long to generate speech as to play it (about 4 s for a 4 to 5 second reply on 4 cores). "Hear again" shows a spinner meanwhile. More vCPUs make it faster.

### Licence

`facebook/mms-tts-kin` is licensed **CC-BY-NC 4.0: non-commercial use only**. It's fine for a personal or research project, but not for a paid app or one that earns money in other ways. Before any commercial use, switch to a model whose licence allows it, such as Digital Umuganda's Kinyarwanda TTS model (CC-BY-SA: commercial use allowed, with attribution and share-alike terms).

### Changing the model

The model is chosen in one place: `TTS_MODEL` (default in `tts/engine.py`). Any Hugging Face VITS checkpoint that `transformers` can load works by setting `TTS_MODEL` on the tts service and redeploying (the build downloads that model into the image). A model in another format needs a small engine class in `tts/engine.py`, with `model_id`, `sample_rate` and `synthesize(text)`, plus its own download step in `download()`. Nothing else changes.

### Adding the TTS service on Railway

1. In your Railway project: **+ Create > GitHub Repo** and pick this same repository. This adds a second service.
2. In the new service's **Settings**:
   - **Source > Root Directory**: `/tts`.
   - **Config-as-code > Railway Config File**: `/tts/railway.json`. Railway doesn't look for it inside the root directory by itself. The file sets the `/health` check (5 minutes, to allow for loading the model) and only redeploys when `tts/` changes.
   - Rename the service to `tts`. Then under **Networking > Private Networking** check that its DNS name is `tts`, i.e. `tts.railway.internal`.
   - Don't generate a public domain. The service only needs to be reached privately.
   - **Deploy > Resource Limits**: give it at least **2 GB of memory** (see Memory below), and 2 or more vCPUs if you can.
3. In the tts service's **Variables**:
   - `TTS_SHARED_SECRET` = `${{secret(48)}}` (Railway fills in a random 48-character string).
   - `PORT` = `8000`.
4. In the web service's **Variables**:
   - `TTS_URL` = `http://${{tts.RAILWAY_PRIVATE_DOMAIN}}:${{tts.PORT}}`
   - `TTS_SHARED_SECRET` = `${{tts.TTS_SHARED_SECRET}}`

   These are reference variables: Railway fills in the tts service's values, so the secret is typed in only one place.
5. Deploy both. The tts build downloads torch and the model (a few minutes the first time). In the web service's logs you should see `Kinyarwanda read aloud via http://tts.railway.internal:8000`.

How the services connect: services in one Railway project and environment share a private network. Each service gets the name `<service>.railway.internal`. The backend calls `http://tts.railway.internal:8000/synthesize` over it, with plain `http` (the network is private and encrypted, and has no TLS endpoint) and the port the service listens on. The TTS service listens on `::`, which covers the IPv6 that Railway's private network uses as well as IPv4. Private networking only works at runtime, not during builds.

Memory: the service keeps torch and the model (about 140 MB of weights) in memory. Measured in Docker, it used about 300 MB after loading, about 450 MB after synthesizing, and peaked at about 820 MB with the longest text allowed. Set the limit to **2 GB** for headroom. 1 GB is the minimum.

Text limit: 300 characters per request, which is about 20 seconds of speech; tutor replies are much shorter. Longer text is read by the device's voice instead.

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

TTS service (optional; without it the app uses the device's voice). You need Python 3.12:

```
cd tts
python -m venv .venv
.venv/Scripts/activate                       # Mac/Linux: source .venv/bin/activate
pip install torch --index-url https://download.pytorch.org/whl/cpu
pip install -r requirements-dev.txt
TTS_SHARED_SECRET=local-dev-secret-123456 uvicorn app:create_app --factory --port 8000
```

In PowerShell, set the secret first with `$env:TTS_SHARED_SECRET="local-dev-secret-123456"`. The first start downloads the model (about 140 MB). Then add `TTS_URL=http://localhost:8000` and `TTS_SHARED_SECRET=local-dev-secret-123456` to `backend/.env` and restart the backend.

Or with Docker:

```
docker build -t tuganire-tts tts
docker run --rm -p 8000:8000 -e TTS_SHARED_SECRET=local-dev-secret-123456 tuganire-tts
```

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
cd tts && .venv/Scripts/python -m pytest      # Mac/Linux: .venv/bin/python -m pytest
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
railway.json                      Railway build and health check settings (web service)
backend/
  server.js                       reads env vars, starts the server
  app.js                          routes: /api, auth check, web app and index.html fallback
  auth.js                         Supabase token check and ALLOWED_EMAILS
  tutor.js                        calls Claude and parses the tutor's reply
  prompt.js                       how the tutor teaches (levels, situations, instructions)
  tts.js                          calls the TTS service, caches audio in memory
  test/                           backend tests (npm test)
tts/
  app.py                          FastAPI: POST /synthesize (needs X-TTS-Secret), GET /health
  engine.py                       the speech model: the one place to change it
  Dockerfile, railway.json        the tts Railway service
  test_app.py                     tests (pytest)
lib/
  main.dart                       app entry, Supabase setup, sign-in gate
  config.dart                     backend URL and Supabase settings from --dart-define
  theme.dart                      colours and Material 3 theme
  models/scenario.dart            levels and role-play situations
  models/chat.dart                messages, feedback, suggestions, JSON parsing
  services/auth_service.dart      Supabase email and password sign-in
  services/tutor_service.dart     calls your backend with the user's token
  services/speech_service.dart    speech to text (device recogniser)
  services/voice_service.dart     read aloud interface, and the device voice (fallback)
  services/remote_voice_service.dart   Kinyarwanda voice from the backend (default)
  controllers/conversation_controller.dart   the conversation state
  screens/sign_in_screen.dart     email and password sign-in
  screens/setup_screen.dart       pick level and situation, sign out
  screens/chat_screen.dart        the conversation and composer
  widgets/message_bubble.dart     tutor and learner bubbles, correction cards
```

Adding a new situation: add it to `SCENARIOS` in `backend/prompt.js` and to `scenarios` in `lib/models/scenario.dart` with the same id.

## Known limitation: speech recognition

Devices rarely include Kinyarwanda speech recognition. If the device can't recognise Kinyarwanda, the mic listens in English and the tutor shows how to say it in Kinyarwanda. Meta's MMS models also include Kinyarwanda speech recognition, which could run on the TTS service the same way.

Read aloud uses the TTS service. Only when that's unavailable does it fall back to the device's voice (Swahili if there is one, which is only an approximation).

## Before publishing to the Play Store

- Rate-limit requests per user on the server.
- Set a monthly spend limit in the Anthropic console.
