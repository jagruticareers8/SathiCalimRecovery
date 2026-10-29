import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Runs OCR on a local image path through native ML Kit APIs.
/// The image is not uploaded by this service. Latin catches English/Roman
/// Hinglish; Devanagari catches Hindi-script text. Duplicate lines from the
/// two recognizers are removed while preserving the text found by either.
class OnDeviceOcrService {
  Future<String> readImageText(String imagePath) async {
    final image = InputImage.fromFilePath(imagePath);
    final outputs = <String>[];

    for (final script in <TextRecognitionScript>[
      TextRecognitionScript.latin,
      TextRecognitionScript.devanagiri,
    ]) {
      final recognizer = TextRecognizer(script: script);
      try {
        final result = await recognizer.processImage(image);
        if (result.text.trim().isNotEmpty) outputs.add(result.text.trim());
      } catch (_) {
        // Preserve any text returned by the other script recognizer. The UI
        // reports a no-text message if neither recognizer succeeds.
      } finally {
        await recognizer.close();
      }
    }

    final seen = <String>{};
    final mergedLines = <String>[];
    for (final output in outputs) {
      for (final line in output.split(RegExp(r'\r?\n'))) {
        final cleaned = line.trim();
        if (cleaned.isEmpty) continue;
        final key = cleaned.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        if (seen.add(key)) mergedLines.add(cleaned);
      }
    }
    return mergedLines.join('\n').trim();
  }
}
