# Firebase and partner API setup (optional next phase)

Firebase is shown in the architecture view, but this source archive does not include a Firebase project or live credentials. The app uses mock claim data by default.

## Firebase

1. Create a Firebase project in your organisation account.
2. From the project directory, run `dart pub global activate flutterfire_cli` and then `flutterfire configure`.
3. Add only the plugins needed for the selected journey, for example `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`, `firebase_messaging` and/or `firebase_analytics`.
4. Initialise Firebase before `runApp` using the generated `firebase_options.dart`.
5. Use Firebase Security Rules and App Check where appropriate. Never rely on hidden UI elements for access control.
6. Do not store medical records, OCR text or decision-letter contents in Analytics. Make data retention/deletion and consent clear.

Official setup: https://firebase.google.com/docs/flutter/setup

## Partner services

Use a backend adapter between the Flutter client and each regulated partner. Do not put partner secrets or LLM API keys in the app. Keep production and sandbox base URLs separate. The backend must authenticate the user, confirm consent and authorisation, validate every claim/identity mapping, rate-limit requests, and return provider event/reference IDs.

## RAG and citations

A production retrieval service should:

- index only documents the partner is authorised to use;
- attach insurer, product, policy-version, effective-date, page/section metadata to every chunk;
- filter retrieval by the user's specific product/policy and the version effective on the relevant date;
- return the exact excerpt and citation metadata along with a summary;
- say “I could not verify this in the supplied documents” when retrieval returns no relevant source;
- treat document text as untrusted input and defend against instructions embedded inside a document;
- keep an audit record that is access-controlled and avoids raw sensitive text where possible.

The app's response format accepts `citations: [{"sourceTitle":"...","section":"...","excerpt":"...","page":2}]`. Do not invent page numbers or policy clauses.

## WebSocket events

The `ClaimUpdatesSocket` helper parses JSON events from an already-authenticated `WebSocketChannel`. Your backend must define an event schema such as `{ "type": "claim_status", "eventId": "...", "status": "documents_received", "occurredAt": "ISO-8601" }`. Check permission to the claim on every connection, use TLS, and avoid long-lived tokens in URLs.
