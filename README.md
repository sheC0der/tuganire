# Tuganire: Kinyarwanda conversation tutor (Flutter)

Two parts:

- `backend/` is a small Node server. It holds your Claude API key and the tutor's teaching instructions, and the app talks only to it.
- The Flutter app is the rest of this repository (`lib/`, `android/`, `ios/`, ...).

Why a backend: if the API key were inside the app, anyone could pull it out of the APK and run up your bill. The server also lets you improve the tutor's prompt without publishing a new app version.

## 1. Run the backend

You need Node 18 or newer.

```
cd backend
npm install
cp .env.example .env      # then open .env and paste your key from console.anthropic.com
npm start
```

Check it works: open http://localhost:8787/health in a browser. You should see `{"ok":true,...}`.

## 2. Platform setup

Already applied in this repository:

- Android: `INTERNET` and `RECORD_AUDIO` permissions and the `queries` block for the speech recogniser and text to speech, in `android/app/src/main/AndroidManifest.xml`.
- Android: `usesCleartextTraffic` is set only in `android/app/src/debug/AndroidManifest.xml`, so debug builds can reach a local `http://` backend and release builds can't. Release builds need the backend on https.
- Android: `minSdk` uses Flutter's default (24), which meets flutter_tts (24) and speech_to_text (21).
- iOS: microphone and speech recognition usage descriptions in `ios/Runner/Info.plist`.

## 3. Run the app

Android emulator (10.0.2.2 is the emulator's address for your computer, so no flag is needed):

```
flutter pub get
flutter run
```

A real phone on the same Wi-Fi as your computer. Find your computer's local IP (ipconfig on Windows, `ip a` or `ifconfig` on Mac/Linux):

```
flutter run --dart-define=BACKEND_URL=http://192.168.1.20:8787
```

If the phone can't connect, check your computer's firewall allows port 8787.

## How the code is organised

```
lib/
  main.dart                       app entry, wires up services
  config.dart                     backend URL and token from --dart-define
  theme.dart                      colours and Material 3 theme
  models/scenario.dart            levels and role-play situations
  models/chat.dart                messages, feedback, suggestions, JSON parsing
  services/tutor_service.dart     calls your backend
  services/speech_service.dart    speech to text (phone's recogniser)
  services/voice_service.dart     text to speech behind an interface you can swap
  controllers/conversation_controller.dart   the conversation state
  screens/setup_screen.dart       pick level and situation
  screens/chat_screen.dart        the conversation and composer
  widgets/message_bubble.dart     tutor and learner bubbles, correction cards
```

Adding a new situation: add it to `SCENARIOS` in `backend/prompt.js` and to `scenarios` in `lib/models/scenario.dart` with the same id.

## Known limitation: voice

Phones rarely include Kinyarwanda speech recognition or a Kinyarwanda voice.

- If the phone can't recognise Kinyarwanda, the mic listens in English and the tutor shows how to say it in Kinyarwanda.
- If there's no Kinyarwanda voice, the app uses Swahili, which is an approximation.

The planned fix is to run a real Kinyarwanda speech model on the backend (Meta's open MMS models include Kinyarwanda speech recognition and text to speech) and add a `RemoteVoiceService` that implements `VoiceService`. No screen code needs to change for that.

## Before publishing to the Play Store

- Deploy the backend somewhere with https (Render, Railway, Fly.io, or a Google Cloud Run service).
- Add real user accounts (for example Firebase Auth) and verify the user's token on the server, then rate-limit per user. The `APP_TOKEN` shared secret is only a speed bump.
- Set a monthly spend limit in the Anthropic console.
