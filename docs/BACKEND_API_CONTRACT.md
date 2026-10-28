# Sathi backend API contract

This archive now includes a runnable FastAPI demo backend in `backend/main.py`. The endpoints below are implemented. They use a fictional sample claim only and are not connected to any insurer. The remaining sections describe future production endpoints, not features that are already live.

## Implemented: `GET /health`

Reports whether `GEMINI_API_KEY` is present in the backend environment and which model IDs are configured. It does not prove that the key is valid or that the account has access to those models; use a request to `/v1/agent/chat` to smoke-test actual access.

## Implemented: `POST /v1/agent/chat`

Example request:

```json
{
  "message": "Mera claim reject ho gaya, ab kya karu?",
  "language": "hinglish",
  "claimContext": {
    "claimId": "STH-26-10482",
    "status": "Partially approved",
    "requestedAmount": 68500,
    "approvedAmount": 42000,
    "unpaidAmount": 26500,
    "statedReason": "The sample decision letter refers to a missing itemised hospital bill and discharge summary.",
    "requiredDocuments": ["Itemised hospital bill", "Discharge summary"]
  }
}
```

When `GEMINI_API_KEY` is configured, the backend requests a structured intent/tool plan from Gemini, applies a server-side allow-list and runs only a demo helper, then asks Gemini to phrase the result. If the key is absent, deterministic local rules run and the response reports `mode: local_rules`. Live model access should be tested because a key may be invalid, restricted or out of quota.

Allowed demo helpers: `get_claim_status`, `get_required_documents`, `explain_claim_reason`, `prepare_reconsideration_draft`, and `none`. They only read fictional data or create an editable draft. No helper submits a claim or contacts an insurer.

## Implemented: `POST /v1/voice/transcribe`

Multipart request with `audio` (`.wav`, up to 8 MB) and optional `language_hint=hinglish`. After separate user consent in the app, the backend calls Gemini 3.5 Transcribe with a prompt to preserve Hindi-English code-switching. The app shows the transcript for review before it sends the text to `/v1/agent/chat`.

The application does not intentionally save recordings or log transcripts, but the HTTP framework may temporarily buffer an upload while processing it. Do not use real health, identity or claim data with this demo backend.

## Future production endpoints (not implemented)

- `POST /v1/consents` — record purpose-specific consent, expiry and revocation.
- `POST /v1/claims` — create a case after authentication and consent.
- `POST /v1/claims/{claimId}/documents` — upload validated files using short-lived upload credentials; scan files and record document metadata.
- `POST /v1/claims/{claimId}/analyze` — run OCR and policy-grounded analysis server-side. Return evidence references and confidence, not an ungrounded approval prediction.
- `POST /v1/claims/{claimId}/drafts` — save a draft version without submitting it.
- `GET /v1/claims/{claimId}/events` — fetch verified status events.
- `POST /v1/claims/{claimId}/feedback` — collect user corrections and usefulness ratings.

## Security requirements before production

1. Authenticate each request and authorise every claim/document by customer and case. The included demo backend has no authentication, rate limiting or tenant isolation.
2. Validate file MIME type, extension, size and content; use malware scanning and encrypted storage.
3. Collect explicit, purpose-specific consent before accessing or transferring sensitive data; support revocation and deletion rules. A client preference is not a legal consent record by itself.
4. Minimise PII sent to the model, keep secrets on the backend, redact application logs and set retention limits.
5. Ground every claim explanation in relevant policy/decision text, show source excerpts to the user, and label uncertain points. This demo has no RAG/vector store or verified clause citations.
6. Require customer review and explicit confirmation before any submission or irreversible action.
7. Never let an LLM determine final coverage, accept/reject claims, or invent deadlines or policy clauses.
