# Sathi implementation status

| Capability | Status | Notes |
|---|---|---|
| Flutter UI / BLoC | Implemented | Home, Claim, Documents, Tracker, Draft, Assistant and Privacy screens. No seeded claim amounts/status/rejection reason. |
| Encrypted local vault | Implemented | AES-GCM encrypted attachments and encrypted JSON snapshot; vault key stored via platform secure storage. |
| On-device OCR | Implemented for supported images | Google ML Kit Latin script; PDF OCR is not bundled. OCR text is masked and saved locally. |
| Local document Q&A | Implemented as retrieval/rules | Keyword/sentence retrieval over local OCR text, not local generative AI. |
| Offline insurance FAQ | Implemented | Fixed general definitions/checklists in English, Hindi and Roman Hinglish. |
| Editable reconsideration draft | Implemented locally | Template grounded in local excerpts/placeholders; user must review and submit manually. |
| Live general-information AI | Implemented behind backend config | Gemini 3.6 Flash default, only after local lookup and explicit per-question confirmation. Private query/document text is not sent. |
| Hinglish device voice | Available | Uses OS speech service. Accuracy and installed locales vary. |
| Cloud voice transcription | Optional | Sends short audio to Gemini only after voice consent, General-information mode and per-recording confirmation. |
| Live claim-text cloud analysis | Disabled | `/v1/claims/analyze` returns HTTP 410 to protect private claim text. |
| Live insurer/TPA status | Not implemented | Requires authenticated partner API. |
| Claim submission/resubmission/escalation | Not implemented | The app prepares/copies a draft only. |
| Verified policy RAG/vector search | Not implemented | No approved policy corpus, retrieval index or citations connected. |
| On-device generative Gemma | Not bundled | Offline mode uses retrieval, rules and FAQ, not a generative LLM. |
| Production authentication/operations | Not implemented | No Firebase/OIDC login, tenant isolation, production rate limits, audit framework or security review. |

## Privacy boundary

Sathi checks local OCR/document text and the offline FAQ first. An obvious personal/claim-specific question remains local. When an unanswered generic question may go online, the user sees the exact text and confirms it. The HTTP adapter sends only the current general question; the backend rejects non-empty context/history and obvious personal queries. Cloud voice is a separate opt-in because the audio itself leaves the device.

A Gemini answer is not insurer verification. Never claim that a claim status was checked, a letter was submitted, a policy clause is verified, or recovery is guaranteed unless a future authenticated partner integration actually performs that operation.
