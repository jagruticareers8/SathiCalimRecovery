# Sathi — automatic document reading update

This ZIP contains **changed files only**, not the complete Flutter project. Extract it into the root of your existing Sathi project and merge/overwrite the matching files.

## Apply and verify

From your existing project root, run:

```bash
flutter pub get
flutter test test/local_first_document_qa_test.dart
flutter test test/local_first_document_amount_test.dart
flutter test test/on_device_document_reader_test.dart
flutter test
```

Then test on a physical Android/iOS device with a digital PDF, a scanned PDF and a photo.

## User journey

1. Tap **Add a document** once.
2. Select one or more PDFs or photos.
3. Sathi saves an encrypted app copy and reads the file automatically.
4. Sathi extracts digital PDF text directly; scanned PDF pages and photos are processed with on-device OCR.
5. When reading finishes, the app returns to Home with **Ask Sathi** and simple suggested questions.

Users do not need to copy/paste text, choose OCR, or tap a separate read button. Basic PDF reading and local fact extraction do not require downloading the optional Qwen/Embedding models. Those optional models improve natural-language retrieval and answer generation, but do not block document reading.

## Privacy and limits

- PDF extraction, page rendering, image OCR and private document Q&A run locally in the app.
- The selected document is stored as an encrypted app-private copy. Short-lived decrypted files and rendered page images are deleted after processing.
- This upload/reading flow does not send PDF files, OCR text or claim context to Gemini.
- Prototype file-size limit: 25 MB.
- Password-protected PDFs must be unlocked before adding them.
- Blurred or unreadable pages may need a clearer copy; Sathi should not invent missing facts.
- Sathi is not connected to insurer/TPA systems and cannot verify live claim status or submit claims.

## Dependency resolution

`pubspec.lock` is intentionally not included because Flutter/Dart SDK was unavailable in the build environment. Run `flutter pub get` locally to resolve the new `pdfrx` and `image` dependencies and update the lockfile.

## Validation note

Source changes, YAML configuration and ZIP paths were checked. Flutter analyzer, tests and Android/iOS builds could not be run in this environment because the Flutter SDK is not installed. Please run the commands above on your Mac before release.
