# On-device RAG: model choice and implementation

Sathi now has an opt-in on-device retrieval-augmented generation path. It does not fine-tune a model on customer data. Instead, it retrieves relevant local passages for each new question and gives only those passages to the local language model. Personal documents and vectors remain in the AES-GCM encrypted vault and are not passed to Gemini by this path.

## Models

- **Generation:** `litert-community/Qwen3-0.6B`, file `Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm` (about 329 MB).
- **Semantic retrieval:** `litert-community/embeddinggemma-2-text-270m-litert-lm`, file `embeddinggemma-2-text-270m.litertlm` (about 165 MB). Embedding vectors use retrieval-document / retrieval-query task prefixes and are cached inside the encrypted local vault.
- Both model cards list Apache-2.0. Preserve required notices and check terms before distributing an app.
- Models are downloaded only after the user taps the download button; no large model files are committed into Git. After the initial download, the generation and retrieval path works without network access.

## Implemented flow

1. Existing exact fact extraction handles high-confidence fields such as labelled claim amount, status and references where available.
2. If a model is installed, the current user question is embedded locally. The service chunks the local OCR text and local offline guide, retrieves the top semantically similar passages (with lexical overlap as a secondary signal), and supplies those passages to Qwen3.
3. The prompt requires evidence-only answers, treats documents as untrusted text, uses the selected language (English, Hindi or Roman Hinglish), asks for citations to source labels, and abstains when evidence is insufficient.
4. If local RAG cannot answer, existing local retrieval/FAQ and private-question abstention remain in place. Only a separate general-information query can enter the optional Gemini fallback after consent and a per-question confirmation. Documents, OCR, local embeddings, claim context and previous chat history are never attached to that cloud request.
5. The encrypted vault persists a bounded embedding cache using the embedding-profile ID. Claim-state writes use a merge operation so they do not erase the RAG cache.

## App usage

Open **How Sathi works → Download offline AI models**. Connect to Wi-Fi for the one-time download and ensure at least 1 GB of free space. When the UI reports both models ready, questions with relevant local documents or built-in guide evidence can be answered by on-device RAG. The model is small, so verify its responses; the app is not an insurer decision engine.

## Platform configuration

- Android: min SDK 30; arm64-v8a is required for LiteRT-LM native inference.
- iOS: deployment target 15.0 and static framework linkage. LiteRT-LM documents additional memory entitlements for models that need them; configure these only after confirming Apple signing/team capabilities.
- Dependencies: `flutter_edge_ai` and `flutter_edge_ai_litertlm`. Initialize the LiteRT-LM inference engine and embedding backend before installation/inference.

## Limitations

This is a privacy-preserving local RAG MVP, not a trained insurance-specialist model. The embedded local guide is deliberately short; it is not a verified insurer policy database. New/rare questions may return “not found”. OCR mistakes can affect retrieval. The current model files are not bundled and must be downloaded once by the user. Live insurer status, claim submission, policy verification and formal escalation are not integrated.

## Test on a device

1. `flutter pub get`, `flutter analyze`, and `flutter test`.
2. Run the app, open **How Sathi works**, download the models, and wait for both to show ready.
3. Upload the synthetic claim letter and rerun on-device OCR.
4. Ask multiple phrasings in Hindi/Hinglish/English about amounts, rejection reasons, missing papers and next steps. Inspect the displayed model/evidence labels.
5. Turn off Wi-Fi and repeat a document question. It should continue to use local RAG; the cloud general fallback must not be invoked.
