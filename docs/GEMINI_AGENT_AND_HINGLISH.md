# Gemini agent and Hinglish voice: implementation details

## Actual model invocation

`backend/main.py` reads `GEMINI_API_KEY` from the backend environment. The Flutter binary never contains this key. If the key is absent, `/v1/agent/chat` returns `mode: local_rules`; it does not pretend the model ran.

When configured, `/v1/agent/chat` uses a two-step Gemini model process:

1. Planner call uses a Pydantic JSON schema to choose an intent and a single tool name from a strict allow-list.
2. Server code executes that tool against fictional demo data.
3. A second Gemini call turns the tool result into a simple answer in Hinglish (Roman script), Hindi (Devanagari), or English.

Available tools: `get_claim_status`, `get_required_documents`, `explain_claim_reason`, `prepare_reconsideration_draft`, and `none`. No tool submits an appeal or contacts an insurer.

## Actual Hinglish voice path

The assistant defaults to Hinglish. Local mode chooses the available `hi-IN`/`hi_IN` speech locale first, with fallback to an available Hindi locale and then English. Locale ids are normalized so `hi-IN` and `hi_IN` don't fail an exact string comparison. The local intent router recognises frequently used Roman Hinglish and Devanagari terms such as `claim reject kyun hua`, `kaun se documents chahiye`, `claim ka status kya hai`, `रिजेक्ट`, `दस्तावेज`, and `स्टेटस`.

Device speech engines do not guarantee accurate code-switching across all devices. For better mixed Hindi-English transcription, the opt-in cloud route records a short WAV and calls `/v1/voice/transcribe`; the backend invokes `gemini-3.5-transcribe` with explicit instructions to preserve Hindi-English code-switching. The user can review the transcript before asking the agent to act on it.

## Test from a terminal

```bash
curl http://127.0.0.1:8000/health
curl -X POST http://127.0.0.1:8000/v1/agent/chat \
  -H 'Content-Type: application/json' \
  -d '{"message":"Mera claim reject ho gaya, ab kya karu?","language":"hinglish"}'
```

To test the microphone, use a real Android/iOS device or emulator with microphone permission and a supported recognition service. To test the AI voice route, enable the separate voice consent switch, configure the backend URL, set `GEMINI_API_KEY`, and tap the microphone to start/stop the recording.

## Limits

The cloud models are not an on-device Gemma runtime. The claim tools use the fabricated sample claim. Policy RAG, verified clause citations, real insurer APIs, identity checks, backend authentication and production access control must be built before any real claimant data can be used.
