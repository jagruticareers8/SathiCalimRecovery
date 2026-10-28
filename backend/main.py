"""Sathi AI backend for a local/hackathon prototype.

This backend generates answers from the user's question and explicitly supplied,
PII-masked document text. It does not fabricate claim status and does not connect
to an insurer. Real insurer status/claim submission requires a provider-specific,
authenticated integration and is intentionally not simulated here.

Before accepting real customer data in production, add Firebase/OIDC authentication,
per-user authorization, rate limiting, audit controls, secret management, a retention
policy, and a reviewed privacy/security design. The local development endpoints are
not a production insurance service.
"""
from __future__ import annotations

import base64
import json
import logging
import os
import re
import time
from typing import Literal

from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from google import genai
from google.genai import types
from pydantic import BaseModel, Field

load_dotenv()
logger = logging.getLogger("uvicorn.error")

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "").strip()
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-3.8-flash").strip()
GEMINI_TRANSCRIPTION_MODEL = os.getenv("GEMINI_TRANSCRIPTION_MODEL", "gemini-3.5-transcribe").strip()
MAX_AUDIO_BYTES = 8 * 1024 * 1024
MAX_CONTEXT_CHARS = 18_000
# Set true only for a local, short-lived hackathon backend using synthetic or
# thoroughly redacted data. Production authentication is not implemented here.
ALLOW_UNAUTHENTICATED_DEV = os.getenv("SATHI_ALLOW_UNAUTHENTICATED_DEV", "false").strip().lower() == "true"


def safe_provider_error(exc: Exception) -> str:
    """Summarize provider errors without logging user prompts or API credentials."""
    message = str(exc)
    if GEMINI_API_KEY:
        message = message.replace(GEMINI_API_KEY, "[REDACTED_API_KEY]")
    message = re.sub(r"(?i)bearer\s+\S+", "Bearer [REDACTED]", message)
    return message[:800] or "(no provider message)"
# Google Gen AI SDK HttpOptions.timeout is configured in milliseconds.
# Bound model requests so the Flutter client can wait slightly longer and
# display a useful error if the model itself takes too long.
client = (
    genai.Client(
        api_key=GEMINI_API_KEY,
        http_options=types.HttpOptions(timeout=120_000),
    )
    if GEMINI_API_KEY
    else None
)

app = FastAPI(title="Sathi AI Assistant API", version="1.0.0")
allowed_origins = [item.strip() for item in os.getenv("SATHI_ALLOWED_ORIGINS", "*").split(",") if item.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization", "X-Sathi-Prototype"],
)


@app.middleware("http")
async def log_request_duration(request: Request, call_next):
    """Log timing/status only; never log questions, OCR, audio, or response text."""
    started = time.perf_counter()
    response = await call_next(request)
    elapsed = time.perf_counter() - started
    if request.url.path in {"/v1/agent/chat", "/v1/claims/analyze", "/v1/voice/transcribe"}:
        print(
            f"[sathi-timing] {request.method} {request.url.path} "
            f"status={response.status_code} duration_s={elapsed:.1f}"
        )
    return response


def mask_pii(text: str) -> str:
    """Best-effort additional masking. This does not replace a reviewed DLP layer."""
    text = re.sub(r"\b\d{4}[ -]?\d{4}[ -]?\d{4}\b", "[ID REDACTED]", text)
    text = re.sub(r"\b[A-Z]{5}\d{4}[A-Z]\b", "[PAN REDACTED]", text, flags=re.I)
    text = re.sub(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", "[EMAIL REDACTED]", text, flags=re.I)
    text = re.sub(r"(?:\+?91[\s-]?)?[6-9]\d{4}[\s-]?\d{5}\b", "[PHONE REDACTED]", text)
    return text


def clean_text(value: object, limit: int = 7000) -> str:
    if not isinstance(value, str):
        return ""
    return mask_pii(value.strip())[:limit]


def safe_history(history: list[dict[str, str]]) -> list[dict[str, str]]:
    """Bounded in-memory turns for follow-up questions; do not persist or log."""
    cleaned: list[dict[str, str]] = []
    for turn in history[-10:]:
        if not isinstance(turn, dict):
            continue
        role = str(turn.get("role", ""))
        content = clean_text(turn.get("content"), 1500)
        if role in ("user", "assistant") and content:
            cleaned.append({"role": role, "content": content})
    return cleaned


def safe_context(context: dict | None) -> dict:
    """Accept only supported, bounded, user-supplied context; never add sample data."""
    if not isinstance(context, dict):
        return {}
    safe: dict = {}
    raw_docs = context.get("documentTexts", [])
    docs: list[dict[str, str]] = []
    if isinstance(raw_docs, list):
        for item in raw_docs[:5]:
            if not isinstance(item, dict):
                continue
            title = clean_text(item.get("title"), 120)
            text = clean_text(item.get("text"), 6000)
            if text:
                docs.append({"title": title or "User-provided document", "text": text})
    if docs:
        safe["documentTexts"] = docs
    names = context.get("attachedDocumentNames", [])
    if isinstance(names, list):
        safe_names = [clean_text(name, 120) for name in names[:20] if isinstance(name, str)]
        safe_names = [name for name in safe_names if name]
        if safe_names:
            safe["attachedDocumentNames"] = safe_names
    # Only accept explicitly user-entered, non-authoritative fields. The prompt is
    # instructed not to present them as insurer-verified facts.
    for key in ("userEnteredClaimStatus", "userEnteredReason", "insurerName"):
        value = clean_text(context.get(key), 1200)
        if value:
            safe[key] = value
    encoded = json.dumps(safe, ensure_ascii=False)
    if len(encoded) > MAX_CONTEXT_CHARS:
        # Document texts are already bounded but truncate the total defensively.
        return {"contextNote": "Provided context was too large and was omitted; ask the user for a shorter excerpt."}
    return safe


Intent = Literal[
    "claim_status", "required_documents", "prepare_reconsideration",
    "explain_rejection", "document_review", "general_help"
]


class AgentRequest(BaseModel):
    message: str = Field(min_length=1, max_length=3000)
    language: Literal["hinglish", "hindi", "english"] = "hinglish"
    cloudConsent: bool = False
    claimContext: dict | None = None
    chatHistory: list[dict[str, str]] = Field(default_factory=list, max_length=12)


class AgentOutput(BaseModel):
    answer: str = Field(description="A useful, direct answer in the requested language. Do not invent personal claim facts.")
    intent: Intent
    actionIndex: int = Field(ge=1, le=4)
    actionLabel: str
    draft: str = Field(default="", description="A complete editable reconsideration draft only when the user asks for one; otherwise empty.")
    evidenceUsed: list[str] = Field(default_factory=list)
    notice: str = Field(description="Short data/source limitation, if relevant; do not claim a live insurer lookup happened.")


class ClaimAnalyzeRequest(BaseModel):
    cloudConsent: bool = False
    insurerReason: str = Field(default="", max_length=5000)
    uploadedDocuments: list[str] = Field(default_factory=list, max_length=30)
    requiredDocuments: list[str] = Field(default_factory=list, max_length=30)
    documentTexts: list[dict[str, str]] = Field(default_factory=list, max_length=5)


class ClaimAnalysisOutput(BaseModel):
    summary: str
    missingDocuments: list[str] = Field(default_factory=list)
    nextSteps: list[str] = Field(default_factory=list)
    disclaimer: str
    evidenceUsed: list[str] = Field(default_factory=list)


SYSTEM_PROMPT = """You are Sathi, a careful health-insurance claim support assistant for customers in India.
Help in the user's requested language: natural Roman-script Hinglish for 'hinglish',
simple Devanagari Hindi for 'hindi', and plain English for 'english'. Be practical,
kind, specific, and easy to understand. Answer the user's actual question, including
questions that do not match a predefined list.

TRUTH AND DATA RULES:
- You have NO live connection to any insurer, TPA, hospital, bank, credit bureau, or claim portal.
- Never invent a real claim status, claim ID, amount, policy clause, coverage decision, deadline,
  document receipt, insurer response, or claim-submission result.
- If asked for live claim status, say you cannot fetch it yet and explain that an authenticated
  insurer/TPA integration or the insurer's portal is needed. You may explain how the user can check.
- The supplied context, if any, is user-provided OCR or text. It is not verified by an insurer.
- If a decision letter excerpt is provided, explain only what that excerpt supports and name the
  document title as the source. If no letter text is available, ask the user to attach/read the
  letter or paste a redacted excerpt; do not guess why their claim was rejected.
- If asked for required documents and the policy/letter doesn't specify them, offer a general
  starter checklist but clearly say exact requirements vary by insurer, claim type, and policy.
- If asked to draft a reconsideration/appeal, create a usable editable draft grounded only in the
  user's facts. Use bracketed placeholders for missing facts. Do not invent policy clauses, dates,
  medical facts, amounts, or evidence. Do not state the draft has been sent.
- Explain eligibility, exclusions, waiting periods, co-pay, sub-limits, or medical necessity only
  when supported by user-provided wording. Encourage confirmation with the insurer for decisions.
- Do not ask for Aadhaar, PAN, full policy number, bank credentials, OTP, or unnecessary medical IDs.
- Never claim to have uploaded, submitted, escalated, or checked something unless an integrated
  external service actually did that. This service has no such integrations.
- Provide a short, concrete next step. Do not promise claim recovery or act as legal/medical advice.
Return a concise but complete answer, usually 3-8 short sentences. Longer drafts are allowed when
requested. EvidenceUsed must mention only supplied evidence, not invented citations.
"""


def detect_intent(message: str) -> Intent:
    text = message.casefold()
    if any(x in text for x in ["status", "track", "tracking", "kaha tak", "kahan tak", "claim kaha", "claim kahan", "स्टेटस", "स्थिति", "कहाँ तक", "कहां तक"]):
        return "claim_status"
    if any(x in text for x in ["draft", "appeal", "reconsider", "dobara review", "letter bana", "reply likh", "अपील", "ड्राफ्ट"]):
        return "prepare_reconsideration"
    if any(x in text for x in ["document", "docs", "bill", "paper", "kagaz", "कागज", "कागज़", "दस्तावेज", "डॉक्यूमेंट", "upload", "missing"]):
        return "required_documents"
    if any(x in text for x in ["reject", "rejected", "rejection", "denied", "deny", "partial", "partly", "short pay", "reason", "kyu", "kyun", "kyon", "क्यों", "अस्वीकृत", "रिजेक्ट"]):
        return "explain_rejection"
    if any(x in text for x in ["read this", "check this document", "analyse this", "analyze this", "is this letter", "document mein", "letter mein"]):
        return "document_review"
    return "general_help"


def action_for_intent(intent: Intent, language: str) -> tuple[int, str]:
    labels = {
        "claim_status": (3, "ट्रैकर देखें" if language == "hindi" else "Open tracker"),
        "required_documents": (2, "दस्तावेज़ देखें" if language == "hindi" else "Open documents"),
        "prepare_reconsideration": (4, "ड्राफ्ट देखें" if language == "hindi" else "Review draft"),
        "explain_rejection": (1, "क्लेम देखें" if language == "hindi" else "Review claim"),
        "document_review": (2, "दस्तावेज़ देखें" if language == "hindi" else "Open documents"),
        "general_help": (1, "क्लेम देखें" if language == "hindi" else "Review claim"),
    }
    return labels[intent]


def require_prototype_access() -> None:
    if not ALLOW_UNAUTHENTICATED_DEV:
        raise HTTPException(
            status_code=503,
            detail="This backend has no production authentication. For local synthetic-data development only, set SATHI_ALLOW_UNAUTHENTICATED_DEV=true. Do not expose that mode publicly or send real customer data.",
        )


def require_model() -> None:
    if client is None:
        raise HTTPException(
            status_code=503,
            detail="Live AI is not configured. Start the Sathi backend with GEMINI_API_KEY set in backend/.env. No demo answer was returned.",
        )


@app.get("/health")
def health() -> dict:
    return {
        "status": "ok",
        "modelConfigured": client is not None,
        "agentModel": GEMINI_MODEL if client else None,
        "transcriptionModelConfigured": client is not None,
        "transcriptionModel": GEMINI_TRANSCRIPTION_MODEL if client else None,
        "insurerIntegrationConfigured": False,
        "unauthenticatedDevelopmentMode": ALLOW_UNAUTHENTICATED_DEV,
        "mode": "live_gemini" if client else "ai_not_configured",
    }


@app.post("/v1/agent/chat")
def chat(request: AgentRequest) -> dict:
    require_prototype_access()
    if not request.cloudConsent:
        raise HTTPException(status_code=403, detail="Cloud analysis consent is required. Enable it in How Sathi works before sending this question.")
    require_model()
    message = clean_text(request.message, 3000)
    if not message:
        raise HTTPException(status_code=400, detail="Message is empty after validation.")
    context = safe_context(request.claimContext)
    history = safe_history(request.chatHistory)
    intent = detect_intent(message)
    action_index, action_label = action_for_intent(intent, request.language)
    prompt = (
        f"User language preference: {request.language}.\n"
        f"Recent conversation turns (PII masked; use only for conversational continuity): {json.dumps(history, ensure_ascii=False)}\n"
        f"Detected topic for navigation only: {intent}.\n"
        f"User's actual question (PII masked): {message}\n\n"
        f"User-provided document/context excerpts (PII masked; may be empty): {json.dumps(context, ensure_ascii=False)}\n\n"
        "Answer the actual question. Use OCR excerpts as evidence only when relevant. If asked about live status, "
        "state there is no insurer/TPA integration and no status lookup was performed. Do not use or invent any sample claim. "
        "For unknown/absent details, say what input is missing and how the customer can supply it safely. "
        "If the user asks for an appeal/reconsideration letter, put the complete editable letter in the JSON 'draft' field, "
        "and put a short explanation/next step in 'answer'. Otherwise set 'draft' to an empty string. "
        f"Return intent={intent}, actionIndex={action_index}, actionLabel={action_label}."
    )
    try:
        result = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=prompt,
            config=types.GenerateContentConfig(
                system_instruction=SYSTEM_PROMPT,
                response_mime_type="application/json",
                response_schema=AgentOutput,
                temperature=0.2,
                max_output_tokens=1600,
            ),
        )
        output_text = (result.text or "").strip()
        if not output_text:
            raise ValueError("The model returned an empty response.")
        output = AgentOutput.model_validate_json(output_text)
        # Do not trust the model to change which application screen a user opens.
        output.intent = intent
        output.actionIndex = action_index
        output.actionLabel = action_label
        output.notice = (output.notice or "").strip()
        return {
            **output.model_dump(),
            "mode": "gemini_agent",
            "model": GEMINI_MODEL,
            "notice": output.notice or "AI-generated from your question and any provided document text. No insurer portal was queried.",
        }
    except HTTPException:
        raise
    except Exception as exc:
        # Log provider error metadata only, never the user's prompt, OCR, or response.
        logger.error("Sathi Gemini chat failed (%s): %s", type(exc).__name__, safe_provider_error(exc))
        raise HTTPException(status_code=502, detail=f"Live AI request failed ({type(exc).__name__}). See backend terminal for sanitized provider error details.") from exc


@app.post("/v1/claims/analyze")
def analyze_claim(request: ClaimAnalyzeRequest) -> dict:
    require_prototype_access()
    if not request.cloudConsent:
        raise HTTPException(status_code=403, detail="Cloud analysis consent is required before analysing claim text.")
    require_model()
    reason = clean_text(request.insurerReason, 5000)
    uploaded = [clean_text(x, 120) for x in request.uploadedDocuments[:30] if clean_text(x, 120)]
    requested = [clean_text(x, 120) for x in request.requiredDocuments[:30] if clean_text(x, 120)]
    docs = []
    for item in request.documentTexts[:5]:
        title = clean_text(item.get("title", "User-provided document"), 120)
        text = clean_text(item.get("text", ""), 6000)
        if text:
            docs.append({"title": title or "User-provided document", "text": text})
    context = {
        "insurerReasonTextProvidedByUser": reason,
        "userAttachedDocumentNames": uploaded,
        "userProvidedChecklist": requested,
        "userProvidedDocumentText": docs,
    }
    prompt = (
            "Review this customer-provided health insurance claim information. It may be incomplete and is not verified by the insurer. "
            "Summarise what the text explicitly states; identify only document gaps supported by the supplied letter/checklist; "
            "if there is no decision letter text or policy text, clearly say the analysis is incomplete and do not invent missing documents. "
            "Provide practical next steps and a clear non-legal/non-insurer-decision disclaimer. Do not infer claim status or success likelihood. "
            "Return the requested JSON fields: summary, missingDocuments, nextSteps, disclaimer, evidenceUsed.\n\n"
            + json.dumps(context, ensure_ascii=False)
    )
    try:
        result = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=prompt,
            config=types.GenerateContentConfig(
                system_instruction=SYSTEM_PROMPT,
                response_mime_type="application/json",
                response_schema=ClaimAnalysisOutput,
                temperature=0.2,
                max_output_tokens=1600,
            ),
        )
        output_text = (result.text or "").strip()
        if not output_text:
            raise ValueError("The model returned an empty response.")
        output = ClaimAnalysisOutput.model_validate_json(output_text)
        return {**output.model_dump(), "mode": "gemini_agent", "model": GEMINI_MODEL}
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Sathi Gemini claim analysis failed (%s): %s", type(exc).__name__, safe_provider_error(exc))
        raise HTTPException(status_code=502, detail=f"Live claim analysis failed ({type(exc).__name__}). See backend terminal for sanitized provider error details.") from exc


@app.post("/v1/voice/transcribe")
async def transcribe_voice(
        audio: UploadFile = File(...),
        language_hint: str = Form(default="hinglish"),
        cloudConsent: bool = Form(default=False),
) -> dict:
    require_prototype_access()
    if not cloudConsent:
        raise HTTPException(status_code=403, detail="Cloud voice consent is required before sending audio for transcription.")
    require_model()
    if audio.content_type not in ("audio/wav", "application/octet-stream", "audio/x-wav"):
        if not (audio.filename or "").lower().endswith(".wav"):
            raise HTTPException(status_code=415, detail="Please send a WAV voice recording.")
    data = await audio.read(MAX_AUDIO_BYTES + 1)
    if len(data) > MAX_AUDIO_BYTES:
        raise HTTPException(status_code=413, detail="Keep voice recordings under 8 MB.")
    if not data:
        raise HTTPException(status_code=400, detail="The voice recording is empty.")
    prompt = (
            "Transcribe this short Indian speech recording verbatim. The speaker may code-switch between Hindi and English (Hinglish), "
            "including English financial/insurance words inside Hindi sentences. Preserve the words, Roman-script English tokens, and meaning; "
            "do not translate, summarise, answer, or guess missing words. Return only the transcript. Language hint: " + language_hint[:30]
    )
    try:
        response = client.interactions.create(
            model=GEMINI_TRANSCRIPTION_MODEL,
            input=[
                {"type": "text", "text": prompt},
                {"type": "audio", "data": base64.b64encode(data).decode("ascii"), "mime_type": "audio/wav"},
            ],
        )
        transcript = (response.output_text or "").strip()
        if not transcript:
            raise ValueError("empty transcript")
        return {"text": transcript, "mode": "gemini_transcribe", "model": GEMINI_TRANSCRIPTION_MODEL}
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Sathi Gemini voice transcription failed (%s): %s", type(exc).__name__, safe_provider_error(exc))
        raise HTTPException(status_code=502, detail=f"Voice transcription failed ({type(exc).__name__}). See backend terminal for sanitized provider error details.") from exc
