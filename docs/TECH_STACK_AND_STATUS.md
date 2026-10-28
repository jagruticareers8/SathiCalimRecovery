# Sathi technology stack and implementation status

This document distinguishes code that is present from services that become active only after you configure the backend. The UI must never claim that a model ran when it used local rules.

## Client app

| Technology | Status | Role |
|---|---|---|
| Flutter + Dart | Implemented | Cross-platform demo UI |
| BLoC (`flutter_bloc`) | Implemented | Claim journey state in `ClaimCubit` |
| Platform channels | Used through native plugin bridges | OCR, microphone recording and device speech APIs |
| Secure storage | Implemented for privacy preferences | Stores separate cloud-text and cloud-voice consent flags; not the uploaded claim documents |
| Camera/gallery/file picker | Implemented as a local selection flow | Records a selected filename in the demo checklist; this is not an insurer upload |

## On-device features

| Technology | Status | Role |
|---|---|---|
| On-device OCR (ML Kit) | Implemented for selected image files; Latin script configured by default | Extracts text when the user taps Read text on device |
| PII masking | Implemented as a lightweight helper | Masks common phone, email, PAN-like and Aadhaar-like patterns; this is best-effort and not a full DLP control |
| Device speech (`speech_to_text`) | Implemented with locale discovery and status/error handling | Uses the OS recognition service, preferring Hindi for Hinglish; mixed Hindi-English accuracy depends on installed service and device |
| Google Gemma on-device inference | Not bundled or connected | No Gemma weights/runtime are included in this source archive |
| MediaPipe LLM Inference | Not wired | Google documentation says the API is in maintenance-only mode; evaluate LiteRT-LM for a future local-model implementation. See `ON_DEVICE_LLM.md`. |

## Cloud AI and voice

| Technology | Status | Role |
|---|---|---|
| Gemini agent (`backend/main.py`) | Implemented; inactive until `GEMINI_API_KEY` is set and backend is running | A planner model selects one intent, the server enforces an allow-listed demo tool, and a second model call produces the response in Roman-script Hinglish, Devanagari Hindi or English |
| Gemini transcription (`gemini-3.5-transcribe`) | Implemented as opt-in `/v1/voice/transcribe`; requires the same backend key | Receives a short WAV after separate cloud-voice consent and asks the model to preserve Hindi-English code-switching; user must review transcript before sending it as a question |
| Local Hinglish rules | Implemented | Deterministic fallback for common demo intents; not a language model |
| RAG pipeline / vector search | Not deployed | No real policy corpus or production vector index is connected |
| Clause citations | Response model can be extended to carry citations; verified policy citations are not implemented | Do not show a claim-specific policy citation unless the backend retrieved it from a verified policy source |
| Guardrails | Partial demo controls | PII masking, separate consent flags, allow-listed tools, fictional claim data and no automatic claim submission; production auth and server-side controls remain required |

## Platform and integrations

| Technology | Status | Role |
|---|---|---|
| REST | Implemented client adapter for agent text and voice transcription | Targets `/v1/agent/chat` and `/v1/voice/transcribe` on the configured backend |
| WebSocket | Example event parser only | `ClaimUpdatesSocket` parses events from an already-authenticated channel; no live endpoint configured |
| Firebase | Not configured | Requires a Firebase project and `flutterfire configure`; add only the plugins actually needed |
| Partner APIs | Mock/demo data only | No live insurer, TPA, Account Aggregator, DigiLocker or payment integration |
| Analytics | Design target only | Track non-sensitive funnel events; never log OCR text, claim IDs, policy numbers or medical details |
| CI/CD | GitHub Actions starter included | `.github/workflows/flutter.yml` runs checks and a debug Android build after platform scaffolding is present |

## Exact data flow

1. User asks by text or presses the microphone.
2. For local voice mode, the device speech service recognizes text. Device providers may use their own network services according to device configuration.
3. For AI voice mode, the app records a short WAV and uploads it only after the separate cloud-voice consent is on and a backend URL is configured. The backend calls Gemini transcription; the user reviews the transcript before submitting it as a question.
4. For cloud text analysis, the app masks common PII patterns and calls the backend only when cloud-text consent is enabled. The backend masks again, asks Gemini for a structured intent/tool plan, enforces the allow-list in server code and asks Gemini to phrase the tool result.
5. The only tool data is the fabricated sample claim. No claim is submitted and no actual insurer is contacted.
6. Without a valid key/model response, the UI must show `LOCAL DEMO` or `OFFLINE FALLBACK`, never `GEMINI AGENT`.

Client-side masking is best-effort, not a complete privacy guarantee. The current backend is a hackathon prototype with no production authentication, rate limiting, tenant isolation, live policy retrieval or insurer integration. Do not send real claimant/medical documents to it.
