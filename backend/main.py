"""Sathi demo agent backend.

This is a local hackathon backend, not production-ready insurance infrastructure.
It calls Gemini only when GEMINI_API_KEY is configured; otherwise text chat returns
clearly labelled deterministic demo guidance. The application does not intentionally
persist audio or log transcripts, but the HTTP upload framework may temporarily
buffer an uploaded file. Do not send real claimant/medical data to this demo.
"""
from __future__ import annotations

import base64
import json
import os
import re
from typing import Literal

from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from google import genai
from pydantic import BaseModel, Field

load_dotenv()

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "").strip()
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-3.8-flash").strip()
GEMINI_TRANSCRIPTION_MODEL = os.getenv("GEMINI_TRANSCRIPTION_MODEL", "gemini-3.5-transcribe").strip()
MAX_AUDIO_BYTES = 8 * 1024 * 1024
client = genai.Client(api_key=GEMINI_API_KEY) if GEMINI_API_KEY else None

app = FastAPI(title="Sathi AI Agent API", version="0.2.0")
allowed_origins = [item.strip() for item in os.getenv("SATHI_ALLOWED_ORIGINS", "*").split(",") if item.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization"],
)

DEMO_CLAIM = {
    "claimId": "STH-26-10482",
    "status": "Partially approved",
    "requestedAmount": 68500,
    "approvedAmount": 42000,
    "unpaidAmount": 26500,
    "statedReason": "The sample decision letter says the itemised hospital bill and discharge summary were not attached to the submitted claim.",
    "requiredDocuments": ["Itemised hospital bill", "Discharge summary"],
}


def mask_pii(text: str) -> str:
    """Basic second-layer masking. This is not a complete DLP system."""
    text = re.sub(r"\b\d{4}[ -]?\d{4}[ -]?\d{4}\b", "[ID REDACTED]", text)
    text = re.sub(r"\b[A-Z]{5}\d{4}[A-Z]\b", "[PAN REDACTED]", text, flags=re.I)
    text = re.sub(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", "[EMAIL REDACTED]", text, flags=re.I)
    text = re.sub(r"(?:\+?91[\s-]?)?[6-9]\d{4}[\s-]?\d{5}\b", "[PHONE REDACTED]", text)
    return text


def detect_intent(message: str) -> str:
    text = message.lower()
    status_terms = ["status", "track", "tracking", "claim kaha", "claim kahan", "kaha tak", "kahan tak", "कहाँ तक", "कहां तक", "स्थिति", "स्टेटस", "अपडेट"]
    docs_terms = ["document", "docs", "bill", "paper", "upload", "photo", "kagaz", "kagaz", "kya chahiye", "दस्तावेज", "कागज", "कागज़", "बिल", "फोटो", "डिस्चार्ज", "itemised", "itemized"]
    draft_terms = ["draft", "appeal", "reconsider", "dobara review", "phir se review", "letter bana", "अपील", "ड्राफ्ट", "शिकायत पत्र"]
    reject_terms = ["reject", "rejected", "rejection", "deny", "denied", "partial", "partly", "short pay", "kam paisa", "kam mila", "paisa kam", "kyu reject", "kyun reject", "why was", "why did", "reason", "रिजेक्ट", "अस्वीकृत", "कम मिला", "पैसे कम", "क्यों रिजेक्ट"]
    if any(term in text for term in status_terms):
        return "claim_status"
    if any(term in text for term in docs_terms):
        return "required_documents"
    if any(term in text for term in draft_terms):
        return "prepare_reconsideration"
    if any(term in text for term in reject_terms):
        return "explain_rejection"
    return "general_help"


def action_for_intent(intent: str, language: str) -> tuple[int, str]:
    labels = {
        "claim_status": (3, "क्लेम ट्रैकर खोलें" if language == "hindi" else "Open claim tracker"),
        "required_documents": (2, "दस्तावेज़ खोलें" if language == "hindi" else "Open documents"),
        "prepare_reconsideration": (4, "ड्राफ्ट देखें" if language == "hindi" else "Review draft"),
        "explain_rejection": (1, "क्लेम की समीक्षा करें" if language == "hindi" else "Review my claim"),
        "general_help": (1, "क्लेम की समीक्षा करें" if language == "hindi" else "Review my claim"),
    }
    return labels.get(intent, labels["general_help"])


def local_answer(message: str, language: str) -> dict:
    intent = detect_intent(message)
    if language == "hindi":
        answers = {
            "claim_status": "डेमो में क्लेम आंशिक रूप से मंजूर है: ₹68,500 मांगे गए, ₹42,000 मंजूर हुए और ₹26,500 अभी मंजूर नहीं हुए हैं। यह बीमा कंपनी का लाइव स्टेटस नहीं है।",
            "required_documents": "डेमो निर्णय पत्र में अस्पताल का मदवार बिल और डिस्चार्ज समरी का ज़िक्र है। केवल वही दस्तावेज़ जोड़ें जो वास्तव में आपके पास हैं और असली पत्र से पुष्टि करें।",
            "prepare_reconsideration": "मैं समीक्षा के लिए संपादन योग्य अनुरोध तैयार करने में मदद कर सकता हूँ। सभी तथ्यों और दस्तावेज़ों की जाँच करें। Sathi स्वयं दावा जमा नहीं करता।",
            "explain_rejection": "डेमो पत्र के अनुसार अस्पताल का मदवार बिल और डिस्चार्ज समरी जमा नहीं हुए थे। यह राशि मंजूर न होने से संबंधित हो सकता है, लेकिन सही कारण और कवरेज की पुष्टि बीमा कंपनी ही कर सकती है।",
            "general_help": "आप पूछ सकते हैं: क्लेम का स्टेटस क्या है, कौन से दस्तावेज़ चाहिए, क्लेम क्यों अस्वीकृत हुआ, या समीक्षा का ड्राफ्ट कैसे बनाएँ।",
        }
    elif language == "english":
        answers = {
            "claim_status": "The demo claim is partially approved: ₹68,500 requested, ₹42,000 approved and ₹26,500 not yet approved. This is not a live insurer status.",
            "required_documents": "The sample decision letter mentions an itemised hospital bill and discharge summary. Attach only documents you actually have and verify the list against the real letter.",
            "prepare_reconsideration": "I can help prepare an editable reconsideration request. Verify every statement and supporting document. Sathi does not submit a claim for you.",
            "explain_rejection": "The sample decision letter says the itemised hospital bill and discharge summary were not attached. This may be relevant to the amount not approved, but only the insurer can confirm the exact reason and coverage.",
            "general_help": "Ask: what is my claim status, which documents are needed, why was my claim rejected, or help me draft a reconsideration request.",
        }
    else:
        answers = {
            "claim_status": "Demo mein claim partially approved hai: ₹68,500 request hue the, ₹42,000 approve hue aur ₹26,500 abhi approve nahi hue. Yeh insurer ka live status nahi hai.",
            "required_documents": "Sample decision letter mein itemised hospital bill aur discharge summary ka zikr hai. Sirf wahi documents attach karein jo aapke paas sach mein hain; real letter se verify karein.",
            "prepare_reconsideration": "Main editable reconsideration draft banane mein help kar sakta hoon. Har fact aur document verify karein. Sathi claim khud submit nahi karta.",
            "explain_rejection": "Sample letter ke mutabik itemised hospital bill aur discharge summary attach nahi hue the. Yeh amount approve na hone se relevant ho sakta hai, lekin exact reason aur coverage insurer hi confirm kar sakta hai.",
            "general_help": "Aap Hinglish mein pooch sakte hain: claim status kya hai, kaun se documents chahiye, claim reject kyun hua, ya reconsideration draft bana do.",
        }
    action_index, action_label = action_for_intent(intent, language)
    return {
        "answer": answers[intent],
        "intent": intent,
        "actionIndex": action_index,
        "actionLabel": action_label,
        "mode": "local_rules",
        "model": "",
        "notice": "Gemini API key is not configured; deterministic demo guidance was used.",
    }


class AgentRequest(BaseModel):
    message: str = Field(min_length=1, max_length=3000)
    language: Literal["hinglish", "hindi", "english"] = "hinglish"
    claimContext: dict | None = None


class AgentPlan(BaseModel):
    intent: Literal["claim_status", "required_documents", "prepare_reconsideration", "explain_rejection", "general_help"]
    tool: Literal["get_claim_status", "get_required_documents", "explain_claim_reason", "prepare_reconsideration_draft", "none"]
    reason: str = Field(description="A short internal routing rationale; do not expose chain-of-thought to the user.")


def execute_demo_tool(tool_name: str) -> dict:
    """Allow-listed demo tools. These never call an insurer and never submit a claim."""
    if tool_name == "get_claim_status":
        return {"tool": tool_name, "data": DEMO_CLAIM}
    if tool_name == "get_required_documents":
        return {"tool": tool_name, "requiredDocuments": DEMO_CLAIM["requiredDocuments"], "note": "List copied from fabricated sample claim data, not a real policy rule."}
    if tool_name == "explain_claim_reason":
        return {"tool": tool_name, "statedReason": DEMO_CLAIM["statedReason"], "warning": "This is an example insurer reason. No real policy clause has been retrieved or verified."}
    if tool_name == "prepare_reconsideration_draft":
        return {
            "tool": tool_name,
            "draft": "Subject: Request for review of health claim\n\nDear Claims Team,\n\nPlease review the decision on my health claim. Kindly confirm the documents or policy terms relied upon for the amount not approved. I will provide supporting documents that are available and relevant. Please share the next steps and a reference number for this request.\n\nRegards,\n[Policyholder name]\n[Claim reference]",
            "warning": "Draft only. It has not been sent and requires the policyholder to verify every statement.",
        }
    return {"tool": "none", "note": "No claim tool needed."}


@app.get("/health")
def health() -> dict:
    return {
        "status": "ok",
        "modelConfigured": client is not None,
        "agentModel": GEMINI_MODEL if client else None,
        "transcriptionModelConfigured": client is not None,
        "transcriptionModel": GEMINI_TRANSCRIPTION_MODEL if client else None,
        "mode": "gemini_agent" if client else "local_rules_only",
    }


@app.post("/v1/agent/chat")
def chat(request: AgentRequest) -> dict:
    message = mask_pii(request.message).strip()
    if not message:
        raise HTTPException(status_code=400, detail="Message is empty after validation.")
    if client is None:
        result = local_answer(message, request.language)
        result["notice"] = "Gemini API key is missing on the backend; no language model ran. Local demo rules were used."
        return result

    context = request.claimContext or DEMO_CLAIM
    try:
        plan_prompt = f"""You are the planner for Sathi, a health-insurance claim-recovery companion.
Choose exactly one intent and one allowed demo tool. Do not make up policy wording, sources, claim state, coverage, legal advice, or likelihood of recovery.
Tools are READ-ONLY except prepare_reconsideration_draft, which creates editable text only and never submits anything.
Available demo context (fictional): {json.dumps(context, ensure_ascii=False)}
User language preference: {request.language}. User message (PII masked): {message}
Mapping:
- status/tracker questions -> intent claim_status, tool get_claim_status
- requested papers/bill/document questions -> intent required_documents, tool get_required_documents
- ask to write appeal/reconsideration -> intent prepare_reconsideration, tool prepare_reconsideration_draft
- rejection/partial amount/why questions -> intent explain_rejection, tool explain_claim_reason
- otherwise -> general_help, tool none
Return only the structured plan. Do not put internal reasoning into user-visible text."""
        plan_result = client.interactions.create(
            model=GEMINI_MODEL,
            input=plan_prompt,
            response_format={
                "type": "text",
                "mime_type": "application/json",
                "schema": AgentPlan.model_json_schema(),
            },
        )
        plan = AgentPlan.model_validate_json(plan_result.output_text)
        # The model proposes a tool, but the server enforces intent/tool pairing.
        # Never execute an arbitrary name or a tool inconsistent with the selected intent.
        expected_tools = {
            "claim_status": "get_claim_status",
            "required_documents": "get_required_documents",
            "prepare_reconsideration": "prepare_reconsideration_draft",
            "explain_rejection": "explain_claim_reason",
            "general_help": "none",
        }
        safe_tool = expected_tools[plan.intent]
        tool_result = execute_demo_tool(safe_tool)
        final_prompt = f"""You are Sathi, a compassionate helper for the fictional demo claim. Reply in {request.language}: for hinglish use natural Roman-script Hinglish, for hindi use simple Devanagari Hindi, for english use simple English.
Answer the user's actual question in 2-5 short sentences. Use only the tool result below. Do not invent policy clauses/citations, claim status updates or deadlines. Never guarantee recovery. Clearly say status and numbers are demo data. If the tool returns a draft, present it as editable only. End with one practical next step.
User message: {message}
Selected intent: {plan.intent}
Tool result: {json.dumps(tool_result, ensure_ascii=False)}"""
        final_result = client.interactions.create(model=GEMINI_MODEL, input=final_prompt)
        action_index, action_label = action_for_intent(plan.intent, request.language)
        answer = (final_result.output_text or "").strip()
        if not answer:
            raise ValueError("The model returned an empty answer.")
        return {
            "answer": answer,
            "intent": plan.intent,
            "actionIndex": action_index,
            "actionLabel": action_label,
            "mode": "gemini_agent",
            "model": GEMINI_MODEL,
            "tool": safe_tool,
            "toolResult": tool_result,
            "notice": "Gemini selected an allow-listed demo tool. No insurer API is connected and no claim was submitted.",
        }
    except Exception as exc:
        # Do not disclose prompts or user text in logs/responses.
        raise HTTPException(status_code=502, detail=f"Gemini agent request failed ({type(exc).__name__}). Check backend model access and logs without logging user text.") from exc


@app.post("/v1/voice/transcribe")
async def transcribe_voice(
    audio: UploadFile = File(...),
    language_hint: str = Form(default="hinglish"),
) -> dict:
    if client is None:
        raise HTTPException(status_code=503, detail="Gemini is not configured. Add GEMINI_API_KEY to the backend .env file.")
    if audio.content_type not in ("audio/wav", "application/octet-stream", "audio/x-wav"):
        # Multipart clients may omit content type; the filename is also accepted below.
        if not (audio.filename or "").lower().endswith(".wav"):
            raise HTTPException(status_code=415, detail="Please send a WAV voice recording.")
    # Read at most one byte beyond the limit so an unexpectedly large request
    # is rejected without materialising an arbitrary upload into application memory.
    data = await audio.read(MAX_AUDIO_BYTES + 1)
    if len(data) > MAX_AUDIO_BYTES:
        raise HTTPException(status_code=413, detail="Keep voice recordings under 8 MB.")
    if not data:
        raise HTTPException(status_code=400, detail="The voice recording is empty.")
    prompt = (
        "Transcribe this short Indian speech recording verbatim. The speaker may code-switch between Hindi and English (Hinglish), "
        "including English financial terms inside Hindi sentences. Preserve the words and meaning; do not translate, summarise, answer, "
        "or guess missing words. Return only the transcript. Language hint: " + language_hint[:30]
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
        # The app does not explicitly persist the recording. Keep transcript out of logs.
        return {"text": transcript, "mode": "gemini_transcribe", "model": GEMINI_TRANSCRIPTION_MODEL}
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Voice transcription failed ({type(exc).__name__}).") from exc
