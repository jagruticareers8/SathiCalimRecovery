# Sathi Final Product Specification — Local-First Claim Recovery

**Project:** SathiCalimRecovery `dev_v3`  
**Track:** Paytm Build for India AI Hackathon, Track 2 — AI-Powered Financial Journeys  
**Primary journey:** Understand a rejected/partly approved health-insurance claim and prepare an evidence-backed next step.

## 1. Product principles

1. **Local first:** Read the user's saved claim text and local guide before considering online information.
2. **No invented claim facts:** Never seed claim IDs, insurer names, claim amounts, approval values, deadlines or live status. If the document does not show a value, say it was not found.
3. **Privacy boundary:** Private claim questions, documents, OCR text, embeddings and local chat context must not be sent to Gemini. Online Gemini is only a separate general-information route and requires saved consent plus confirmation of the exact question.
4. **Simple UI:** One main flow: add the decision letter → read/paste its text → ask Sathi → review a draft. Secondary documents are optional unless the insurer asks for them.
5. **Honest status:** The activity tracker records local actions only. It does not imply a claim was submitted or the insurer updated it.
6. **Failure should be visible:** A model download, OCR run or AI request that fails must show a retryable error and must not quietly return a canned answer as if it were model-generated.

## 2. Technology and responsibilities

| Component | Responsibilities | Boundary / status |
|---|---|---|
| Flutter + BLoC | App UI, state, local journey | Implemented in project |
| On-device OCR | Extract text from supported images using ML Kit Latin + Devanagari recognizers | Runs on device; PDFs currently require copy/paste of text |
| Encrypted local storage | AES-GCM vault for app-owned attachment copies, OCR text, drafts, activity and embedding cache; key stored using platform secure storage | App-private encrypted copy; does not move/delete the original in Photos/Downloads |
| Local document retrieval | Chunks OCR text, lexical/semantic ranks evidence and returns source titles | Private queries never require a network call |
| On-device LLM | Qwen3 0.6B generates a grounded response using retrieved local passages; EmbeddingGemma provides semantic vectors | Optional; user installs models. It is not fine-tuned on user's data. Requires supported runtime/device |
| Gemini API | Generic background information only when local answer/FAQ is insufficient, consent is on, the question is not personal and the user confirms the exact question | Server accepts no claim context, OCR or chat history; credentials stay on backend |
| Voice input | Device speech recognition by default; optional cloud Hinglish transcription in General Information mode | OS speech services may have their own network behaviour; cloud audio upload has separate consent and confirmation |
| Insurer integration | Live claim lookup, claim submission, live claim status | **Not implemented.** The app must never imply otherwise. |

## 3. User flow

### Step A — Add decision letter
- User selects a document image or file.
- The app creates an encrypted app-private copy before displaying it as locally saved.
- Other document slots are optional and are not presented as universal requirements.
- The user is told that files are not submitted to the insurer from this app.

### Step B — Extract text locally
- For image files, run OCR on device with Latin and Devanagari recognizers.
- PII masking is best-effort and should not be described as perfect anonymisation.
- For PDF files, the user copies the relevant text in a PDF viewer and pastes it into Sathi. The current prototype does not run native PDF OCR.
- Show the extracted text so users can review it before asking questions.

### Step C — Ask Sathi
- Private mode runs fact extraction/local FAQ/RAG on-device only.
- RAG retrieves passages from the user's saved OCR and the bundled general guide. If the local LLM+embedder are not installed, local deterministic extraction/FAQ still works but open-ended generation is unavailable.
- If evidence is insufficient, say what information is missing. Do not answer from unrelated snippets.
- Online mode may only send a separate general question when enabled and confirmed. Never attach filenames, documents, OCR, claim identifiers or chat history.

### Step D — Draft and next steps
- A reconsideration letter is editable and contains placeholders for missing facts.
- It is not submitted to the insurer by Sathi.
- Timeline events are local user actions. No fake live status or official acknowledgement is displayed.

## 4. UI rules to avoid confusion

- Home presents a single clear start action and the Sathi assistant; duplicated claim summaries are removed.
- Documents screen says “Start with decision letter.” It does not report a percentage complete against all optional document categories.
- The global FilledButton and OutlinedButton minimum widths are finite to avoid `BoxConstraints forces an infinite width` inside `Row`/unconstrained layouts.
- Model settings clearly distinguish “not installed,” “installing,” and “installed”. No model is reported ready until both inference and embedding models are confirmed installed.
- Model download needs internet once and roughly 500 MB plus runtime overhead; local inference after installation works without Gemini/network.
- On-device LiteRT-LM support is limited to compatible devices (Android API 30+ arm64-v8a; supported iOS builds iOS 15.5+ due to Devanagari OCR pod). An x86_64 emulator may not support the local LLM runtime.

## 5. Error states

| Event | Required behaviour |
|---|---|
| OCR finds no text | Explain image quality may be poor; allow re-attach/paste text |
| Local RAG models not installed | Use local facts/FAQ and explain open-ended offline AI needs model installation |
| Model is unsupported or fails | Show a local model failure; do not silently send the question/documents to cloud |
| General Gemini request fails | Explain online request failed; retain local data and let the user retry |
| No matching local evidence | Say the answer is not in saved text; do not guess |
| No insurer API | Clearly say that live status/submission is unavailable |
| Local vault fails to decrypt | Do not overwrite vault with a new key; show recovery/reset guidance |
| Speech recogniser returns no match | Clear session state and let user retry/type; do not lock microphone button |

## 6. Acceptance checklist

Run on a supported Android arm64 phone, plus an Android emulator for layout smoke tests:

- [ ] `flutter pub get` succeeds.
- [ ] `flutter analyze` completes without errors.
- [ ] `flutter test` passes, including `app_theme_layout_test.dart`.
- [ ] Home screen opens without overflow/infinite-width errors.
- [ ] First-start state has no invented amount, insurer, claim ID, or status.
- [ ] Decision letter can be attached, encrypted, re-opened through OCR, and saved text survives app restart.
- [ ] English/Roman Hinglish image OCR works; Hindi-script OCR works after native dependencies are installed.
- [ ] PDF text can be pasted and saved locally.
- [ ] Without local model installation, the UI clearly says local generation is unavailable but local facts/FAQ work.
- [ ] After downloading both models, an offline question uses local retrieval + local inference with Wi-Fi disabled.
- [ ] Private question produces no `/v1/agent/chat` network request.
- [ ] A general online question triggers confirmation and sends only the current question, with no claim context/history.
- [ ] A cloud/API failure does not return a seeded demo answer.
- [ ] Draft remains editable and is not marked submitted until the user records an external action.
- [ ] Tracker never claims a live insurer update without a real integration.
- [ ] Camera, photo selection, microphone, and delete-local-data paths are tested on a real device.

## 7. Security and scope caveats

This is a hackathon MVP, not a production health-data service. PII masking is heuristic, local-device security depends on OS security and app permissions, and app-private encrypted copies do not implement production backups or identity management. Use synthetic data during the hackathon. The unauthenticated FastAPI development mode must stay on a trusted local network only and must never be deployed publicly. No claim recovery outcome is guaranteed.
