# On-device Gemma / LLM integration plan

The current app demonstrates on-device OCR and PII masking. It does **not** ship a Gemma model or claim to run a local LLM yet.

## Why the model is not bundled

A model requires a compatible artifact, appropriate licensing checks, device memory/performance testing, native Android/iOS runtime setup and a lifecycle for downloading/updating the model. Committing a multi-gigabyte model into a small source archive is not a good default.

## MediaPipe note

As of this project update, Google AI Edge's MediaPipe LLM Inference documentation marks the API as maintenance-only and recommends LiteRT-LM for new features and optimisations. The pitch may keep “Gemma / MediaPipe LLM” as its intended/prototype stack, but the engineering implementation should evaluate LiteRT-LM before production.

Official documentation: https://developers.google.com/edge/mediapipe/solutions/genai/llm_inference

## Recommended interface boundary

Implement a Dart interface such as:

```dart
abstract interface class OnDeviceLanguageModel {
  Future<String> explain({
    required String question,
    required String verifiedSourceText,
  });
}
```

Provide a `DemoOnDeviceLanguageModel` for tests and a native platform-channel implementation for the chosen LiteRT-LM runtime. The native method must accept only the minimised prompt and approved source text; it must not access arbitrary file paths or network APIs. Keep generation cancellable, enforce token/output limits, and ask users to verify the result.

## Integration acceptance checklist

- Select and document a compatible model/version and licence.
- Confirm supported hardware, app size, memory ceiling, startup time and battery usage on real target devices.
- Download model artifacts from a verified source; verify integrity before loading.
- Keep prompts/outputs on-device by default and give the user a clear control before any cloud fallback.
- Add tests for unsupported devices, model-load failure, cancellation, poor OCR text and prompt injection inside a claim document.
- Do not treat model output as policy truth; show citations only from verified retrieval results.
