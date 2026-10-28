# Sathi — Hinglish Voice + Gemini Agent MVP

Sathi is a Flutter demo for one focused problem: helping a customer understand a partially approved/rejected health-insurance claim, check sample documents, prepare an editable reconsideration letter, and track next steps.

This release corrects the earlier demo limitation: the old “assistant” was a local keyword router only. This version contains (1) a more robust local Hinglish intent router, (2) device speech input with locale discovery and clear error states, (3) an optional cloud audio transcription route intended for Hindi-English code-switching, and (4) a real server-side Gemini model agent that plans a tool, executes an allow-listed demo tool, then creates a grounded response.

> **Truth-in-demo:** The Gemini model runs only after you configure `GEMINI_API_KEY` on the backend and start the server. Without this, the app identifies responses as `LOCAL DEMO` and uses deterministic rules. It does not bundle a Gemma model. The only claim data available to the agent is fictional sample data; no real insurer API, RAG/vector database, or claim submission is connected.

## The easy customer journey

1. User asks by typing or tapping the microphone.
2. Choose **Hinglish**, **हिन्दी**, or **English**. Device speech chooses a supported locale, preferring Hindi for Hinglish.
3. For better code-switching, the user may separately allow **AI Hinglish voice transcription**. With a backend URL configured, the app records a short WAV and sends it to the Sathi server, which calls Gemini's transcription model. This is opt-in because raw audio is sensitive.
4. The user reviews the transcript and taps **Help me with this**.
5. If cloud text analysis consent is enabled and the backend runs with an API key, Gemini selects one allow-listed demo tool and returns a response. Otherwise, local rules answer common questions.
6. User can open the claim, documents, tracker, or draft screen. No claim gets submitted automatically.

## Project tree

```text
sathi_flutter_plus/
  lib/
    core/security/                 # PII masker + separate text/audio consent
    core/services/                 # OCR, WebSocket event helper
    features/claim/data/
      claim_analysis_service.dart   # sample claim analysis adapter
      sathi_agent_service.dart      # local Hinglish router + HTTP API + audio upload
    features/claim/presentation/pages/
      sathi_assistant_card.dart     # microphone, transcript, language mode, agent status
      technology_page.dart          # stack and privacy controls
      home_page.dart / claim_page.dart / documents_page.dart / tracker_page.dart / appeal_page.dart
  backend/
    main.py                         # Gemini planner + allow-listed demo tools + voice transcription endpoint
    requirements.txt
    .env.example
    test_agent_rules.py
  docs/
    PLATFORM_PERMISSIONS.md
    GEMINI_AGENT_AND_HINGLISH.md
    ON_DEVICE_LLM.md
```

## Requirements

- Flutter 3.44+/Dart 3.12+ for the package versions in `pubspec.yaml`.
- Python 3.11+ for the API server.
- Google AI Studio API key for Gemini-backed chat and cloud audio transcription.
- Android emulator or Android device for the easiest mic demo. iOS requires macOS + Xcode.

## 1) Prepare Flutter platform folders and permissions

The archive intentionally does not include generated `android/` and `ios/` runner projects. From this folder, if they are missing:

```bash
flutter create . --platforms=android,ios
```

Follow `docs/PLATFORM_PERMISSIONS.md` and add the microphone, speech, Internet, camera and photo-library permission snippets for your generated platform projects. Restart the app after changing native permissions; hot reload is not enough for manifest changes.

## 2) Start the actual Gemini agent backend

Create a key in Google AI Studio. Keep it only in the backend, never in Flutter or a committed `.env` file.

```bash
cd backend
python -m venv .venv
# macOS/Linux:
source .venv/bin/activate
# Windows PowerShell:
# .venv\\Scripts\\Activate.ps1
pip install -r requirements.txt
cp .env.example .env
```

Edit `backend/.env` and replace `GEMINI_API_KEY=replace_me` with your private key. Default models are `gemini-3.8-flash` for agent responses and `gemini-3.5-transcribe` for voice transcription; both may be changed in `.env` if model access differs for your account.

Start the server from inside the `backend/` directory:

```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Confirm it is running:

```bash
curl http://127.0.0.1:8000/health
curl -X POST http://127.0.0.1:8000/v1/agent/chat \\
  -H 'Content-Type: application/json' \\
  -d '{"message":"Mera claim reject ho gaya, ab kya karu?","language":"hinglish"}'
```

`/health` must show `"modelConfigured": true` and `"mode": "gemini_agent"` for live model calls. If it shows `local_rules_only`, no model is running yet.

## 3) Run Flutter against the backend

In a **second terminal**, from the project root:

```bash
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=SATHI_API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` is the Android emulator's route to your development computer. In generated `android/app/src/main/AndroidManifest.xml`, for local development only, set `android:usesCleartextTraffic="true"` on the `<application>` element to permit the local `http://` API. Do not use cleartext traffic for a deployed service.

For a **physical phone**, connect it and your computer to the same Wi-Fi and use the computer's LAN IP instead, e.g. `--dart-define=SATHI_API_BASE_URL=http://192.168.1.20:8000`. Permit the port in your firewall. Use HTTPS for any hosted backend.

## 4) Turn on the model and Hinglish voice

1. Open Home → **How Sathi works**.
2. Enable **Allow redacted cloud analysis**. This lets the assistant send the user's masked question to your configured backend for Gemini reasoning.
3. Enable **Allow cloud voice transcription** separately. This allows the app to send a short WAV recording to the configured backend for Hinglish transcription. Voice consent is separate from text consent.
4. Return Home, select **Hinglish**, tap the microphone, speak a short query such as “Mera claim reject ho gaya, ab kya karu?”, and tap stop.
5. Review the transcript. Then press **Help me with this**.
6. Inspect the reply badge: `GEMINI AGENT` means a Gemini call returned; `LOCAL DEMO` means local deterministic rules were used; `OFFLINE FALLBACK` means the server call failed and the app fell back locally.

With cloud voice transcription disabled, the microphone uses the phone's speech recognition service with a Hindi-first locale for Hinglish. Device ASR quality and language availability vary by Android/iOS speech service. If the device engine cannot recognise code-switching well, enable the optional Gemini voice transcription path.

## What the agent actually does

The backend uses a two-step model flow:

1. A Gemini model outputs a structured plan: intent + one allowed tool.
2. The server executes only a safe demo tool (`get_claim_status`, `get_required_documents`, `explain_claim_reason`, `prepare_reconsideration_draft`, or `none`).
3. A second Gemini call writes the user-facing response in the selected language using the tool result.

These tools read fictional example data or create a draft only. No tool submits a claim, changes policy data, contacts an insurer, makes an eligibility decision, or promises recovery.

## Tests and verification

```bash
# Flutter tests (from project root)
flutter test

# Python backend tests (from project root, after installing backend requirements)
python -m unittest discover -s backend -v
```

The package sources and backend tests are included. This execution environment does not have a Flutter SDK or a Gemini key, so a full device build or a live model request could not be run here. Run the commands above locally to validate the environment-specific Android/iOS plugins and your account's model access.

## Important security boundary

- Never commit the backend `.env` file or expose the Gemini key in Dart.
- For this hackathon demo, use only the fictional sample claim and never upload real patient documents.
- The backend does not deliberately persist recordings or log audio/messages, but the upload framework may buffer audio temporarily during processing. Audio is still transmitted to the configured backend and Google's transcription service when cloud voice is enabled.
- PII masking is a helpful second layer, not complete DLP. Do not send policy numbers, Aadhaar numbers, medical records or claim letters through this public-demo setup.
- The backend has no production authentication, rate limiting, tenant isolation or RAG. Do not deploy it publicly with real claimant data until these controls are built and reviewed.
